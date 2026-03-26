import 'dart:async';
import 'dart:typed_data';

import 'package:logger/logger.dart';

import '../protocol/kiss.dart';
import 'radio_transport.dart';

final _log = Logger(printer: SimplePrinter(printTime: false));

/// A [RadioTransport] decorator that adds KISS TNC framing on top of any
/// underlying transport.
///
/// Outbound: each [send] call wraps the payload in a KISS data frame
/// (command byte 0x00, port 0) before passing it to the inner transport.
///
/// Inbound: raw bytes from the inner transport's [dataStream] are fed through
/// a [KissFrameAccumulator]; complete KISS frames are decoded and their data
/// payloads are forwarded to callers.
class KissTransport implements RadioTransport {
  KissTransport(this._inner);

  final RadioTransport _inner;
  final _accumulator = KissFrameAccumulator();
  final _dataController = StreamController<Uint8List>.broadcast();

  @override
  bool get usesFraming => true;
  StreamSubscription<Uint8List>? _innerSub;

  @override
  String get displayName => '${_inner.displayName} [KISS]';

  @override
  bool get isConnected => _inner.isConnected;

  @override
  Stream<Uint8List> get dataStream => _dataController.stream;

  @override
  Future<bool> connect() async {
    final ok = await _inner.connect();
    if (!ok) return false;
    _innerSub = _inner.dataStream.listen(
      _onRawData,
      onError: (e) => _log.w('KissTransport inner stream error: $e'),
    );
    return true;
  }

  @override
  Future<void> disconnect() async {
    await _innerSub?.cancel();
    _innerSub = null;
    _accumulator.reset();
    await _inner.disconnect();
  }

  @override
  Future<void> send(Uint8List data) async {
    // Wrap with KISS framing: command byte 0x00 (port 0, data frame)
    final kissFrame = Kiss.encode(0x00, data);
    await _inner.send(kissFrame);
  }

  @override
  Future<void> dispose() async {
    await disconnect();
    await _dataController.close();
    await _inner.dispose();
  }

  void _onRawData(Uint8List data) {
    final rawFrames = _accumulator.feed(data);
    for (final rawFrame in rawFrames) {
      final kissFrame = Kiss.decode(rawFrame);
      if (kissFrame == null) continue;
      if (!kissFrame.isData) {
        _log.d(
          'KISS: ignoring non-data frame (command=0x${kissFrame.command.toRadixString(16)})',
        );
        continue;
      }
      _dataController.add(kissFrame.data);
    }
  }
}
