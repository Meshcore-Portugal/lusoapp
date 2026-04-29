part of '../radio_providers.dart';

// Messages
class MessagesNotifier extends StateNotifier<List<ChatMessage>> {
  MessagesNotifier(this._ref) : super([]);
  final Ref _ref;

  final Set<String> _loadedKeys = {};

  /// Per-key save lock: ensures saves for the same key are serialised so a
  /// slower earlier save never overwrites a faster later save.
  final Map<String, Future<void>> _saveLocks = {};

  // Internal partition: partitionKey → messages for that conversation.
  // Maintained alongside state so addMessage() dedup and forContact/forChannel
  // queries are O(bucket_size) instead of O(all_messages).
  Map<String, List<ChatMessage>> _partitioned = {};

  /// Compute the partition key for a message.
  ///   'c_<hex6>'  — private contact (outgoing or incoming)
  ///   'ch_<idx>'  — channel
  static String _partitionKey(ChatMessage m) {
    if (m.channelIndex != null) return 'ch_${m.channelIndex}';
    if (m.senderKey != null) return 'c_${_hex6(m.senderKey!)}';
    return 'other';
  }

  void _rebuildPartitioned(List<ChatMessage> msgs) {
    final Map<String, List<ChatMessage>> map = {};
    for (final m in msgs) {
      (map[_partitionKey(m)] ??= []).add(m);
    }
    _partitioned = map;
  }

  /// Bump the per-key version counter so scoped provider watchers rebuild.
  void _bumpVersion(String key) {
    final current = _ref.read(messageVersionsProvider);
    _ref.read(messageVersionsProvider.notifier).state = {
      ...current,
      key: (current[key] ?? 0) + 1,
    };
  }

  // ---------------------------------------------------------------------------
  // Send-failure timer: arm when a private outgoing message is added; cancel
  // when the radio confirms it was sent (SentResponse). If the timer fires
  // without a SentResponse the message is marked as failed.
  // ---------------------------------------------------------------------------

  /// One timer per outgoing private message (keyed by timestamp).
  final Map<int, Timer> _sendTimers = {};

  static const _sendTimeout = Duration(seconds: 45);

  void _armSendTimer(int timestamp) {
    _sendTimers[timestamp]?.cancel();
    _sendTimers[timestamp] = Timer(_sendTimeout, () {
      _sendTimers.remove(timestamp);
      _markPrivateMessageFailed(timestamp);
    });
  }

  void _markPrivateMessageFailed(int timestamp) {
    final idx = state.indexWhere(
      (m) =>
          m.isOutgoing &&
          m.isPrivate &&
          m.timestamp == timestamp &&
          m.sentRouteFlag == null &&
          !m.failed,
    );
    if (idx < 0) return;
    final updated = state[idx].copyWith(failed: true);
    final newList = List<ChatMessage>.from(state);
    newList[idx] = updated;
    state = newList;
    _saveForMessage(updated);
  }

  /// Reset [msg] to pending state and re-arm the send timer. Returns the
  /// updated message (with retryCount incremented) for the caller to resend.
  /// A fresh timestamp is generated so the radio does not deduplicate the
  /// retry, and the message is moved to the end of the list so the positional
  /// SentResponse match always lands on it.
  ChatMessage? markMessageRetrying(ChatMessage msg) {
    for (var i = state.length - 1; i >= 0; i--) {
      final m = state[i];
      if (m.isOutgoing &&
          m.isPrivate &&
          m.timestamp == msg.timestamp &&
          _senderKeyMatch(m, msg)) {
        // New timestamp so the radio treats this as a fresh packet and the
        // per-message failure timer is keyed correctly.
        final newTs = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final updated = ChatMessage(
          text: m.text,
          timestamp: newTs,
          isOutgoing: true,
          senderKey: m.senderKey,
          channelIndex: null,
          senderName: m.senderName,
          confirmed: false,
          snr: null,
          pathLen: null,
          heardCount: 0,
          sentRouteFlag: null,
          packetHashHex: null,
          isCliResponse: m.isCliResponse,
          failed: false,
          retryCount: m.retryCount + 1,
        );
        // Remove from old position and append so it becomes the list tail.
        // markLastOutgoingRoute searches from the end, so the SentResponse
        // will land on this message rather than a newer failed one.
        final newList = List<ChatMessage>.from(state)..removeAt(i);
        newList.add(updated);
        state = newList;
        _rebuildPartitioned(state);
        _bumpVersion(_partitionKey(updated));
        _saveForMessage(updated);
        _armSendTimer(newTs);
        return updated;
      }
    }
    return null;
  }

  @override
  void dispose() {
    for (final t in _sendTimers.values) {
      t.cancel();
    }
    _sendTimers.clear();
    super.dispose();
  }

  void addMessage(ChatMessage message) {
    // Dedup: check only the bucket for this conversation — O(bucket) not O(all).
    // Include senderKey prefix so messages from different contacts with
    // identical text+timestamp are never wrongly merged.
    final key = _partitionKey(message);
    final bucket = _partitioned[key] ?? const [];
    final dominated = bucket.any(
      (m) =>
          m.timestamp == message.timestamp &&
          m.channelIndex == message.channelIndex &&
          m.text == message.text &&
          m.isOutgoing == message.isOutgoing &&
          _senderKeyMatch(m, message),
    );
    if (dominated) return;
    state = [...state, message];
    _rebuildPartitioned(state);
    _bumpVersion(key);
    _saveForMessage(message);
  }

  void addOutgoing(ChatMessage message) {
    state = [...state, message];
    final key = _partitionKey(message);
    _rebuildPartitioned(state);
    _bumpVersion(key);
    _saveForMessage(message);
    _ref.read(networkStatsProvider.notifier).incrementTx();
    // Arm failure timer for private messages (no timer for channel messages —
    // they don't use SentResponse and are best-effort).
    if (message.isPrivate) {
      _armSendTimer(message.timestamp);
    }
  }

  /// Increment heard count on an outgoing channel message matched by packet
  /// hash.  The first 0x88 duplicate for a GRP_TXT packet is the original
  /// transmission; subsequent duplicates are repeater echoes.  [totalHeard]
  /// is the cumulative repeater count (duplicates minus 1).
  ///
  /// If [hashHex] matches a message that already has the same packetHashHex,
  /// Clear [packetHashHex] and [heardCount] on a channel message so that a
  /// retransmission can claim a fresh hash from the next loopback echo.
  void resetChannelResend(ChatMessage msg) {
    final idx = state.indexWhere(
      (m) => m.timestamp == msg.timestamp && m.channelIndex == msg.channelIndex,
    );
    if (idx < 0) return;
    final updated = state[idx].copyWith(packetHashHex: null, heardCount: 0);
    final newList = List<ChatMessage>.from(state);
    newList[idx] = updated;
    state = newList;
    _saveForMessage(updated);
  }

  /// update its heardCount.  Otherwise try to assign the hash to the most
  /// recent outgoing message on [channelIndex] that has no hash yet.
  ///
  /// Returns `true` if the hash was matched/assigned to an outgoing message,
  /// `false` if not (i.e. this is an incoming message from another station).
  bool incrementHeardByHash(int channelIndex, String hashHex, int totalHeard) {
    // First pass — find a message already tagged with this hash.
    for (var i = state.length - 1; i >= 0; i--) {
      final msg = state[i];
      if (msg.packetHashHex == hashHex) {
        if (msg.heardCount != totalHeard) {
          final updated = msg.copyWith(heardCount: totalHeard);
          final newList = List<ChatMessage>.from(state);
          newList[i] = updated;
          state = newList;
          _bumpVersion(_partitionKey(updated));
          _saveForMessage(updated);
        }
        return true;
      }
    }
    // Second pass — assign hash to the most recent outgoing message on this
    // channel that does not yet have a packetHashHex.
    // Only consider messages sent in the last 60 seconds to avoid wrongly
    // assigning an incoming packet's hash to a stale outgoing message.
    final cutoff = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 60;
    for (var i = state.length - 1; i >= 0; i--) {
      final msg = state[i];
      if (!msg.isOutgoing || msg.channelIndex != channelIndex) continue;
      if (msg.packetHashHex != null) continue;
      if (msg.timestamp < cutoff) break; // too old — stop searching
      final updated = msg.copyWith(
        packetHashHex: hashHex,
        heardCount: totalHeard,
      );
      final newList = List<ChatMessage>.from(state);
      newList[i] = updated;
      state = newList;
      _rebuildPartitioned(state);
      _bumpVersion(_partitionKey(updated));
      _saveForMessage(updated);
      return true;
    }
    return false;
  }

  // Per-channel FIFO buffer of unmatched GRP_TXT packet hashes from 0x88 frames.
  // Populated when the hash doesn't match any outgoing message (i.e. it came
  // from another station).  Consumed when the corresponding ChannelMessageResponse
  // arrives so the incoming ChatMessage can be tagged with its packetHashHex.
  final Map<int, List<String>> _pendingIncomingHashes = {};

  /// Buffer [hashHex] as a pending incoming-message path for [channelIndex].
  void queueIncomingHash(int channelIndex, String hashHex) {
    final q = _pendingIncomingHashes[channelIndex] ?? <String>[];
    if (q.length >= 16) q.removeAt(0); // prevent unbounded growth
    _pendingIncomingHashes[channelIndex] = [...q, hashHex];
  }

  /// Pop and return the oldest pending incoming hash for [channelIndex],
  /// or null if none is buffered.
  String? consumeIncomingHash(int channelIndex) {
    final q = _pendingIncomingHashes[channelIndex];
    if (q == null || q.isEmpty) return null;
    final hash = q.first;
    _pendingIncomingHashes[channelIndex] = q.sublist(1);
    return hash;
  }

  /// Mark the most recent unconfirmed outgoing message as confirmed.
  /// Called when a [SendConfirmedPush] arrives from the radio.
  void confirmLastOutgoing() {
    // Walk backwards and only touch the most-recently-added unconfirmed
    // outgoing message (private or channel — whichever came last).
    for (var i = state.length - 1; i >= 0; i--) {
      final msg = state[i];
      if (msg.isOutgoing && !msg.confirmed) {
        final updated = msg.copyWith(confirmed: true);
        final newList = List<ChatMessage>.from(state);
        newList[i] = updated;
        state = newList;
        _bumpVersion(_partitionKey(updated));
        _saveForMessage(updated);
        return;
      }
    }
  }

  /// Store the route flag on the most recent outgoing *private* message that
  /// does not yet have a sentRouteFlag.  Channel messages don't use this flag.
  /// Called when [SentResponse] arrives: 0 = direct, 1 = flood.
  void markLastOutgoingRoute(int routeFlag) {
    for (var i = state.length - 1; i >= 0; i--) {
      final msg = state[i];
      if (msg.isOutgoing &&
          msg.sentRouteFlag == null &&
          msg.channelIndex == null &&
          !msg.failed) {
        // Cancel the failure timer — radio confirmed it sent the packet.
        _sendTimers[msg.timestamp]?.cancel();
        _sendTimers.remove(msg.timestamp);
        final updated = msg.copyWith(sentRouteFlag: routeFlag);
        final newList = List<ChatMessage>.from(state);
        newList[i] = updated;
        state = newList;
        _bumpVersion(_partitionKey(updated));
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

  /// Returns the device-scoped storage key for a channel message conversation.
  /// Falls back to the unscoped key when no radio is connected (e.g. on cold
  /// startup before a connection is established).
  String _channelKey(int index) {
    final deviceId = _ref.read(currentRadioIdProvider);
    if (deviceId != null) {
      return 'ch_${StorageService.sanitizeId(deviceId)}_$index';
    }
    return 'ch_$index';
  }

  /// Lazily load persisted messages for a channel index.
  Future<void> ensureLoadedForChannel(int index) async {
    final key = _channelKey(index);
    if (_loadedKeys.contains(key)) return;
    _loadedKeys.add(key);
    final stored = await StorageService.instance.loadMessages(key);
    if (stored.isEmpty) return;
    _mergeStored(stored);
  }

  /// Remove all channel messages from in-memory state without touching storage.
  /// Called when connecting to a different radio so that stale channel messages
  /// from the previous radio are not visible before the new radio's history loads.
  void clearChannelMessages() {
    state = state.where((m) => m.channelIndex == null).toList();
    _rebuildPartitioned(state);
    // Remove channel-keyed entries from the loaded-keys set so that the new
    // radio's channel messages can be loaded fresh.
    _loadedKeys.removeWhere((k) => k.startsWith('ch_'));
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
    _rebuildPartitioned(state);
    // Bump versions for all keys touched by the newly merged messages.
    final touchedKeys = incoming.map(_partitionKey).toSet();
    for (final k in touchedKeys) {
      _bumpVersion(k);
    }
  }

  String _msgId(ChatMessage m) {
    // Use the full text instead of hashCode — hashCode is not stable and
    // can collide, causing legitimate messages to be treated as duplicates.
    final keyPart =
        m.senderKey != null ? _hex6(m.senderKey!) : 'ch${m.channelIndex}';
    return '${m.timestamp}_${m.isOutgoing ? 1 : 0}_${m.channelIndex}_${m.text}_$keyPart';
  }

  /// True when both messages have the same sender (or both have no sender).
  bool _senderKeyMatch(ChatMessage a, ChatMessage b) {
    if (a.senderKey == null && b.senderKey == null) return true;
    if (a.senderKey == null || b.senderKey == null) return false;
    return _prefixMatch6(a.senderKey!, b.senderKey!);
  }

  void _saveForMessage(ChatMessage msg) {
    final String storageKey;
    if (msg.channelIndex != null) {
      storageKey = _channelKey(msg.channelIndex!);
    } else if (msg.senderKey != null) {
      storageKey = 'contact_${_hex6(msg.senderKey!)}';
    } else {
      return;
    }
    // Use the partition to get messages for this key — O(1) instead of O(n).
    final partKey = _partitionKey(msg);
    final forKey = List<ChatMessage>.from(_partitioned[partKey] ?? const []);

    // Serialise saves per key: chain each save behind the previous one so
    // a slower earlier future never overwrites a faster later snapshot.
    final prev = _saveLocks[storageKey] ?? Future.value();
    final next = prev.then(
      (_) => StorageService.instance.saveMessages(storageKey, forKey),
    );
    _saveLocks[storageKey] = next;
    // Clean up the lock entry once the save completes to avoid unbounded growth.
    next.whenComplete(() {
      if (_saveLocks[storageKey] == next) _saveLocks.remove(storageKey);
    });
  }

  bool _prefixMatch6(Uint8List a, Uint8List b) {
    final len = (a.length < b.length ? a.length : b.length).clamp(0, 6);
    if (len == 0) return false; // don't match two empty/unknown keys
    for (var i = 0; i < len; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Get messages for a specific contact (private).
  /// O(1) via _partitioned map — no list scan needed.
  List<ChatMessage> forContact(Uint8List? contactKey) {
    if (contactKey == null) return const [];
    return _partitioned['c_${_hex6(contactKey)}'] ?? const [];
  }

  /// Get messages for a specific channel.
  /// O(1) via _partitioned map — no list scan needed.
  List<ChatMessage> forChannel(int channelIndex) {
    return _partitioned['ch_$channelIndex'] ?? const [];
  }

  /// Delete a single message from state and re-persist its conversation.
  void deleteMessage(ChatMessage msg) {
    final targetId = _msgId(msg);
    state = state.where((m) => _msgId(m) != targetId).toList();
    _rebuildPartitioned(state);
    if (msg.channelIndex != null) {
      final forKey =
          state.where((m) => m.channelIndex == msg.channelIndex).toList();
      StorageService.instance.saveMessages(
        _channelKey(msg.channelIndex!),
        forKey,
      );
    } else if (msg.senderKey != null) {
      final key = 'contact_${_hex6(msg.senderKey!)}';
      final forKey =
          state
              .where(
                (m) =>
                    m.senderKey != null &&
                    _prefixMatch6(m.senderKey!, msg.senderKey!),
              )
              .toList();
      StorageService.instance.saveMessages(key, forKey);
    }
  }

  /// Delete all messages for a channel from state and storage.
  Future<void> deleteChannelHistory(int channelIndex) async {
    state = state.where((m) => m.channelIndex != channelIndex).toList();
    _rebuildPartitioned(state);
    await StorageService.instance.clearMessages(_channelKey(channelIndex));
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
      return MessagesNotifier(ref);
    });
