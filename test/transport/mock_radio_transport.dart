import 'dart:async';
import 'dart:typed_data';

import 'package:lusoapp/transport/radio_transport.dart';

/// A controllable [RadioTransport] test double.
///
/// - [sentData] records every call to [send].
/// - [injectData] pushes bytes into [dataStream] as if received from radio.
/// - [injectConnectionLost] fires a connection-lost event.
/// - [connectResult] controls what [connect] returns.
class MockRadioTransport implements RadioTransport {
  MockRadioTransport({
    this.connectResult = true,
    bool usesFraming = true,
    String displayName = 'Mock Transport',
  }) : _usesFraming = usesFraming,
       _displayName = displayName;

  final bool connectResult;
  final bool _usesFraming;
  final String _displayName;

  bool _connected = false;
  bool _disposed = false;

  final _dataController = StreamController<Uint8List>.broadcast();
  final _connectionLostController = StreamController<void>.broadcast();

  /// All data passed to [send], in order.
  final List<Uint8List> sentData = [];

  @override
  String get displayName => _displayName;

  @override
  bool get isConnected => _connected;

  @override
  bool get usesFraming => _usesFraming;

  @override
  Stream<Uint8List> get dataStream => _dataController.stream;

  @override
  Stream<void> get connectionLost => _connectionLostController.stream;

  @override
  Future<bool> connect() async {
    _connected = connectResult;
    return connectResult;
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
  }

  @override
  Future<void> send(Uint8List data) async {
    sentData.add(Uint8List.fromList(data));
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await _dataController.close();
    await _connectionLostController.close();
  }

  /// Whether [dispose] has been called.
  bool get isDisposed => _disposed;

  /// Push bytes into [dataStream] as if received from the radio.
  void injectData(Uint8List data) {
    _dataController.add(data);
  }

  /// Fire a connection-lost event.
  void injectConnectionLost() {
    _connectionLostController.add(null);
  }
}
