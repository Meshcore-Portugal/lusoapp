import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../providers/radio_providers.dart';
import '../../transport/transport.dart';

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
  _ConnectTarget? _connectingTarget;

  @override
  void dispose() {
    _bleScanSub?.cancel();
    super.dispose();
  }

  Future<void> _startScan() async {
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
    setState(() => _connectingTarget = target);
    final connection = ref.read(connectionProvider.notifier);
    bool ok;

    switch (target.type) {
      case _ConnectType.ble:
        ok = await connection.connectBle(target.device.id);
      case _ConnectType.serialCompanion:
        ok = await connection.connectSerial(
          target.device.id,
          mode: ConnectionMode.companion,
        );
      case _ConnectType.serialKiss:
        ok = await connection.connectSerial(
          target.device.id,
          mode: ConnectionMode.kiss,
        );
    }

    if (ok && mounted) {
      context.go('/channels');
    } else if (mounted) {
      setState(() => _connectingTarget = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Falha ao ligar ao dispositivo'),
          backgroundColor: Colors.red,
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
              Icon(
                Icons.cell_tower,
                size: 80,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'MeshCore PT',
                style: theme.textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Comunidade Portuguesa MeshCore',
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
                )
              else ...[
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
  });

  final _ConnectTarget? target;
  final String stepLabel;
  final int stepIndex;
  final int totalSteps;
  final ThemeData theme;

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
