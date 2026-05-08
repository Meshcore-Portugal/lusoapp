import 'dart:async';
import 'dart:typed_data';

import 'radio_transport.dart';

/// Web stub — dart:ffi and flutter_libserialport are not available on web.
/// Serial ports are always unavailable; all methods are no-ops.
class SerialTransport implements RadioTransport {
  SerialTransport(String portName, {String? displayLabel})
    : _displayLabel = displayLabel ?? portName;

  final String _displayLabel;

  @override
  String get displayName => 'Serial: $_displayLabel';

  @override
  bool get isConnected => false;

  @override
  bool get usesFraming => true;

  @override
  Stream<Uint8List> get dataStream => const Stream.empty();

  @override
  Stream<void> get connectionLost => const Stream.empty();

  @override
  Future<bool> connect() async => false;

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> send(Uint8List data) async {
    throw UnsupportedError('Serial transport not available on web');
  }

  @override
  Future<void> dispose() async {}

  static Future<List<RadioDevice>> listDevices() async => [];

  static Future<SerialTransport?> fromDeviceId(String portName) async => null;

  /// Always false on non-web platforms — port registry is a web-only concept.
  static bool isRegistered(String portId) => false;
}
