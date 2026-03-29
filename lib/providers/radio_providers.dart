import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';

import '../protocol/cayenne_lpp.dart';
import '../protocol/protocol.dart';
import '../services/notification_service.dart';
import '../services/radio_service.dart';
import '../services/storage_service.dart';
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
// Last connected device (loaded on app start from SharedPreferences)
// ---------------------------------------------------------------------------

final lastDeviceProvider = StateProvider<LastDevice?>((_) => null);

// ---------------------------------------------------------------------------
// Connection manager
// ---------------------------------------------------------------------------

class ConnectionNotifier extends StateNotifier<TransportState> {
  ConnectionNotifier(this._ref) : super(TransportState.disconnected);
  final Ref _ref;

  StreamSubscription<void>? _connectionLostSub;
  Timer? _batteryPollTimer;

  void _setStep(int step, String label) {
    _ref.read(connectionProgressProvider.notifier).state = step;
    _ref.read(connectionStepProvider.notifier).state = label;
  }

  Future<bool> connectBle(String deviceId, String deviceName) async {
    state = TransportState.connecting;
    _setStep(0, 'A ligar via Bluetooth...');
    try {
      final transport = BleTransport.fromDeviceId(deviceId);
      final service = RadioService(transport);
      _ref.read(radioServiceProvider.notifier).state = service;
      _setupListeners(service);
      final ok = await service.connect();
      if (ok) {
        await _fetchInitialData(service);
        state = TransportState.connected;
        await StorageService.instance.saveLastDevice(
          id: deviceId,
          type: 'ble',
          name: deviceName,
        );
        _ref.read(lastDeviceProvider.notifier).state = LastDevice(
          id: deviceId,
          type: 'ble',
          name: deviceName,
        );
        _setupAutoReconnect(service, () => connectBle(deviceId, deviceName));
        _startBatteryPolling(service);
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
    String deviceId,
    String deviceName, {
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
      _ref.read(radioServiceProvider.notifier).state = service;
      _setupListeners(service);
      final ok = await service.connect();
      if (ok) {
        await _fetchInitialData(service);
        state = TransportState.connected;
        final typeStr =
            mode == ConnectionMode.kiss ? 'serialKiss' : 'serialCompanion';
        await StorageService.instance.saveLastDevice(
          id: deviceId,
          type: typeStr,
          name: deviceName,
        );
        _ref.read(lastDeviceProvider.notifier).state = LastDevice(
          id: deviceId,
          type: typeStr,
          name: deviceName,
        );
        _startBatteryPolling(service);
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
    _batteryPollTimer?.cancel();
    _batteryPollTimer = null;
    await _connectionLostSub?.cancel();
    _connectionLostSub = null;
    final service = _ref.read(radioServiceProvider);
    if (service != null) {
      await service.dispose();
      _ref.read(radioServiceProvider.notifier).state = null;
    }
    _ref.read(unreadCountsProvider.notifier).reset();
    _setStep(0, '');
    state = TransportState.disconnected;
  }

  /// Poll battery every 30 s while connected.
  void _startBatteryPolling(RadioService service) {
    _batteryPollTimer?.cancel();
    _batteryPollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (state == TransportState.connected) {
        service.requestBattAndStorage().catchError((_) {});
      }
    });
  }

  /// Subscribe to unexpected connection loss and attempt one auto-reconnect.
  void _setupAutoReconnect(
    RadioService service,
    Future<bool> Function() reconnector,
  ) {
    _connectionLostSub?.cancel();
    _connectionLostSub = service.connectionLost.listen((_) async {
      if (state != TransportState.connected) return;
      _ref.read(radioServiceProvider.notifier).state = null;
      _setStep(0, 'Conexão perdida. A reconectar...');
      state = TransportState.connecting;
      await Future.delayed(const Duration(seconds: 2));
      final ok = await reconnector();
      if (!ok) {
        state = TransportState.error;
        _setStep(0, 'Reconexão falhou.');
      }
    });
  }

  void _setupListeners(RadioService service) {
    service.responses.listen((response) {
      switch (response) {
        case ContactResponse():
        case EndContactsResponse():
          _ref.read(contactsProvider.notifier).refresh(service.contacts);
        case ContactDeletedPush():
          // Radio confirmed deletion — refresh from the service's now-updated list.
          _ref.read(contactsProvider.notifier).refresh(service.contacts);
        case ChannelInfoResponse():
          _ref.read(channelsProvider.notifier).refresh(service.channels);
        case PrivateMessageResponse(:final message):
          _ref.read(messagesProvider.notifier).addMessage(message);
          if (!message.isOutgoing) {
            _ref.read(networkStatsProvider.notifier).incrementRx();
          }
          if (message.senderKey != null) {
            _ref
                .read(unreadCountsProvider.notifier)
                .incrementContact(_hex6(message.senderKey!));
          }
          if (!message.isOutgoing) {
            final senderHex6 =
                message.senderKey != null ? _hex6(message.senderKey!) : null;
            final contacts = _ref.read(contactsProvider);
            final contact =
                senderHex6 != null
                    ? contacts
                        .where((c) => _hex6(c.publicKey) == senderHex6)
                        .firstOrNull
                    : null;
            final senderName = contact?.name ?? senderHex6 ?? 'Desconhecido';
            NotificationService.instance.showPrivateMessage(
              senderName: senderName,
              text: message.text,
              isAppInForeground: AppLifecycleObserver.isInForeground,
            );
          }
        case ChannelMessageResponse(:final message):
          _ref.read(messagesProvider.notifier).addMessage(message);
          if (!message.isOutgoing) {
            _ref.read(networkStatsProvider.notifier).incrementRx();
          }
          if (message.channelIndex != null) {
            _ref
                .read(unreadCountsProvider.notifier)
                .incrementChannel(message.channelIndex!);
          }
          if (!message.isOutgoing) {
            final channels = _ref.read(channelsProvider);
            final idx = message.channelIndex ?? 0;
            final channel = channels.where((c) => c.index == idx).firstOrNull;
            final channelName =
                (channel != null && channel.name.isNotEmpty)
                    ? channel.name
                    : 'Canal $idx';
            NotificationService.instance.showChannelMessage(
              channelName: channelName,
              senderName: message.senderName ?? 'Desconhecido',
              text: message.text,
              isAppInForeground: AppLifecycleObserver.isInForeground,
            );
          }
        case SelfInfoResponse(:final info):
          _ref.read(selfInfoProvider.notifier).state = info;
          _ref.read(radioConfigProvider.notifier).state = info.radioConfig;
        case BattAndStorageResponse(:final batteryMv):
          _ref.read(batteryProvider.notifier).state = batteryMv;
          _ref.read(batteryHistoryProvider.notifier).add(batteryMv);
        case DeviceInfoResponse(:final info):
          _ref.read(deviceInfoProvider.notifier).state = info;
        case SendConfirmedPush():
          _ref.read(messagesProvider.notifier).confirmLastOutgoing();
        case SentResponse(:final routeFlag):
          _ref.read(networkStatsProvider.notifier).incrementTx();
          _ref.read(messagesProvider.notifier).markLastOutgoingRoute(routeFlag);
        case ErrorResponse():
          _ref.read(networkStatsProvider.notifier).incrementError();
        case AdvertPush():
          _ref.read(networkStatsProvider.notifier).incrementHeard();
        case TelemetryPush(:final data):
          final readings = CayenneLPP.decode(data);
          if (readings.isNotEmpty) {
            _ref.read(telemetryProvider.notifier).add(readings);
          }
        case TraceDataPush(:final data):
          final contacts = _ref.read(contactsProvider);
          final result = parseTraceDataPush(data, contacts);
          if (result != null) {
            _ref.read(traceResultProvider.notifier).state = result;
          }
        case StatusResponsePush(:final data):
          final stats = RepeaterStats.fromPushData(data);
          if (stats != null) {
            final current = Map<String, RepeaterStats>.from(
              _ref.read(repeaterStatusProvider),
            );
            current[stats.pubKeyPrefixHex] = stats;
            _ref.read(repeaterStatusProvider.notifier).state = current;
          }
        case LoginSuccessPush():
          _ref.read(loginResultProvider.notifier).state = true;
        case LoginFailPush():
          _ref.read(loginResultProvider.notifier).state = false;
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
  bool _loaded = false;

  /// Load cached contacts from storage (called once on app start).
  Future<void> loadFromStorage() async {
    if (_loaded) return;
    _loaded = true;
    final stored = await StorageService.instance.loadContacts();
    if (stored.isNotEmpty) state = stored;
  }

  void refresh(List<Contact> contacts) {
    final merged =
        contacts.map((incoming) {
          final existing = state.firstWhere(
            (c) => _keysEqual(c.publicKey, incoming.publicKey),
            orElse: () => incoming,
          );
          return existing.customName != null
              ? incoming.withCustomName(existing.customName)
              : incoming;
        }).toList();
    state = merged;
    StorageService.instance.saveContacts(merged);
  }

  void setCustomName(Uint8List publicKey, String? customName) {
    final next =
        state
            .map(
              (c) =>
                  _keysEqual(c.publicKey, publicKey)
                      ? c.withCustomName(customName)
                      : c,
            )
            .toList();
    state = next;
    StorageService.instance.saveContacts(next);
  }

  void remove(Uint8List publicKey) {
    final next =
        state.where((c) => !_keysEqual(c.publicKey, publicKey)).toList();
    state = next;
    StorageService.instance.saveContacts(next);
  }

  static bool _keysEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
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

  final Set<String> _loadedKeys = {};

  void addMessage(ChatMessage message) {
    state = [...state, message];
    _saveForMessage(message);
  }

  void addOutgoing(ChatMessage message) {
    state = [...state, message];
    _saveForMessage(message);
  }

  /// Increment the heard-by-repeater count on the matching sent channel message.
  /// Called when a loopback echo of our own channel message is received.
  /// Matches first by [channelIndex] + [timestamp] (exact, since both encoder
  /// and stored message now share the same computed second), then falls back
  /// to body-text match as a safeguard for messages sent before this fix.
  void incrementHeardCount(
    int channelIndex,
    String bodyText, {
    int? timestamp,
  }) {
    for (var i = state.length - 1; i >= 0; i--) {
      final msg = state[i];
      if (!msg.isOutgoing || msg.channelIndex != channelIndex) continue;
      final matchByTs = timestamp != null && msg.timestamp == timestamp;
      final matchByText = msg.text == bodyText;
      if (matchByTs || matchByText) {
        final updated = msg.copyWith(heardCount: msg.heardCount + 1);
        final newList = List<ChatMessage>.from(state);
        newList[i] = updated;
        state = newList;
        _saveForMessage(updated);
        return;
      }
    }
  }

  /// Mark the most recent unconfirmed outgoing message as confirmed.
  /// Called when a [SendConfirmedPush] arrives from the radio.
  void confirmLastOutgoing() {
    for (var i = state.length - 1; i >= 0; i--) {
      final msg = state[i];
      if (msg.isOutgoing && !msg.confirmed) {
        final updated = msg.copyWith(confirmed: true);
        final newList = List<ChatMessage>.from(state);
        newList[i] = updated;
        state = newList;
        _saveForMessage(updated);
        return;
      }
    }
  }

  /// Store the route flag on the most recent outgoing private message.
  /// Called when [SentResponse] arrives: 0 = direct, 1 = flood (via repeaters).
  void markLastOutgoingRoute(int routeFlag) {
    for (var i = state.length - 1; i >= 0; i--) {
      final msg = state[i];
      if (msg.isOutgoing &&
          msg.sentRouteFlag == null &&
          msg.channelIndex == null) {
        final updated = msg.copyWith(sentRouteFlag: routeFlag);
        final newList = List<ChatMessage>.from(state);
        newList[i] = updated;
        state = newList;
        _saveForMessage(updated);
        return;
      }
    }
  }

  /// Lazily load persisted messages for a private contact key (hex6).
  /// No-op if already loaded. Safe to call on every screen open.
  Future<void> ensureLoadedForContact(String hex6) async {
    final key = 'contact_$hex6';
    if (_loadedKeys.contains(key)) return;
    _loadedKeys.add(key);
    final stored = await StorageService.instance.loadMessages(key);
    if (stored.isEmpty) return;
    _mergeStored(stored);
  }

  /// Lazily load persisted messages for a channel index.
  Future<void> ensureLoadedForChannel(int index) async {
    final key = 'ch_$index';
    if (_loadedKeys.contains(key)) return;
    _loadedKeys.add(key);
    final stored = await StorageService.instance.loadMessages(key);
    if (stored.isEmpty) return;
    _mergeStored(stored);
  }

  void _mergeStored(List<ChatMessage> stored) {
    // Deduplicate by (timestamp, isOutgoing, text hashCode).
    final existing = {for (final m in state) _msgId(m)};
    final incoming =
        stored.where((m) => !existing.contains(_msgId(m))).toList();
    if (incoming.isEmpty) return;
    final merged = [...incoming, ...state]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    state = merged;
  }

  String _msgId(ChatMessage m) =>
      '${m.timestamp}_${m.isOutgoing ? 1 : 0}_${m.text.hashCode}';

  void _saveForMessage(ChatMessage msg) {
    final String storageKey;
    if (msg.channelIndex != null) {
      storageKey = 'ch_${msg.channelIndex}';
    } else if (msg.senderKey != null) {
      storageKey = 'contact_${_hex6(msg.senderKey!)}';
    } else {
      return;
    }
    // Collect all messages for this key.
    final forKey =
        state.where((m) {
          if (msg.channelIndex != null) {
            return m.channelIndex == msg.channelIndex;
          }
          if (m.senderKey == null) return false;
          return _prefixMatch6(m.senderKey!, msg.senderKey!);
        }).toList();
    StorageService.instance.saveMessages(storageKey, forKey);
  }

  bool _prefixMatch6(Uint8List a, Uint8List b) {
    final len = (a.length < b.length ? a.length : b.length).clamp(0, 6);
    for (var i = 0; i < len; i++) {
      if (a[i] != b[i]) return false;
    }
    return len > 0;
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

// ---------------------------------------------------------------------------
// Notification settings
// ---------------------------------------------------------------------------

class NotificationSettingsNotifier extends StateNotifier<NotificationSettings> {
  NotificationSettingsNotifier() : super(const NotificationSettings());

  Future<void> loadFromStorage() async {
    final s = await StorageService.instance.loadNotificationSettings();
    state = s;
    NotificationService.instance.settings = s;
  }

  void update(NotificationSettings settings) {
    state = settings;
    NotificationService.instance.settings = settings;
    StorageService.instance.saveNotificationSettings(settings);
  }
}

final notificationSettingsProvider =
    StateNotifierProvider<NotificationSettingsNotifier, NotificationSettings>(
      (ref) => NotificationSettingsNotifier(),
    );

/// Returns the first 6 bytes of [key] as a lowercase hex string.
String _hex6(Uint8List key) =>
    key.take(6).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

// ---------------------------------------------------------------------------
// Battery history
// ---------------------------------------------------------------------------

class BatteryReading {
  const BatteryReading({required this.timestamp, required this.millivolts});
  final DateTime timestamp;
  final int millivolts;
  double get volts => millivolts / 1000.0;
}

class BatteryHistoryNotifier extends StateNotifier<List<BatteryReading>> {
  BatteryHistoryNotifier() : super([]);

  static const _maxEntries = 120;

  void add(int millivolts) {
    if (millivolts <= 0) return;
    final entry = BatteryReading(
      timestamp: DateTime.now(),
      millivolts: millivolts,
    );
    final updated = [...state, entry];
    state =
        updated.length > _maxEntries
            ? updated.sublist(updated.length - _maxEntries)
            : updated;
  }
}

final batteryHistoryProvider =
    StateNotifierProvider<BatteryHistoryNotifier, List<BatteryReading>>(
      (ref) => BatteryHistoryNotifier(),
    );

// ---------------------------------------------------------------------------
// Network statistics
// ---------------------------------------------------------------------------

class NetworkStats {
  const NetworkStats({
    this.rxMessages = 0,
    this.txMessages = 0,
    this.errors = 0,
    this.heardNodes = 0,
  });
  final int rxMessages;
  final int txMessages;
  final int errors;
  final int heardNodes;

  NetworkStats copyWith({
    int? rxMessages,
    int? txMessages,
    int? errors,
    int? heardNodes,
  }) => NetworkStats(
    rxMessages: rxMessages ?? this.rxMessages,
    txMessages: txMessages ?? this.txMessages,
    errors: errors ?? this.errors,
    heardNodes: heardNodes ?? this.heardNodes,
  );
}

class NetworkStatsNotifier extends StateNotifier<NetworkStats> {
  NetworkStatsNotifier() : super(const NetworkStats());

  void incrementRx() =>
      state = state.copyWith(rxMessages: state.rxMessages + 1);
  void incrementTx() =>
      state = state.copyWith(txMessages: state.txMessages + 1);
  void incrementError() => state = state.copyWith(errors: state.errors + 1);
  void incrementHeard() =>
      state = state.copyWith(heardNodes: state.heardNodes + 1);
  void reset() => state = const NetworkStats();
}

final networkStatsProvider =
    StateNotifierProvider<NetworkStatsNotifier, NetworkStats>(
      (ref) => NetworkStatsNotifier(),
    );

// ---------------------------------------------------------------------------
// Telemetry (CayenneLPP sensor readings)
// ---------------------------------------------------------------------------

class TelemetryEntry {
  const TelemetryEntry({required this.timestamp, required this.readings});
  final DateTime timestamp;
  final List<CayenneReading> readings;
}

class TelemetryNotifier extends StateNotifier<List<TelemetryEntry>> {
  TelemetryNotifier() : super([]);

  static const _maxEntries = 50;

  void add(List<CayenneReading> readings) {
    if (readings.isEmpty) return;
    final entry = TelemetryEntry(timestamp: DateTime.now(), readings: readings);
    final updated = [entry, ...state];
    state =
        updated.length > _maxEntries
            ? updated.sublist(0, _maxEntries)
            : updated;
  }
}

final telemetryProvider =
    StateNotifierProvider<TelemetryNotifier, List<TelemetryEntry>>(
      (ref) => TelemetryNotifier(),
    );

// ---------------------------------------------------------------------------
// Scanned devices
// ---------------------------------------------------------------------------

final scannedDevicesProvider = StateProvider<List<RadioDevice>>((_) => []);

// ---------------------------------------------------------------------------
// Trace result
// ---------------------------------------------------------------------------

/// Latest parsed [TraceResult] received from a PUSH_CODE_TRACE_DATA (0x89).
/// Updated whenever a new trace push arrives; null until first trace received.
final traceResultProvider = StateProvider<TraceResult?>((ref) => null);

// ---------------------------------------------------------------------------
// Repeater remote-admin
// ---------------------------------------------------------------------------

/// Map of repeater pub-key-prefix hex → latest [RepeaterStats] received.
final repeaterStatusProvider = StateProvider<Map<String, RepeaterStats>>(
  (_) => {},
);

/// Login result: null = no attempt, true = success, false = fail.
/// Reset to null by the admin sheet before each new login attempt.
final loginResultProvider = StateProvider<bool?>((_) => null);

// ---------------------------------------------------------------------------
// Contact favorites (app-side, not stored on radio)
// ---------------------------------------------------------------------------

class FavoritesNotifier extends StateNotifier<Set<String>> {
  FavoritesNotifier() : super({});

  Future<void> loadFromStorage() async {
    state = await StorageService.instance.loadFavorites();
  }

  void toggle(String keyHex) {
    final next = Set<String>.from(state);
    if (next.contains(keyHex)) {
      next.remove(keyHex);
    } else {
      next.add(keyHex);
    }
    state = next;
    StorageService.instance.saveFavorites(next);
  }

  bool isFavorite(String keyHex) => state.contains(keyHex);
}

final favoritesProvider = StateNotifierProvider<FavoritesNotifier, Set<String>>(
  (ref) => FavoritesNotifier(),
);
