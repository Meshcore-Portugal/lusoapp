import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logger/logger.dart';

import 'radio_transport.dart';

final _log = Logger(printer: SimplePrinter(printTime: false));

/// Nordic UART Service UUIDs used by MeshCore BLE radios.
class BleUuids {
  static final service = Guid('6E400001-B5A3-F393-E0A9-E50E24DCCA9E');
  static final rxCharacteristic = Guid('6E400002-B5A3-F393-E0A9-E50E24DCCA9E');
  static final txCharacteristic = Guid('6E400003-B5A3-F393-E0A9-E50E24DCCA9E');
}

/// BLE transport for MeshCore companion radio protocol.
class BleTransport implements RadioTransport {
  BleTransport(this._device);

  final BluetoothDevice _device;
  BluetoothCharacteristic? _rxChar;
  BluetoothCharacteristic? _txChar;
  StreamSubscription<List<int>>? _notifySub;
  StreamSubscription<BluetoothConnectionState>? _connStateSub;
  final _dataController = StreamController<Uint8List>.broadcast();
  final _connectionLostController = StreamController<void>.broadcast();
  bool _connected = false;

  /// Set to true when disconnect() is called by the app, so the
  /// connectionState listener doesn't fire a spurious connectionLost event.
  bool _userDisconnected = false;

  @override
  String get displayName => 'BLE: ${_device.platformName}';

  @override
  bool get isConnected => _connected;

  @override
  bool get usesFraming => false;

  @override
  Stream<Uint8List> get dataStream => _dataController.stream;

  @override
  Stream<void> get connectionLost => _connectionLostController.stream;

  @override
  Future<bool> connect() async {
    _userDisconnected = false;
    try {
      _log.i('BLE connecting to ${_device.platformName} (web=$kIsWeb)');

      await _device.connect(
        autoConnect: false,
        timeout: const Duration(seconds: 15),
      );

      // On native platforms, request a larger MTU before service discovery.
      // This stabilises the GATT connection and avoids early descriptor
      // write failures.  Web Bluetooth negotiates MTU automatically.
      if (!kIsWeb) {
        try {
          await _device.requestMtu(247);
        } catch (e) {
          _log.d('MTU request skipped: $e');
        }
      }

      final services = await _device.discoverServices();
      final uartService = services.firstWhere(
        (s) => s.serviceUuid == BleUuids.service,
        orElse: () => throw StateError('UART service not found'),
      );

      _rxChar = uartService.characteristics.firstWhere(
        (c) => c.characteristicUuid == BleUuids.rxCharacteristic,
      );
      _txChar = uartService.characteristics.firstWhere(
        (c) => c.characteristicUuid == BleUuids.txCharacteristic,
      );

      _log.d('TX char properties: ${_txChar!.properties}');

      // Subscribe to incoming data BEFORE enabling notifications
      // (per flutter_blue_plus docs — avoids missing early values).
      _notifySub = _txChar!.onValueReceived.listen((data) {
        _dataController.add(Uint8List.fromList(data));
      });

      // Brief settle after service discovery — GATT needs time before
      // descriptor writes / startNotifications will succeed.
      const settleMs = kIsWeb ? 600 : 300;
      await Future.delayed(const Duration(milliseconds: settleMs));

      // Enable notifications on the TX characteristic (radio → app).
      await _enableNotifications(_txChar!);

      _connected = true;
      _log.i('BLE connected: ${_device.platformName}');

      // Monitor for unexpected disconnects (not triggered by dispose/disconnect).
      _connStateSub = _device.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected &&
            _connected &&
            !_userDisconnected) {
          _log.w('BLE connection lost unexpectedly');
          _connected = false;
          _connectionLostController.add(null);
        }
      });

      return true;
    } catch (e) {
      _log.e('BLE connect failed: $e');
      await _notifySub?.cancel();
      _notifySub = null;
      _connected = false;
      return false;
    }
  }

  @override
  Future<void> disconnect() async {
    _userDisconnected = true;
    _connected = false;
    await _notifySub?.cancel();
    _notifySub = null;
    await _connStateSub?.cancel();
    _connStateSub = null;
    try {
      await _device.disconnect();
    } catch (_) {}
    _log.i('BLE disconnected');
  }

  @override
  Future<void> send(Uint8List data) async {
    if (_rxChar == null || !_connected) {
      throw StateError('Not connected');
    }
    // On web, Web Bluetooth handles ATT fragmentation internally — write the
    // full payload in a single call.  Chunking would cause the firmware to
    // receive each write as a separate command frame, truncating messages.
    //
    // requestMtu(247) on native gives 244 usable bytes, larger than the
    // protocol's MAX_FRAME_SIZE=172, so a single write is always sufficient.
    //
    // Use Write Without Response when the characteristic supports it (NUS RX
    // always does).  This eliminates the ATT Write Response round-trip
    // (~1 BLE connection interval per command) so the full _sendAndWait
    // timeout is available for the firmware's notification reply.
    // We still get delivery confirmation implicitly: if the write is lost we
    // time out waiting for the response notification and can retry.
    final withoutResponse = _rxChar!.properties.writeWithoutResponse;
    await _rxChar!.write(data, withoutResponse: withoutResponse);
  }

  @override
  Future<void> dispose() async {
    await disconnect();
    await _dataController.close();
    await _connectionLostController.close();
  }

  /// Enable notifications on a characteristic, handling the flutter_blue_plus
  /// web bug where setNotifyValue always times out.
  ///
  /// **Root cause (flutter_blue_plus_web 7.0.2):**
  /// The web implementation of `setNotifyValue` calls the Web Bluetooth
  /// `startNotifications()` JS API and adds the event listener, then returns
  /// `true` (hasCCCD). The platform-agnostic layer interprets `true` as
  /// "wait for an `onDescriptorWritten` confirmation event" — but the web
  /// plugin *never* emits that event because Web Bluetooth handles the CCCD
  /// descriptor internally. So the call always times out after 15 s, even
  /// though `startNotifications()` already succeeded.
  ///
  /// **Workaround:** On web we call `setNotifyValue` with a short 2 s timeout.
  /// The JS `startNotifications()` finishes almost instantly — the timeout
  /// only fires in the stale "wait for CCCD" phase. We catch it and proceed,
  /// because notifications are already active.
  ///
  /// On native platforms we use the normal retry path.
  static Future<void> _enableNotifications(BluetoothCharacteristic char) async {
    if (kIsWeb) {
      try {
        _log.d('setNotifyValue (web, timeout=2s)');
        await char.setNotifyValue(true, timeout: 2);
        _log.i('setNotifyValue succeeded (web)');
      } catch (e) {
        // Expected: the CCCD-wait phase times out. But startNotifications()
        // and the event listener are already active — safe to proceed.
        _log.w(
          'setNotifyValue web timeout (expected) — notifications active: $e',
        );
      }
    } else {
      // Native platforms: retry with escalating backoff.
      const maxAttempts = 3;
      const delay = Duration(milliseconds: 500);
      for (var attempt = 1; attempt <= maxAttempts; attempt++) {
        try {
          _log.d('setNotifyValue attempt $attempt/$maxAttempts');
          await char.setNotifyValue(true);
          _log.i('setNotifyValue succeeded on attempt $attempt');
          return;
        } catch (e) {
          _log.w('setNotifyValue attempt $attempt/$maxAttempts failed: $e');
          if (attempt == maxAttempts) rethrow;
          await Future.delayed(delay * attempt);
        }
      }
    }
  }

  /// Scan for MeshCore BLE devices.
  ///
  /// Passing [BleUuids.service] in [withServices] serves double duty on web:
  /// it tells the Web Bluetooth browser picker to filter to NUS devices AND
  /// it declares the UUID in `optionalServices`, which is required by the
  /// Web Bluetooth security model before [discoverServices] is allowed.
  /// Removing it (acceptAllDevices) causes a SecurityError on discoverServices.
  ///
  /// **Web note:** On web, [FlutterBluePlus.startScan] calls the browser's
  /// `requestDevice()` which blocks until the user picks a device, emits the
  /// result to [FlutterBluePlus.onScanResults], then returns.  We must
  /// subscribe to [onScanResults] *before* calling [startScan]; otherwise the
  /// result has already been emitted by the time the `await for` loop starts
  /// and is silently missed.
  static Stream<RadioDevice> scan({
    Duration timeout = const Duration(seconds: 10),
  }) {
    final controller = StreamController<RadioDevice>();
    final seen = <String>{};

    Future<void> doScan() async {
      // Subscribe to results BEFORE startScan — critical on web where
      // startScan blocks inside the browser requestDevice() picker and emits
      // the chosen device before returning.
      final sub = FlutterBluePlus.onScanResults.listen((results) {
        for (final r in results) {
          if (!seen.contains(r.device.remoteId.str)) {
            seen.add(r.device.remoteId.str);
            if (!controller.isClosed) {
              controller.add(
                RadioDevice(
                  id: r.device.remoteId.str,
                  name:
                      r.device.platformName.isNotEmpty
                          ? r.device.platformName
                          : 'MeshCore (${r.device.remoteId.str.substring(0, 8)})',
                  type: RadioDeviceType.ble,
                  rssi: r.rssi,
                ),
              );
            }
          }
        }
      });

      try {
        await FlutterBluePlus.startScan(
          withServices: [BleUuids.service],
          timeout: timeout,
        );
      } catch (e) {
        _log.e('BLE startScan failed: $e');
      }

      // On native the scan keeps running for `timeout`; wait for it to stop.
      // On web startScan already returned after the picker resolved — done.
      if (!kIsWeb) {
        await FlutterBluePlus.isScanning.where((scanning) => !scanning).first;
      }

      await sub.cancel();
      await controller.close();
    }

    doScan();
    return controller.stream;
  }

  /// Create a BLE transport from a scanned device ID.
  static BleTransport fromDeviceId(String deviceId) {
    final device = BluetoothDevice.fromId(deviceId);
    return BleTransport(device);
  }
}
