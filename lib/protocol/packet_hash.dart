/// MeshCore raw packet parser and SHA-256 packet hash computation.
///
/// The firmware pushes `PUSH_CODE_LOG_RX_DATA` (0x88) for every raw RF
/// packet received.  The frame layout after the push code byte:
///
///   Byte 0: SNR (int8, value / 4.0 = dB)
///   Byte 1: RSSI (int8)
///   Bytes 2+: raw over-the-air packet
///
/// Raw packet wire format:
///   [header(1)] [transport_codes(0|4)] [path_len(1)] [path(N)] [payload]
///
/// The **packet hash** is SHA-256 of `[payload_type(1)] + [payload]`,
/// truncated to 8 bytes (`MAX_HASH_SIZE`).  This is the same algorithm
/// the firmware uses for mesh deduplication (`Packet::calculatePacketHash`).
library;

import 'dart:typed_data';

import 'package:crypto/crypto.dart';

// ---------------------------------------------------------------------------
// MeshCore payload types (from Packet.h)
// ---------------------------------------------------------------------------

const int payloadTypeReq = 0x00;
const int payloadTypeResponse = 0x01;
const int payloadTypeTxtMsg = 0x02;
const int payloadTypeAck = 0x03;
const int payloadTypeAdvert = 0x04;
const int payloadTypeGrpTxt = 0x05;
const int payloadTypeGrpData = 0x06;
const int payloadTypeAnonReq = 0x07;
const int payloadTypePath = 0x08;
const int payloadTypeTrace = 0x09;
const int payloadTypeMultipart = 0x0A;
const int payloadTypeControl = 0x0B;
const int payloadTypeRawCustom = 0x0F;

// Header bit layout
const int _routeMask = 0x03;
const int _typeShift = 2;
const int _typeMask = 0x0F;

const int _routeTransportFlood = 0x00;
const int _routeTransportDirect = 0x03;

/// Max hash size matching the firmware constant MAX_HASH_SIZE.
const int maxHashSize = 8;

// ---------------------------------------------------------------------------
// Parsed raw MeshCore packet
// ---------------------------------------------------------------------------

/// A parsed MeshCore raw over-the-air packet.
class RawMeshPacket {
  const RawMeshPacket({
    required this.header,
    required this.payloadType,
    required this.routeType,
    required this.pathLen,
    required this.pathHashSize,
    required this.pathHashCount,
    required this.pathBytes,
    required this.payload,
    required this.packetHash,
  });

  final int header;
  final int payloadType;
  final int routeType;

  /// Raw path_len byte (upper 2 bits = hash-size encoding, lower 6 = count).
  final int pathLen;

  /// Bytes per hop hash (1, 2, or 3).
  final int pathHashSize;

  /// Number of hops in the path.
  final int pathHashCount;

  /// Concatenated path hop hashes ([pathHashCount] * [pathHashSize] bytes).
  final Uint8List pathBytes;

  /// The unencrypted-framing payload (still encrypted for GRP_TXT etc.).
  final Uint8List payload;

  /// 8-byte SHA-256 packet hash (same as firmware `calculatePacketHash`).
  final Uint8List packetHash;

  /// First byte of payload for GRP_TXT/GRP_DATA — the 1-byte channel hash.
  int? get channelHashByte =>
      (payloadType == payloadTypeGrpTxt || payloadType == payloadTypeGrpData) &&
              payload.isNotEmpty
          ? payload[0]
          : null;

  /// Hex representation of [packetHash].
  String get packetHashHex =>
      packetHash.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

// ---------------------------------------------------------------------------
// Parsed 0x88 push frame
// ---------------------------------------------------------------------------

/// Fully parsed `PUSH_CODE_LOG_RX_DATA` (0x88) frame.
class ParsedLogRx {
  const ParsedLogRx({
    required this.snr,
    required this.rssi,
    required this.packet,
  });

  /// Signal-to-noise ratio in dB.
  final double snr;

  /// Received signal strength in dBm.
  final int rssi;

  /// The parsed raw packet (null if the raw bytes were too short / corrupt).
  final RawMeshPacket? packet;
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Parse a `PUSH_CODE_LOG_RX_DATA` frame (bytes AFTER the 0x88 push code).
///
/// Returns null if [data] is too short (< 2 bytes for SNR+RSSI).
ParsedLogRx? parseLogRxData(Uint8List data) {
  if (data.length < 2) return null;

  final snrByte = data[0];
  final snr = (snrByte < 128 ? snrByte : snrByte - 256) / 4.0;
  final rssiByte = data[1];
  final rssi = rssiByte < 128 ? rssiByte : rssiByte - 256;

  final rawBytes = data.length > 2 ? data.sublist(2) : Uint8List(0);
  final packet = parseRawPacket(rawBytes);

  return ParsedLogRx(snr: snr, rssi: rssi, packet: packet);
}

/// Parse a raw over-the-air MeshCore packet and compute its packet hash.
///
/// Returns null if [raw] is too short or corrupt.
RawMeshPacket? parseRawPacket(Uint8List raw) {
  if (raw.length < 2) return null; // need at least header + path_len

  var i = 0;
  final header = raw[i++];
  final routeType = header & _routeMask;
  final payloadType = (header >> _typeShift) & _typeMask;

  final hasTransport =
      routeType == _routeTransportFlood || routeType == _routeTransportDirect;

  if (hasTransport) {
    if (i + 4 > raw.length) return null;
    i += 4; // skip 2 × uint16 transport codes
  }

  if (i >= raw.length) return null;
  final pathLenByte = raw[i++];
  final pathHashSize = (pathLenByte >> 6) + 1;
  if (pathHashSize == 4) return null; // reserved
  final pathHashCount = pathLenByte & 63;
  final pathByteLen = pathHashCount * pathHashSize;

  if (i + pathByteLen > raw.length) return null;
  final pathBytes = Uint8List.fromList(raw.sublist(i, i + pathByteLen));
  i += pathByteLen;

  final payload = Uint8List.fromList(raw.sublist(i));
  final packetHash = computePacketHash(payloadType, payload);

  return RawMeshPacket(
    header: header,
    payloadType: payloadType,
    routeType: routeType,
    pathLen: pathLenByte,
    pathHashSize: pathHashSize,
    pathHashCount: pathHashCount,
    pathBytes: pathBytes,
    payload: payload,
    packetHash: packetHash,
  );
}

/// Compute the MeshCore packet hash: SHA-256([payloadType] + [payload])[0:8].
///
/// This matches the firmware's `Packet::calculatePacketHash()`.
Uint8List computePacketHash(int payloadType, Uint8List payload) {
  final input = Uint8List(1 + payload.length);
  input[0] = payloadType;
  input.setRange(1, input.length, payload);
  final digest = sha256.convert(input);
  return Uint8List.fromList(digest.bytes.sublist(0, maxHashSize));
}

/// Compute the 1-byte channel hash from a 16-byte channel secret.
///
/// This matches the firmware: `SHA-256(secret)[0:PATH_HASH_SIZE]`
/// where `PATH_HASH_SIZE = 1`.
int computeChannelHash(Uint8List secret) {
  final digest = sha256.convert(secret);
  return digest.bytes[0];
}
