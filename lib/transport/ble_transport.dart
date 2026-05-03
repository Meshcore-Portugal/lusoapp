import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logger/logger.dart';

import 'radio_transport.dart';
import 'win_ble_bridge.dart';

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

      // flutter_blue_plus_windows (WinBle.connect) ignores the timeout
      // parameter entirely — the underlying WinRT call has no timeout guard.
      // Wrap with a Dart-level Future.timeout on Windows so an unreachable
      // device does not block the UI indefinitely.
      final connectFuture = _device.connect(
        autoConnect: false,
        timeout: const Duration(seconds: 15),
      );
      await (!kIsWeb && Platform.isWindows
          ? connectFuture.timeout(
              const Duration(seconds: 15),
              onTimeout: () =>
                  throw TimeoutException('BLE connect timed out (Windows)'),
            )
          : connectFuture);

      // On native platforms, request a larger MTU before service discovery.
      // This stabilises the GATT connection and avoids early descriptor
      // write failures.  Web Bluetooth negotiates MTU automatically.
      //
      // On Windows, flutter_blue_plus_windows ignores the requested MTU value
      // and returns the system-negotiated MTU instead.  The try/catch handles
      // this silently — the system MTU is typically 247 bytes anyway on modern
      // Windows BLE stacks.
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

  /// Enable notifications on a characteristic, with platform-specific handling.
  ///
  /// **Web bug (flutter_blue_plus_web 7.0.2):**
  /// The web implementation of `setNotifyValue` calls the Web Bluetooth
  /// `startNotifications()` JS API and adds the event listener, then returns
  /// `true` (hasCCCD). The platform-agnostic layer interprets `true` as
  /// "wait for an `onDescriptorWritten` confirmation event" — but the web
  /// plugin *never* emits that event because Web Bluetooth handles the CCCD
  /// descriptor internally. So the call always times out after 15 s, even
  /// though `startNotifications()` already succeeded.
  ///
  /// **Web workaround:** Call `setNotifyValue` with a short 2 s timeout; the
  /// timeout only fires in the stale "wait for CCCD" phase. Notifications are
  /// already active at that point, so catching and ignoring the error is safe.
  ///
  /// **Windows (flutter_blue_plus_windows):**
  /// Uses `WriteClientCharacteristicConfigurationDescriptorAsync` via WinRT —
  /// no timeout bug.  Falls through to the native retry path below.
  ///
  /// **Android / iOS / macOS / Linux:** native retry path.
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

  /// Pure filter used by [isWindowsMeshCoreDevice]: accepts the device when
  /// [serviceUuids] contains the NUS service GUID, or when [deviceName]
  /// contains "meshcore" (case-insensitive) as a fallback for radios that
  /// omit the service UUID from their advertisement packet.
  ///
  /// Separated so tests can call this function directly without constructing
  /// a [ScanResult].
  static bool isMeshCoreAdvertisement(
    List<Guid> serviceUuids,
    String deviceName,
  ) {
    if (serviceUuids.contains(BleUuids.service)) return true;
    return deviceName.toLowerCase().contains('meshcore');
  }

  /// Scan for MeshCore BLE devices.
  ///
  /// On Windows, delegates entirely to [WinBleBridge.scan] which uses
  /// win_ble (WinRT/BLEServer.exe) and applies MeshCore filtering internally.
  ///
  /// On web, [withServices] goes into the browser picker `filters`.
  /// [webOptionalServices] populates `optionalServices` in `requestDevice()`
  /// so the Web Bluetooth security model allows [discoverServices].
  ///
  /// **Web note:** [FlutterBluePlus.startScan] blocks inside `requestDevice()`
  /// until the user picks a device.  We must subscribe to [onScanResults]
  /// *before* calling [startScan] so the result is not missed.
  static Stream<RadioDevice> scan({
    Duration timeout = const Duration(seconds: 10),
  }) {
    // Windows: win_ble handles BLEServer subprocess, scanning, and filtering.
    if (!kIsWeb && Platform.isWindows) {
      return WinBleBridge.scan(timeout: timeout);
    }

    final controller = StreamController<RadioDevice>();
    final seen = <String>{};

    Future<void> doScan() async {
      // Subscribe BEFORE startScan — critical on web where startScan blocks
      // inside requestDevice() and emits the chosen device before returning.
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
          // Required on web: declares service UUIDs in requestDevice()
          // optionalServices so discoverServices() is not blocked by the
          // browser security model (separate from the picker filters above).
          webOptionalServices: [BleUuids.service],
          timeout: timeout,
        );
      } catch (e) {
        _log.e('BLE startScan failed: $e');
      }

      if (!kIsWeb) {
        // On native (Android/iOS/Linux/macOS) the scan runs for `timeout`;
        // wait for it to stop before closing.
        await FlutterBluePlus.isScanning.where((scanning) => !scanning).first;
      } else {
        // On web, `startScan` returns as soon as the user picks a device from
        // `requestDevice()`. However, flutter_blue_plus buffers the result in
        // `_BufferStream` and only delivers it to `_scanResults` (and therefore
        // to our `sub` listener above) after 1–2 asynchronous event-loop turns.
        // If we cancelled `sub` immediately the device event would be lost.
        //
        // Fix: yield briefly so `_scanSubscription` can process the buffered
        // response and push to `_scanResults`. Then check `lastScanResults`
        // as a guaranteed fallback for any device that still wasn't delivered
        // to our listener in time.
        await Future<void>.delayed(const Duration(milliseconds: 100));
        for (final r in FlutterBluePlus.lastScanResults) {
          if (!seen.contains(r.device.remoteId.str) && !controller.isClosed) {
            seen.add(r.device.remoteId.str);
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

      await sub.cancel();
      await controller.close();
    }

    doScan();
    return controller.stream;
  }

  /// Create a BLE transport from a scanned device ID.
  ///
  /// On Windows, returns a [WindowsBleTransport] backed by win_ble (WinRT)
  /// because flutter_blue_plus has no Windows platform registration.
  /// On all other platforms, creates a standard [BleTransport].
  static RadioTransport fromDeviceId(String deviceId) {
    if (!kIsWeb && Platform.isWindows) {
      return WinBleBridge.createTransport(deviceId);
    }
    return BleTransport(BluetoothDevice.fromId(deviceId));
  }
}
