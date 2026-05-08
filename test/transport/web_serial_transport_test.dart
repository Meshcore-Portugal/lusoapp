/// Tests for the Web Serial transport layer.
///
/// The transport implementation is selected at compile time by the conditional
/// export in serial_transport.dart:
///
///   • dart.library.ffi  (native)  → serial_transport_native.dart
///   • dart.library.html (web)     → web_serial_transport.dart
///   • fallback                    → serial_transport_stub.dart
///
/// This file runs on the native test runner (flutter test), so
/// [SerialTransport] resolves to the native implementation.
/// Web-specific behaviour (actual port registry, browser picker) requires a
/// real browser context and should be tested with:
///
///   flutter test --platform chrome test/transport/web_serial_transport_test.dart
///
/// The tests below focus on the public API contract that is shared across all
/// three implementations, plus the native-specific stubs for web-only methods.

import 'package:flutter_test/flutter_test.dart';
import 'package:lusoapp/transport/serial_transport.dart';

void main() {
  // ---------------------------------------------------------------------------
  // isRegistered — present on all three implementations.
  // On native/stub it always returns false; on web it checks the in-memory
  // port registry populated by listDevices().
  // ---------------------------------------------------------------------------

  group('SerialTransport.isRegistered', () {
    test('returns false for an unknown port ID on native', () {
      /// On native the port registry does not exist — this is a web-only
      /// concept. The native stub always returns false regardless of input.
      expect(SerialTransport.isRegistered('webserial:0'), isFalse);
    });

    test('returns false for an empty string', () {
      expect(SerialTransport.isRegistered(''), isFalse);
    });

    test('returns false for an arbitrary non-web ID', () {
      /// Native serial port names (COM3, /dev/ttyUSB0) are never registered
      /// in the JS registry, so isRegistered should always be false for them.
      expect(SerialTransport.isRegistered('COM3'), isFalse);
      expect(SerialTransport.isRegistered('/dev/ttyUSB0'), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // fromDeviceId — factory that creates a transport from a stored device ID.
  // Native: always returns a non-null SerialTransport (port existence is
  //         checked lazily at connect() time, not at creation).
  // Web stub: always returns null (no port registry, no JS interop).
  // Web real: returns null if the port ID is not in the registry.
  // ---------------------------------------------------------------------------

  group('SerialTransport.fromDeviceId', () {
    test('returns non-null for any port name on native', () async {
      /// Native serial transport wraps the port name string and defers
      /// existence checks until connect() is called. An invalid name is
      /// allowed here — connect() will fail, not fromDeviceId().
      final transport = await SerialTransport.fromDeviceId('COM_DOES_NOT_EXIST');
      expect(transport, isNotNull);
      // Clean up without connecting.
      await transport!.dispose();
    });

    test('displayName includes the port identifier', () async {
      final transport = await SerialTransport.fromDeviceId('COM99');
      expect(transport, isNotNull);
      expect(transport!.displayName, contains('COM99'));
      await transport.dispose();
    });

    test('isConnected is false before connect()', () async {
      final transport = await SerialTransport.fromDeviceId('COM99');
      expect(transport, isNotNull);
      expect(transport!.isConnected, isFalse);
      await transport.dispose();
    });

    test('usesFraming is true (serial always uses length framing)', () async {
      final transport = await SerialTransport.fromDeviceId('COM99');
      expect(transport, isNotNull);
      expect(transport!.usesFraming, isTrue);
      await transport.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // listDevices — enumerates available ports.
  // On native: enumerates real COM/tty ports; returns [] on mobile.
  // On web stub: always returns [].
  // On web real: calls requestPort() (browser picker — untestable headlessly).
  // ---------------------------------------------------------------------------

  group('SerialTransport.listDevices', () {
    test('returns a List (may be empty depending on test environment)', () async {
      /// Does not assert a specific count — the number of serial ports on the
      /// CI machine is unknown. We just verify the return type and that no
      /// exception is thrown.
      final devices = await SerialTransport.listDevices();
      expect(devices, isA<List>());
    });

    test('every returned device has a non-empty id and name', () async {
      final devices = await SerialTransport.listDevices();
      for (final d in devices) {
        expect(d.id, isNotEmpty);
        expect(d.name, isNotEmpty);
      }
    });
  });
}
