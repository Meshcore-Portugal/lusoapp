import 'dart:typed_data';
import 'package:equatable/equatable.dart';

/// Represents a MeshCore contact as received from the radio.
class Contact extends Equatable {
  const Contact({
    required this.publicKey,
    required this.type,
    required this.flags,
    required this.pathLen,
    required this.name,
    required this.lastAdvertTimestamp,
    this.latitude,
    this.longitude,
    this.lastModified,
  });

  final Uint8List publicKey; // 32 bytes Ed25519
  final int type; // advType*
  final int flags;
  final int pathLen;
  final String name;
  final int lastAdvertTimestamp; // Unix epoch
  final double? latitude;
  final double? longitude;
  final int? lastModified;

  /// Human-readable hex of the first 4 bytes of the public key.
  String get shortId {
    if (publicKey.length < 4) return '';
    return publicKey
        .sublist(0, 4)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  bool get isChat => type == 0x01;
  bool get isRepeater => type == 0x02;
  bool get isRoom => type == 0x03;
  bool get isSensor => type == 0x04;

  @override
  List<Object?> get props => [publicKey, type, name];
}

/// A chat message (private or channel).
class ChatMessage extends Equatable {
  const ChatMessage({
    required this.text,
    required this.timestamp,
    required this.isOutgoing,
    this.senderKey,
    this.channelIndex,
    this.senderName,
    this.confirmed = false,
    this.snr,
    this.pathLen,
  });

  final String text;
  final int timestamp; // Unix epoch
  final bool isOutgoing;
  final Uint8List? senderKey;
  final int? channelIndex; // null = private message
  final String? senderName;
  final bool confirmed;
  final double? snr; // Signal-to-noise ratio (V3 only)
  final int? pathLen; // Hop count

  bool get isChannel => channelIndex != null;
  bool get isPrivate => channelIndex == null;

  @override
  List<Object?> get props => [text, timestamp, isOutgoing, channelIndex];
}

/// Radio configuration parameters.
class RadioConfig extends Equatable {
  const RadioConfig({
    required this.frequencyHz,
    required this.bandwidthHz,
    required this.spreadingFactor,
    required this.codingRate,
    required this.txPowerDbm,
  });

  final int frequencyHz;
  final int bandwidthHz;
  final int spreadingFactor; // 5-12
  final int codingRate; // 5-8
  final int txPowerDbm;

  double get frequencyMHz => frequencyHz / 1e6;
  double get bandwidthKHz => bandwidthHz / 1e3;

  RadioConfig copyWith({
    int? frequencyHz,
    int? bandwidthHz,
    int? spreadingFactor,
    int? codingRate,
    int? txPowerDbm,
  }) {
    return RadioConfig(
      frequencyHz: frequencyHz ?? this.frequencyHz,
      bandwidthHz: bandwidthHz ?? this.bandwidthHz,
      spreadingFactor: spreadingFactor ?? this.spreadingFactor,
      codingRate: codingRate ?? this.codingRate,
      txPowerDbm: txPowerDbm ?? this.txPowerDbm,
    );
  }

  @override
  List<Object?> get props => [
    frequencyHz,
    bandwidthHz,
    spreadingFactor,
    codingRate,
    txPowerDbm,
  ];
}

/// Device information returned from DEVICE_QUERY (0x0D).
class DeviceInfo extends Equatable {
  const DeviceInfo({
    required this.firmwareVersion,
    required this.deviceName,
    required this.batteryMillivolts,
    this.storageUsed,
    this.storageTotal,
    this.maxContacts,
    this.maxChannels,
    this.blePin,
    this.firmwareBuild,
    this.model,
    this.versionString,
  });

  final int firmwareVersion;
  final String deviceName;
  final int batteryMillivolts;
  final int? storageUsed;
  final int? storageTotal;
  final int? maxContacts;
  final int? maxChannels;
  final int? blePin;
  final String? firmwareBuild;
  final String? model;
  final String? versionString;

  double get batteryVolts => batteryMillivolts / 1000.0;

  @override
  List<Object?> get props => [firmwareVersion, deviceName, batteryMillivolts];
}

/// Self identity information returned by PACKET_SELF_INFO (0x05).
class SelfInfo extends Equatable {
  const SelfInfo({
    required this.publicKey,
    required this.name,
    required this.radioConfig,
    this.advType = 0,
    this.txPower = 0,
    this.maxTxPower = 0,
    this.latitude,
    this.longitude,
  });

  final Uint8List publicKey; // 32 bytes
  final String name;
  final RadioConfig radioConfig;
  final int advType;
  final int txPower;
  final int maxTxPower;
  final double? latitude;
  final double? longitude;

  @override
  List<Object?> get props => [publicKey, name, radioConfig];
}

/// Channel information returned by PACKET_CHANNEL_INFO (0x12).
class ChannelInfo extends Equatable {
  const ChannelInfo({required this.index, required this.name, this.secret});

  final int index;
  final String name;
  final Uint8List? secret; // 16-byte channel secret

  /// Whether this channel slot is empty (no name and all-zero secret).
  bool get isEmpty =>
      name.isEmpty && (secret == null || secret!.every((b) => b == 0));

  @override
  List<Object?> get props => [index, name];
}
