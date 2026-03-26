import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';

import '../protocol/protocol.dart';
import '../services/radio_service.dart';
import '../transport/transport.dart';

// ---------------------------------------------------------------------------
// Transport state
// ---------------------------------------------------------------------------

final transportStateProvider = StateProvider<TransportState>(
  (_) => TransportState.disconnected,
);

// ---------------------------------------------------------------------------
// Radio service — the central singleton managing the connection
// ---------------------------------------------------------------------------

final radioServiceProvider = StateProvider<RadioService?>((_) => null);

// ---------------------------------------------------------------------------
// Connection manager
// ---------------------------------------------------------------------------

class ConnectionNotifier extends StateNotifier<TransportState> {
  ConnectionNotifier(this._ref) : super(TransportState.disconnected);
  final Ref _ref;

  Future<bool> connectBle(String deviceId) async {
    state = TransportState.connecting;
    try {
      final transport = BleTransport.fromDeviceId(deviceId);
      final service = RadioService(transport);
      // Wire up listeners BEFORE connect() so we don't miss the radio's
      // immediate response to APP_START (SelfInfo, etc.).
      _ref.read(radioServiceProvider.notifier).state = service;
      _setupListeners(service);
      final ok = await service.connect();
      if (ok) {
        state = TransportState.connected;
        await _fetchInitialData(service);
        return true;
      }
      _ref.read(radioServiceProvider.notifier).state = null;
      state = TransportState.error;
      return false;
    } catch (e) {
      state = TransportState.error;
      return false;
    }
  }

  Future<bool> connectSerial(
    String deviceId, {
    ConnectionMode mode = ConnectionMode.companion,
  }) async {
    state = TransportState.connecting;
    try {
      final baseTransport = await SerialTransport.fromDeviceId(deviceId);
      if (baseTransport == null) {
        state = TransportState.error;
        return false;
      }
      final RadioTransport transport =
          mode == ConnectionMode.kiss
              ? KissTransport(baseTransport)
              : baseTransport;
      final service = RadioService(transport);
      // Wire up listeners BEFORE connect() so we don't miss early responses.
      _ref.read(radioServiceProvider.notifier).state = service;
      _setupListeners(service);
      final ok = await service.connect();
      if (ok) {
        state = TransportState.connected;
        await _fetchInitialData(service);
        return true;
      }
      _ref.read(radioServiceProvider.notifier).state = null;
      state = TransportState.error;
      return false;
    } catch (e) {
      state = TransportState.error;
      return false;
    }
  }

  Future<void> disconnect() async {
    final service = _ref.read(radioServiceProvider);
    if (service != null) {
      await service.dispose();
      _ref.read(radioServiceProvider.notifier).state = null;
    }
    _ref.read(unreadCountsProvider.notifier).reset();
    state = TransportState.disconnected;
  }

  void _setupListeners(RadioService service) {
    service.responses.listen((response) {
      switch (response) {
        case ContactResponse():
        case EndContactsResponse():
          _ref.read(contactsProvider.notifier).refresh(service.contacts);
        case ChannelInfoResponse():
          _ref.read(channelsProvider.notifier).refresh(service.channels);
        case PrivateMessageResponse(:final message):
          _ref.read(messagesProvider.notifier).addMessage(message);
          if (message.senderKey != null) {
            _ref
                .read(unreadCountsProvider.notifier)
                .incrementContact(_hex6(message.senderKey!));
          }
        case ChannelMessageResponse(:final message):
          _ref.read(messagesProvider.notifier).addMessage(message);
          if (message.channelIndex != null) {
            _ref
                .read(unreadCountsProvider.notifier)
                .incrementChannel(message.channelIndex!);
          }
        case SelfInfoResponse(:final info):
          _ref.read(selfInfoProvider.notifier).state = info;
          _ref.read(radioConfigProvider.notifier).state = info.radioConfig;
        case BattAndStorageResponse(:final batteryMv):
          _ref.read(batteryProvider.notifier).state = batteryMv;
        case DeviceInfoResponse(:final info):
          _ref.read(deviceInfoProvider.notifier).state = info;
        case SendConfirmedPush():
          // Could notify UI of confirmed send
          break;
        default:
          break;
      }
    });
  }

  /// Wait for a specific response type from the radio after sending a command.
  /// Returns the matching response, or null on timeout.
  Future<CompanionResponse?> _sendAndWait(
    RadioService service,
    Future<void> Function() sendFn,
    bool Function(CompanionResponse) matcher, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final completer = Completer<CompanionResponse>();
    late StreamSubscription<CompanionResponse> sub;
    sub = service.responses.listen((response) {
      if (!completer.isCompleted && matcher(response)) {
        completer.complete(response);
        sub.cancel();
      }
    });

    await sendFn();

    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      await sub.cancel();
      return null;
    }
  }

  /// Request all initial data from the radio after connection.
  ///
  /// DeviceInfo is fetched first to discover maxChannels.
  /// Contacts are fetched with response-aware sequencing (EndContactsResponse
  /// marks completion).  Channels are sent one-at-a-time with a 150 ms gap
  /// to avoid overflowing the firmware's BLE send queue.
  ///
  /// MsgWaitingPush triggers syncNextMessage() immediately at all times
  /// so incoming messages are never missed.
  Future<void> _fetchInitialData(RadioService service) async {
    final log = Logger(printer: SimplePrinter(printTime: false));

    // Give radio time to process APP_START and return SelfInfo.
    await Future.delayed(const Duration(milliseconds: 300));

    // 1. Device info — we need maxChannels before requesting channels.
    final devResp = await _sendAndWait(
      service,
      () => service.requestDeviceInfo(),
      (r) => r is DeviceInfoResponse || r is ErrorResponse,
    );
    log.d('DeviceInfo: ${devResp?.runtimeType ?? "TIMEOUT"}');

    // 2. Battery — fire and forget, let it arrive whenever.
    await service.requestBattAndStorage();

    // 3. Contacts — wait for the end-of-contacts marker.
    final contactsResp = await _sendAndWait(
      service,
      () => service.requestContacts(),
      (r) => r is EndContactsResponse,
      timeout: const Duration(seconds: 10),
    );
    log.d('Contacts: ${contactsResp?.runtimeType ?? "TIMEOUT"}');

    // 4. Channels — send each request with a 150 ms gap.
    //    Responses arrive asynchronously; _setupListeners handles them.
    //    Do NOT suppress MsgWaitingPush here — auto-sync runs freely.
    final maxChannels = service.deviceInfo?.maxChannels ?? 8;
    for (var i = 0; i < maxChannels; i++) {
      await service.requestChannel(i);
      await Future.delayed(const Duration(milliseconds: 150));
    }
    log.d('Channel requests sent (maxChannels=$maxChannels)');
  }
}

final connectionProvider =
    StateNotifierProvider<ConnectionNotifier, TransportState>((ref) {
      return ConnectionNotifier(ref);
    });

// ---------------------------------------------------------------------------
// Data providers
// ---------------------------------------------------------------------------

final selfInfoProvider = StateProvider<SelfInfo?>((_) => null);
final radioConfigProvider = StateProvider<RadioConfig?>((_) => null);
final deviceInfoProvider = StateProvider<DeviceInfo?>((_) => null);
final batteryProvider = StateProvider<int>((_) => 0);

// Contacts
class ContactsNotifier extends StateNotifier<List<Contact>> {
  ContactsNotifier() : super([]);

  void refresh(List<Contact> contacts) {
    state = List.from(contacts);
  }
}

final contactsProvider = StateNotifierProvider<ContactsNotifier, List<Contact>>(
  (ref) {
    return ContactsNotifier();
  },
);

// Channels
class ChannelsNotifier extends StateNotifier<List<ChannelInfo>> {
  ChannelsNotifier() : super([]);

  void refresh(List<ChannelInfo> channels) {
    state = List.from(channels)..sort((a, b) => a.index.compareTo(b.index));
  }
}

final channelsProvider =
    StateNotifierProvider<ChannelsNotifier, List<ChannelInfo>>((ref) {
      return ChannelsNotifier();
    });

// Messages
class MessagesNotifier extends StateNotifier<List<ChatMessage>> {
  MessagesNotifier() : super([]);

  void addMessage(ChatMessage message) {
    state = [...state, message];
  }

  void addOutgoing(ChatMessage message) {
    state = [...state, message];
  }

  /// Get messages for a specific contact (private).
  List<ChatMessage> forContact(Uint8List? contactKey) {
    if (contactKey == null) return [];
    return state.where((m) {
      if (m.isChannel) return false;
      if (m.senderKey == null) return false;
      // Match on the first 6 bytes (prefix)
      final prefix =
          contactKey.length >= 6 ? contactKey.sublist(0, 6) : contactKey;
      final msgPrefix =
          m.senderKey!.length >= 6 ? m.senderKey!.sublist(0, 6) : m.senderKey!;
      return _prefixMatch(prefix, msgPrefix);
    }).toList();
  }

  /// Get messages for a specific channel.
  List<ChatMessage> forChannel(int channelIndex) {
    return state.where((m) => m.channelIndex == channelIndex).toList();
  }

  bool _prefixMatch(Uint8List a, Uint8List b) {
    final len = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < len; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

final messagesProvider =
    StateNotifierProvider<MessagesNotifier, List<ChatMessage>>((ref) {
      return MessagesNotifier();
    });

// ---------------------------------------------------------------------------
// Unread message counts
// ---------------------------------------------------------------------------

/// Immutable snapshot of unread counts per channel and per contact.
class UnreadCounts {
  const UnreadCounts({this.channels = const {}, this.contacts = const {}});

  /// channelIndex → unread count
  final Map<int, int> channels;

  /// 6-byte sender key hex → unread count
  final Map<String, int> contacts;

  int get totalChannels => channels.values.fold(0, (a, b) => a + b);
  int get totalContacts => contacts.values.fold(0, (a, b) => a + b);
  int forChannel(int i) => channels[i] ?? 0;
  int forContact(String hex6) => contacts[hex6] ?? 0;
}

class UnreadCountsNotifier extends StateNotifier<UnreadCounts> {
  UnreadCountsNotifier() : super(const UnreadCounts());

  void incrementChannel(int index) {
    final ch = Map<int, int>.from(state.channels)
      ..[index] = (state.channels[index] ?? 0) + 1;
    state = UnreadCounts(channels: ch, contacts: state.contacts);
  }

  void incrementContact(String hex6) {
    final co = Map<String, int>.from(state.contacts)
      ..[hex6] = (state.contacts[hex6] ?? 0) + 1;
    state = UnreadCounts(channels: state.channels, contacts: co);
  }

  void markChannelRead(int index) {
    if ((state.channels[index] ?? 0) == 0) return;
    final ch = Map<int, int>.from(state.channels)..remove(index);
    state = UnreadCounts(channels: ch, contacts: state.contacts);
  }

  void markContactRead(String hex6) {
    if ((state.contacts[hex6] ?? 0) == 0) return;
    final co = Map<String, int>.from(state.contacts)..remove(hex6);
    state = UnreadCounts(channels: state.channels, contacts: co);
  }

  void reset() => state = const UnreadCounts();
}

final unreadCountsProvider =
    StateNotifierProvider<UnreadCountsNotifier, UnreadCounts>(
      (ref) => UnreadCountsNotifier(),
    );

/// Returns the first 6 bytes of [key] as a lowercase hex string.
String _hex6(Uint8List key) =>
    key.take(6).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

// ---------------------------------------------------------------------------
// Scanned devices
// ---------------------------------------------------------------------------

final scannedDevicesProvider = StateProvider<List<RadioDevice>>((_) => []);
