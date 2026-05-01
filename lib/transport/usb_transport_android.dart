// USB serial transport for Android using the Android USB Host API.
//
// Implements [RadioTransport] via the `usb_serial` Flutter package, which
// wraps Android's UsbManager/UsbDeviceConnection APIs. Supports the chip
// families most commonly found on LoRa radio USB adapters: CH340, CP210x,
// FTDI, PL2303, and CDC-ACM. The [connect] call tries each driver in order
// and triggers the system USB permission dialog on first use.
//
// Runtime guard: [Platform.isAndroid] prevents any execution on
// Windows/Linux where this file is also compiled (via the dart.library.ffi
// conditional export in usb_transport.dart).

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:logger/logger.dart';
import 'package:usb_serial/usb_serial.dart';

import 'radio_transport.dart';

final _log = Logger(printer: SimplePrinter(printTime: false));

/// USB serial transport for Android.
///
/// Uses the Android USB Host API via the `usb_serial` package.
/// Supports CH340, CP210x, FTDI, PL2303, and CDC-ACM chips.
/// Triggers the system USB permission dialog the first time [connect] is called
/// for a given device.
class UsbTransport implements RadioTransport {
  /// Constructs a transport for the given [UsbDevice].
  /// Use [listDevices] + [fromDeviceId] to obtain a [UsbDevice].
  UsbTransport(this._device);

  final UsbDevice _device;

  /// Active port once [connect] succeeds; null otherwise.
  UsbPort? _port;
  StreamSubscription<Uint8List>? _dataSub;
  final _dataController = StreamController<Uint8List>.broadcast();
  bool _connected = false;

  /// Builds a human-readable label from the device's product/manufacturer name.
  /// Falls back to the numeric device ID when neither field is populated.
  static String _label(UsbDevice d) {
    final parts = [d.productName, d.manufacturerName]
        .where((s) => s != null && s.isNotEmpty)
        .cast<String>()
        .toList();
    return parts.isNotEmpty ? parts.join(' — ') : 'USB ${d.deviceId}';
  }

  // The MeshCore companion protocol wraps frames with direction + length bytes,
  // so framing is always required regardless of transport.
  @override
  bool get usesFraming => true;

  @override
  String get displayName => 'USB: ${_label(_device)}';

  @override
  bool get isConnected => _connected;

  /// USB serial does not surface disconnect events; returns an empty stream.
  @override
  Stream<void> get connectionLost => const Stream.empty();

  @override
  Stream<Uint8List> get dataStream => _dataController.stream;

  /// Opens the USB serial port at 115200 8N1 with DTR+RTS asserted.
  ///
  /// Iterates over known driver types (CDC → CH34x → CP210x → FTDI → PL2303)
  /// and uses the first one the device accepts. Calling [open] also triggers
  /// the Android system USB permission dialog if the app hasn't been granted
  /// access to this device yet.
  @override
  Future<bool> connect() async {
    if (!Platform.isAndroid) return false;
    try {
      // Probe driver types in order of prevalence for LoRa USB adapters.
      for (final type in [
        UsbSerial.CDC,
        UsbSerial.CH34x,
        UsbSerial.CP210x,
        UsbSerial.FTDI,
        UsbSerial.PL2303,
      ]) {
        _port = await _device.create(type);
        if (_port != null) break;
      }

      if (_port == null) {
        _log.e('No USB serial driver matched: ${_label(_device)}');
        return false;
      }

      // open() triggers the Android USB permission dialog on first use.
      if (!await _port!.open()) {
        _log.e('USB open/permission denied: ${_label(_device)}');
        _port = null;
        return false;
      }

      // Configure 115200 8N1 with control lines asserted — same settings
      // used by the desktop serial transport.
      await _port!.setDTR(true);
      await _port!.setRTS(true);
      await _port!.setPortParameters(
        115200,
        UsbPort.DATABITS_8,
        UsbPort.STOPBITS_1,
        UsbPort.PARITY_NONE,
      );

      // Forward incoming bytes to the broadcast stream consumed by RadioService.
      _dataSub = _port!.inputStream?.listen(
        (data) => _dataController.add(data),
        onError: (e) => _log.w('USB read error: $e'),
      );

      _connected = true;
      _log.i('USB connected: ${_label(_device)}');
      return true;
    } catch (e) {
      _log.e('USB connect failed: $e');
      _connected = false;
      await _port?.close();
      _port = null;
      return false;
    }
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    await _dataSub?.cancel();
    _dataSub = null;
    try {
      await _port?.close();
    } catch (_) {}
    _port = null;
    _log.i('USB disconnected: ${_label(_device)}');
  }

  @override
  Future<void> send(Uint8List data) async {
    if (!_connected || _port == null) throw StateError('Not connected');
    await _port!.write(data);
  }

  @override
  Future<void> dispose() async {
    await disconnect();
    await _dataController.close();
  }

  /// Returns a [RadioDevice] entry for each USB serial device currently
  /// attached to this Android device.
  ///
  /// Skips non-Android platforms — [flutter_libserialport] (used by the
  /// desktop serial transport) handles those.
  static Future<List<RadioDevice>> listDevices() async {
    if (!Platform.isAndroid) return [];
    try {
      final devices = await UsbSerial.listDevices();
      _log.i('Found ${devices.length} USB device(s)');
      return devices
          .map(
            (d) => RadioDevice(
              id: d.deviceId.toString(),
              name: _label(d),
              type: RadioDeviceType.serial,
            ),
          )
          .toList();
    } catch (e) {
      _log.w('USB enumeration failed: $e');
      return [];
    }
  }

  /// Looks up the [UsbDevice] with [deviceId] in the current device list
  /// and returns a ready-to-connect [UsbTransport].
  ///
  /// Returns null if the device is no longer attached or the ID is invalid.
  static Future<UsbTransport?> fromDeviceId(String deviceId) async {
    if (!Platform.isAndroid) return null;
    final id = int.tryParse(deviceId);
    if (id == null) return null;
    try {
      final devices = await UsbSerial.listDevices();
      final d = devices.where((d) => d.deviceId == id).firstOrNull;
      return d != null ? UsbTransport(d) : null;
    } catch (_) {
      return null;
    }
  }
}
