// Conditional export for the USB serial transport.
//
// Routing logic:
//   dart.library.ffi available  → native platforms (Android, Windows, Linux, macOS, iOS)
//                                  → usb_transport_android.dart
//                                    (runtime Platform.isAndroid guard prevents
//                                     execution on non-Android native targets)
//   dart.library.ffi unavailable → web
//                                  → usb_transport_stub.dart (no-op)
//
// The Android implementation uses the `usb_serial` package (Android USB Host
// API). Desktop serial ports are handled separately by serial_transport.dart
// via flutter_libserialport.
export 'usb_transport_stub.dart'
    if (dart.library.ffi) 'usb_transport_android.dart';
