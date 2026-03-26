import 'dart:async';
import 'dart:io';

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

    // Serial devices — not available on mobile (SELinux / no POSIX TTY access).
    // Only enumerate on desktop platforms.
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
      } catch (_) {
        // Serial not available on this platform (e.g. web)
      }
    }
  }

  Future<void> _connectTo(_ConnectTarget target) async {
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
    final theme = Theme.of(context);

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
                const Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('A ligar...'),
                  ],
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
