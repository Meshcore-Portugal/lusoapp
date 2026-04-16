import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:equatable/equatable.dart';

/// Derives the 16-byte hashtag channel key used by MeshCore firmware.
/// Key = first 16 bytes of SHA-256("#name"), where [name] gets a '#' prefix
/// if it does not already start with one.
Uint8List hashtagChannelKey(String name) {
  final withHash = name.startsWith('#') ? name : '#$name';
  final digest = sha256.convert(utf8.encode(withHash));
  return Uint8List.fromList(digest.bytes.sublist(0, 16));
}

/// Represents a MeshCore contact as received from the radio.
class Contact extends Equatable {
  factory Contact.fromJson(Map<String, dynamic> json) => Contact(
    publicKey: base64Decode(json['publicKey'] as String),
    type: json['type'] as int,
    flags: json['flags'] as int,
    pathLen: json['pathLen'] as int,
    name: json['name'] as String,
    lastAdvertTimestamp: json['lastAdvertTimestamp'] as int,
    latitude: (json['latitude'] as num?)?.toDouble(),
    longitude: (json['longitude'] as num?)?.toDouble(),
    lastModified: json['lastModified'] as int?,
    customName: json['customName'] as String?,
  );
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
    this.customName,
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

  /// User-defined alias; if set, takes precedence over [name] in the UI.
  final String? customName;

  /// Name to show in the UI: [customName] if set, [name] if non-empty, else [shortId].
  String get displayName {
    if (customName != null && customName!.trim().isNotEmpty) {
      return customName!.trim();
    }
    if (name.isNotEmpty) return name;
    return shortId;
  }

  /// Returns a copy of this contact with [customName] replaced by [value].
  Contact withCustomName(String? value) => Contact(
    publicKey: publicKey,
    type: type,
    flags: flags,
    pathLen: pathLen,
    name: name,
    lastAdvertTimestamp: lastAdvertTimestamp,
    latitude: latitude,
    longitude: longitude,
    lastModified: lastModified,
    customName: value,
  );

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

  /// Bit 0 (LSB, mask 0x01) of [flags] is the 'favourite' flag on the radio
  /// firmware. See MeshCore `examples/companion_radio/MyMesh.cpp` where the
  /// telemetry permission lookup does `uint8_t cp = contact.flags >> 1;`
  /// with the comment: "LSB used as 'favourite' bit (so only use upper bits)".
  /// The whole [flags] byte is round-tripped unchanged through RESP_CONTACT /
  /// CMD_ADD_UPDATE_CONTACT, so toggling bit 0 on the app side is authoritative.
  static const int _flagFavoriteMask = 0x01;

  /// True when this contact is marked as a favourite on the radio.
  bool get isFavorite => (flags & _flagFavoriteMask) != 0;

  /// Returns a copy of this contact with bit 0 of [flags] set to [value].
  /// All other bits (permissions encoded in the upper bits) are preserved.
  Contact withFavorite(bool value) {
    final newFlags =
        value ? (flags | _flagFavoriteMask) : (flags & ~_flagFavoriteMask);
    if (newFlags == flags) return this;
    return Contact(
      publicKey: publicKey,
      type: type,
      flags: newFlags,
      pathLen: pathLen,
      name: name,
      lastAdvertTimestamp: lastAdvertTimestamp,
      latitude: latitude,
      longitude: longitude,
      lastModified: lastModified,
      customName: customName,
    );
  }

  @override
  List<Object?> get props => [publicKey, type, name, customName];

  Map<String, dynamic> toJson() => {
    'publicKey': base64Encode(publicKey),
    'type': type,
    'flags': flags,
    'pathLen': pathLen,
    'name': name,
    'lastAdvertTimestamp': lastAdvertTimestamp,
    'latitude': latitude,
    'longitude': longitude,
    'lastModified': lastModified,
    'customName': customName,
  };
}

/// A single reception path recorded for an outgoing channel message.
/// Each instance corresponds to one 0x88 LogRxData frame (a repeater echo).
class MessagePath {
  const MessagePath({
    required this.snr,
    required this.rssi,
    required this.pathHashCount,
    required this.pathHashSize,
    required this.pathBytes,
  });

  factory MessagePath.fromJson(Map<String, dynamic> json) => MessagePath(
    snr: (json['snr'] as num).toDouble(),
    rssi: json['rssi'] as int,
    pathHashCount: json['pathHashCount'] as int,
    pathHashSize: json['pathHashSize'] as int,
    pathBytes: base64Decode(json['pathBytes'] as String),
  );

  /// Signal-to-noise ratio in dB.
  final double snr;

  /// Received signal strength in dBm.
  final int rssi;

  /// Number of relay hops recorded in the packet path.
  final int pathHashCount;

  /// Bytes per hop hash (1–3).
  final int pathHashSize;

  /// Concatenated hop hash bytes: [pathHashCount] × [pathHashSize] bytes.
  /// Each hop hash is the first [pathHashSize] bytes of the relay node's public key.
  final Uint8List pathBytes;

  Map<String, dynamic> toJson() => {
    'snr': snr,
    'rssi': rssi,
    'pathHashCount': pathHashCount,
    'pathHashSize': pathHashSize,
    'pathBytes': base64Encode(pathBytes),
  };
}

/// A chat message (private or channel).
class ChatMessage extends Equatable {
  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    text: json['text'] as String,
    timestamp: json['timestamp'] as int,
    isOutgoing: json['isOutgoing'] as bool,
    senderKey:
        json['senderKey'] != null
            ? base64Decode(json['senderKey'] as String)
            : null,
    channelIndex: json['channelIndex'] as int?,
    senderName: json['senderName'] as String?,
    confirmed: json['confirmed'] as bool? ?? false,
    snr: (json['snr'] as num?)?.toDouble(),
    pathLen: json['pathLen'] as int?,
    heardCount: json['heardCount'] as int? ?? 0,
    sentRouteFlag:
        json['sentRouteFlag'] as int? ??
        (json['sentViaFlood'] == true ? 1 : null),
    packetHashHex: json['packetHashHex'] as String?,
  );
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
    this.heardCount = 0,
    this.sentRouteFlag,
    this.packetHashHex,
    this.isCliResponse = false,
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
  /// Number of times this channel message was heard back via a repeater (loopback).
  final int heardCount;

  /// Route flag from RESP_CODE_SENT: null=unknown, 0=direct, 1=flood (via repeaters).
  final int? sentRouteFlag;

  /// 8-byte packet hash (hex) from 0x88 LogRxData frames.
  /// Used to track how many repeaters re-broadcast this message.
  final String? packetHashHex;

  /// True when this message carries TXT_TYPE_CLI_DATA (0x01) — i.e. it is a
  /// CLI command response, not a user-visible chat message.
  final bool isCliResponse;

  bool get isChannel => channelIndex != null;
  bool get isPrivate => channelIndex == null;

  ChatMessage copyWith({
    String? text,
    int? timestamp,
    bool? isOutgoing,
    Uint8List? senderKey,
    int? channelIndex,
    String? senderName,
    bool? confirmed,
    double? snr,
    int? pathLen,
    int? heardCount,
    int? sentRouteFlag,
    String? packetHashHex,
    bool? isCliResponse,
  }) {
    return ChatMessage(
      text: text ?? this.text,
      timestamp: timestamp ?? this.timestamp,
      isOutgoing: isOutgoing ?? this.isOutgoing,
      senderKey: senderKey ?? this.senderKey,
      channelIndex: channelIndex ?? this.channelIndex,
      senderName: senderName ?? this.senderName,
      confirmed: confirmed ?? this.confirmed,
      snr: snr ?? this.snr,
      pathLen: pathLen ?? this.pathLen,
      heardCount: heardCount ?? this.heardCount,
      sentRouteFlag: sentRouteFlag ?? this.sentRouteFlag,
      packetHashHex: packetHashHex ?? this.packetHashHex,
      isCliResponse: isCliResponse ?? this.isCliResponse,
    );
  }

  Map<String, dynamic> toJson() => {
    'text': text,
    'timestamp': timestamp,
    'isOutgoing': isOutgoing,
    'senderKey': senderKey != null ? base64Encode(senderKey!) : null,
    'channelIndex': channelIndex,
    'senderName': senderName,
    'confirmed': confirmed,
    'snr': snr,
    'pathLen': pathLen,
    'heardCount': heardCount,
    'sentRouteFlag': sentRouteFlag,
    'packetHashHex': packetHashHex,
  };

  @override
  List<Object?> get props => [
    text,
    timestamp,
    isOutgoing,
    channelIndex,
    heardCount,
    sentRouteFlag,
    packetHashHex,
  ];
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

  // frequencyHz stores the raw 32-bit firmware value which is freq_MHz * 1000
  // (i.e. kHz units). The field name is kept for compatibility.
  final int frequencyHz;
  final int bandwidthHz;
  final int spreadingFactor; // 5-12
  final int codingRate; // 5-8
  final int txPowerDbm;

  /// Frequency in MHz. Raw firmware value is in kHz units (freq_MHz × 1000).
  double get frequencyMHz => frequencyHz / 1e3;
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

// ---------------------------------------------------------------------------
// Trace path models
// ---------------------------------------------------------------------------

/// A single hop in a MeshCore trace route.
class TraceHop {
  const TraceHop({
    required this.hashHex,
    required this.snrDb,
    this.name,
    this.latitude,
    this.longitude,
  });

  final String hashHex; // node hash as hex string (1–8 bytes)
  final double snrDb; // receive SNR at this hop (dB)
  final String? name; // matched contact name, if known
  final double? latitude;
  final double? longitude;

  bool get hasGps => latitude != null && longitude != null;
}

/// Parsed result from a PUSH_CODE_TRACE_DATA (0x89) push.
class TraceResult {
  const TraceResult({
    required this.tag,
    required this.hops,
    required this.finalSnrDb,
    required this.timestamp,
  });

  final int tag;
  final List<TraceHop> hops;
  final double finalSnrDb; // SNR of the last link into our radio
  final DateTime timestamp;

  int get hopCount => hops.length;
}

// ---------------------------------------------------------------------------
// Repeater remote-admin stats
// ---------------------------------------------------------------------------

/// Statistics returned by a repeater in response to a status request (0x1B).
/// Binary layout: [reserved:1][pub_key_prefix:6][RepeaterStats:56]
/// All integers are little-endian.
class RepeaterStats {
  const RepeaterStats({
    required this.pubKeyPrefixHex,
    required this.batteryMv,
    required this.txQueueLen,
    required this.noiseFloor,
    required this.lastRssi,
    required this.packetsRecv,
    required this.packetsSent,
    required this.airTimeSecs,
    required this.uptimeSecs,
    required this.sentFlood,
    required this.sentDirect,
    required this.recvFlood,
    required this.recvDirect,
    required this.errEvents,
    required this.lastSnrDb,
    required this.directDups,
    required this.floodDups,
    this.rxAirTimeSecs,
    this.recvErrors,
    required this.receivedAt,
  });

  final String pubKeyPrefixHex; // 6-byte hex key identifying the repeater
  final int batteryMv;
  final int txQueueLen;
  final int noiseFloor; // dBm
  final int lastRssi; // dBm
  final int packetsRecv;
  final int packetsSent;
  final int airTimeSecs; // cumulative TX air time
  final int uptimeSecs;
  final int sentFlood;
  final int sentDirect;
  final int recvFlood;
  final int recvDirect;
  final int errEvents;
  final double lastSnrDb; // SNR×4 converted to dB
  final int directDups;
  final int floodDups;
  final int? rxAirTimeSecs; // present only in full repeater stats (not room)
  final int? recvErrors;
  final DateTime receivedAt;

  String get uptimeFormatted {
    final h = uptimeSecs ~/ 3600;
    final m = (uptimeSecs % 3600) ~/ 60;
    final s = uptimeSecs % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  double get batteryVolts => batteryMv / 1000.0;

  /// Parse from the raw push data (after 0x87 code stripped).
  /// data[0] = reserved, data[1..6] = pub_key_prefix, data[7..] = struct.
  static RepeaterStats? fromPushData(Uint8List data) {
    if (data.length < 51) return null; // minimum: 7 header + 44 common fields

    final bd = ByteData.sublistView(data);
    final prefixHex =
        data
            .sublist(1, 7)
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join();

    const base = 7; // struct starts at offset 7
    int readU16(int off) => bd.getUint16(base + off, Endian.little);
    int readI16(int off) => bd.getInt16(base + off, Endian.little);
    int readU32(int off) => bd.getUint32(base + off, Endian.little);

    final snrRaw = readI16(42);
    int? rxAirTime;
    int? recvErrors;
    if (data.length >= base + 56) {
      rxAirTime = readU32(48);
      recvErrors = readU32(52);
    }

    return RepeaterStats(
      pubKeyPrefixHex: prefixHex,
      batteryMv: readU16(0),
      txQueueLen: readU16(2),
      noiseFloor: readI16(4),
      lastRssi: readI16(6),
      packetsRecv: readU32(8),
      packetsSent: readU32(12),
      airTimeSecs: readU32(16),
      uptimeSecs: readU32(20),
      sentFlood: readU32(24),
      sentDirect: readU32(28),
      recvFlood: readU32(32),
      recvDirect: readU32(36),
      errEvents: readU16(40),
      lastSnrDb: snrRaw / 4.0,
      directDups: readU16(44),
      floodDups: readU16(46),
      rxAirTimeSecs: rxAirTime,
      recvErrors: recvErrors,
      receivedAt: DateTime.now(),
    );
  }
}

/// Channel information returned by PACKET_CHANNEL_INFO (0x12).
class ChannelInfo extends Equatable {
  const ChannelInfo({required this.index, required this.name, this.secret});

  factory ChannelInfo.fromJson(Map<String, dynamic> json) => ChannelInfo(
    index: json['index'] as int,
    name: json['name'] as String,
    secret:
        json['secret'] != null ? base64Decode(json['secret'] as String) : null,
  );

  final int index;
  final String name;
  final Uint8List? secret; // 16-byte channel secret

  /// Whether this channel slot is empty (no name and all-zero secret).
  bool get isEmpty =>
      name.isEmpty && (secret == null || secret!.every((b) => b == 0));

  Map<String, dynamic> toJson() => {
    'index': index,
    'name': name,
    if (secret != null) 'secret': base64Encode(secret!),
  };

  @override
  List<Object?> get props => [index, name];
}
