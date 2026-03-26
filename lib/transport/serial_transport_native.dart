import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:logger/logger.dart';

import 'radio_transport.dart';

final _log = Logger(printer: SimplePrinter(printTime: false));

/// Serial (COM port) transport for MeshCore companion radio protocol.
///
/// Uses flutter_libserialport which supports Windows, macOS and Linux.
/// Not available on web — use serial_transport_stub.dart there.
class SerialTransport implements RadioTransport {
  SerialTransport(this._portName, {String? displayLabel})
    : _displayLabel = displayLabel ?? _portName;

  final String _portName;
  final String _displayLabel;
  SerialPort? _port;
  SerialPortReader? _reader;
  StreamSubscription<Uint8List>? _dataSub;
  final _dataController = StreamController<Uint8List>.broadcast();
  bool _connected = false;

  @override
  bool get usesFraming => true;

  @override
  String get displayName => 'Serial: $_displayLabel';

  @override
  bool get isConnected => _connected;

  @override
  Stream<Uint8List> get dataStream => _dataController.stream;

  @override
  Future<bool> connect() async {
    try {
      _port = SerialPort(_portName);

      if (!_port!.openReadWrite()) {
        _log.e('Failed to open $_portName: ${SerialPort.lastError}');
        _port!.dispose();
        _port = null;
        return false;
      }

      // Configure 115200 8N1 with DTR+RTS asserted
      final config =
          SerialPortConfig()
            ..baudRate = 115200
            ..bits = 8
            ..stopBits = 1
            ..parity = SerialPortParity.none
            ..setFlowControl(SerialPortFlowControl.none)
            ..dtr = SerialPortDtr.on
            ..rts = SerialPortRts.on;
      _port!.config = config;
      config.dispose();

      _reader = SerialPortReader(_port!);
      _dataSub = _reader!.stream.listen(
        (data) => _dataController.add(data),
        onError: (e) => _log.w('Serial read error: $e'),
      );

      _connected = true;
      _log.i('Serial connected: $_portName');
      return true;
    } catch (e) {
      _log.e('Serial connect failed: $e');
      _connected = false;
      _port?.dispose();
      _port = null;
      return false;
    }
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    await _dataSub?.cancel();
    _dataSub = null;
    _reader?.close();
    _reader = null;
    try {
      _port?.close();
      _port?.dispose();
    } catch (_) {}
    _port = null;
    _log.i('Serial disconnected: $_portName');
  }

  @override
  Future<void> send(Uint8List data) async {
    if (!_connected || _port == null) throw StateError('Not connected');
    _port!.write(data);
  }

  @override
  Future<void> dispose() async {
    await disconnect();
    await _dataController.close();
  }

  /// List all available serial/COM ports on this machine.
  static Future<List<RadioDevice>> listDevices() async {
    try {
      final portNames = SerialPort.availablePorts;
      final devices = <RadioDevice>[];

      for (final name in portNames) {
        String label = name;
        try {
          final p = SerialPort(name);
          final desc = p.description;
          final manufacturer = p.manufacturer;
          p.dispose();

          if (desc != null && desc.isNotEmpty) {
            label = '$name — $desc';
          } else if (manufacturer != null && manufacturer.isNotEmpty) {
            label = '$name — $manufacturer';
          }
        } catch (_) {}

        devices.add(
          RadioDevice(id: name, name: label, type: RadioDeviceType.serial),
        );
      }

      _log.i('Found ${devices.length} serial port(s): ${portNames.join(", ")}');
      return devices;
    } catch (e) {
      _log.w('Serial port enumeration failed: $e');
      return [];
    }
  }

  /// Create a serial transport for the given port name (e.g. "COM3").
  static Future<SerialTransport?> fromDeviceId(String portName) async {
    return SerialTransport(portName);
  }
}
