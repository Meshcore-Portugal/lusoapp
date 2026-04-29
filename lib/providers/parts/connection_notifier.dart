part of '../radio_providers.dart';

// ---------------------------------------------------------------------------
// Connection manager
// ---------------------------------------------------------------------------

class ConnectionNotifier extends StateNotifier<TransportState> {
  ConnectionNotifier(this._ref) : super(TransportState.disconnected);
  final Ref _ref;

  StreamSubscription<void>? _connectionLostSub;
  StreamSubscription<CompanionResponse>? _responseSub;
  Timer? _batteryPollTimer;
  Timer? _keepaliveTimer;

  /// Set to true in [disconnect] to abort any in-progress reconnect loop.
  bool _reconnectCancelled = false;

  /// When true the next [EndContactsResponse] will also update
  /// [radioContactsSnapshotProvider].  Set before explicit contact syncs
  /// (initial connect, deletion); left false for path-update auto-refreshes
  /// so the discover screen is not destabilised by background syncs.
  bool _pendingSnapshotUpdate = false;

  void _setStep(int step, String label) {
    _ref.read(connectionProgressProvider.notifier).state = step;
    _ref.read(connectionStepProvider.notifier).state = label;
  }

  Future<bool> connectBle(String deviceId, String deviceName) async {
    // Clear stale snapshot and sync flag so the contacts screen falls back
    // to the cached list while the new radio's sync is in progress.
    _ref.read(radioContactsSnapshotProvider.notifier).state = {};
    _ref.read(contactsSyncedProvider.notifier).state = false;
    state = TransportState.connecting;
    _setStep(0, 'A ligar via Bluetooth...');
    try {
      final transport = BleTransport.fromDeviceId(deviceId);
      final service = RadioService(transport);
      _ref.read(radioServiceProvider.notifier).state = service;
      _setupListeners(service);
      final ok = await service.connect();
      if (ok) {
        // Scope channel data to this radio device.  If we're switching to a
        // different radio, clear stale channel messages and channels from
        // memory so data from the previous radio never bleeds through.
        final prevDeviceId = _ref.read(currentRadioIdProvider);
        if (prevDeviceId != deviceId) {
          _ref.read(messagesProvider.notifier).clearChannelMessages();
          _ref.read(channelsProvider.notifier).clearChannels();
          _ref.read(unreadCountsProvider.notifier).resetChannels();
        }
        _ref.read(currentRadioIdProvider.notifier).state = deviceId;
        // Pre-load cached channels and mute state for this radio before the
        // live fetch so the UI shows something while waiting for responses.
        await _ref
            .read(channelsProvider.notifier)
            .loadFromStorageForRadio(deviceId);
        await _ref.read(mutedChannelsProvider.notifier).loadForRadio(deviceId);
        await _ref.read(advertAutoAddProvider.notifier).loadForRadio(deviceId);

        await _fetchInitialData(service);
        state = TransportState.connected;
        // Prefer the radio's configured node name; fall back to the BLE
        // advertisement name so the reconnect button always shows something.
        final radioNodeName = _ref.read(selfInfoProvider)?.name;
        final displayName =
            (radioNodeName != null && radioNodeName.isNotEmpty)
                ? radioNodeName
                : deviceName;
        final recentList = await StorageService.instance.upsertRecentDevice(
          id: deviceId,
          type: 'ble',
          name: displayName,
        );
        _ref.read(recentDevicesProvider.notifier).state = recentList;
        _ref.read(lastDeviceProvider.notifier).state = recentList.first;
        _setupAutoReconnect(service, () => connectBle(deviceId, deviceName));
        _startBatteryPolling(service);
        _startKeepalive(service);
        _pushWidget();
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
    // Clear stale snapshot and sync flag so the contacts screen falls back
    // to the cached list while the new radio's sync is in progress.
    _ref.read(radioContactsSnapshotProvider.notifier).state = {};
    _ref.read(contactsSyncedProvider.notifier).state = false;
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
        // Scope channel data to this radio device.
        final prevDeviceId = _ref.read(currentRadioIdProvider);
        if (prevDeviceId != deviceId) {
          _ref.read(messagesProvider.notifier).clearChannelMessages();
          _ref.read(channelsProvider.notifier).clearChannels();
          _ref.read(unreadCountsProvider.notifier).resetChannels();
        }
        _ref.read(currentRadioIdProvider.notifier).state = deviceId;
        await _ref
            .read(channelsProvider.notifier)
            .loadFromStorageForRadio(deviceId);
        await _ref.read(mutedChannelsProvider.notifier).loadForRadio(deviceId);
        await _ref.read(advertAutoAddProvider.notifier).loadForRadio(deviceId);

        await _fetchInitialData(service);
        state = TransportState.connected;
        final typeStr =
            mode == ConnectionMode.kiss ? 'serialKiss' : 'serialCompanion';
        // Prefer the radio's configured node name; fall back to the USB
        // device name so the reconnect button always shows something.
        final radioNodeName = _ref.read(selfInfoProvider)?.name;
        final displayName =
            (radioNodeName != null && radioNodeName.isNotEmpty)
                ? radioNodeName
                : deviceName;
        final recentList = await StorageService.instance.upsertRecentDevice(
          id: deviceId,
          type: typeStr,
          name: displayName,
        );
        _ref.read(recentDevicesProvider.notifier).state = recentList;
        _ref.read(lastDeviceProvider.notifier).state = recentList.first;
        _startBatteryPolling(service);
        _startKeepalive(service);
        _pushWidget();
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
    _reconnectCancelled = true;
    _batteryPollTimer?.cancel();
    _batteryPollTimer = null;
    _keepaliveTimer?.cancel();
    _keepaliveTimer = null;
    await _connectionLostSub?.cancel();
    _connectionLostSub = null;
    await _responseSub?.cancel();
    _responseSub = null;
    _ref.read(packetHeardProvider.notifier).reset();
    final service = _ref.read(radioServiceProvider);
    if (service != null) {
      await service.dispose();
      _ref.read(radioServiceProvider.notifier).state = null;
    }
    _ref.read(unreadCountsProvider.notifier).reset();
    // Clear snapshot and sync flag so the contacts screen no longer filters
    // by the disconnected radio's keys on the next connection.
    _ref.read(radioContactsSnapshotProvider.notifier).state = {};
    _ref.read(contactsSyncedProvider.notifier).state = false;
    _ref.read(traceHistoryProvider.notifier).clear();
    // Clear the current radio ID so channel storage is not accidentally
    // written to the disconnected radio's scope.
    _ref.read(currentRadioIdProvider.notifier).state = null;
    _setStep(0, '');
    state = TransportState.disconnected;
    _pushWidget();
  }

  /// Push current radio state to the Android home screen widget.
  void _pushWidget() {
    final selfInfo = _ref.read(selfInfoProvider);
    final batteryMv = _ref.read(batteryProvider);
    final contacts = _ref.read(contactsProvider);
    final channels = _ref.read(channelsProvider);

    // Same LiPo curve used by the home screen: 4200 mV = 100%, 3200 mV = 0%
    final batteryPct =
        batteryMv == 0
            ? 0
            : (((batteryMv.clamp(3200, 4200) - 3200) / 1000) * 100).round();

    WidgetService.update(
      radioName: selfInfo?.name ?? '—',
      connected: state == TransportState.connected,
      batteryPct: batteryPct,
      contactCount: contacts.length,
      channelCount: channels.where((c) => !c.isEmpty).length,
    );
  }

  /// Poll battery every 5 min while connected.
  /// Also silently re-requests any channel slots that are still empty —
  /// a zero-cost safety net for slots that were missed at startup.
  void _startBatteryPolling(RadioService service) {
    _batteryPollTimer?.cancel();
    _batteryPollTimer = Timer.periodic(const Duration(seconds: 300), (_) {
      if (state != TransportState.connected) return;
      service.requestBattAndStorage().catchError((_) {});
      unawaited(service.requestStats(statsTypeCore).catchError((_) {}));
      unawaited(service.requestStats(statsTypeRadio).catchError((_) {}));
      unawaited(service.requestStats(statsTypePackets).catchError((_) {}));

      // Re-request any channel slots that were never populated.
      final maxCh = service.deviceInfo?.maxChannels ?? 8;
      final currentChannels = _ref.read(channelsProvider);
      final receivedIndices = currentChannels.map((c) => c.index).toSet();
      for (var i = 0; i < maxCh; i++) {
        if (!receivedIndices.contains(i)) {
          service.requestChannel(i).catchError((_) {});
        }
      }
    });
  }

  /// Send a lightweight ping every 15 s to keep the BLE link alive.
  ///
  /// Android (and some iOS) BLE stacks drop idle connections after ~20–30 s of
  /// no ATT traffic. A periodic requestBattAndStorage() is cheap (1-byte write)
  /// and its response is already handled by the normal response stream, so it
  /// produces no extra UI rebuilds. Errors are silently swallowed — if the
  /// radio is gone the connectionState listener will fire connectionLost.
  void _startKeepalive(RadioService service) {
    _keepaliveTimer?.cancel();
    _keepaliveTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (state != TransportState.connected) return;
      service.requestBattAndStorage().catchError((_) {});
    });
  }

  /// Subscribe to unexpected connection loss and attempt auto-reconnect with
  /// exponential back-off (2 s → 4 s → 8 s → 16 s → 30 s, then 30 s forever)
  /// until the connection is restored or the user calls [disconnect].
  ///
  /// When the [autoReconnectProvider] setting is off the connection simply
  /// transitions to [TransportState.disconnected] with no retry attempt.
  void _setupAutoReconnect(
    RadioService service,
    Future<bool> Function() reconnector,
  ) {
    _connectionLostSub?.cancel();
    _connectionLostSub = service.connectionLost.listen((_) async {
      if (state != TransportState.connected) return;

      _batteryPollTimer?.cancel();
      _batteryPollTimer = null;
      _keepaliveTimer?.cancel();
      _keepaliveTimer = null;
      _ref.read(radioServiceProvider.notifier).state = null;
      _reconnectCancelled = false;

      // If the user has disabled auto-reconnect, just go to disconnected.
      if (!_ref.read(autoReconnectProvider)) {
        state = TransportState.disconnected;
        _setStep(0, '');
        _pushWidget();
        return;
      }

      const backoffSeconds = [2, 4, 8, 16, 30];
      var attempt = 0;

      while (!_reconnectCancelled) {
        final delaySec =
            attempt < backoffSeconds.length
                ? backoffSeconds[attempt]
                : backoffSeconds.last;
        _setStep(
          0,
          'Ligação perdida. A reconectar em ${delaySec}s... (tentativa ${attempt + 1})',
        );
        state = TransportState.connecting;
        _pushWidget();

        await Future.delayed(Duration(seconds: delaySec));
        if (_reconnectCancelled) break;

        // User may have toggled the setting off while we were waiting.
        if (!_ref.read(autoReconnectProvider)) break;

        attempt++;
        _setStep(0, 'A reconectar... (tentativa $attempt)');

        final ok = await reconnector();
        // reconnector sets state = connected and installs a fresh listener.
        if (ok) return;
        if (_reconnectCancelled) break;
      }

      // Reconnect loop ended without success.
      if (!_reconnectCancelled) {
        state = TransportState.error;
        _setStep(0, 'Reconexão falhou.');
        _pushWidget();
      }
    });
  }

  void _setupListeners(RadioService service) {
    _responseSub?.cancel();
    _responseSub = service.responses.listen((response) {
      switch (response) {
        case ContactResponse():
          // Do NOT refresh here — service.contacts is still partial (the radio
          // sends contacts one-by-one after clearing its list on ContactsStart).
          // Refreshing on each individual response would drop all locally-cached
          // contacts and make the provider count drop to 1, 2, 3... during sync,
          // breaking the connect-screen "+N new" badge.  Wait for EndContacts.
          break;
        case EndContactsResponse():
          // Full list has arrived — replace provider state with final radio list.
          _ref.read(contactsProvider.notifier).refresh(service.contacts);
          // Always update the snapshot: it is the authoritative set of keys
          // stored on the radio, used by the contacts screen to filter out
          // advert-only (not-on-radio) entries.  The discover screen no longer
          // uses this snapshot, so updating it on every sync is safe.
          _pendingSnapshotUpdate = false;
          _ref.read(radioContactsSnapshotProvider.notifier).state =
              service.contacts.map((c) => _keyHex(c.publicKey)).toSet();
          // Mark that a full sync has completed for this connection — the
          // contacts screen uses this (not snapshot size) to know it should
          // show only radio contacts, even when the radio has zero contacts.
          _ref.read(contactsSyncedProvider.notifier).state = true;
          _pushWidget();
        case ContactDeletedPush():
          // Radio confirmed deletion — request a fresh contact list so
          // service.contacts is rebuilt without the deleted entry before
          // refreshing contactsProvider.  Also schedule a snapshot update so
          // the discover screen correctly reflects the post-deletion state.
          _pendingSnapshotUpdate = true;
          unawaited(service.requestContacts().catchError((_) {}));
        case ChannelInfoResponse():
          _ref.read(channelsProvider.notifier).refresh(service.channels);
          _pushWidget();
        case PrivateMessageResponse(:final message):
          _ref.read(messagesProvider.notifier).addMessage(message);
          if (!message.isOutgoing && !message.isCliResponse) {
            _ref.read(networkStatsProvider.notifier).incrementRx();
          }
          // Update last-heard timestamp on the matching contact for any
          // incoming private message (chat or CLI response).
          if (!message.isOutgoing && message.senderKey != null) {
            _ref
                .read(contactsProvider.notifier)
                .touchLastHeard(message.senderKey!);
          }
          // Unread badge + notification only for real chat messages.
          if (!message.isOutgoing && !message.isCliResponse) {
            if (message.senderKey != null) {
              _ref
                  .read(unreadCountsProvider.notifier)
                  .incrementContact(_hex6(message.senderKey!));
            }
            final senderHex6 =
                message.senderKey != null ? _hex6(message.senderKey!) : null;
            // O(1) lookup via the internal index instead of O(n) list scan.
            final contact =
                senderHex6 != null
                    ? _ref
                        .read(contactsProvider.notifier)
                        .lookupByHex6(senderHex6)
                    : null;
            final senderName = contact?.name ?? senderHex6 ?? 'Desconhecido';
            NotificationService.instance.showPrivateMessage(
              senderName: senderName,
              text: message.text,
              senderKeyHex: senderHex6,
              isAppInForeground: AppLifecycleObserver.isInForeground,
            );
          }
        case ChannelMessageResponse(:final message):
          // Channel messages arrive via CMD_SYNC_NEXT_MESSAGE.
          // Heard-by-repeater counting is driven by PUSH_CODE_LOG_RX_DATA
          // (0x88) packet-hash deduplication — not loopback text matching.
          //
          // Skip if this is a loopback echo of our own sent message.
          // The firmware may pass the first repeater echo through dedup and
          // queue it.  We already have the outgoing copy from addOutgoing().
          final isLoopback =
              message.channelIndex != null &&
              _ref
                  .read(messagesProvider)
                  .any(
                    (m) =>
                        m.isOutgoing &&
                        m.channelIndex == message.channelIndex &&
                        m.timestamp == message.timestamp,
                  );
          if (isLoopback) break;
          // For incoming channel messages, try to link the packet hash from
          // the most recent unmatched 0x88 GRP_TXT frame for this channel.
          // The 0x88 frame always arrives before the ChannelMessageResponse.
          ChatMessage finalMessage = message;
          if (!message.isOutgoing && message.channelIndex != null) {
            final pendingHash = _ref
                .read(messagesProvider.notifier)
                .consumeIncomingHash(message.channelIndex!);
            if (pendingHash != null) {
              finalMessage = message.copyWith(packetHashHex: pendingHash);
            }
          }
          _ref.read(messagesProvider.notifier).addMessage(finalMessage);
          // Auto-log incoming CQ Plano 333 messages on the #plano333 channel
          // as stations heard.
          if (!finalMessage.isOutgoing && finalMessage.channelIndex != null) {
            final channels = _ref.read(channelsProvider);
            final plan333Ch =
                channels
                    .where((c) => c.name.trim().toLowerCase() == '#plano333')
                    .firstOrNull;
            if (plan333Ch != null &&
                finalMessage.channelIndex == plan333Ch.index) {
              final cq = Plan333Service.tryParseCq(
                finalMessage.text,
                pathLen: finalMessage.pathLen,
              );
              if (cq != null) {
                // Skip own CQ (echo from the radio).
                final myStation =
                    _ref.read(plan333ConfigProvider).stationName.trim();
                if (myStation.isEmpty ||
                    cq.stationName.toLowerCase() != myStation.toLowerCase()) {
                  // Deduplicate — same station sends up to 3 CQs per event.
                  final log = _ref.read(qslLogProvider);
                  if (!log.any(
                    (r) =>
                        r.stationName.toLowerCase() ==
                        cq.stationName.toLowerCase(),
                  )) {
                    _ref.read(qslLogProvider.notifier).add(cq);
                  }
                }
              }
            }
          }
          if (!finalMessage.isOutgoing) {
            _ref.read(networkStatsProvider.notifier).incrementRx();
            final isMuted =
                message.channelIndex != null &&
                _ref
                    .read(mutedChannelsProvider)
                    .contains(message.channelIndex!);
            if (message.channelIndex != null) {
              _ref
                  .read(unreadCountsProvider.notifier)
                  .incrementChannel(message.channelIndex!);
            }
            // Notifications (OS alert + app-icon badge) are suppressed for
            // muted channels; the in-app unread badge is still shown above.
            if (!isMuted) {
              final channels = _ref.read(channelsProvider);
              final idx = message.channelIndex ?? 0;
              final channel = channels.where((c) => c.index == idx).firstOrNull;
              final channelName =
                  (channel != null && channel.name.isNotEmpty)
                      ? channel.name
                      : 'Canal $idx';
              // Channel messages embed sender as "Name: body" when senderName
              // is not set separately.  Parse both parts so the notification
              // shows "Name: body" rather than "Desconhecido: Name: body".
              final String notifSender;
              final String notifBody;
              if (message.senderName != null &&
                  message.senderName!.isNotEmpty) {
                notifSender = message.senderName!;
                notifBody = message.text;
              } else {
                final colonIdx = message.text.indexOf(': ');
                if (colonIdx > 0) {
                  notifSender = message.text.substring(0, colonIdx).trim();
                  notifBody = message.text.substring(colonIdx + 2);
                } else {
                  notifSender = 'Desconhecido';
                  notifBody = message.text;
                }
              }
              NotificationService.instance.showChannelMessage(
                channelName: channelName,
                senderName: notifSender,
                text: notifBody,
                channelIndex: idx,
                isAppInForeground: AppLifecycleObserver.isInForeground,
              );
            }
          }
        case SelfInfoResponse(:final info):
          _ref.read(selfInfoProvider.notifier).state = info;
          _ref.read(radioConfigProvider.notifier).state = info.radioConfig;
          _pushWidget();
          // Keep the reconnect-button name in sync with the radio's node
          // name. This fires both at initial connect and whenever the user
          // renames the radio while connected.
          if (info.name.isNotEmpty && state == TransportState.connected) {
            final last = _ref.read(lastDeviceProvider);
            if (last != null && last.name != info.name) {
              final updated = LastDevice(
                id: last.id,
                type: last.type,
                name: info.name,
              );
              _ref.read(lastDeviceProvider.notifier).state = updated;
              // Also update the name in the recent devices list.
              final recent = _ref.read(recentDevicesProvider);
              _ref.read(recentDevicesProvider.notifier).state = [
                for (final d in recent) d.id == last.id ? updated : d,
              ];
              unawaited(
                StorageService.instance.upsertRecentDevice(
                  id: last.id,
                  type: last.type,
                  name: info.name,
                ),
              );
            }
          }
        case BattAndStorageResponse(
          :final batteryMv,
          :final storageUsed,
          :final storageTotal,
        ):
          _ref.read(batteryProvider.notifier).state = batteryMv;
          _ref.read(batteryHistoryProvider.notifier).add(batteryMv);
          if (storageUsed != null || storageTotal != null) {
            _ref.read(storageProvider.notifier).state = (
              storageUsed,
              storageTotal,
            );
          }
          _pushWidget();
        case DeviceInfoResponse(:final info):
          _ref.read(deviceInfoProvider.notifier).state = info;
        case SendConfirmedPush():
          _ref.read(messagesProvider.notifier).confirmLastOutgoing();
        case SentResponse(:final routeFlag):
          _ref.read(messagesProvider.notifier).markLastOutgoingRoute(routeFlag);
        case ErrorResponse():
          _ref.read(networkStatsProvider.notifier).incrementError();
        case AdvertPush(
          :final publicKey,
          :final type,
          :final name,
          :final isNew,
        ):
          _ref.read(networkStatsProvider.notifier).incrementHeard();
          _ref
              .read(contactsProvider.notifier)
              .upsertFromAdvert(publicKey, type, name);
          // When pushNewAdvert (isNew=true) the radio may NOT have added the
          // contact to its own table (manual-contact mode). Write it back
          // explicitly — but only if the user's auto-add setting allows this
          // node type AND the advert carries a real name. Nameless adverts
          // are path-update pings; pushing them would create unnamed
          // contacts in the radio's table (shown as bare hex IDs).
          if (isNew && name.trim().isNotEmpty) {
            final autoAdd = _ref.read(advertAutoAddProvider);
            if (type != 0 && autoAdd.allowsType(type)) {
              final service = _ref.read(radioServiceProvider);
              if (service != null) {
                final contact =
                    _ref
                        .read(contactsProvider)
                        .where(
                          (c) => ContactsNotifier._keysEqual(
                            c.publicKey,
                            publicKey,
                          ),
                        )
                        .firstOrNull;
                if (contact != null && contact.name.trim().isNotEmpty) {
                  // After pushing the contact to the radio, refresh contacts
                  // and update the snapshot so the discover screen removes
                  // the now-saved contact from its list.
                  service
                      .addUpdateContact(contact)
                      .then((_) {
                        _pendingSnapshotUpdate = true;
                        return service.requestContacts().catchError((_) {});
                      })
                      .catchError((_) {});
                }
              }
            }
          }
        case TelemetryPush(:final data):
          final readings = CayenneLPP.decode(data);
          if (readings.isNotEmpty) {
            _ref.read(telemetryProvider.notifier).add(readings);
          }
        case PathDiscoveryPush(:final pubKeyPrefix, :final outPath):
          if (pubKeyPrefix.length >= 6 && outPath.isNotEmpty) {
            final prefixHex =
                pubKeyPrefix
                    .sublist(0, 6)
                    .map((b) => b.toRadixString(16).padLeft(2, '0'))
                    .join();
            final current = Map<String, List<int>>.from(
              _ref.read(pathCacheProvider),
            );
            current[prefixHex] = outPath;
            _ref.read(pathCacheProvider.notifier).state = current;
          }
        case TraceDataPush(:final data):
          final contacts = _ref.read(contactsProvider);
          final result = parseTraceDataPush(data, contacts);
          if (result != null) {
            _ref.read(traceResultProvider.notifier).state = result;
            _ref.read(traceHistoryProvider.notifier).add(result);
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
        case PathUpdatedPush():
          // Radio has updated a contact's cached route — re-sync the contact
          // list so the UI shows the new hop count.  Do NOT set
          // _pendingSnapshotUpdate here: path-update refreshes must not
          // update the discover snapshot (race condition where auto-re-added
          // contacts would disappear from discover before the user can see them).
          service.requestContacts().catchError((_) {});
        case StatsCoreResponse():
          _ref.read(radioStatsCoreProvider.notifier).state = response;
        case StatsRadioResponse():
          _ref.read(radioStatsRadioProvider.notifier).state = response;
          _ref
              .read(noiseFloorHistoryProvider.notifier)
              .add(response.noiseFloor);
          _ref.read(rssiHistoryProvider.notifier).add(response.lastRssi);
        case StatsPacketsResponse():
          _ref.read(radioStatsPacketsProvider.notifier).state = response;
        case AutoAddConfigResponse(:final bitmask, :final maxHops):
          _ref
              .read(advertAutoAddProvider.notifier)
              .loadFromRadio(bitmask, maxHops);
        case LogRxDataPush(:final data):
          _processLogRxData(data);
        default:
          break;
      }
    });
  }

  /// Process a PUSH_CODE_LOG_RX_DATA (0x88) frame.
  ///
  /// Parses the raw RF packet, computes its SHA-256 packet hash, and checks
  /// for duplicate hashes.  Each duplicate = another repeater heard the
  /// packet.  For outgoing channel messages the heard count on the matching
  /// [ChatMessage] is incremented.
  void _processLogRxData(Uint8List data) {
    _ref.read(rxLogProvider.notifier).recordFromLogRxFrame(data);

    final parsed = parseLogRxData(data);
    if (parsed == null || parsed.packet == null) return;

    final pkt = parsed.packet!;
    final hashHex = pkt.packetHashHex;
    final log = Logger(printer: SimplePrinter(printTime: false));
    log.d(
      '0x88: type=0x${pkt.payloadType.toRadixString(16)} '
      'hash=$hashHex chHash=${pkt.channelHashByte} '
      'path=${pkt.pathHashCount}hops snr=${parsed.snr} rssi=${parsed.rssi}',
    );

    // Update the global packet-heard tracker.
    final tracker = _ref.read(packetHeardProvider.notifier);
    final count = tracker.record(
      hashHex,
      snr: parsed.snr,
      rssi: parsed.rssi,
      pathBytes: pkt.pathBytes,
      pathHashCount: pkt.pathHashCount,
      pathHashSize: pkt.pathHashSize,
    );

    // For advert packets, update last-heard on the matching contact.
    // The radio doesn't push 0x80 for already-known contacts, so the 0x88
    // log frame is the only signal we get.
    // Advert payload starts with 32-byte public key — first 6 bytes = prefix.
    if (pkt.payloadType == payloadTypeAdvert && pkt.payload.length >= 6) {
      _ref
          .read(contactsProvider.notifier)
          .touchLastHeard(Uint8List.fromList(pkt.payload.sublist(0, 6)));
    }

    // Only GRP_TXT packets can match outgoing channel messages.
    if (pkt.payloadType != payloadTypeGrpTxt) return;
    // For our outgoing messages the radio never receives its own TX via 0x88,
    // so every 0x88 occurrence with a GRP_TXT hash IS a repeater echo.

    // Determine which channel index this RF packet belongs to by comparing
    // the 1-byte channel hash from the raw payload against our known channels.
    final rxChHash = pkt.channelHashByte;
    if (rxChHash == null) return;

    final channels = _ref.read(channelsProvider);
    int? matchedChannelIdx;
    for (final ch in channels) {
      if (ch.secret != null && !ch.isEmpty) {
        if (computeChannelHash(ch.secret!) == rxChHash) {
          matchedChannelIdx = ch.index;
          break;
        }
      }
    }
    if (matchedChannelIdx == null) {
      log.d(
        '0x88: no channel matched for chHash=0x${rxChHash.toRadixString(16)}',
      );
      return;
    }
    log.i('0x88: GRP_TXT ch=$matchedChannelIdx hash=$hashHex count=$count');

    // Try to match against an outgoing message first.
    // If not matched (i.e. this is an incoming packet from another station),
    // buffer the hash so the ChannelMessageResponse can claim it.
    final matchedOutgoing = _ref
        .read(messagesProvider.notifier)
        .incrementHeardByHash(matchedChannelIdx, hashHex, count);
    if (!matchedOutgoing) {
      _ref
          .read(messagesProvider.notifier)
          .queueIncomingHash(matchedChannelIdx, hashHex);
    }
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

    // 2. Battery + radio stats — fire and forget, let them arrive whenever.
    await service.requestBattAndStorage();
    unawaited(service.requestStats(statsTypeCore).catchError((_) {}));
    unawaited(service.requestStats(statsTypeRadio).catchError((_) {}));
    unawaited(service.requestStats(statsTypePackets).catchError((_) {}));

    // 3. Contacts — wait for the end-of-contacts marker.
    // Mark that the resulting EndContactsResponse should update the discover
    // snapshot — this is the authoritative initial sync.
    _setStep(3, 'A sincronizar contactos...');
    _pendingSnapshotUpdate = true;
    final contactsResp = await _sendAndWait(
      service,
      () => service.requestContacts(),
      (r) => r is EndContactsResponse,
      timeout: const Duration(seconds: 10),
    );
    log.d('Contacts: ${contactsResp?.runtimeType ?? "TIMEOUT"}');

    // 3a. One-shot migration of any pre-fix app-local favourites to the
    // radio's `flags` byte. Idempotent: clears SharedPreferences on success.
    unawaited(_migrateLegacyFavorites(_ref, service).catchError((_) {}));

    // 4. Channels — send all requests with a short stagger and collect
    //    responses in parallel rather than round-tripping one at a time.
    //    Strategy:
    //      a) Start a listener that collects every ChannelInfoResponse index.
    //      b) Fire all requests 30 ms apart (lets the firmware TX queue drain).
    //      c) Wait up to 2 s for all slots to arrive.
    //      d) Retry any missing slots once (BLE packet loss / radio busy after
    //         contacts sync), waiting 500 ms per missing slot.
    //      e) Final explicit refresh so storage always reflects the authoritative
    //         complete set — not whatever the last intermediate save had.
    _setStep(4, 'A sincronizar canais...');
    final maxChannels = service.deviceInfo?.maxChannels ?? 8;
    final receivedChannels = <int>{};

    Future<void> waitForChannels({
      required Duration timeout,
      required Set<int> alreadyReceived,
    }) async {
      final done = Completer<void>();
      final sub = service.responses.listen((r) {
        if (r is ChannelInfoResponse) {
          alreadyReceived.add(r.channel.index);
          if (alreadyReceived.length >= maxChannels && !done.isCompleted) {
            done.complete();
          }
        }
      });
      try {
        await done.future.timeout(timeout);
      } on TimeoutException {
        // Continue with whatever arrived.
      }
      await sub.cancel();
    }

    // First sweep — request all slots.
    final sweepDone = Completer<void>();
    final sweepSub = service.responses.listen((r) {
      if (r is ChannelInfoResponse) {
        receivedChannels.add(r.channel.index);
        if (receivedChannels.length >= maxChannels && !sweepDone.isCompleted) {
          sweepDone.complete();
        }
      }
    });
    for (var i = 0; i < maxChannels; i++) {
      await service.requestChannel(i);
      if (i < maxChannels - 1) {
        await Future.delayed(const Duration(milliseconds: 30));
      }
    }
    try {
      await sweepDone.future.timeout(const Duration(milliseconds: 2000));
    } on TimeoutException {
      // Fall through to retry.
    }
    await sweepSub.cancel();
    log.d('Channels sweep: ${receivedChannels.length}/$maxChannels received');

    // Retry any slots that were missed (BLE loss, radio busy, etc.).
    final missing =
        List.generate(
          maxChannels,
          (i) => i,
        ).where((i) => !receivedChannels.contains(i)).toList();

    if (missing.isNotEmpty) {
      log.w('Channels: ${missing.length} missing slots, retrying: $missing');
      for (final slot in missing) {
        await service.requestChannel(slot);
        await Future.delayed(const Duration(milliseconds: 50));
      }
      await waitForChannels(
        timeout: Duration(milliseconds: missing.length * 500),
        alreadyReceived: receivedChannels,
      );
      log.d(
        'Channels after retry: ${receivedChannels.length}/$maxChannels received',
      );
    }

    // Persist the final authoritative channel set.  This overwrites any
    // intermediate partial saves that _setupListeners may have written during
    // the sweep, ensuring storage is always consistent.
    _ref.read(channelsProvider.notifier).refresh(service.channels);
    log.d('Channels done: ${receivedChannels.length}/$maxChannels received');

    // 5. Read the radio's auto-add config and seed the UI from the radio's
    //    persisted values (radio is source of truth for these settings).
    unawaited(service.requestAutoAddConfig().catchError((_) {}));

    // 6. Drain any messages queued while the app was disconnected.
    //    The spec says to send CMD_SYNC_NEXT_MESSAGE during initialisation.
    //    RadioService._processResponse() continues the chain automatically
    //    (each received message triggers the next sync until the queue is empty).
    await service.syncNextMessage();

    _setStep(5, 'Ligado!');
  }

  // ---------------------------------------------------------------------------
  // Private key backup / restore
  // ---------------------------------------------------------------------------

  /// Request the radio to export its 64-byte private key via the companion
  /// protocol (requires firmware built with ENABLE_PRIVATE_KEY_EXPORT=1).
  ///
  /// Returns the key as a 128-char hex string on success, or null if the radio
  /// timed out, replied with an error, or has the feature disabled.
  Future<String?> exportPrivateKey() async {
    final service = _ref.read(radioServiceProvider);
    if (service == null) return null;
    final resp = await _sendAndWait(
      service,
      () => service.requestPrivateKeyExport(),
      (r) => r is PrivateKeyResponse || r is ErrorResponse,
      timeout: const Duration(seconds: 5),
    );
    if (resp is PrivateKeyResponse) {
      return resp.privateKey
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
    }
    return null;
  }

  /// Send a 64-byte private key to the radio (requires firmware built with
  /// ENABLE_PRIVATE_KEY_IMPORT=1).
  ///
  /// [prvKeyHex] must be exactly 128 hex characters (64 bytes).
  /// Returns true on success (radio replied OK), false otherwise.
  Future<bool> importPrivateKey(String prvKeyHex) async {
    final service = _ref.read(radioServiceProvider);
    if (service == null) return false;
    if (prvKeyHex.length != 128) return false;
    final bytes = Uint8List(64);
    for (var i = 0; i < 64; i++) {
      bytes[i] = int.parse(prvKeyHex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    final resp = await _sendAndWait(
      service,
      () => service.importPrivateKey(bytes),
      (r) => r is OkResponse || r is ErrorResponse,
      timeout: const Duration(seconds: 5),
    );
    return resp is OkResponse;
  }
}

final connectionProvider =
    StateNotifierProvider<ConnectionNotifier, TransportState>((ref) {
      return ConnectionNotifier(ref);
    });
