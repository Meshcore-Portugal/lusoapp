// Web Serial transport — implements [RadioTransport] for Chrome and Edge
// using the browser's Web Serial API (navigator.serial).
//
// The Web Serial API is not yet part of the stable package:web surface, so
// all required types are declared here as dart:js_interop extension types:
//   _Serial         — navigator.serial (getPorts / requestPort)
//   _SerialPort     — an individual port (open / close / readable / writable)
//   _SerialOptions  — open() configuration (baudRate)
//   _SerialPortInfo — vendor/product IDs returned by getInfo()
//   _ReadableStream / _WritableStream — WHATWG stream handles
//   _StreamReader / _StreamWriter     — locked reader/writer for I/O
//   _ReadResult     — {done, value} object from reader.read()
//
// Port-picker flow (Chrome security model):
//   requestPort() must originate from a user gesture — it opens the browser's
//   native port-selection dialog. The chosen JS port object is stored in the
//   module-level [_portRegistry] map under a generated ID so that
//   fromDeviceId() can reconstruct the transport without a second dialog.
//
// Reconnect flow for previously-authorized ports:
//   listDevices() calls getPorts() which returns ports the user has already
//   granted access to in a previous session. These are registered under
//   'auth-N' IDs for stable lookup by fromDeviceId().

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:logger/logger.dart';
import 'package:web/web.dart' as web;

import 'radio_transport.dart';

final _log = Logger(printer: SimplePrinter(printTime: false));

// ---------------------------------------------------------------------------
// JS interop extension types for the Web Serial API
// ---------------------------------------------------------------------------

/// Extends Navigator to expose the `serial` property (Web Serial API entry point).
extension type _NavigatorWithSerial._(JSObject _) implements JSObject {
  external _Serial get serial;
}

/// navigator.serial — lists authorized ports and requests new ones.
extension type _Serial._(JSObject _) implements JSObject {
  /// Returns ports the browser has already authorized (no dialog shown).
  external JSPromise<JSArray<_SerialPort>> getPorts();

  /// Shows the browser port-picker. Requires a user gesture.
  external JSPromise<_SerialPort> requestPort();
}

/// A single serial port returned by getPorts() or requestPort().
extension type _SerialPort._(JSObject _) implements JSObject {
  /// Opens the port with the given options (e.g. baudRate: 115200).
  external JSPromise<JSAny?> open(_SerialOptions options);

  /// Closes the port, releasing hardware resources.
  external JSPromise<JSAny?> close();

  /// WHATWG ReadableStream for incoming bytes.
  external _ReadableStream get readable;

  /// WHATWG WritableStream for outgoing bytes.
  external _WritableStream get writable;

  /// Returns USB vendor/product IDs for labelling the device.
  external _SerialPortInfo getInfo();
}

/// Options passed to SerialPort.open() — only baudRate is required here.
extension type _SerialOptions._(JSObject _) implements JSObject {
  external factory _SerialOptions({int baudRate});
}

/// USB identification returned by SerialPort.getInfo().
extension type _SerialPortInfo._(JSObject _) implements JSObject {
  external int? get usbVendorId;
  external int? get usbProductId;
}

/// Thin wrapper around the WHATWG ReadableStream to expose getReader().
extension type _ReadableStream._(JSObject _) implements JSObject {
  /// Locks the stream and returns an exclusive reader.
  external _StreamReader getReader();
}

/// Thin wrapper around the WHATWG WritableStream to expose getWriter().
extension type _WritableStream._(JSObject _) implements JSObject {
  /// Locks the stream and returns an exclusive writer.
  external _StreamWriter getWriter();
}

/// Locked reader for a ReadableStream — yields {done, value} results.
extension type _StreamReader._(JSObject _) implements JSObject {
  /// Reads the next chunk. Resolves when data arrives or stream ends.
  external JSPromise<_ReadResult> read();

  /// Signals that the consumer is done; causes pending read() to resolve as done.
  external JSPromise<JSAny?> cancel([JSAny? reason]);

  /// Releases the lock, allowing the stream to be read by another reader.
  external void releaseLock();
}

/// Result object from _StreamReader.read(): {done: bool, value: Uint8Array?}.
extension type _ReadResult._(JSObject _) implements JSObject {
  external bool get done;
  external JSAny? get value;
}

/// Locked writer for a WritableStream — accepts chunks (Uint8Array) to send.
extension type _StreamWriter._(JSObject _) implements JSObject {
  /// Queues a chunk for sending. Returns a Promise that resolves when accepted.
  external JSPromise<JSAny?> write(JSAny? chunk);

  /// Releases the writer lock so the stream can accept another writer.
  external void releaseLock();
}

// ---------------------------------------------------------------------------
// Port registry
// ---------------------------------------------------------------------------

/// In-session map of generated port ID → JS SerialPort object.
///
/// Bridges the gap between requestPort() (which returns a JS object) and
/// fromDeviceId() (which needs that same object later). Cleared on page reload.
final _portRegistry = <String, _SerialPort>{};
var _portIdCounter = 0;

/// Convenience getter for the Web Serial API entry point.
_Serial get _serial =>
    (web.window.navigator as _NavigatorWithSerial).serial;

// ---------------------------------------------------------------------------
// Transport implementation
// ---------------------------------------------------------------------------

/// Serial transport for web browsers (Chrome / Edge) using the Web Serial API.
///
/// Two discovery paths are supported:
/// - [listDevices] — surfaces ports already authorized in a previous session
///   via navigator.serial.getPorts(); no dialog is shown.
/// - [requestPort] — triggers the browser port-picker dialog; must be called
///   from a user-gesture handler (e.g. button onPressed).
///
/// Once a [RadioDevice] is obtained by either path, [fromDeviceId] reconstructs
/// the transport using the in-session [_portRegistry] or by re-calling getPorts().
///
/// Reads are driven by an async pump [_pumpReads] that loops on reader.read()
/// and pushes incoming Uint8Array chunks into [dataStream]. The pump exits when
/// the reader is cancelled (e.g. during [disconnect]).
class SerialTransport implements RadioTransport {
  /// Private constructor — use [fromDeviceId] or [requestPort] to create.
  SerialTransport._(this._port, this._label);

  final _SerialPort _port;
  final String _label;

  /// Locked reader — active while connected; null otherwise.
  _StreamReader? _reader;

  /// Locked writer — active while connected; null otherwise.
  _StreamWriter? _writer;

  final _dataController = StreamController<Uint8List>.broadcast();
  bool _connected = false;

  // The MeshCore companion protocol uses direction+length framing.
  @override
  bool get usesFraming => true;

  @override
  String get displayName => 'USB: $_label';

  @override
  bool get isConnected => _connected;

  /// Web Serial does not fire disconnect events; returns an empty stream.
  @override
  Stream<void> get connectionLost => const Stream.empty();

  @override
  Stream<Uint8List> get dataStream => _dataController.stream;

  /// Opens the port at 115200 baud, locks the readable/writable streams,
  /// and starts the read pump.
  @override
  Future<bool> connect() async {
    try {
      await _port.open(_SerialOptions(baudRate: 115200)).toDart;

      // Lock both streams immediately so no other consumer can steal them.
      _reader = _port.readable.getReader();
      _writer = _port.writable.getWriter();
      _connected = true;

      // Start the read loop in the background; it feeds _dataController.
      _pumpReads();

      _log.i('Web serial connected: $_label');
      return true;
    } catch (e) {
      _log.e('Web serial connect failed: $e');
      return false;
    }
  }

  /// Continuously reads from the locked ReadableStream and forwards each
  /// Uint8Array chunk to [dataStream].
  ///
  /// Exits when the stream signals done or when [disconnect] calls cancel(),
  /// which causes the awaited read() to throw. The finally block always
  /// releases the reader lock so the port can be closed cleanly.
  void _pumpReads() async {
    final reader = _reader;
    if (reader == null) return;
    try {
      while (_connected) {
        final result = await reader.read().toDart;
        if (result.done) break;
        final value = result.value;
        if (value != null && !_dataController.isClosed) {
          // value is a JS Uint8Array — convert to Dart Uint8List.
          _dataController.add((value as JSUint8Array).toDart);
        }
      }
    } catch (_) {
      // Thrown when the reader is cancelled by disconnect() — expected path.
    } finally {
      try {
        reader.releaseLock();
      } catch (_) {}
    }
  }

  /// Cancels the read pump, releases reader/writer locks, and closes the port.
  ///
  /// cancel() on the reader causes the blocked read() in [_pumpReads] to throw,
  /// which exits the pump and triggers releaseLock() in its finally block.
  @override
  Future<void> disconnect() async {
    _connected = false;
    final reader = _reader;
    final writer = _writer;
    _reader = null;
    _writer = null;
    try {
      if (reader != null) {
        await reader.cancel().toDart; // unblocks _pumpReads
        reader.releaseLock(); // belt-and-suspenders; _pumpReads also does this
      }
      writer?.releaseLock();
      await _port.close().toDart;
    } catch (e) {
      _log.w('Web serial disconnect error: $e');
    }
    _log.i('Web serial disconnected: $_label');
  }

  /// Sends [data] by writing a JS Uint8Array to the locked WritableStream.
  @override
  Future<void> send(Uint8List data) async {
    final writer = _writer;
    if (!_connected || writer == null) throw StateError('Not connected');
    // data.toJS converts Dart Uint8List → JS Uint8Array (zero-copy on V8).
    await writer.write(data.toJS).toDart;
  }

  @override
  Future<void> dispose() async {
    await disconnect();
    await _dataController.close();
  }

  // ---------------------------------------------------------------------------
  // Static discovery helpers
  // ---------------------------------------------------------------------------

  /// Returns [RadioDevice] entries for each serial port that the browser has
  /// already authorized. Registers them in [_portRegistry] under 'auth-N' IDs.
  ///
  /// Returns an empty list on first use (no ports authorized yet) or when the
  /// Web Serial API is unavailable.
  static Future<List<RadioDevice>> listDevices() async {
    try {
      final ports = (await _serial.getPorts().toDart).toDart;
      final result = <RadioDevice>[];
      for (var i = 0; i < ports.length; i++) {
        final id = 'auth-$i';
        _portRegistry[id] = ports[i]; // store for fromDeviceId lookup
        result.add(
          RadioDevice(
            id: id,
            name: _portLabel(ports[i].getInfo(), i),
            type: RadioDeviceType.serial,
          ),
        );
      }
      return result;
    } catch (e) {
      _log.w('Web serial getPorts failed: $e');
      return [];
    }
  }

  /// Shows the browser port-picker dialog and returns the chosen device.
  ///
  /// The JS port object is stored in [_portRegistry] so [fromDeviceId] can
  /// reconnect without a second dialog. Returns null if the user cancels.
  ///
  /// Must be called from a user gesture (e.g. a button tap).
  static Future<RadioDevice?> requestPort() async {
    try {
      final port = await _serial.requestPort().toDart;
      final id = 'req-${_portIdCounter++}';
      _portRegistry[id] = port; // register for fromDeviceId
      return RadioDevice(
        id: id,
        name: _portLabel(port.getInfo(), _portIdCounter - 1),
        type: RadioDeviceType.serial,
      );
    } catch (e) {
      _log.w('Web serial requestPort cancelled: $e');
      return null;
    }
  }

  /// Reconstructs a [SerialTransport] for a previously discovered device.
  ///
  /// Lookup order:
  ///   1. In-session registry (covers ports obtained via [requestPort]).
  ///   2. navigator.serial.getPorts() by index (covers [listDevices] reconnect).
  static Future<SerialTransport?> fromDeviceId(String deviceId) async {
    // 1. In-session registry — fastest path, covers the same-session flow.
    final cached = _portRegistry[deviceId];
    if (cached != null) return SerialTransport._(cached, deviceId);

    // 2. Re-enumerate authorized ports and match by index (auth-N).
    try {
      final ports = (await _serial.getPorts().toDart).toDart;
      final idxStr = deviceId.startsWith('auth-')
          ? deviceId.substring(5)
          : deviceId;
      final idx = int.tryParse(idxStr);
      if (idx != null && idx < ports.length) {
        return SerialTransport._(ports[idx], deviceId);
      }
    } catch (_) {}
    return null;
  }

  /// Formats a device label from USB vendor/product IDs.
  /// Falls back to 'Serial Port N' when IDs are unavailable.
  static String _portLabel(_SerialPortInfo info, int fallback) {
    final vid = info.usbVendorId;
    final pid = info.usbProductId;
    return vid != null
        ? 'USB ${_hex(vid)}:${_hex(pid ?? 0)}'
        : 'Serial Port $fallback';
  }

  static String _hex(int v) =>
      '0x${v.toRadixString(16).padLeft(4, '0').toUpperCase()}';
}
