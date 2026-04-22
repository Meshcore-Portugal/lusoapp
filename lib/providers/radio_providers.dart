import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart' show Color;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../protocol/cayenne_lpp.dart';
import '../protocol/protocol.dart';
import '../services/notification_service.dart';
import '../services/plan333_service.dart';
import '../services/radio_service.dart';
import '../services/storage_service.dart';
import '../services/widget_service.dart';
import '../transport/transport.dart';

/// Returns the 64-char hex string of the first 32 bytes of a public key.
/// Used as a stable map key for comparing contact identity across providers.
String _keyHex(Uint8List key) =>
    key.take(32).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

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

/// Snapshot of the public-key hex-strings of contacts confirmed to be stored
/// on the radio at the last explicit sync (initial connect or contact deletion).
/// Used by [discoveredContactsProvider] so that background path-update refreshes
/// don't falsely hide contacts from the discover screen.
final radioContactsSnapshotProvider = StateProvider<Set<String>>((_) => {});

/// True once the first [EndContactsResponse] has been received after the
/// current connection was established.  Reset to false on every new connect
/// attempt and on disconnect.  Used by the contacts screen to distinguish
/// "no contacts on this radio" (synced, empty snapshot) from "not yet synced"
/// (should fall back to the local cache).
final contactsSyncedProvider = StateProvider<bool>((_) => false);

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
  StreamSubscription<CompanionResponse>? _responseSub;
  Timer? _batteryPollTimer;

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
                isAppInForeground: AppLifecycleObserver.isInForeground,
              );
            }
          }
        case SelfInfoResponse(:final info):
          _ref.read(selfInfoProvider.notifier).state = info;
          _ref.read(radioConfigProvider.notifier).state = info.radioConfig;
          _pushWidget();
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

// ---------------------------------------------------------------------------
// Data providers
// ---------------------------------------------------------------------------

final selfInfoProvider = StateProvider<SelfInfo?>((_) => null);
final radioConfigProvider = StateProvider<RadioConfig?>((_) => null);
final deviceInfoProvider = StateProvider<DeviceInfo?>((_) => null);
final batteryProvider = StateProvider<int>((_) => 0);

/// (storageUsed, storageTotal) in bytes; both null until first RESP_BATT_AND_STORAGE.
final storageProvider = StateProvider<(int?, int?)>((_) => (null, null));

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
    // Contacts from the radio — carry over local-only fields (customName,
    // lastAdvertTimestamp) from the cache.  The radio doesn't track when we
    // last heard an advert from a node, so without this merge a background
    // sync (e.g. after auto-add or path update) would wipe lastAdvertTimestamp
    // and the discover screen would lose the contact.
    final merged =
        contacts.map((incoming) {
          final existing = state.firstWhere(
            (c) => _keysEqual(c.publicKey, incoming.publicKey),
            orElse: () => incoming,
          );
          // Identical instance — no local cache hit, nothing to preserve.
          if (identical(existing, incoming)) return incoming;
          var merged =
              existing.customName != null
                  ? incoming.withCustomName(existing.customName)
                  : incoming;
          // Preserve the most recent advert timestamp seen locally.
          if (existing.lastAdvertTimestamp > merged.lastAdvertTimestamp) {
            merged = Contact(
              publicKey: merged.publicKey,
              type: merged.type,
              flags: merged.flags,
              pathLen: merged.pathLen,
              name: merged.name,
              lastAdvertTimestamp: existing.lastAdvertTimestamp,
              latitude: merged.latitude,
              longitude: merged.longitude,
              lastModified: merged.lastModified,
              customName: merged.customName,
            );
          }
          return merged;
        }).toList();

    // Preserve locally-cached contacts that are not in the radio's list.
    // These are contacts received via AdvertPush (heard on the mesh) but not
    // yet formally stored in the radio's contacts table.  Dropping them on
    // every refresh causes the node to "disappear" after an app restart.
    for (final local in state) {
      if (!merged.any((c) => _keysEqual(c.publicKey, local.publicKey))) {
        merged.add(local);
      }
    }

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

  /// Optimistically flips the favourite bit on the cached contact and saves
  /// storage. Callers are expected to push the updated contact to the radio
  /// via [RadioService.addUpdateContact] so the change persists across
  /// disconnects and reaches other apps connected to the same radio.
  void setFavorite(Uint8List publicKey, bool value) {
    final next =
        state
            .map(
              (c) =>
                  _keysEqual(c.publicKey, publicKey)
                      ? c.withFavorite(value)
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

  /// Called when an AdvertPush is received over the mesh.
  /// Update lastModified on a contact matched by key prefix (6 bytes).
  /// Called when any incoming private message (chat or CLI) is received.
  void touchLastHeard(Uint8List senderKey) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final idx = state.indexWhere(
      (c) =>
          c.publicKey.length >= 6 &&
          senderKey.length >= 6 &&
          c.publicKey[0] == senderKey[0] &&
          c.publicKey[1] == senderKey[1] &&
          c.publicKey[2] == senderKey[2] &&
          c.publicKey[3] == senderKey[3] &&
          c.publicKey[4] == senderKey[4] &&
          c.publicKey[5] == senderKey[5],
    );
    if (idx < 0) return;
    final existing = state[idx];
    final next = [...state];
    next[idx] = Contact(
      publicKey: existing.publicKey,
      type: existing.type,
      flags: existing.flags,
      pathLen: existing.pathLen,
      name: existing.name,
      lastAdvertTimestamp: existing.lastAdvertTimestamp,
      latitude: existing.latitude,
      longitude: existing.longitude,
      lastModified: now,
      customName: existing.customName,
    );
    state = next;
    StorageService.instance.saveContacts(next);
  }

  /// Adds a new contact if unseen, or refreshes the name/type/timestamp if already known.
  void upsertFromAdvert(Uint8List publicKey, int type, String name) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final idx = state.indexWhere((c) => _keysEqual(c.publicKey, publicKey));
    List<Contact> next;
    if (idx >= 0) {
      final existing = state[idx];
      next = [...state];
      next[idx] = Contact(
        publicKey: existing.publicKey,
        // Preserve the known type if the advert carries type=0 (unknown).
        // Firmware pushAdvert (0x80) can omit the type for path-update adverts.
        type: type != 0 ? type : existing.type,
        flags: existing.flags,
        pathLen: existing.pathLen,
        name: name.isNotEmpty ? name : existing.name,
        lastAdvertTimestamp: now,
        latitude: existing.latitude,
        longitude: existing.longitude,
        // Update lastModified so _bestTs() reflects the live reception time.
        // Without this, _bestTs prefers the old lastModified and "Visto" never changes.
        lastModified: now,
        customName: existing.customName,
      );
    } else {
      // Don't create a nameless contact — an advert without a name is a
      // path-update ping for a node we haven't met yet; ignore it until
      // a proper advert with a name arrives.
      if (name.isEmpty) return;
      next = [
        ...state,
        Contact(
          publicKey: publicKey,
          type: type,
          flags: 0,
          pathLen: 0,
          name: name,
          lastAdvertTimestamp: now,
        ),
      ];
    }
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

  Future<void> loadFromStorage() async {
    final stored = await StorageService.instance.loadChannels();
    if (stored.isNotEmpty) {
      state = List.from(stored)..sort((a, b) => a.index.compareTo(b.index));
    }
  }

  void refresh(List<ChannelInfo> channels) {
    state = List.from(channels)..sort((a, b) => a.index.compareTo(b.index));
    StorageService.instance.saveChannels(state);
  }
}

final channelsProvider =
    StateNotifierProvider<ChannelsNotifier, List<ChannelInfo>>((ref) {
      return ChannelsNotifier();
    });

// Messages
class MessagesNotifier extends StateNotifier<List<ChatMessage>> {
  MessagesNotifier(this._ref) : super([]);
  final Ref _ref;

  final Set<String> _loadedKeys = {};

  /// Per-key save lock: ensures saves for the same key are serialised so a
  /// slower earlier save never overwrites a faster later save.
  final Map<String, Future<void>> _saveLocks = {};

  void addMessage(ChatMessage message) {
    // Dedup: skip if an identical message already exists in state.
    // Include senderKey prefix so messages from different contacts with
    // identical text+timestamp are never wrongly merged.
    final dominated = state.any(
      (m) =>
          m.timestamp == message.timestamp &&
          m.channelIndex == message.channelIndex &&
          m.text == message.text &&
          m.isOutgoing == message.isOutgoing &&
          _senderKeyMatch(m, message),
    );
    if (dominated) return;
    state = [...state, message];
    _saveForMessage(message);
  }

  void addOutgoing(ChatMessage message) {
    state = [...state, message];
    _saveForMessage(message);
    _ref.read(networkStatsProvider.notifier).incrementTx();
  }

  /// Increment heard count on an outgoing channel message matched by packet
  /// hash.  The first 0x88 duplicate for a GRP_TXT packet is the original
  /// transmission; subsequent duplicates are repeater echoes.  [totalHeard]
  /// is the cumulative repeater count (duplicates minus 1).
  ///
  /// If [hashHex] matches a message that already has the same packetHashHex,
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
      storageKey = 'ch_${msg.channelIndex}';
    } else if (msg.senderKey != null) {
      storageKey = 'contact_${_hex6(msg.senderKey!)}';
    } else {
      return;
    }
    // Collect all messages for this key (snapshot current state).
    final forKey =
        state.where((m) {
          if (msg.channelIndex != null) {
            return m.channelIndex == msg.channelIndex;
          }
          if (m.senderKey == null) return false;
          return _prefixMatch6(m.senderKey!, msg.senderKey!);
        }).toList();

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

  /// Delete a single message from state and re-persist its conversation.
  void deleteMessage(ChatMessage msg) {
    final targetId = _msgId(msg);
    state = state.where((m) => _msgId(m) != targetId).toList();
    if (msg.channelIndex != null) {
      final forKey =
          state.where((m) => m.channelIndex == msg.channelIndex).toList();
      StorageService.instance.saveMessages('ch_${msg.channelIndex}', forKey);
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
    await StorageService.instance.clearMessages('ch_$channelIndex');
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

// ---------------------------------------------------------------------------
// Unread message counts
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Muted channels
// ---------------------------------------------------------------------------

class MutedChannelsNotifier extends StateNotifier<Set<int>> {
  MutedChannelsNotifier() : super({}) {
    _load();
  }

  static const _key = 'muted_channels_v1';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? [];
    state = list.map(int.parse).toSet();
  }

  Future<void> toggle(int channelIndex) async {
    final next = Set<int>.from(state);
    if (next.contains(channelIndex)) {
      next.remove(channelIndex);
    } else {
      next.add(channelIndex);
    }
    state = next;
    await _save();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, state.map((i) => '$i').toList());
  }
}

final mutedChannelsProvider =
    StateNotifierProvider<MutedChannelsNotifier, Set<int>>(
      (ref) => MutedChannelsNotifier(),
    );

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

  static const _chKey = 'unread_channels_v1';
  static const _coKey = 'unread_contacts_v1';

  Future<void> loadFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final chRaw = prefs.getString(_chKey);
    final coRaw = prefs.getString(_coKey);
    Map<int, int> ch = {};
    Map<String, int> co = {};
    if (chRaw != null) {
      for (final part in chRaw.split(',')) {
        final kv = part.split(':');
        if (kv.length == 2) {
          final k = int.tryParse(kv[0]);
          final v = int.tryParse(kv[1]);
          if (k != null && v != null && v > 0) ch[k] = v;
        }
      }
    }
    if (coRaw != null) {
      for (final part in coRaw.split(',')) {
        final kv = part.split(':');
        if (kv.length == 2 && kv[0].isNotEmpty) {
          final v = int.tryParse(kv[1]);
          if (v != null && v > 0) co[kv[0]] = v;
        }
      }
    }
    state = UnreadCounts(channels: ch, contacts: co);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _chKey,
      state.channels.entries.map((e) => '${e.key}:${e.value}').join(','),
    );
    await prefs.setString(
      _coKey,
      state.contacts.entries.map((e) => '${e.key}:${e.value}').join(','),
    );
  }

  void incrementChannel(int index) {
    final ch = Map<int, int>.from(state.channels)
      ..[index] = (state.channels[index] ?? 0) + 1;
    state = UnreadCounts(channels: ch, contacts: state.contacts);
    _save();
  }

  void incrementContact(String hex6) {
    final co = Map<String, int>.from(state.contacts)
      ..[hex6] = (state.contacts[hex6] ?? 0) + 1;
    state = UnreadCounts(channels: state.channels, contacts: co);
    _save();
  }

  void markChannelRead(int index) {
    if ((state.channels[index] ?? 0) == 0) return;
    final ch = Map<int, int>.from(state.channels)..remove(index);
    state = UnreadCounts(channels: ch, contacts: state.contacts);
    _save();
  }

  void markContactRead(String hex6) {
    if ((state.contacts[hex6] ?? 0) == 0) return;
    final co = Map<String, int>.from(state.contacts)..remove(hex6);
    state = UnreadCounts(channels: state.channels, contacts: co);
    _save();
  }

  void reset() {
    state = const UnreadCounts();
    _save();
  }
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

// ---------------------------------------------------------------------------
// Auto-reconnect setting
// ---------------------------------------------------------------------------

class AutoReconnectNotifier extends StateNotifier<bool> {
  AutoReconnectNotifier() : super(true) {
    _load();
  }

  static const _key = 'auto_reconnect';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_key) ?? true;
  }

  Future<void> set(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
  }
}

final autoReconnectProvider =
    StateNotifierProvider<AutoReconnectNotifier, bool>(
      (ref) => AutoReconnectNotifier(),
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
  BatteryHistoryNotifier() : super([]) {
    _loadFromPrefs();
  }

  static const _prefKey = 'battery_history_v1';
  static const _maxAge = Duration(days: 7);

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey);
    if (raw == null) return;
    try {
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      final cutoff = DateTime.now().subtract(_maxAge);
      final readings =
          list
              .map(
                (e) => BatteryReading(
                  timestamp: DateTime.fromMillisecondsSinceEpoch(
                    e['ts'] as int,
                  ),
                  millivolts: e['mv'] as int,
                ),
              )
              .where((r) => r.timestamp.isAfter(cutoff))
              .toList();
      if (readings.isNotEmpty) state = readings;
    } catch (_) {
      // Ignore malformed persisted data
    }
  }

  void add(int millivolts) {
    if (millivolts <= 0) return;
    final cutoff = DateTime.now().subtract(_maxAge);
    state = [
      ...state.where((r) => r.timestamp.isAfter(cutoff)),
      BatteryReading(timestamp: DateTime.now(), millivolts: millivolts),
    ];
    _saveToPrefs();
  }

  Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final data =
        state
            .map(
              (r) => {
                'ts': r.timestamp.millisecondsSinceEpoch,
                'mv': r.millivolts,
              },
            )
            .toList();
    await prefs.setString(_prefKey, jsonEncode(data));
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

/// Cache of outPath bytes per contact, keyed by 6-byte pubKeyPrefix hex.
/// Populated whenever a PathDiscoveryPush (0x8D) is received.
/// Used by the trace flow to supply correct hop-hash path bytes.
final pathCacheProvider = StateProvider<Map<String, List<int>>>((_) => {});

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
// Contact favorites — derived from the radio's `flags` byte (bit 0).
// The firmware owns the canonical list; the UI reads Contact.isFavorite
// directly. ContactsNotifier.setFavorite mutates the bit locally and the
// caller pushes the updated contact via RadioService.addUpdateContact.
// ---------------------------------------------------------------------------

/// Migrates any app-local favourites (from pre-fix SharedPreferences) to the
/// radio's `flags` byte. Called once after the initial contact sync on every
/// connect — it's idempotent: after the first migration, the stored set is
/// cleared and subsequent calls are no-ops.
Future<void> _migrateLegacyFavorites(Ref ref, RadioService service) async {
  final legacy = await StorageService.instance.loadFavorites();
  if (legacy.isEmpty) return;
  final contactsNotifier = ref.read(contactsProvider.notifier);
  for (final contact in ref.read(contactsProvider)) {
    final keyHex =
        contact.publicKey
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join();
    if (!legacy.contains(keyHex) || contact.isFavorite) continue;
    contactsNotifier.setFavorite(contact.publicKey, true);
    // Fire-and-forget — OkResponse isn't awaited; failures fall through to
    // the next connect's migration retry (the legacy set is still present
    // until clearFavorites below runs on success).
    unawaited(
      service.addUpdateContact(contact.withFavorite(true)).catchError((_) {}),
    );
  }
  await StorageService.instance.clearFavorites();
}

// ---------------------------------------------------------------------------
// Advert auto-add settings (app-side, per contact type)
// ---------------------------------------------------------------------------

/// Controls whether incoming adverts are automatically written back to the
/// radio's contact table (via CMD_ADD_UPDATE_CONTACT) for each node type.
///
/// Auto-add contact settings. Persisted to SharedPreferences.
class AdvertAutoAddSettings {
  const AdvertAutoAddSettings({
    this.addAll = true,
    this.addChat = true,
    this.addRepeater = true,
    this.addRoom = true,
    this.addSensor = true,
    this.overwriteOldest = false,
    this.maxHops,
    this.pullToRefresh = true,
    this.showPublicKeys = true,
  });

  /// When true, auto-add all advert types (ignores per-type flags).
  final bool addAll;
  final bool addChat; // type 1
  final bool addRepeater; // type 2
  final bool addRoom; // type 3
  final bool addSensor; // type 4
  /// Overwrite oldest non-favourite contact when the list is full.
  final bool overwriteOldest;

  /// Maximum hop count for auto-add; null means no limit.
  final int? maxHops;

  /// Allow pull-to-refresh gesture on the contacts list.
  final bool pullToRefresh;

  /// Show public key prefix (shortId) in the contacts list tiles.
  final bool showPublicKeys;

  bool allowsType(int type) {
    if (addAll) return true;
    switch (type) {
      case 1:
        return addChat;
      case 2:
        return addRepeater;
      case 3:
        return addRoom;
      case 4:
        return addSensor;
      default:
        return false;
    }
  }

  static const Object _sentinel = Object();

  AdvertAutoAddSettings copyWith({
    bool? addAll,
    bool? addChat,
    bool? addRepeater,
    bool? addRoom,
    bool? addSensor,
    bool? overwriteOldest,
    Object? maxHops = _sentinel,
    bool? pullToRefresh,
    bool? showPublicKeys,
  }) => AdvertAutoAddSettings(
    addAll: addAll ?? this.addAll,
    addChat: addChat ?? this.addChat,
    addRepeater: addRepeater ?? this.addRepeater,
    addRoom: addRoom ?? this.addRoom,
    addSensor: addSensor ?? this.addSensor,
    overwriteOldest: overwriteOldest ?? this.overwriteOldest,
    maxHops: identical(maxHops, _sentinel) ? this.maxHops : maxHops as int?,
    pullToRefresh: pullToRefresh ?? this.pullToRefresh,
    showPublicKeys: showPublicKeys ?? this.showPublicKeys,
  );
}

class AdvertAutoAddNotifier extends StateNotifier<AdvertAutoAddSettings> {
  AdvertAutoAddNotifier(this._getService)
    : super(const AdvertAutoAddSettings()) {
    _load();
  }

  final RadioService? Function() _getService;

  static const _key = 'advert_autoadd_v1';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final maxHopsRaw = prefs.getInt('${_key}_maxHops');
    state = AdvertAutoAddSettings(
      addAll: prefs.getBool('${_key}_addAll') ?? true,
      addChat: prefs.getBool('${_key}_chat') ?? true,
      addRepeater: prefs.getBool('${_key}_repeater') ?? true,
      addRoom: prefs.getBool('${_key}_room') ?? true,
      addSensor: prefs.getBool('${_key}_sensor') ?? true,
      overwriteOldest: prefs.getBool('${_key}_overwriteOldest') ?? false,
      maxHops: maxHopsRaw,
      pullToRefresh: prefs.getBool('${_key}_pullToRefresh') ?? true,
      showPublicKeys: prefs.getBool('${_key}_showPublicKeys') ?? true,
    );
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final futures = <Future<void>>[
      prefs.setBool('${_key}_addAll', state.addAll),
      prefs.setBool('${_key}_chat', state.addChat),
      prefs.setBool('${_key}_repeater', state.addRepeater),
      prefs.setBool('${_key}_room', state.addRoom),
      prefs.setBool('${_key}_sensor', state.addSensor),
      prefs.setBool('${_key}_overwriteOldest', state.overwriteOldest),
      prefs.setBool('${_key}_pullToRefresh', state.pullToRefresh),
      prefs.setBool('${_key}_showPublicKeys', state.showPublicKeys),
    ];
    if (state.maxHops != null) {
      futures.add(prefs.setInt('${_key}_maxHops', state.maxHops!));
    } else {
      futures.add(prefs.remove('${_key}_maxHops'));
    }
    await Future.wait(futures);
  }

  /// Push current state to the radio.  No-op when not connected.
  Future<void> _pushToRadioIfConnected() async {
    final service = _getService();
    if (service == null) return;
    final (bitmask, radioMaxHops) = toRadioConfig();
    await service.setAutoAddConfig(bitmask, radioMaxHops).catchError((_) {});
  }

  /// Encodes current state as the two radio bytes.
  ///
  /// Returns `(autoadd_config bitmask, autoadd_max_hops)` where
  /// maxHops 0 = no limit, 1 = direct, N = up to N-1 hops.
  (int, int) toRadioConfig() {
    int bitmask = 0;
    if (state.overwriteOldest) bitmask |= autoAddOverwriteOldest;
    if (state.addAll || state.addChat) bitmask |= autoAddChat;
    if (state.addAll || state.addRepeater) bitmask |= autoAddRepeater;
    if (state.addAll || state.addRoom) bitmask |= autoAddRoom;
    if (state.addAll || state.addSensor) bitmask |= autoAddSensor;
    final radioMaxHops = state.maxHops == null ? 0 : state.maxHops! + 1;
    return (bitmask, radioMaxHops);
  }

  /// Seeds state from the radio's persisted config (called on connect).
  ///
  /// App-only fields ([AdvertAutoAddSettings.pullToRefresh],
  /// [AdvertAutoAddSettings.showPublicKeys]) are preserved from the
  /// current local state.
  void loadFromRadio(int bitmask, int maxHops) {
    final addChat = (bitmask & autoAddChat) != 0;
    final addRepeater = (bitmask & autoAddRepeater) != 0;
    final addRoom = (bitmask & autoAddRoom) != 0;
    final addSensor = (bitmask & autoAddSensor) != 0;
    final addAll = addChat && addRepeater && addRoom && addSensor;
    state = state.copyWith(
      addAll: addAll,
      addChat: addChat,
      addRepeater: addRepeater,
      addRoom: addRoom,
      addSensor: addSensor,
      overwriteOldest: (bitmask & autoAddOverwriteOldest) != 0,
      maxHops: maxHops == 0 ? null : maxHops - 1, // 0→null, N→N-1
    );
    _save();
  }

  void setAddAll(bool v) {
    state = state.copyWith(addAll: v);
    _save();
    unawaited(_pushToRadioIfConnected());
  }

  void setChat(bool v) {
    state = state.copyWith(addChat: v);
    _save();
    unawaited(_pushToRadioIfConnected());
  }

  void setRepeater(bool v) {
    state = state.copyWith(addRepeater: v);
    _save();
    unawaited(_pushToRadioIfConnected());
  }

  void setRoom(bool v) {
    state = state.copyWith(addRoom: v);
    _save();
    unawaited(_pushToRadioIfConnected());
  }

  void setSensor(bool v) {
    state = state.copyWith(addSensor: v);
    _save();
    unawaited(_pushToRadioIfConnected());
  }

  void setOverwriteOldest(bool v) {
    state = state.copyWith(overwriteOldest: v);
    _save();
    unawaited(_pushToRadioIfConnected());
  }

  void setMaxHops(int? v) {
    state = state.copyWith(maxHops: v);
    _save();
    unawaited(_pushToRadioIfConnected());
  }

  void setPullToRefresh(bool v) {
    state = state.copyWith(pullToRefresh: v);
    _save();
  }

  void setShowPublicKeys(bool v) {
    state = state.copyWith(showPublicKeys: v);
    _save();
  }
}

final advertAutoAddProvider =
    StateNotifierProvider<AdvertAutoAddNotifier, AdvertAutoAddSettings>(
      (ref) => AdvertAutoAddNotifier(() => ref.read(radioServiceProvider)),
    );

// ---------------------------------------------------------------------------
// Radio hardware stats (CMD_GET_STATS responses)
// ---------------------------------------------------------------------------

/// Latest core device statistics from the connected radio.
/// Polled every 5 minutes alongside the battery; null until first response.
final radioStatsCoreProvider = StateProvider<StatsCoreResponse?>((_) => null);

/// Latest radio-layer statistics (noise floor, RSSI, SNR, airtime).
final radioStatsRadioProvider = StateProvider<StatsRadioResponse?>((_) => null);

/// Latest packet counters (received, sent, flood/direct breakdown, CRC errors).
final radioStatsPacketsProvider = StateProvider<StatsPacketsResponse?>(
  (_) => null,
);

// ---------------------------------------------------------------------------
// Noise floor history (in-session ring buffer, up to 300 readings)
// ---------------------------------------------------------------------------

class NoiseFloorReading {
  const NoiseFloorReading({required this.timestamp, required this.dBm});
  final DateTime timestamp;
  final int dBm;
}

class NoiseFloorHistoryNotifier extends StateNotifier<List<NoiseFloorReading>> {
  NoiseFloorHistoryNotifier() : super([]);

  static const _maxReadings = 300;

  void add(int dBm) {
    final next = [
      ...state,
      NoiseFloorReading(timestamp: DateTime.now(), dBm: dBm),
    ];
    state =
        next.length > _maxReadings
            ? next.sublist(next.length - _maxReadings)
            : next;
  }

  void clear() => state = [];
}

final noiseFloorHistoryProvider =
    StateNotifierProvider<NoiseFloorHistoryNotifier, List<NoiseFloorReading>>(
      (ref) => NoiseFloorHistoryNotifier(),
    );

// ---------------------------------------------------------------------------
// Packet heard tracker (driven by 0x88 raw RF log)
// ---------------------------------------------------------------------------

/// Tracks how many times each unique packet hash has been received.
///
/// The firmware pushes `PUSH_CODE_LOG_RX_DATA` (0x88) for every raw RF
/// reception **before** mesh deduplication.  Identical packet hashes mean the
/// same logical packet was heard multiple times — each duplicate represents
/// a different repeater that forwarded it.
///
/// The state maps `packetHashHex` → list of [MessagePath] records.
class PacketHeardNotifier
    extends StateNotifier<Map<String, List<MessagePath>>> {
  PacketHeardNotifier() : super({});

  /// Load persisted paths from storage (called on app start and after reset).
  Future<void> loadFromStorage() async {
    final saved = await StorageService.instance.loadMessagePaths();
    if (saved.isNotEmpty) {
      // Merge: runtime data wins over stored data for any shared key.
      state = {...saved, ...state};
    }
  }

  /// Record a reception of [hashHex] with its path details.
  /// Returns the new total count (number of paths stored for this hash).
  int record(
    String hashHex, {
    required double snr,
    required int rssi,
    required Uint8List pathBytes,
    required int pathHashCount,
    required int pathHashSize,
  }) {
    final path = MessagePath(
      snr: snr,
      rssi: rssi,
      pathHashCount: pathHashCount,
      pathHashSize: pathHashSize,
      pathBytes: pathBytes,
    );
    final prev = state[hashHex] ?? [];
    final next = [...prev, path];
    state = {...state, hashHex: next};
    // Persist after every record so paths survive app restarts.
    StorageService.instance.saveMessagePaths(state);
    return next.length;
  }

  /// Clear the in-memory state (e.g. on disconnect) then reload persisted
  /// paths so historical data remains available for the UI.
  void reset() {
    state = {};
    Future.microtask(loadFromStorage);
  }
}

final packetHeardProvider =
    StateNotifierProvider<PacketHeardNotifier, Map<String, List<MessagePath>>>(
      (ref) => PacketHeardNotifier(),
    );

// ---------------------------------------------------------------------------
// RX log (raw 0x88 frames for diagnostics / PCAP export)
// ---------------------------------------------------------------------------

class RxLogEntry {
  const RxLogEntry({
    required this.receivedAt,
    required this.snr,
    required this.rssi,
    required this.rawPacket,
    this.payloadType,
    this.packetHashHex,
    this.pathHops,
  });

  final DateTime receivedAt;
  final double snr;
  final int rssi;

  /// Raw over-the-air packet bytes (without the 0x88 SNR/RSSI preamble).
  final Uint8List rawPacket;

  final int? payloadType;
  final String? packetHashHex;
  final int? pathHops;
}

class RxLogNotifier extends StateNotifier<List<RxLogEntry>> {
  RxLogNotifier() : super(const []);

  static const int _maxEntries = 4000;

  /// Record one PUSH_CODE_LOG_RX_DATA frame payload (bytes after 0x88).
  void recordFromLogRxFrame(Uint8List data) {
    if (data.length < 2) return;

    final snrByte = data[0];
    final snr = (snrByte < 128 ? snrByte : snrByte - 256) / 4.0;
    final rssiByte = data[1];
    final rssi = rssiByte < 128 ? rssiByte : rssiByte - 256;
    final raw =
        data.length > 2 ? Uint8List.fromList(data.sublist(2)) : Uint8List(0);

    final parsed = parseRawPacket(raw);

    final entry = RxLogEntry(
      receivedAt: DateTime.now(),
      snr: snr,
      rssi: rssi,
      rawPacket: raw,
      payloadType: parsed?.payloadType,
      packetHashHex: parsed?.packetHashHex,
      pathHops: parsed?.pathHashCount,
    );

    final next = [...state, entry];
    if (next.length > _maxEntries) {
      state = next.sublist(next.length - _maxEntries);
    } else {
      state = next;
    }
  }

  void clear() => state = const [];
}

final rxLogProvider = StateNotifierProvider<RxLogNotifier, List<RxLogEntry>>(
  (ref) => RxLogNotifier(),
);

// ---------------------------------------------------------------------------
// Contacts screen persistent UI state (survives app restarts)
// ---------------------------------------------------------------------------

enum ContactFilter {
  todos,
  favoritos,
  companheiros,
  repetidores,
  salas,
  sensores,
}

enum ContactSort { nome, ouvidoRecentemente, ultimaMensagem }

class _ContactFilterNotifier extends StateNotifier<ContactFilter> {
  _ContactFilterNotifier() : super(ContactFilter.todos) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final idx = prefs.getInt('contacts_filter');
    if (idx != null && idx >= 0 && idx < ContactFilter.values.length) {
      state = ContactFilter.values[idx];
    }
  }

  Future<void> set(ContactFilter f) async {
    state = f;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('contacts_filter', f.index);
  }
}

class _ContactSortNotifier extends StateNotifier<ContactSort> {
  _ContactSortNotifier() : super(ContactSort.ouvidoRecentemente) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final idx = prefs.getInt('contacts_sort');
    if (idx != null && idx >= 0 && idx < ContactSort.values.length) {
      state = ContactSort.values[idx];
    }
  }

  Future<void> set(ContactSort s) async {
    state = s;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('contacts_sort', s.index);
  }
}

final contactFilterProvider =
    StateNotifierProvider<_ContactFilterNotifier, ContactFilter>(
      (_) => _ContactFilterNotifier(),
    );

final contactSortProvider =
    StateNotifierProvider<_ContactSortNotifier, ContactSort>(
      (_) => _ContactSortNotifier(),
    );

// ---------------------------------------------------------------------------
// Mention pill colours (persisted to SharedPreferences)
// ---------------------------------------------------------------------------

class MentionColorNotifier extends StateNotifier<Color> {
  MentionColorNotifier(super.defaultColor, this._key) {
    _load();
  }
  final String _key;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final val = prefs.getInt(_key);
    if (val != null) {
      state = Color.fromARGB(
        (val >> 24) & 0xFF,
        (val >> 16) & 0xFF,
        (val >> 8) & 0xFF,
        val & 0xFF,
      );
    }
  }

  Future<void> setColor(Color color) async {
    state = color;
    final prefs = await SharedPreferences.getInstance();
    final a = (color.a * 255).round();
    final r = (color.r * 255).round();
    final g = (color.g * 255).round();
    final b = (color.b * 255).round();
    await prefs.setInt(_key, (a << 24) | (r << 16) | (g << 8) | b);
  }
}

/// Pill background for @[YourName] (you are mentioned).  Default: amber.
final selfMentionColorProvider =
    StateNotifierProvider<MentionColorNotifier, Color>(
      (ref) => MentionColorNotifier(
        const Color.fromARGB(0xFF, 0xFF, 0xB3, 0x47), // amber
        'mention_color_self',
      ),
    );

/// Pill background for @[OtherName] (someone else mentioned).  Default: orange.
final otherMentionColorProvider =
    StateNotifierProvider<MentionColorNotifier, Color>(
      (ref) => MentionColorNotifier(
        const Color.fromARGB(0xFF, 0xFF, 0x6B, 0x00), // orange
        'mention_color_other',
      ),
    );
