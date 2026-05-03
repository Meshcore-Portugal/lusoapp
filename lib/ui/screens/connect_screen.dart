import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart'
    show FlutterBluePlus, BluetoothAdapterState, FlutterBluePlusException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../l10n/l10n.dart';
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

// Supported connection types shown in the connect screen.
// serialCompanion / serialKiss — desktop serial via flutter_libserialport (Windows/Linux)
// usbCompanion    / usbKiss    — Android USB Host via usb_serial
enum _ConnectType { ble, serialCompanion, serialKiss, usbCompanion, usbKiss }

/// Pairs a discovered [RadioDevice] with the connection type the user selected.
/// Drives the label and icon shown in the device list and the connect logic.
class _ConnectTarget {
  const _ConnectTarget({required this.device, required this.type});
  final RadioDevice device;
  final _ConnectType type;

  /// Human-readable connection type label shown below the device name.
  String get typeLabel {
    switch (type) {
      case _ConnectType.ble:
        return 'Bluetooth LE';
      case _ConnectType.serialCompanion:
      case _ConnectType.usbCompanion:
        return 'Série USB — Companion';
      case _ConnectType.serialKiss:
      case _ConnectType.usbKiss:
        return 'KISS TNC';
    }
  }

  /// Icon representing the physical connection medium.
  IconData get icon {
    switch (type) {
      case _ConnectType.ble:
        return Icons.bluetooth;
      case _ConnectType.serialCompanion:
      case _ConnectType.usbCompanion:
        return Icons.usb;
      case _ConnectType.serialKiss:
      case _ConnectType.usbKiss:
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
            title: Row(
              children: [
                const Icon(Icons.bluetooth_disabled),
                const SizedBox(width: 10),
                Flexible(child: Text(context.l10n.connectBluetoothOff)),
              ],
            ),
            content: const Text(
              'O Bluetooth está desligado. Deseja activá-lo para ligar ao rádio MeshCore?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(context.l10n.commonNo),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(context.l10n.connectBluetoothEnable),
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
              SnackBar(
                content: Text(context.l10n.connectBluetoothDeniedMessage),
                duration: const Duration(seconds: 3),
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

    // On web, BLE scan = browser requestDevice() picker.
    // The picker is both scan and selection: await the single result and
    // connect immediately without an intermediate list.
    if (kIsWeb) {
      try {
        // Use a long timeout so the user has time to interact with the picker.
        final device =
            await BleTransport.scan(timeout: const Duration(minutes: 2)).first;
        if (!mounted) return;
        setState(() => _scanning = false);
        await _connectTo(
          _ConnectTarget(device: device, type: _ConnectType.ble),
        );
      } catch (_) {
        // User dismissed the picker or scan failed — just stop spinning.
        if (mounted) setState(() => _scanning = false);
      }
      return;
    }

    // Request Bluetooth permissions on Android before attempting any scan.
    // Without these, startScan silently returns no results on Android 6+.
    // Platform.isAndroid must not be called on web (dart:io throws there).
    if (Platform.isAndroid) {
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

    // Desktop serial (Windows / Linux) via flutter_libserialport.
    if (!Platform.isAndroid && !Platform.isIOS) {
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
      } catch (_) {}
    }

    // Android USB Host via usb_serial — runs alongside the BLE scan.
    if (Platform.isAndroid) {
      try {
        final usbDevices = await UsbTransport.listDevices();
        if (mounted) {
          setState(() {
            for (final d in usbDevices) {
              _targets.add(
                _ConnectTarget(device: d, type: _ConnectType.usbCompanion),
              );
              _targets.add(
                _ConnectTarget(device: d, type: _ConnectType.usbKiss),
              );
            }
          });
        }
      } catch (_) {}
    }
  }

  /// Triggers the browser Web Serial port-picker (web only).
  /// Must be initiated from a user gesture. Connects immediately in
  /// Companion mode after the user selects a port.
  Future<void> _connectWebSerial() async {
    final device = await SerialTransport.requestPort();
    if (device == null || !mounted) return;
    await _connectTo(
      _ConnectTarget(device: device, type: _ConnectType.serialCompanion),
    );
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
      // Desktop serial via flutter_libserialport.
      case _ConnectType.serialCompanion:
        ok = await connection.connectSerial(
          target.device.id, name, mode: ConnectionMode.companion,
        );
      case _ConnectType.serialKiss:
        ok = await connection.connectSerial(
          target.device.id, name, mode: ConnectionMode.kiss,
        );
      // Android USB Host via usb_serial.
      case _ConnectType.usbCompanion:
        ok = await connection.connectUsb(
          target.device.id, name, mode: ConnectionMode.companion,
        );
      case _ConnectType.usbKiss:
        ok = await connection.connectUsb(
          target.device.id, name, mode: ConnectionMode.kiss,
        );
    }

    if (ok && mounted) {
      context.go('/channels');
    } else if (mounted) {
      setState(() => _connectingTarget = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.connectFailTitle),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  /// Reconnects to a previously connected device from the recent-devices list.
  ///
  /// Routes to the correct transport method (BLE, USB Host, or desktop serial)
  /// and restores the original connection mode (Companion or KISS TNC).
  Future<void> _connectToLastDevice(LastDevice last) async {
    // Map stored type string back to a _ConnectType for UI state.
    final connectType =
        last.type == 'ble'
            ? _ConnectType.ble
            : last.type == 'serialKiss'
            ? _ConnectType.serialKiss
            : last.type == 'usbCompanion'
            ? _ConnectType.usbCompanion
            : last.type == 'usbKiss'
            ? _ConnectType.usbKiss
            : _ConnectType.serialCompanion;

    setState(() {
      _connectingTarget = _ConnectTarget(
        device: RadioDevice(
          id: last.id,
          name: last.name,
          type:
              last.type == 'ble' ? RadioDeviceType.ble : RadioDeviceType.serial,
        ),
        type: connectType,
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
    } else if (last.type == 'usbCompanion' || last.type == 'usbKiss') {
      // Android USB Host reconnect.
      ok = await connection.connectUsb(
        last.id, last.name,
        mode: last.type == 'usbKiss' ? ConnectionMode.kiss : ConnectionMode.companion,
      );
    } else {
      // Desktop serial reconnect.
      ok = await connection.connectSerial(
        last.id, last.name,
        mode: last.type == 'serialKiss' ? ConnectionMode.kiss : ConnectionMode.companion,
      );
    }
    if (ok && mounted) {
      context.go('/channels');
    } else if (mounted) {
      setState(() => _connectingTarget = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.connectLastFailTitle),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _removeRecentDevice(LastDevice device) async {
    final updated = await StorageService.instance.removeRecentDevice(device.id);
    if (!mounted) return;
    ref.read(recentDevicesProvider.notifier).state = updated;
    // If the removed device was the most-recent, update lastDeviceProvider too.
    final currentLast = ref.read(lastDeviceProvider);
    if (currentLast?.id == device.id) {
      ref.read(lastDeviceProvider.notifier).state =
          updated.isNotEmpty ? updated.first : null;
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
                    final recent = ref.watch(recentDevicesProvider);
                    if (recent.isEmpty) return const SizedBox.shrink();
                    final last = recent.first;
                    final others = recent.skip(1).toList();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Primary reconnect card — most recently connected radio.
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Card(
                            color: theme.colorScheme.primaryContainer,
                            child: ListTile(
                              leading: Icon(
                                last.type == 'ble'
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
                                last.name,
                                style: TextStyle(
                                  color: theme.colorScheme.onPrimaryContainer
                                      .withAlpha(180),
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.arrow_forward_ios,
                                    size: 16,
                                    color: theme.colorScheme.onPrimaryContainer,
                                  ),
                                  const SizedBox(width: 4),
                                  IconButton(
                                    icon: Icon(
                                      Icons.close,
                                      size: 16,
                                      color: theme
                                          .colorScheme
                                          .onPrimaryContainer
                                          .withAlpha(160),
                                    ),
                                    onPressed: () => _removeRecentDevice(last),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    visualDensity: VisualDensity.compact,
                                    tooltip: 'Remover da lista',
                                  ),
                                ],
                              ),
                              onTap: () => _connectToLastDevice(last),
                            ),
                          ),
                        ),
                        // Additional recent radios.
                        if (others.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.only(
                              left: 4,
                              top: 4,
                              bottom: 4,
                            ),
                            child: Text(
                              'OUTROS RÁDIOS',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurface.withAlpha(
                                  120,
                                ),
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                          ...others.map(
                            (d) => Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Card(
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor:
                                        theme
                                            .colorScheme
                                            .surfaceContainerHighest,
                                    child: Icon(
                                      d.type == 'ble'
                                          ? Icons.bluetooth
                                          : Icons.usb,
                                    ),
                                  ),
                                  title: Text(d.name),
                                  subtitle: Text(
                                    d.type == 'ble'
                                        ? 'Bluetooth LE'
                                        : (d.type == 'serialKiss' || d.type == 'usbKiss')
                                        ? 'KISS TNC'
                                        : 'Série USB',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.arrow_forward_ios,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 4),
                                      IconButton(
                                        icon: const Icon(Icons.close, size: 16),
                                        onPressed: () => _removeRecentDevice(d),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        visualDensity: VisualDensity.compact,
                                        tooltip: 'Remover da lista',
                                      ),
                                    ],
                                  ),
                                  onTap: () => _connectToLastDevice(d),
                                ),
                              ),
                            ),
                          ),
                        ],
                        Padding(
                          padding: const EdgeInsets.only(top: 4, bottom: 8),
                          child: TextButton.icon(
                            icon: const Icon(Icons.wifi_off, size: 18),
                            label: Text(context.l10n.connectContinueOffline),
                            onPressed: () => context.go('/channels'),
                          ),
                        ),
                        const SizedBox(height: 8),
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
                  // BLE picker note.
                  Text(
                    context.l10n.connectBrowserNote,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withAlpha(140),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Web Serial API button — triggers browser port-picker.
                  OutlinedButton.icon(
                    onPressed: _connectWebSerial,
                    icon: const Icon(Icons.usb, size: 18),
                    label: Text(context.l10n.connectUsbButton),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.l10n.connectWebSerialNote,
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
