part of '../radio_providers.dart';

// Messages
class MessagesNotifier extends StateNotifier<List<ChatMessage>> {
  MessagesNotifier(this._ref) : super([]);
  final Ref _ref;

  static const _sendTimeout = Duration(seconds: 45);
  static const _minAckTimeoutMs = 1500;
  static const _maxPrivateAttempts = 4;
  static const _floodAfterAttempt = 2;

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

  /// Append one message to its own bucket instead of re-partitioning the whole
  /// list. Messages are appended in arrival order, which matches the order a
  /// full rebuild would produce, so the buckets stay identical.
  void _appendPartitioned(ChatMessage m) {
    (_partitioned[_partitionKey(m)] ??= <ChatMessage>[]).add(m);
  }

  /// Keep [contactLastMsgTsProvider] up to date for the private messages in
  /// [msgs]. Maintained incrementally — this map used to be derived by scanning
  /// every message (and hashing every entry) on each state change, with the
  /// contacts screen watching the result.
  void _touchLastMsgTs(Iterable<ChatMessage> msgs) {
    final current = _ref.read(contactLastMsgTsProvider);
    Map<String, int>? next;
    for (final m in msgs) {
      if (m.channelIndex != null) continue;
      final key = m.senderKey;
      if (key == null || key.length < 6) continue;
      final hex = _hex6(key);
      if (((next ?? current)[hex] ?? 0) >= m.timestamp) continue;
      next ??= Map<String, int>.from(current);
      next[hex] = m.timestamp;
    }
    if (next != null) {
      _ref.read(contactLastMsgTsProvider.notifier).state = next;
    }
  }

  /// Recompute the last-message timestamp for one contact from its bucket.
  /// Needed after a delete, where the newest message may be the one removed.
  void _recomputeLastMsgTs(Uint8List senderKey) {
    if (senderKey.length < 6) return;
    final hex = _hex6(senderKey);
    var newest = 0;
    for (final m in _partitioned['c_$hex'] ?? const <ChatMessage>[]) {
      if (m.timestamp > newest) newest = m.timestamp;
    }
    final current = _ref.read(contactLastMsgTsProvider);
    if ((current[hex] ?? 0) == newest) return;
    final next = Map<String, int>.from(current);
    if (newest == 0) {
      next.remove(hex);
    } else {
      next[hex] = newest;
    }
    _ref.read(contactLastMsgTsProvider.notifier).state = next;
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

  /// One timer per outgoing private message waiting for delivery confirmation.
  final Map<int, Timer> _ackTimers = {};

  /// FIFO of pending outgoing private message timestamps.
  /// SentResponse has no timestamp, so we must match by send order.
  final List<int> _pendingPrivateRouteQueue = [];

  /// FIFO of outgoing private messages accepted by the radio and still
  /// waiting for SendConfirmedPush.
  final List<int> _pendingPrivateAckQueue = [];

  void _armSendTimer(int timestamp) {
    _sendTimers[timestamp]?.cancel();
    _sendTimers[timestamp] = Timer(_sendTimeout, () {
      _sendTimers.remove(timestamp);
      _markPrivateMessageFailed(timestamp);
    });
  }

  void _markPrivateMessageFailed(int timestamp) {
    _pendingPrivateRouteQueue.remove(timestamp);
    _pendingPrivateAckQueue.remove(timestamp);
    _ackTimers[timestamp]?.cancel();
    _ackTimers.remove(timestamp);
    final idx = state.indexWhere(
      (m) =>
          m.isOutgoing && m.isPrivate && m.timestamp == timestamp && !m.failed,
    );
    if (idx < 0) return;
    final updated = state[idx].copyWith(failed: true);
    final newList = List<ChatMessage>.from(state);
    newList[idx] = updated;
    state = newList;
    _rebuildPartitioned(state);
    _bumpVersion(_partitionKey(updated));
    _saveForMessage(updated);
  }

  Duration _ackTimeoutFor(int suggestedTimeoutMs) {
    final baseMs =
        suggestedTimeoutMs > 0
            ? suggestedTimeoutMs
            : _sendTimeout.inMilliseconds;
    final paddedMs = (baseMs * 1.2).round();
    return Duration(
      milliseconds: paddedMs < _minAckTimeoutMs ? _minAckTimeoutMs : paddedMs,
    );
  }

  ChatMessage? _findPendingPrivateMessage(int timestamp) {
    final idx = state.indexWhere(
      (m) =>
          m.isOutgoing && m.isPrivate && m.timestamp == timestamp && !m.failed,
    );
    return idx >= 0 ? state[idx] : null;
  }

  void _armAckTimer(int timestamp, int suggestedTimeoutMs) {
    _ackTimers[timestamp]?.cancel();
    _ackTimers[timestamp] = Timer(_ackTimeoutFor(suggestedTimeoutMs), () {
      _ackTimers.remove(timestamp);
      unawaited(_handleAckTimeout(timestamp));
    });
  }

  Future<void> _handleAckTimeout(int timestamp) async {
    _pendingPrivateAckQueue.remove(timestamp);
    final msg = _findPendingPrivateMessage(timestamp);
    if (msg == null || msg.confirmed) return;

    if (msg.retryCount + 1 >= _maxPrivateAttempts) {
      _markPrivateMessageFailed(timestamp);
      return;
    }

    await _retryPrivateMessage(
      msg,
      useFlood: msg.retryCount + 1 >= _floodAfterAttempt,
    );
  }

  Future<bool> retryPrivateMessage(
    ChatMessage msg, {
    bool forceFlood = false,
  }) async {
    if (!msg.isOutgoing || !msg.isPrivate) return false;
    return _retryPrivateMessage(
      msg,
      useFlood: forceFlood || msg.retryCount + 1 >= _floodAfterAttempt,
    );
  }

  Future<bool> _retryPrivateMessage(
    ChatMessage msg, {
    required bool useFlood,
  }) async {
    final service = _ref.read(radioServiceProvider);
    if (service == null || msg.senderKey == null || msg.senderKey!.isEmpty) {
      _markPrivateMessageFailed(msg.timestamp);
      return false;
    }

    final updated = markMessageRetrying(msg);
    if (updated == null) return false;

    final fullKey = updated.senderKey!;
    final keyPrefix = fullKey.length >= 6 ? fullKey.sublist(0, 6) : fullKey;

    if (useFlood) {
      await service.resetPath(fullKey);
      final prefixHex =
          keyPrefix.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      final cache = Map<String, PathCacheEntry>.from(
        _ref.read(pathCacheProvider),
      );
      cache.remove(prefixHex);
      _ref.read(pathCacheProvider.notifier).state = cache;
    }

    await service.sendPrivateMessage(
      keyPrefix,
      updated.text,
      attempt: updated.retryCount,
      timestamp: updated.timestamp,
    );
    return true;
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
          expectedAck: null,
          suggestedTimeoutMs: null,
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
        _pendingPrivateRouteQueue.add(newTs);
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
    for (final t in _ackTimers.values) {
      t.cancel();
    }
    _ackTimers.clear();
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
    _appendPartitioned(message);
    _touchLastMsgTs([message]);
    _bumpVersion(key);
    _saveForMessage(message);
  }

  void addOutgoing(ChatMessage message) {
    state = [...state, message];
    final key = _partitionKey(message);
    _appendPartitioned(message);
    _touchLastMsgTs([message]);
    _bumpVersion(key);
    _saveForMessage(message);
    _ref.read(networkStatsProvider.notifier).incrementTx();
    // Arm failure timer for private messages (no timer for channel messages —
    // they don't use SentResponse and are best-effort).
    if (message.isPrivate) {
      _armSendTimer(message.timestamp);
      _pendingPrivateRouteQueue.add(message.timestamp);
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
    _rebuildPartitioned(state);
    _bumpVersion(_partitionKey(updated));
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
          _rebuildPartitioned(state);
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
    while (_pendingPrivateAckQueue.isNotEmpty) {
      final ts = _pendingPrivateAckQueue.removeAt(0);
      final idx = state.indexWhere(
        (m) =>
            m.isOutgoing &&
            m.isPrivate &&
            m.timestamp == ts &&
            !m.confirmed &&
            !m.failed,
      );
      if (idx < 0) continue;
      _ackTimers[ts]?.cancel();
      _ackTimers.remove(ts);
      final updated = state[idx].copyWith(confirmed: true);
      final newList = List<ChatMessage>.from(state);
      newList[idx] = updated;
      state = newList;
      _rebuildPartitioned(state);
      _bumpVersion(_partitionKey(updated));
      _saveForMessage(updated);
      return;
    }

    // Walk backwards and only touch the most-recently-added unconfirmed
    // outgoing message (private or channel — whichever came last).
    for (var i = state.length - 1; i >= 0; i--) {
      final msg = state[i];
      if (msg.isOutgoing && !msg.confirmed) {
        final updated = msg.copyWith(confirmed: true);
        final newList = List<ChatMessage>.from(state);
        newList[i] = updated;
        state = newList;
        _rebuildPartitioned(state);
        _bumpVersion(_partitionKey(updated));
        _saveForMessage(updated);
        return;
      }
    }
  }

  /// Store the route flag on the most recent outgoing *private* message that
  /// does not yet have a sentRouteFlag.  Channel messages don't use this flag.
  /// Called when [SentResponse] arrives: 0 = direct, 1 = flood.
  void markLastOutgoingRoute(
    int routeFlag, {
    int expectedAck = 0,
    int suggestedTimeoutMs = 0,
  }) {
    // Preferred path: match in FIFO send order.
    while (_pendingPrivateRouteQueue.isNotEmpty) {
      final ts = _pendingPrivateRouteQueue.removeAt(0);
      final idx = state.indexWhere(
        (m) =>
            m.isOutgoing &&
            m.isPrivate &&
            m.timestamp == ts &&
            m.sentRouteFlag == null &&
            !m.failed,
      );
      if (idx < 0) continue;
      final msg = state[idx];
      _sendTimers[msg.timestamp]?.cancel();
      _sendTimers.remove(msg.timestamp);
      final updated = msg.copyWith(
        sentRouteFlag: routeFlag,
        expectedAck: expectedAck,
        suggestedTimeoutMs: suggestedTimeoutMs,
        failed: false,
      );
      final newList = List<ChatMessage>.from(state);
      if (expectedAck != 0) {
        newList[idx] = updated;
        state = newList;
        _rebuildPartitioned(state);
        _bumpVersion(_partitionKey(updated));
        _saveForMessage(updated);
        _pendingPrivateAckQueue.add(updated.timestamp);
        _armAckTimer(updated.timestamp, suggestedTimeoutMs);
      } else {
        final confirmed = updated.copyWith(confirmed: true);
        newList[idx] = confirmed;
        state = newList;
        _rebuildPartitioned(state);
        _bumpVersion(_partitionKey(confirmed));
        _saveForMessage(confirmed);
      }
      return;
    }

    // Fallback for legacy in-memory states where queue was not populated.
    for (var i = state.length - 1; i >= 0; i--) {
      final msg = state[i];
      if (msg.isOutgoing &&
          msg.sentRouteFlag == null &&
          msg.channelIndex == null &&
          !msg.failed) {
        // Cancel the failure timer — radio confirmed it sent the packet.
        _sendTimers[msg.timestamp]?.cancel();
        _sendTimers.remove(msg.timestamp);
        final updated = msg.copyWith(
          sentRouteFlag: routeFlag,
          expectedAck: expectedAck,
          suggestedTimeoutMs: suggestedTimeoutMs,
          failed: false,
        );
        final newList = List<ChatMessage>.from(state);
        if (expectedAck != 0) {
          newList[i] = updated;
          state = newList;
          _rebuildPartitioned(state);
          _bumpVersion(_partitionKey(updated));
          _saveForMessage(updated);
          _pendingPrivateAckQueue.add(updated.timestamp);
          _armAckTimer(updated.timestamp, suggestedTimeoutMs);
        } else {
          final confirmed = updated.copyWith(confirmed: true);
          newList[i] = confirmed;
          state = newList;
          _rebuildPartitioned(state);
          _bumpVersion(_partitionKey(confirmed));
          _saveForMessage(confirmed);
        }
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
  /// Uses the currently connected radio's ID when available; falls back to the
  /// most-recently-used device so that cold-start loads find the correct key.
  /// Returns the legacy unscoped key only when no device is known at all.
  String _channelKey(int index) {
    final deviceId = _ref.read(currentRadioIdProvider);
    if (deviceId != null) {
      return 'ch_${StorageService.sanitizeId(deviceId)}_$index';
    }
    // Not connected yet — use the last known device so offline cache loads
    // from the same key that was used to save messages in the previous session.
    final recent = _ref.read(recentDevicesProvider);
    if (recent.isNotEmpty) {
      return 'ch_${StorageService.sanitizeId(recent.first.id)}_$index';
    }
    return 'ch_$index';
  }

  /// Lazily load persisted messages for a channel index.
  Future<void> ensureLoadedForChannel(int index) async {
    final scopedKey = _channelKey(index);
    if (_loadedKeys.contains(scopedKey)) return;
    _loadedKeys.add(scopedKey);
    var stored = await StorageService.instance.loadMessages(scopedKey);
    // Migration fallback: if nothing found at the scoped key, check the
    // legacy unscoped key so users who upgraded keep their message history.
    final legacyKey = 'ch_$index';
    if (stored.isEmpty && scopedKey != legacyKey) {
      stored = await StorageService.instance.loadMessages(legacyKey);
      _loadedKeys.add(legacyKey); // prevent a redundant load later
    }
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
    if (stored.isEmpty) return;

    // Dedup and sort per conversation bucket rather than across the whole app.
    //
    // This runs every time a chat screen is opened. It used to build a
    // full-text identity string for *every message in the app*, then sort and
    // re-partition the entire message list — so opening one conversation got
    // steadily slower as other conversations were loaded.
    //
    // Within a bucket the partition key already pins the channel or sender, so
    // (timestamp, isOutgoing, text) is a sufficient identity. Using a record
    // avoids allocating a concatenated string per message.
    final byKey = <String, List<ChatMessage>>{};
    for (final m in stored) {
      (byKey[_partitionKey(m)] ??= <ChatMessage>[]).add(m);
    }

    final added = <ChatMessage>[];
    for (final entry in byKey.entries) {
      final key = entry.key;
      final bucket = _partitioned[key] ??= <ChatMessage>[];
      final seen = <(int, bool, String)>{
        for (final m in bucket) (m.timestamp, m.isOutgoing, m.text),
      };

      var bucketChanged = false;
      for (final m in entry.value) {
        if (!seen.add((m.timestamp, m.isOutgoing, m.text))) continue;
        bucket.add(m);
        added.add(m);
        bucketChanged = true;
      }

      if (bucketChanged) {
        // Only the touched conversation is re-sorted; display order comes from
        // the bucket, not from the flat state list.
        bucket.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        _bumpVersion(key);
      }
    }

    if (added.isEmpty) return;
    // No global sort: nothing reads ordering off the flat list (addMessage has
    // always appended without sorting), and screens read the partition.
    state = [...state, ...added];
    _touchLastMsgTs(added);
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
    // One row in, or an update of this message's status fields — the database
    // handles both. This used to re-encode the entire conversation (up to
    // maxMessagesPerKey messages) and rewrite the whole preferences file on
    // every message, ack, retry and heard-count bump.
    //
    // Saves are still serialised per key so a slower earlier write cannot land
    // after a later one for the same message.
    final prev = _saveLocks[storageKey] ?? Future.value();
    final next = prev.then(
      (_) => StorageService.instance.upsertMessage(storageKey, msg),
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
  ///
  /// The returned list is owned by this notifier and is appended to in place
  /// by [_appendPartitioned]. Read it during build and do not retain or mutate
  /// it; re-read after the conversation's [messageVersionsProvider] entry ticks.
  List<ChatMessage> forContact(Uint8List? contactKey) {
    if (contactKey == null) return const [];
    return _partitioned['c_${_hex6(contactKey)}'] ?? const [];
  }

  /// Get messages for a specific channel.
  /// O(1) via _partitioned map — no list scan needed.
  ///
  /// Same ownership contract as [forContact].
  List<ChatMessage> forChannel(int channelIndex) {
    return _partitioned['ch_$channelIndex'] ?? const [];
  }

  /// Globally-unique identity for one message: the conversation discriminator
  /// plus the fields that identify it inside that conversation. Used only by
  /// [deleteMessage], where an O(n) pass over all messages is fine because it
  /// is a one-off user action.
  static (String, int, bool, String) _globalMsgId(ChatMessage m) => (
    _partitionKey(m),
    m.timestamp,
    m.isOutgoing,
    m.text,
  );

  /// Delete a single message from state and re-persist its conversation.
  void deleteMessage(ChatMessage msg) {
    final targetId = _globalMsgId(msg);
    state = state.where((m) => _globalMsgId(m) != targetId).toList();
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
      // The deleted message may have been the newest for this contact.
      _recomputeLastMsgTs(msg.senderKey!);
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
