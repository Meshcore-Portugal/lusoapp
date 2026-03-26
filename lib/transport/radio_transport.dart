import 'dart:async';
import 'dart:typed_data';

/// Abstract transport interface for communicating with a MeshCore radio.
///
/// Implementations: [BleTransport], [SerialTransport].
abstract class RadioTransport {
  /// Human-readable name for this transport (e.g. "BLE: MeshCore-1234").
  String get displayName;

  /// Whether the transport is currently connected.
  bool get isConnected;

  /// Whether the transport uses direction+length framing.
  ///
  /// Serial/USB connections use `[dir][len_lsb][len_msb][payload]` framing.
  /// BLE sends raw companion protocol payloads without any framing.
  bool get usesFraming => true;

  /// Stream of raw bytes received from the radio.
  Stream<Uint8List> get dataStream;

  /// Connect to the radio device.
  Future<bool> connect();

  /// Disconnect from the radio device.
  Future<void> disconnect();

  /// Send raw bytes to the radio device.
  Future<void> send(Uint8List data);

  /// Dispose of resources.
  Future<void> dispose();
}

/// Connection state for transport layer.
enum TransportState { disconnected, scanning, connecting, connected, error }

/// Describes a discovered radio device (BLE or Serial).
class RadioDevice {
  const RadioDevice({
    required this.id,
    required this.name,
    required this.type,
    this.rssi,
  });

  final String id;
  final String name;
  final RadioDeviceType type;
  final int? rssi;

  @override
  String toString() => '$name ($type)';
}

enum RadioDeviceType { ble, serial }

/// Framing mode for serial connections.
///
/// [companion] — raw MeshCore Companion Radio Protocol v3 frames.
/// [kiss] — Companion frames wrapped in KISS TNC framing (FEND/FESC escaping).
enum ConnectionMode { companion, kiss }
