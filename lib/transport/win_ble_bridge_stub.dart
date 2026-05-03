// Web stub for WinBleBridge.
//
// Imported when dart.library.io is unavailable (Flutter web build).
// Every method throws — call sites are guarded by `!kIsWeb && Platform.isWindows`
// so this code is never reached at runtime.
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'radio_transport.dart';

class WinBleBridge {
  WinBleBridge._();

  /// Adapter state stream — not available on web.
  static Stream<BluetoothAdapterState> get adapterState =>
      throw UnsupportedError('WinBleBridge is not available on web');

  /// Synchronous adapter state — not available on web.
  static BluetoothAdapterState get adapterStateNow =>
      throw UnsupportedError('WinBleBridge is not available on web');

  /// BLE scan stream — not available on web.
  static Stream<RadioDevice> scan({
    Duration timeout = const Duration(seconds: 10),
  }) =>
      throw UnsupportedError('WinBleBridge is not available on web');

  /// Create transport — not available on web.
  static RadioTransport createTransport(String deviceId) =>
      throw UnsupportedError('WinBleBridge is not available on web');
}
