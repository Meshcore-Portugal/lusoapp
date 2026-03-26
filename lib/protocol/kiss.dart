import 'dart:typed_data';

/// Standard KISS TNC framing constants and encoder/decoder.
///
/// Reference: KA9Q/K3MC KISS protocol specification.
/// Used for serial communication with MeshCore radio TNCs.
class Kiss {
  static const int fend = 0xC0;
  static const int fesc = 0xDB;
  static const int tfend = 0xDC;
  static const int tfesc = 0xDD;

  /// Wrap [data] in a KISS frame with the given [command] type byte.
  static Uint8List encode(int command, Uint8List data) {
    final buf = BytesBuilder();
    buf.addByte(fend);
    buf.addByte(command);
    for (final b in data) {
      if (b == fend) {
        buf.addByte(fesc);
        buf.addByte(tfend);
      } else if (b == fesc) {
        buf.addByte(fesc);
        buf.addByte(tfesc);
      } else {
        buf.addByte(b);
      }
    }
    buf.addByte(fend);
    return buf.toBytes();
  }

  /// Decode a complete KISS frame (with FEND stripped) into command + data.
  /// Returns null if the frame is empty.
  static KissFrame? decode(Uint8List frame) {
    if (frame.isEmpty) return null;

    final command = frame[0];
    final buf = BytesBuilder();
    var escaped = false;

    for (var i = 1; i < frame.length; i++) {
      final b = frame[i];
      if (escaped) {
        if (b == tfend) {
          buf.addByte(fend);
        } else if (b == tfesc) {
          buf.addByte(fesc);
        } else {
          buf.addByte(b);
        }
        escaped = false;
      } else if (b == fesc) {
        escaped = true;
      } else {
        buf.addByte(b);
      }
    }

    return KissFrame(command: command, data: buf.toBytes());
  }
}

class KissFrame {
  const KissFrame({required this.command, required this.data});
  final int command;
  final Uint8List data;

  /// KISS type byte command nibble (lower 4 bits).
  int get commandType => command & 0x0F;

  /// KISS port number (upper 4 bits).
  int get port => (command >> 4) & 0x0F;

  /// True if this is a SetHardware (0x06) frame.
  bool get isSetHardware => commandType == 0x06;

  /// True if this is a data frame (0x00).
  bool get isData => commandType == 0x00;
}

/// Accumulates raw bytes and extracts complete KISS frames.
class KissFrameAccumulator {
  final _buffer = BytesBuilder();
  bool _inFrame = false;

  /// Feed raw bytes from serial/BLE and return any complete frames found.
  List<Uint8List> feed(Uint8List data) {
    final frames = <Uint8List>[];
    for (final b in data) {
      if (b == Kiss.fend) {
        if (_inFrame && _buffer.length > 0) {
          frames.add(_buffer.toBytes());
        }
        _buffer.clear();
        _inFrame = true;
      } else if (_inFrame) {
        _buffer.addByte(b);
      }
    }
    return frames;
  }

  void reset() {
    _buffer.clear();
    _inFrame = false;
  }
}
