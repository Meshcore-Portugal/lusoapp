// Conditional import selector for the Windows BLE bridge.
//
// On native platforms (dart.library.io) the real WinBleBridge delegates to
// FlutterBluePlusWindows (WinRT via win_ble).  On web the stub is loaded;
// all its methods throw, but call sites are always guarded by
// `!kIsWeb && Platform.isWindows` so they are never reached on web.
export 'win_ble_bridge_stub.dart'
    if (dart.library.io) 'win_ble_bridge_native.dart';
