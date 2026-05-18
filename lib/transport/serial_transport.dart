// Conditionally import the correct serial transport implementation.
//
// dart.library.ffi  — true on Windows/macOS/Linux/Android/iOS  → native (flutter_libserialport)
// dart.library.html — true on web (Chrome/Edge)                 → Web Serial API
// fallback          — stub with no-op methods (safety net)
export 'serial_transport_stub.dart'
    if (dart.library.ffi) 'serial_transport_native.dart'
    if (dart.library.html) 'web_serial_transport.dart';
