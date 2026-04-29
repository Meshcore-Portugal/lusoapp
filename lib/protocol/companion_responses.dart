import 'dart:typed_data';

import 'models.dart';

// ---------------------------------------------------------------------------
// Response types
// ---------------------------------------------------------------------------

sealed class CompanionResponse {
  const CompanionResponse();
}

class OkResponse extends CompanionResponse {
  const OkResponse();
}

class ErrorResponse extends CompanionResponse {
  const ErrorResponse(this.errorCode);
  final int errorCode;
}

class ContactsStartResponse extends CompanionResponse {
  const ContactsStartResponse();
}

class ContactResponse extends CompanionResponse {
  const ContactResponse(this.contact);
  final Contact contact;
}

class EndContactsResponse extends CompanionResponse {
  const EndContactsResponse();
}

class SelfInfoResponse extends CompanionResponse {
  const SelfInfoResponse(this.info);
  final SelfInfo info;
}

class SentResponse extends CompanionResponse {
  const SentResponse({this.routeFlag = 0});

  /// 0 = direct, 1 = flood (via repeaters)
  final int routeFlag;
  bool get isFlood => routeFlag == 1;
}

class PrivateMessageResponse extends CompanionResponse {
  const PrivateMessageResponse(this.message);
  final ChatMessage message;
}

class ChannelMessageResponse extends CompanionResponse {
  const ChannelMessageResponse(this.message);
  final ChatMessage message;
}

class CurrTimeResponse extends CompanionResponse {
  const CurrTimeResponse(this.timestamp);
  final int timestamp;
}

class NoMoreMessagesResponse extends CompanionResponse {
  const NoMoreMessagesResponse();
}

class BattAndStorageResponse extends CompanionResponse {
  const BattAndStorageResponse(
    this.batteryMv,
    this.storageUsed,
    this.storageTotal,
  );
  final int batteryMv;
  final int? storageUsed;
  final int? storageTotal;
}

class DeviceInfoResponse extends CompanionResponse {
  const DeviceInfoResponse(this.info);
  final DeviceInfo info;
}

class ChannelInfoResponse extends CompanionResponse {
  const ChannelInfoResponse(this.channel);
  final ChannelInfo channel;
}

// --- Push responses ---

class AdvertPush extends CompanionResponse {
  const AdvertPush(this.publicKey, this.type, this.name, {this.isNew = false});
  final Uint8List publicKey;
  final int type;
  final String name;

  /// True when push code was pushNewAdvert (0x8A). The radio may NOT have saved
  /// this contact to its own table (manual-contact mode). The app must reply
  /// with CMD_ADD_UPDATE_CONTACT to ensure the contact is stored on the radio.
  final bool isNew;
}

class PathUpdatedPush extends CompanionResponse {
  const PathUpdatedPush(this.data);
  final Uint8List data;
}

class SendConfirmedPush extends CompanionResponse {
  const SendConfirmedPush();
}

class MsgWaitingPush extends CompanionResponse {
  const MsgWaitingPush();
}

class LoginSuccessPush extends CompanionResponse {
  const LoginSuccessPush();
}

class LoginFailPush extends CompanionResponse {
  const LoginFailPush();
}

class TraceDataPush extends CompanionResponse {
  const TraceDataPush(this.data);
  final Uint8List data;
}

class TelemetryPush extends CompanionResponse {
  const TelemetryPush(this.data);
  final Uint8List data;
}

class ContactDeletedPush extends CompanionResponse {
  const ContactDeletedPush();
}

class ContactsFullPush extends CompanionResponse {
  const ContactsFullPush();
}

class LogRxDataPush extends CompanionResponse {
  const LogRxDataPush(this.data);
  final Uint8List data;
}

class StatusResponsePush extends CompanionResponse {
  const StatusResponsePush(this.data);
  final Uint8List data;
}

class RawDataPush extends CompanionResponse {
  const RawDataPush(this.data);
  final Uint8List data;
}

class BinaryResponsePush extends CompanionResponse {
  const BinaryResponsePush(this.tag, this.responseData);
  final int tag;
  final Uint8List responseData;
}

class PathDiscoveryPush extends CompanionResponse {
  const PathDiscoveryPush(this.pubKeyPrefix, this.outPath, this.inPath);
  final Uint8List pubKeyPrefix;
  final List<int> outPath;
  final List<int> inPath;
}

class ControlDataPush extends CompanionResponse {
  const ControlDataPush(this.snr, this.rssi, this.pathLen, this.payload);
  final double snr;
  final int rssi;
  final int pathLen;
  final Uint8List payload;
}

class SignatureResponse extends CompanionResponse {
  const SignatureResponse(this.signature);
  final Uint8List signature;
}

class PrivateKeyResponse extends CompanionResponse {
  const PrivateKeyResponse(this.privateKey);

  /// Raw 64-byte private key received from the radio.
  final Uint8List privateKey;
}

/// Response to CMD_GET_AUTOADD_CONFIG (0x3B).
/// Also sent spontaneously after CMD_SET_AUTOADD_CONFIG (0x3A) confirms the write.
class AutoAddConfigResponse extends CompanionResponse {
  const AutoAddConfigResponse({required this.bitmask, required this.maxHops});

  /// autoadd_config bitmask — see [autoAddChat], [autoAddRepeater], etc.
  final int bitmask;

  /// autoadd_max_hops: 0 = no limit, 1 = direct (0 hops), N = up to N-1 hops.
  final int maxHops;
}

/// Core device statistics (CMD_GET_STATS + STATS_TYPE_CORE).
class StatsCoreResponse extends CompanionResponse {
  const StatsCoreResponse({
    required this.batteryMv,
    required this.uptimeSecs,
    required this.errors,
    required this.queueLen,
  });

  /// Battery voltage in millivolts.
  final int batteryMv;

  /// Device uptime in seconds since last boot.
  final int uptimeSecs;

  /// Error flags bitmask.
  final int errors;

  /// Outbound packet queue length.
  final int queueLen;
}

/// Radio statistics (CMD_GET_STATS + STATS_TYPE_RADIO).
class StatsRadioResponse extends CompanionResponse {
  const StatsRadioResponse({
    required this.noiseFloor,
    required this.lastRssi,
    required this.lastSnrDb,
    required this.txAirSecs,
    required this.rxAirSecs,
  });

  /// Radio noise floor in dBm.
  final int noiseFloor;

  /// Last received signal strength in dBm.
  final int lastRssi;

  /// Last SNR in dB (already divided by 4, 0.25 dB precision).
  final double lastSnrDb;

  /// Cumulative transmit airtime in seconds.
  final int txAirSecs;

  /// Cumulative receive airtime in seconds.
  final int rxAirSecs;
}

/// Packet counters (CMD_GET_STATS + STATS_TYPE_PACKETS).
class StatsPacketsResponse extends CompanionResponse {
  const StatsPacketsResponse({
    required this.recv,
    required this.sent,
    required this.floodTx,
    required this.directTx,
    required this.floodRx,
    required this.directRx,
    this.recvErrors,
  });

  final int recv;
  final int sent;
  final int floodTx;
  final int directTx;
  final int floodRx;
  final int directRx;

  /// Receive/CRC errors (RadioLib); present only in 30-byte frame.
  final int? recvErrors;
}

class UnknownResponse extends CompanionResponse {
  const UnknownResponse(this.code, this.data);
  final int code;
  final Uint8List data;
}
