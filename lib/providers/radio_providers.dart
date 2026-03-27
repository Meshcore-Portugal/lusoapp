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
// Connection progress (step label + step index 0-5)
// ---------------------------------------------------------------------------

final connectionStepProvider = StateProvider<String>((_) => '');
final connectionProgressProvider = StateProvider<int>((_) => 0);

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

  void _setStep(int step, String label) {
    _ref.read(connectionProgressProvider.notifier).state = step;
    _ref.read(connectionStepProvider.notifier).state = label;
  }

  Future<bool> connectBle(String deviceId) async {
    state = TransportState.connecting;
    _setStep(0, 'A ligar via Bluetooth...');
    try {
      final transport = BleTransport.fromDeviceId(deviceId);
      final service = RadioService(transport);
      // Wire up listeners BEFORE connect() so we don't miss the radio's
      // immediate response to APP_START (SelfInfo, etc.).
      _ref.read(radioServiceProvider.notifier).state = service;
      _setupListeners(service);
      final ok = await service.connect();
      if (ok) {
        // Keep state = connecting while we fetch initial data so the progress
        // card remains visible.  Only flip to connected when fully ready.
        await _fetchInitialData(service);
        state = TransportState.connected;
        return true;
      }
      _ref.read(radioServiceProvider.notifier).state = null;
      state = TransportState.error;
      _setStep(0, '');
      return false;
    } catch (e) {
      state = TransportState.error;
      _setStep(0, '');
      return false;
    }
  }

  Future<bool> connectSerial(
    String deviceId, {
    ConnectionMode mode = ConnectionMode.companion,
  }) async {
    state = TransportState.connecting;
    _setStep(0, 'A ligar via USB série...');
    try {
      final baseTransport = await SerialTransport.fromDeviceId(deviceId);
      if (baseTransport == null) {
        state = TransportState.error;
        _setStep(0, '');
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
        // Keep state = connecting while we fetch initial data so the progress
        // card remains visible.  Only flip to connected when fully ready.
        await _fetchInitialData(service);
        state = TransportState.connected;
        return true;
      }
      _ref.read(radioServiceProvider.notifier).state = null;
      state = TransportState.error;
      _setStep(0, '');
      return false;
    } catch (e) {
      state = TransportState.error;
      _setStep(0, '');
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
    _setStep(0, '');
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

    // 0. Wait for SelfInfo — the radio sends it automatically after APP_START.
    //    Rather than a fixed 300 ms delay, we watch for the response and
    //    proceed as soon as it arrives (typically 50–100 ms over BLE).
    //    500 ms fallback ensures we still continue even if it never comes.
    _setStep(1, 'A aguardar resposta do rádio...');
    await _sendAndWait(
      service,
      () async {}, // no command needed — just listen
      (r) => r is SelfInfoResponse,
      timeout: const Duration(milliseconds: 500),
    );

    // 1. Device info — we need maxChannels before requesting channels.
    _setStep(2, 'A obter informação do dispositivo...');
    final devResp = await _sendAndWait(
      service,
      () => service.requestDeviceInfo(),
      (r) => r is DeviceInfoResponse || r is ErrorResponse,
    );
    log.d('DeviceInfo: ${devResp?.runtimeType ?? "TIMEOUT"}');

    // 2. Battery — fire and forget, let it arrive whenever.
    await service.requestBattAndStorage();

    // 3. Contacts — wait for the end-of-contacts marker.
    _setStep(3, 'A sincronizar contactos...');
    final contactsResp = await _sendAndWait(
      service,
      () => service.requestContacts(),
      (r) => r is EndContactsResponse,
      timeout: const Duration(seconds: 10),
    );
    log.d('Contacts: ${contactsResp?.runtimeType ?? "TIMEOUT"}');

    // 4. Channels — request each one and wait for its response before sending
    //    the next (spec: "send one command at a time").
    //    Timeout 500 ms: BLE writeWithoutResponse + notification RTT is
    //    typically 20–60 ms; 500 ms gives ample headroom on slow connections.
    //    Also terminates on ErrorResponse so we never block the full timeout
    //    for a channel slot the firmware rejects.
    _setStep(4, 'A sincronizar canais...');
    final maxChannels = service.deviceInfo?.maxChannels ?? 8;
    for (var i = 0; i < maxChannels; i++) {
      await _sendAndWait(
        service,
        () => service.requestChannel(i),
        (r) =>
            (r is ChannelInfoResponse && r.channel.index == i) ||
            r is ErrorResponse,
        timeout: const Duration(milliseconds: 500),
      );
    }
    log.d('Channels done (maxChannels=$maxChannels)');

    // 5. Drain any messages queued while the app was disconnected.
    //    The spec says to send CMD_SYNC_NEXT_MESSAGE during initialisation.
    //    RadioService._processResponse() continues the chain automatically
    //    (each received message triggers the next sync until the queue is empty).
    await service.syncNextMessage();

    _setStep(5, 'Ligado!');
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
