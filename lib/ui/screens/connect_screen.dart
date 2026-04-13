import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart'
    show FlutterBluePlus, BluetoothAdapterState, FlutterBluePlusException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../providers/radio_providers.dart';
import '../../services/storage_service.dart';
import '../../transport/transport.dart';
import '../theme.dart';

// ---------------------------------------------------------------------------
// Temporary event badge — set to false to remove.
// ---------------------------------------------------------------------------
const _showSummitEdition = false;

// ---------------------------------------------------------------------------
// Composite model — a discovered device paired with its connection type.
// ---------------------------------------------------------------------------

enum _ConnectType { ble, serialCompanion, serialKiss }

class _ConnectTarget {
  const _ConnectTarget({required this.device, required this.type});
  final RadioDevice device;
  final _ConnectType type;

  String get typeLabel {
    switch (type) {
      case _ConnectType.ble:
        return 'Bluetooth LE';
      case _ConnectType.serialCompanion:
        return 'Série USB — Companion';
      case _ConnectType.serialKiss:
        return 'KISS TNC';
    }
  }

  IconData get icon {
    switch (type) {
      case _ConnectType.ble:
        return Icons.bluetooth;
      case _ConnectType.serialCompanion:
        return Icons.usb;
      case _ConnectType.serialKiss:
        return Icons.podcasts;
    }
  }
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class ConnectScreen extends ConsumerStatefulWidget {
  const ConnectScreen({super.key});

  @override
  ConsumerState<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends ConsumerState<ConnectScreen> {
  bool _scanning = false;
  final List<_ConnectTarget> _targets = [];
  StreamSubscription<RadioDevice>? _bleScanSub;
  StreamSubscription<BluetoothAdapterState>? _bleStateSub;
  _ConnectTarget? _connectingTarget;
  int _cachedContactCount = 0;
  int _cachedChannelCount = 0;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      // Subscribe to the adapterState stream — this triggers the platform call
      // that populates the actual state. adapterStateNow is 'unknown' until
      // the first subscription, so we cannot rely on it at startup.
      _bleStateSub = FlutterBluePlus.adapterState.listen((state) {
        if (state == BluetoothAdapterState.off) {
          _bleStateSub?.cancel();
          _bleStateSub = null;
          if (mounted) _checkBleOnStartup();
        } else if (state != BluetoothAdapterState.unknown) {
          // BLE is already on (or unavailable) — no dialog needed.
          _bleStateSub?.cancel();
          _bleStateSub = null;
        }
      });
    }
  }

  @override
  void dispose() {
    _bleStateSub?.cancel();
    _bleScanSub?.cancel();
    super.dispose();
  }

  Future<void> _checkBleOnStartup() async {
    if (!mounted) return;

    final enable = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder:
          (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.bluetooth_disabled),
                SizedBox(width: 10),
                Flexible(child: Text('Bluetooth desligado')),
              ],
            ),
            content: const Text(
              'O Bluetooth está desligado. Deseja activá-lo para ligar ao rádio MeshCore?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Não'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Activar'),
              ),
            ],
          ),
    );

    if (!mounted) return;
    if (enable == true) {
      if (Platform.isAndroid) {
        try {
          // turnOn() shows the system dialog and awaits BluetoothAdapterState.on.
          // Throws FlutterBluePlusException if the user denies.
          await FlutterBluePlus.turnOn();
        } on FlutterBluePlusException catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Activação do Bluetooth recusada.'),
                duration: Duration(seconds: 3),
              ),
            );
          }
        }
      } else {
        // iOS does not allow programmatic BLE enable.
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Por favor active o Bluetooth nas Definições do sistema.',
              ),
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
    }
  }

  /// Returns true if Bluetooth is on (or not applicable), false if it is off.
  /// When off, shows a friendly snackbar and returns false so the caller can abort.
  bool _checkBluetoothOn() {
    if (kIsWeb) return true;
    if (!Platform.isAndroid && !Platform.isIOS) return true;
    if (FlutterBluePlus.adapterStateNow == BluetoothAdapterState.off) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.bluetooth_disabled, color: Colors.white),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Bluetooth desligado. Ligue o Bluetooth para procurar dispositivos.',
                ),
              ),
            ],
          ),
          backgroundColor: AppTheme.primary,
          duration: Duration(seconds: 4),
        ),
      );
      return false;
    }
    return true;
  }

  Future<void> _startScan() async {
    if (!_checkBluetoothOn()) return;

    setState(() {
      _scanning = true;
      _targets.clear();
    });

    // Request Bluetooth permissions on Android before attempting any scan.
    // Without these, startScan silently returns no results on Android 6+.
    // Platform.isAndroid must not be called on web (dart:io throws there).
    if (!kIsWeb && Platform.isAndroid) {
      final statuses =
          await [
            Permission.bluetoothScan,
            Permission.bluetoothConnect,
            Permission.location,
          ].request();

      final denied = statuses.values.any(
        (s) => s.isDenied || s.isPermanentlyDenied,
      );
      if (denied) {
        if (mounted) {
          setState(() => _scanning = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Permissões Bluetooth necessárias para procurar dispositivos.',
              ),
              action: SnackBarAction(
                label: 'Definições',
                onPressed: openAppSettings,
              ),
            ),
          );
        }
        return;
      }
    }

    // BLE scan — yields one entry per device (always Companion protocol)
    _bleScanSub = BleTransport.scan(
      timeout: const Duration(seconds: 10),
    ).listen(
      (device) {
        if (mounted) {
          setState(
            () => _targets.add(
              _ConnectTarget(device: device, type: _ConnectType.ble),
            ),
          );
        }
      },
      onDone: () {
        if (mounted) setState(() => _scanning = false);
      },
      onError: (_) {
        if (mounted) setState(() => _scanning = false);
      },
    );

    // Serial devices — not available on mobile or web.
    if (!kIsWeb && !Platform.isAndroid && !Platform.isIOS) {
      try {
        final serialDevices = await SerialTransport.listDevices();
        if (mounted) {
          setState(() {
            for (final d in serialDevices) {
              _targets.add(
                _ConnectTarget(device: d, type: _ConnectType.serialCompanion),
              );
              _targets.add(
                _ConnectTarget(device: d, type: _ConnectType.serialKiss),
              );
            }
          });
        }
      } catch (_) {
        // Serial not available on this platform (e.g. web)
      }
    }
  }

  Future<void> _connectTo(_ConnectTarget target) async {
    if (target.type == _ConnectType.ble && !_checkBluetoothOn()) return;

    setState(() {
      _connectingTarget = target;
      _cachedContactCount = ref.read(contactsProvider).length;
      _cachedChannelCount =
          ref.read(channelsProvider).where((c) => !c.isEmpty).length;
    });
    final connection = ref.read(connectionProvider.notifier);
    final name = target.device.name;
    bool ok;

    switch (target.type) {
      case _ConnectType.ble:
        ok = await connection.connectBle(target.device.id, name);
      case _ConnectType.serialCompanion:
        ok = await connection.connectSerial(
          target.device.id,
          name,
          mode: ConnectionMode.companion,
        );
      case _ConnectType.serialKiss:
        ok = await connection.connectSerial(
          target.device.id,
          name,
          mode: ConnectionMode.kiss,
        );
    }

    if (ok && mounted) {
      context.go('/channels');
    } else if (mounted) {
      setState(() => _connectingTarget = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Falha ao ligar ao dispositivo'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _connectToLastDevice(LastDevice last) async {
    setState(() {
      _connectingTarget = _ConnectTarget(
        device: RadioDevice(
          id: last.id,
          name: last.name,
          type:
              last.type == 'ble' ? RadioDeviceType.ble : RadioDeviceType.serial,
        ),
        type:
            last.type == 'ble'
                ? _ConnectType.ble
                : last.type == 'serialKiss'
                ? _ConnectType.serialKiss
                : _ConnectType.serialCompanion,
      );
      _cachedContactCount = ref.read(contactsProvider).length;
      _cachedChannelCount =
          ref.read(channelsProvider).where((c) => !c.isEmpty).length;
    });
    if (last.type == 'ble' && !_checkBluetoothOn()) return;

    final connection = ref.read(connectionProvider.notifier);
    bool ok;
    if (last.type == 'ble') {
      ok = await connection.connectBle(last.id, last.name);
    } else {
      ok = await connection.connectSerial(
        last.id,
        last.name,
        mode:
            last.type == 'serialKiss'
                ? ConnectionMode.kiss
                : ConnectionMode.companion,
      );
    }
    if (ok && mounted) {
      context.go('/channels');
    } else if (mounted) {
      setState(() => _connectingTarget = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Falha ao ligar ao último dispositivo'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(connectionProvider);
    final stepLabel = ref.watch(connectionStepProvider);
    final stepIndex = ref.watch(connectionProgressProvider);
    final theme = Theme.of(context);

    // Total steps: 0=connecting transport, 1=waiting, 2=device info,
    // 3=contacts, 4=channels, 5=done.
    const totalSteps = 5;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 48),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Image.asset(
                    'assets/images/meshcore-pt-logo.webp',
                    height: 120,
                  ),
                  if (_showSummitEdition)
                    Positioned(
                      bottom: 0,
                      right: -16,
                      child: Transform.rotate(
                        angle: -0.6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: const Color(0xFFFF8C00),
                              width: 1.5,
                            ),
                          ),
                          child: const Text(
                            'SUMMIT\nEDITION',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFFFF8C00),
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'MeshCore Portugal',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurface.withAlpha(180),
                ),
              ),
              const SizedBox(height: 48),

              if (state == TransportState.connecting)
                _ConnectingCard(
                  target: _connectingTarget,
                  stepLabel: stepLabel,
                  stepIndex: stepIndex,
                  totalSteps: totalSteps,
                  theme: theme,
                  contactCount: ref.watch(contactsProvider).length,
                  channelCount:
                      ref
                          .watch(channelsProvider)
                          .where((c) => !c.isEmpty)
                          .length,
                  cachedContactCount: _cachedContactCount,
                  cachedChannelCount: _cachedChannelCount,
                )
              else ...[
                Builder(
                  builder: (context) {
                    final lastDevice = ref.watch(lastDeviceProvider);
                    if (lastDevice == null) return const SizedBox.shrink();
                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Card(
                            color: theme.colorScheme.primaryContainer,
                            child: ListTile(
                              leading: Icon(
                                lastDevice.type == 'ble'
                                    ? Icons.bluetooth
                                    : Icons.usb,
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                              title: Text(
                                'Ligar novamente',
                                style: TextStyle(
                                  color: theme.colorScheme.onPrimaryContainer,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(
                                lastDevice.name,
                                style: TextStyle(
                                  color: theme.colorScheme.onPrimaryContainer
                                      .withAlpha(180),
                                ),
                              ),
                              trailing: Icon(
                                Icons.arrow_forward_ios,
                                size: 16,
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                              onTap: () => _connectToLastDevice(lastDevice),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: TextButton.icon(
                            icon: const Icon(Icons.wifi_off, size: 18),
                            label: const Text('Continuar offline'),
                            onPressed: () => context.go('/channels'),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                FilledButton.icon(
                  onPressed: _scanning ? null : _startScan,
                  icon:
                      _scanning
                          ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Icon(Icons.search),
                  label: Text(
                    _scanning ? 'A procurar...' : 'Procurar Dispositivos',
                  ),
                ),
                if (kIsWeb) ...[
                  const SizedBox(height: 8),
                  Text(
                    'O browser irá mostrar um seletor de dispositivos Bluetooth.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withAlpha(140),
                    ),
                  ),
                ],
                const SizedBox(height: 24),

                Expanded(
                  child:
                      _targets.isEmpty
                          ? Center(
                            child: Text(
                              _scanning
                                  ? 'A procurar rádios MeshCore...'
                                  : 'Toque em "Procurar" para encontrar dispositivos',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurface.withAlpha(
                                  120,
                                ),
                              ),
                            ),
                          )
                          : ListView.builder(
                            itemCount: _targets.length,
                            itemBuilder: (context, index) {
                              final target = _targets[index];
                              final rssiSuffix =
                                  target.type == _ConnectType.ble &&
                                          target.device.rssi != null
                                      ? ' (${target.device.rssi} dBm)'
                                      : '';
                              return Card(
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor:
                                        theme.colorScheme.primaryContainer,
                                    child: Icon(
                                      target.icon,
                                      color:
                                          theme.colorScheme.onPrimaryContainer,
                                    ),
                                  ),
                                  title: Text(target.device.name),
                                  subtitle: Text(
                                    '${target.typeLabel}$rssiSuffix',
                                  ),
                                  trailing: const Icon(
                                    Icons.arrow_forward_ios,
                                    size: 16,
                                  ),
                                  onTap: () => _connectTo(target),
                                ),
                              );
                            },
                          ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Connecting progress card
// ---------------------------------------------------------------------------

class _ConnectingCard extends StatelessWidget {
  const _ConnectingCard({
    required this.target,
    required this.stepLabel,
    required this.stepIndex,
    required this.totalSteps,
    required this.theme,
    required this.contactCount,
    required this.channelCount,
    required this.cachedContactCount,
    required this.cachedChannelCount,
  });

  final _ConnectTarget? target;
  final String stepLabel;
  final int stepIndex;
  final int totalSteps;
  final ThemeData theme;
  final int contactCount;
  final int channelCount;
  final int cachedContactCount;
  final int cachedChannelCount;

  static const _stepLabels = [
    'A ligar...',
    'A aguardar rádio...',
    'Informação do dispositivo',
    'Contactos',
    'Canais',
    'Concluído',
  ];

  @override
  Widget build(BuildContext context) {
    // Step 0 means we just started the transport connection — use indeterminate
    // bar. Steps 1–5 show determinate progress.
    final progress = stepIndex == 0 ? null : stepIndex / totalSteps;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Device name + icon
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircleAvatar(
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Icon(
                    target?.icon ?? Icons.bluetooth,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    target?.device.name ?? 'A ligar...',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: progress, minHeight: 6),
            ),
            const SizedBox(height: 12),

            // Current step label (animated crossfade)
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(
                stepLabel.isNotEmpty ? stepLabel : 'A ligar...',
                key: ValueKey(stepLabel),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withAlpha(180),
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 20),

            // Step checklist
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(_stepLabels.length - 1, (i) {
                // Step indices 1–5 correspond to label indices 1–5
                final done = stepIndex > i;
                final active = stepIndex == i + 1;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child:
                            done
                                ? Icon(
                                  Icons.check_circle,
                                  key: const ValueKey('done'),
                                  size: 18,
                                  color: theme.colorScheme.primary,
                                )
                                : active
                                ? SizedBox(
                                  key: const ValueKey('active'),
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: theme.colorScheme.primary,
                                  ),
                                )
                                : Icon(
                                  Icons.radio_button_unchecked,
                                  key: const ValueKey('pending'),
                                  size: 18,
                                  color: theme.colorScheme.onSurface.withAlpha(
                                    80,
                                  ),
                                ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _stepLabels[i + 1],
                        style: theme.textTheme.bodySmall?.copyWith(
                          color:
                              done
                                  ? theme.colorScheme.primary
                                  : active
                                  ? theme.colorScheme.onSurface
                                  : theme.colorScheme.onSurface.withAlpha(100),
                          fontWeight:
                              active ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      // Show count badge for contacts (i==2) and channels (i==3)
                      if ((i == 2 && contactCount > 0) ||
                          (i == 3 && channelCount > 0)) ...[
                        const SizedBox(width: 6),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: Builder(
                            builder: (context) {
                              final live = i == 2 ? contactCount : channelCount;
                              final cached =
                                  i == 2
                                      ? cachedContactCount
                                      : cachedChannelCount;
                              final newCount = (live - cached).clamp(0, live);
                              final badgeColor = (done
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.primaryContainer)
                                  .withAlpha(40);
                              final borderColor =
                                  done
                                      ? theme.colorScheme.primary.withAlpha(120)
                                      : theme.colorScheme.primary.withAlpha(80);
                              final baseStyle = theme.textTheme.labelSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 10,
                                  );
                              return Container(
                                key: ValueKey('${i}_$live'),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: badgeColor,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: borderColor,
                                    width: 0.8,
                                  ),
                                ),
                                child:
                                    cached > 0 && newCount > 0
                                        ? Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              '$cached',
                                              style: baseStyle?.copyWith(
                                                color: theme
                                                    .colorScheme
                                                    .onSurface
                                                    .withAlpha(110),
                                              ),
                                            ),
                                            Text(
                                              ' +$newCount',
                                              style: baseStyle?.copyWith(
                                                color:
                                                    theme.colorScheme.primary,
                                              ),
                                            ),
                                          ],
                                        )
                                        : Text(
                                          '$live',
                                          style: baseStyle?.copyWith(
                                            color:
                                                done
                                                    ? theme.colorScheme.primary
                                                    : theme
                                                        .colorScheme
                                                        .onSurface
                                                        .withAlpha(160),
                                          ),
                                        ),
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}
