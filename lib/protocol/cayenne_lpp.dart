import 'dart:typed_data';

/// CayenneLPP sensor type descriptors.
enum CayenneType {
  digitalInput(0x00, 'Entrada Digital', '', 1),
  digitalOutput(0x01, 'Saída Digital', '', 1),
  analogInput(0x02, 'Entrada Analógica', '', 2),
  analogOutput(0x03, 'Saída Analógica', '', 2),
  illuminance(0x65, 'Luminosidade', 'lux', 2),
  presence(0x66, 'Presença', '', 1),
  temperature(0x67, 'Temperatura', '°C', 2),
  humidity(0x68, 'Humidade', '%', 1),
  barometricPressure(0x73, 'Pressão', 'hPa', 2),
  percentage(0x75, 'Percentagem', '%', 1),
  voltage(0x74, 'Tensão', 'V', 2),
  current(0x77, 'Corrente', 'mA', 2),
  frequency(0x78, 'Frequência', 'Hz', 4),
  accelerometer(0x71, 'Acelerómetro', 'G', 6),
  gpsLocation(0x88, 'GPS', '', 9),
  unknown(-1, 'Desconhecido', '', 0);

  const CayenneType(this.code, this.label, this.unit, this.size);

  final int code;
  final String label;
  final String unit;

  /// Payload byte size for this type (0 = variable/unknown).
  final int size;

  static CayenneType fromCode(int code) => CayenneType.values.firstWhere(
    (t) => t.code == code,
    orElse: () => CayenneType.unknown,
  );
}

/// A single decoded CayenneLPP sensor reading.
class CayenneReading {
  const CayenneReading({
    required this.channel,
    required this.type,
    required this.displayValue,
    required this.unit,
    required this.rawValue,
  });

  final int channel;
  final CayenneType type;
  final String displayValue;
  final String unit;
  final double rawValue;

  /// Human-readable label with unit.
  String get formatted =>
      unit.isNotEmpty ? '$displayValue $unit' : displayValue;
}

/// Decodes CayenneLPP binary payloads into structured [CayenneReading] lists.
class CayenneLPP {
  /// Decode [data] and return all successfully parsed readings.
  static List<CayenneReading> decode(Uint8List data) {
    final readings = <CayenneReading>[];
    var offset = 0;

    while (offset + 2 <= data.length) {
      final channel = data[offset];
      final typeCode = data[offset + 1];
      offset += 2;

      final type = CayenneType.fromCode(typeCode);
      if (type == CayenneType.unknown) break; // Can't advance reliably
      if (offset + type.size > data.length) break;

      final reading = _decode(channel, type, data, offset);
      if (reading != null) readings.add(reading);
      offset += type.size;
    }

    return readings;
  }

  static CayenneReading? _decode(
    int channel,
    CayenneType type,
    Uint8List data,
    int offset,
  ) {
    switch (type) {
      case CayenneType.digitalInput:
      case CayenneType.digitalOutput:
      case CayenneType.presence:
        final v = data[offset].toDouble();
        return CayenneReading(
          channel: channel,
          type: type,
          displayValue: v == 1 ? 'ON' : 'OFF',
          unit: '',
          rawValue: v,
        );

      case CayenneType.temperature:
        final v = _readInt16BE(data, offset) / 10.0;
        return CayenneReading(
          channel: channel,
          type: type,
          displayValue: v.toStringAsFixed(1),
          unit: '°C',
          rawValue: v,
        );

      case CayenneType.humidity:
        final v = data[offset] / 2.0;
        return CayenneReading(
          channel: channel,
          type: type,
          displayValue: v.toStringAsFixed(1),
          unit: '%',
          rawValue: v,
        );

      case CayenneType.barometricPressure:
        final v = _readUint16BE(data, offset) / 10.0;
        return CayenneReading(
          channel: channel,
          type: type,
          displayValue: v.toStringAsFixed(1),
          unit: 'hPa',
          rawValue: v,
        );

      case CayenneType.illuminance:
        final v = _readUint16BE(data, offset).toDouble();
        return CayenneReading(
          channel: channel,
          type: type,
          displayValue: '${v.toInt()}',
          unit: 'lux',
          rawValue: v,
        );

      case CayenneType.analogInput:
      case CayenneType.analogOutput:
        final v = _readInt16BE(data, offset) / 100.0;
        return CayenneReading(
          channel: channel,
          type: type,
          displayValue: v.toStringAsFixed(2),
          unit: '',
          rawValue: v,
        );

      case CayenneType.percentage:
        final v = data[offset].toDouble();
        return CayenneReading(
          channel: channel,
          type: type,
          displayValue: '${v.toInt()}',
          unit: '%',
          rawValue: v,
        );

      case CayenneType.voltage:
        final v = _readUint16BE(data, offset) / 100.0;
        return CayenneReading(
          channel: channel,
          type: type,
          displayValue: v.toStringAsFixed(2),
          unit: 'V',
          rawValue: v,
        );

      case CayenneType.current:
        final v = _readUint16BE(data, offset) / 1000.0;
        return CayenneReading(
          channel: channel,
          type: type,
          displayValue: v.toStringAsFixed(3),
          unit: 'mA',
          rawValue: v,
        );

      case CayenneType.frequency:
        final v = _readUint32BE(data, offset).toDouble();
        return CayenneReading(
          channel: channel,
          type: type,
          displayValue: '${v.toInt()}',
          unit: 'Hz',
          rawValue: v,
        );

      case CayenneType.accelerometer:
        final x = _readInt16BE(data, offset) / 1000.0;
        final y = _readInt16BE(data, offset + 2) / 1000.0;
        final z = _readInt16BE(data, offset + 4) / 1000.0;
        return CayenneReading(
          channel: channel,
          type: type,
          displayValue:
              'X:${x.toStringAsFixed(3)} Y:${y.toStringAsFixed(3)} Z:${z.toStringAsFixed(3)}',
          unit: 'G',
          rawValue: x,
        );

      case CayenneType.gpsLocation:
        final lat = _readInt24BE(data, offset) / 10000.0;
        final lng = _readInt24BE(data, offset + 3) / 10000.0;
        final alt = _readInt24BE(data, offset + 6) / 100.0;
        return CayenneReading(
          channel: channel,
          type: type,
          displayValue:
              '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}, ${alt.toStringAsFixed(1)}m',
          unit: '',
          rawValue: lat,
        );

      case CayenneType.unknown:
        return null;
    }
  }

  static int _readInt16BE(Uint8List data, int offset) =>
      ByteData.sublistView(data, offset, offset + 2).getInt16(0, Endian.big);

  static int _readUint16BE(Uint8List data, int offset) =>
      ByteData.sublistView(data, offset, offset + 2).getUint16(0, Endian.big);

  static int _readInt24BE(Uint8List data, int offset) {
    final v = (data[offset] << 16) | (data[offset + 1] << 8) | data[offset + 2];
    return v >= 0x800000 ? v - 0x1000000 : v;
  }

  static int _readUint32BE(Uint8List data, int offset) =>
      ByteData.sublistView(data, offset, offset + 4).getUint32(0, Endian.big);
}
