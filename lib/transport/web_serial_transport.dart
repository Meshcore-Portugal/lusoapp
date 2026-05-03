import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'radio_transport.dart';

// ---------------------------------------------------------------------------
// Web Serial API — JS interop extension types.
// Spec: https://developer.mozilla.org/en-US/docs/Web/API/Web_Serial_API
// Supported: Chrome 89+, Edge 89+ on desktop. Not available in Firefox/Safari.
// ---------------------------------------------------------------------------

/// Top-level navigator object — entry point to the Web Serial API.
@JS('navigator')
external _Navigator get _navigator;

@JS()
extension type _Navigator(JSObject _) implements JSObject {
  external _Serial? get serial;
}

/// navigator.serial — manages USB/serial port access in the browser.
@JS()
extension type _Serial(JSObject _) implements JSObject {
  /// Returns previously granted ports without user interaction.
  external JSPromise<JSArray<JSObject>> getPorts();

  /// Opens the browser's port-picker dialog and returns the selected port.
  external JSPromise<JSObject> requestPort([JSObject? options]);
}

/// A single serial port handle returned by the browser.
@JS()
extension type _SerialPort(JSObject _) implements JSObject {
  /// Opens the port with the given configuration.
  /// Returns `Promise<undefined>` — typed as `JSAny?` so dart2js accepts null.
  external JSPromise<JSAny?> open(JSObject options);

  /// Closes the port.
  /// Returns `Promise<undefined>` — typed as `JSAny?` so dart2js accepts null.
  external JSPromise<JSAny?> close();

  /// Returns synchronous hardware metadata (vendor/product IDs).
  external _SerialPortInfo getInfo();

  external _ReadableStream get readable;
  external _WritableStream get writable;
}

/// JS object literal passed to SerialPort.open().
@JS()
extension type _SerialPortOpenOptions._(JSObject _) implements JSObject {
  external factory _SerialPortOpenOptions({
    int baudRate,
    int dataBits,
    int stopBits,
    String parity,
    String flowControl,
  });
}

/// USB vendor/product identifiers for a serial port (may be null for non-USB ports).
@JS()
extension type _SerialPortInfo(JSObject _) implements JSObject {
  external int? get usbVendorId;
  external int? get usbProductId;
}

/// Incoming byte stream from the serial port.
@JS()
extension type _ReadableStream(JSObject _) implements JSObject {
  external _ReadableStreamDefaultReader getReader();
}

@JS()
extension type _ReadableStreamDefaultReader(JSObject _) implements JSObject {
  external JSPromise<JSObject> read();

  /// Cancels the stream, causing the pending read() to reject.
  /// Returns `Promise<undefined>` — typed as `JSAny?` so dart2js accepts null.
  external JSPromise<JSAny?> cancel([JSAny? reason]);

  external void releaseLock();
}

/// Outgoing byte stream to the serial port.
@JS()
extension type _WritableStream(JSObject _) implements JSObject {
  external _WritableStreamDefaultWriter getWriter();
}

@JS()
extension type _WritableStreamDefaultWriter(JSObject _) implements JSObject {
  /// Returns `Promise<undefined>` — typed as `JSAny?` so dart2js accepts null.
  external JSPromise<JSAny?> write(JSUint8Array chunk);
  external void releaseLock();
}

// ---------------------------------------------------------------------------
// SerialTransport — web implementation via the browser's Web Serial API.
// The class name matches the native and stub counterparts so that
// serial_transport.dart's conditional export works without any callers
// needing to know which implementation is loaded.
// ---------------------------------------------------------------------------

/// Web Serial transport for communicating with a MeshCore radio over USB.
///
/// Call [listDevices] to prompt the user to select a port via the browser's
/// built-in picker. Then use [fromDeviceId] to create a transport instance
/// for the selected port and call [connect].
class SerialTransport implements RadioTransport {
  SerialTransport._({
    required _SerialPort port,
    String? displayLabel,
  })  : _port = port,
        _displayLabel = displayLabel ?? '';

  final _SerialPort _port;
  final String _displayLabel;

  final _dataController = StreamController<Uint8List>.broadcast();
  final _connectionLostController = StreamController<void>.broadcast();

  _ReadableStreamDefaultReader? _reader;

  /// Held for the full connection lifetime so concurrent send() calls never
  /// race on getWriter(). The WritableStream lock is released in disconnect().
  _WritableStreamDefaultWriter? _writer;

  /// Completer resolved by the read loop once it has released the reader lock.
  /// disconnect() awaits this before closing the port.
  Completer<void>? _readLoopDone;

  bool _connected = false;

  /// True when disconnect() was called intentionally; suppresses connectionLost.
  bool _userDisconnected = false;

  // Static registry mapping generated string IDs to live JS SerialPort objects.
  // Required because RadioDevice.id is a String but SerialPort is a JS handle.
  // Entries persist for the lifetime of the app so auto-reconnect can reuse them.
  static final _portRegistry = <String, _SerialPort>{};
  static var _portCounter = 0;

  // ---------------------------------------------------------------------------
  // RadioTransport interface
  // ---------------------------------------------------------------------------

  @override
  String get displayName => 'USB: $_displayLabel';

  @override
  bool get isConnected => _connected;

  /// Serial/USB connections always use [dir][len_lsb][len_msb][payload] framing.
  @override
  bool get usesFraming => true;

  @override
  Stream<Uint8List> get dataStream => _dataController.stream;

  @override
  Stream<void> get connectionLost => _connectionLostController.stream;

  /// Opens the port at 115200 8N1, acquires a persistent writer, and starts
  /// the background read loop.
  @override
  Future<bool> connect() async {
    try {
      // 115200 8N1 matches the MeshCore radio UART default configuration.
      await _port
          .open(_SerialPortOpenOptions(
            baudRate: 115200,
            dataBits: 8,
            stopBits: 1,
            parity: 'none',
            flowControl: 'none',
          ))
          .toDart;

      // Acquire the writer once and hold it for the connection lifetime.
      // This prevents "WritableStream is locked" errors when the protocol
      // layer fires multiple unawaited sends concurrently (e.g. requestStats
      // calls during _fetchInitialData). Concurrent send() calls are safe
      // because JS WritableStreamDefaultWriter.write() internally queues.
      _writer = _port.writable.getWriter();

      _connected = true;
      _startReadLoop();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Cancels the read loop, releases the writer lock, and closes the port.
  @override
  Future<void> disconnect() async {
    _userDisconnected = true;
    _connected = false;

    // Cancelling the reader unblocks the pending read() call in the loop.
    try {
      await _reader?.cancel().toDart;
    } catch (_) {}

    // Wait for the loop to call releaseLock() before touching the port.
    await _readLoopDone?.future;

    // Release the writer lock before closing — port.close() requires both
    // the readable and writable streams to be fully unlocked first.
    try {
      _writer?.releaseLock();
    } catch (_) {}
    _writer = null;

    try {
      await _port.close().toDart;
    } catch (_) {}
  }

  /// Sends [data] to the radio using the persistent writer acquired in [connect].
  ///
  /// WritableStreamDefaultWriter.write() queues internally, so concurrent
  /// calls are safe — no external locking is required.
  @override
  Future<void> send(Uint8List data) async {
    final w = _writer;
    if (w == null) throw StateError('WebSerialTransport: send called while disconnected');
    await w.write(data.toJS).toDart;
  }

  @override
  Future<void> dispose() async {
    await disconnect();
    await _dataController.close();
    await _connectionLostController.close();
  }

  // ---------------------------------------------------------------------------
  // Static factory methods
  // ---------------------------------------------------------------------------

  /// Opens the browser's USB port-picker dialog and returns the chosen port
  /// as a [RadioDevice].
  ///
  /// Returns an empty list if the user cancels, Web Serial is unavailable
  /// (non-Chromium browsers), or the browser denies access.
  static Future<List<RadioDevice>> listDevices() async {
    final serial = _navigator.serial;
    if (serial == null) return [];
    try {
      final jsPort = await serial.requestPort().toDart;
      final port = jsPort as _SerialPort;
      return [_registerPort(port)];
    } catch (_) {
      return [];
    }
  }

  /// Returns true if [portId] is still held in the in-memory port registry.
  ///
  /// The registry is cleared on every page refresh (it lives only in JS heap).
  /// Use this before attempting a reconnect so the UI can show a targeted
  /// "port expired — please scan again" message instead of a generic error.
  static bool isRegistered(String portId) => _portRegistry.containsKey(portId);

  /// Returns a [SerialTransport] for a port previously registered by [listDevices].
  ///
  /// Returns null if [portId] is not in the registry (e.g. app was restarted).
  static Future<SerialTransport?> fromDeviceId(String portId) async {
    final port = _portRegistry[portId];
    if (port == null) return null;
    final label = _formatPortLabel(port.getInfo());
    return SerialTransport._(port: port, displayLabel: label);
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Registers [port] with a generated ID and returns a [RadioDevice] for the UI.
  static RadioDevice _registerPort(_SerialPort port) {
    final id = 'webserial:${_portCounter++}';
    _portRegistry[id] = port;
    return RadioDevice(
      id: id,
      name: _formatPortLabel(port.getInfo()),
      type: RadioDeviceType.serial,
    );
  }

  /// Builds a human-readable label from USB vendor/product IDs.
  static String _formatPortLabel(_SerialPortInfo info) {
    final vid = info.usbVendorId?.toRadixString(16).padLeft(4, '0') ?? '????';
    final pid = info.usbProductId?.toRadixString(16).padLeft(4, '0') ?? '????';
    return 'USB Serial ($vid:$pid)';
  }

  /// Acquires the reader lock and launches the async read loop.
  void _startReadLoop() {
    _readLoopDone = Completer<void>();
    _reader = _port.readable.getReader();
    _runReadLoop(_reader!, _readLoopDone!);
  }

  /// Continuously reads chunks from the port and emits them on [_dataController].
  ///
  /// If the stream ends unexpectedly (not from a [disconnect] call) a null event
  /// is added to [_connectionLostController] so the notifier can auto-reconnect.
  Future<void> _runReadLoop(
    _ReadableStreamDefaultReader reader,
    Completer<void> done,
  ) async {
    try {
      while (_connected) {
        final resultObj = await reader.read().toDart;
        final result = resultObj as _ReadResult;
        if (result.done) break;
        final value = result.value;
        if (value != null && !_dataController.isClosed) {
          _dataController.add(value.toDart);
        }
      }
    } catch (_) {
      // Unexpected error — signal connection loss for auto-reconnect.
      if (!_userDisconnected && !_connectionLostController.isClosed) {
        _connectionLostController.add(null);
      }
    } finally {
      reader.releaseLock();
      done.complete();
    }
  }
}

// ---------------------------------------------------------------------------
// _ReadResult — local extension type for the {value, done} object from read().
// Declared here (not in the top-level interop block) because it is only used
// inside _runReadLoop after the cast from JSObject.
// ---------------------------------------------------------------------------

@JS()
extension type _ReadResult(JSObject _) implements JSObject {
  external JSUint8Array? get value;
  external bool get done;
}
