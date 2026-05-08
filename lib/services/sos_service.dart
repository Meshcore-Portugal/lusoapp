import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../protocol/protocol.dart';
import '../providers/radio_providers.dart';
import '../providers/sos_settings_provider.dart';
import '../transport/radio_transport.dart' show TransportState;

enum SosSendOutcome {
  sent,
  notConnected,
  missingContact,
  permissionDenied,
  locationDisabled,
  failed,
}

class SosSendResult {
  const SosSendResult(this.outcome, {this.detail});

  final SosSendOutcome outcome;
  final String? detail;

  bool get ok => outcome == SosSendOutcome.sent;
}

class SosService {
  SosService(this._ref);

  final Ref _ref;

  Future<SosSendResult> sendConfiguredSos({String? baseTextOverride}) async {
    final svc = _ref.read(radioServiceProvider);
    final connected = _ref.read(connectionProvider) == TransportState.connected;
    if (svc == null || !connected) {
      return const SosSendResult(SosSendOutcome.notConnected);
    }

    final settings = _ref.read(sosSettingsProvider);
    final baseText =
        (baseTextOverride != null && baseTextOverride.trim().isNotEmpty)
            ? baseTextOverride.trim()
            : settings.messageTemplate;

    final gpsText = settings.includeGps ? await _buildGpsText() : null;
    final message = _applyGpsTemplate(baseText, gpsText);
    final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    try {
      if (settings.targetType == SosTargetType.channel) {
        await svc.sendChannelMessage(
          settings.channelIndex,
          message,
          timestamp: ts,
        );
        _ref
            .read(messagesProvider.notifier)
            .addOutgoing(
              ChatMessage(
                text: message,
                timestamp: ts,
                isOutgoing: true,
                channelIndex: settings.channelIndex,
              ),
            );
        return const SosSendResult(SosSendOutcome.sent);
      }

      final contact = _resolveTargetContact(settings.contactKeyBase64);
      if (contact == null) {
        return const SosSendResult(SosSendOutcome.missingContact);
      }

      final keyPrefix = contact.publicKey.sublist(
        0,
        contact.publicKey.length < 6 ? contact.publicKey.length : 6,
      );
      await svc.sendPrivateMessage(keyPrefix, message, timestamp: ts);
      _ref
          .read(messagesProvider.notifier)
          .addOutgoing(
            ChatMessage(
              text: message,
              timestamp: ts,
              isOutgoing: true,
              senderKey: contact.publicKey,
              channelIndex: null,
              senderName: contact.displayName,
            ),
          );
      return const SosSendResult(SosSendOutcome.sent);
    } catch (e) {
      return SosSendResult(SosSendOutcome.failed, detail: e.toString());
    }
  }

  Contact? _resolveTargetContact(String? keyBase64) {
    if (keyBase64 == null || keyBase64.isEmpty) return null;
    final contacts = _ref.read(contactsProvider);
    for (final c in contacts) {
      if (base64Encode(c.publicKey) == keyBase64) return c;
    }
    return null;
  }

  String _applyGpsTemplate(String baseText, String? gpsText) {
    final hasToken = baseText.contains('{gps}');
    if (hasToken) {
      return baseText.replaceAll('{gps}', gpsText ?? 'GPS indisponível');
    }
    if (gpsText == null || gpsText.isEmpty) return baseText;
    return '$baseText\n$gpsText';
  }

  Future<String?> _buildGpsText() async {
    try {
      final serviceOn = await Geolocator.isLocationServiceEnabled();
      if (!serviceOn) return null;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return null;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      final lat = _round(pos.latitude, 5);
      final lon = _round(pos.longitude, 5);
      return 'GPS: $lat, $lon\nhttps://maps.google.com/?q=$lat,$lon';
    } catch (_) {
      return null;
    }
  }

  static double _round(double value, int decimals) {
    var m = 1.0;
    for (var i = 0; i < decimals; i++) {
      m *= 10;
    }
    return (value * m).round() / m;
  }
}

final sosServiceProvider = Provider<SosService>((ref) {
  return SosService(ref);
});
