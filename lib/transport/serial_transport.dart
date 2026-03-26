// Conditionally import the native (FFI-based) or web stub implementation.
// dart.library.ffi is available on Windows/macOS/Linux/Android/iOS but NOT on web.
export 'serial_transport_stub.dart'
    if (dart.library.ffi) 'serial_transport_native.dart';
