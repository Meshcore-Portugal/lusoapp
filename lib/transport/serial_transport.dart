// dart.library.ffi  → native desktop/mobile (Windows, Linux, Android, iOS)
// dart.library.js_interop → web browsers (Chrome/Edge Web Serial API)
export 'serial_transport_stub.dart'
    if (dart.library.ffi) 'serial_transport_native.dart'
    if (dart.library.js_interop) 'serial_transport_web.dart';
