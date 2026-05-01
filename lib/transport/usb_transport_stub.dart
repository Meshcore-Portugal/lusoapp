// Stub implementation of UsbTransport for platforms that do not support the
// Android USB Host API (web, iOS).
//
// Selected by the conditional export in usb_transport.dart when
// dart.library.ffi is NOT available (i.e., web builds). All methods are no-ops
// or return empty/false so the rest of the app compiles and runs without
// branching on the platform.

import 'dart:typed_data';

import 'radio_transport.dart';

/// No-op USB transport for platforms where USB Host is not supported.
///
/// This stub is compiled on web and iOS. It satisfies the [RadioTransport]
/// interface so callers need no platform guards beyond checking
/// [UsbTransport.listDevices] returning an empty list.
class UsbTransport implements RadioTransport {
  UsbTransport();

  @override
  bool get usesFraming => false;

  @override
  String get displayName => 'USB (not supported)';

  @override
  bool get isConnected => false;

  @override
  Stream<void> get connectionLost => const Stream.empty();

  @override
  Stream<Uint8List> get dataStream => const Stream.empty();

  @override
  Future<bool> connect() async => false;

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> send(Uint8List data) async =>
      throw UnsupportedError('USB not supported on this platform');

  @override
  Future<void> dispose() async {}

  /// Always returns an empty list — USB Host is unavailable on this platform.
  static Future<List<RadioDevice>> listDevices() async => [];

  /// Always returns null — USB Host is unavailable on this platform.
  static Future<UsbTransport?> fromDeviceId(String _) async => null;
}
