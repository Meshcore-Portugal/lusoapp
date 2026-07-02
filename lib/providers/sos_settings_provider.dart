import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SosTargetType { channel, contact }

class SosSettings extends Equatable {
  const SosSettings({
    this.targetType = SosTargetType.channel,
    this.channelIndex = 0,
    this.contactKeyBase64,
    this.messageTemplate = 'SOS - preciso de ajuda! {gps}',
    this.includeGps = true,
    this.holdDurationSeconds = 3,
  });

  factory SosSettings.fromJson(Map<String, dynamic> json) {
    return SosSettings(
      targetType: SosTargetType.values.firstWhere(
        (t) => t.name == json['targetType'],
        orElse: () => SosTargetType.channel,
      ),
      channelIndex: (json['channelIndex'] as num?)?.toInt() ?? 0,
      contactKeyBase64: json['contactKeyBase64'] as String?,
      messageTemplate:
          (json['messageTemplate'] as String?)?.trim().isNotEmpty == true
              ? json['messageTemplate'] as String
              : 'SOS - preciso de ajuda! {gps}',
      includeGps: json['includeGps'] as bool? ?? true,
      holdDurationSeconds: ((json['holdDurationSeconds'] as num?)?.toInt() ?? 3)
          .clamp(3, 5),
    );
  }

  final SosTargetType targetType;
  final int channelIndex;
  final String? contactKeyBase64;
  final String messageTemplate;
  final bool includeGps;
  final int holdDurationSeconds;

  SosSettings copyWith({
    SosTargetType? targetType,
    int? channelIndex,
    String? contactKeyBase64,
    String? messageTemplate,
    bool? includeGps,
    int? holdDurationSeconds,
    bool clearContact = false,
  }) {
    return SosSettings(
      targetType: targetType ?? this.targetType,
      channelIndex: channelIndex ?? this.channelIndex,
      contactKeyBase64:
          clearContact ? null : (contactKeyBase64 ?? this.contactKeyBase64),
      messageTemplate: messageTemplate ?? this.messageTemplate,
      includeGps: includeGps ?? this.includeGps,
      holdDurationSeconds: holdDurationSeconds ?? this.holdDurationSeconds,
    );
  }

  Map<String, dynamic> toJson() => {
    'targetType': targetType.name,
    'channelIndex': channelIndex,
    if (contactKeyBase64 != null) 'contactKeyBase64': contactKeyBase64,
    'messageTemplate': messageTemplate,
    'includeGps': includeGps,
    'holdDurationSeconds': holdDurationSeconds,
  };

  @override
  List<Object?> get props => [
    targetType,
    channelIndex,
    contactKeyBase64,
    messageTemplate,
    includeGps,
    holdDurationSeconds,
  ];
}

const _kStorageKey = 'sos_settings_v1';

class SosSettingsNotifier extends StateNotifier<SosSettings> {
  SosSettingsNotifier() : super(const SosSettings());

  Future<void> loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kStorageKey);
      if (raw == null) return;
      state = SosSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {}
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kStorageKey, jsonEncode(state.toJson()));
    } catch (_) {}
  }

  Future<void> setTargetType(SosTargetType t) async {
    if (state.targetType == t) return;
    state = state.copyWith(targetType: t);
    await _persist();
  }

  Future<void> setChannelIndex(int idx) async {
    if (state.channelIndex == idx) return;
    state = state.copyWith(channelIndex: idx);
    await _persist();
  }

  Future<void> setContactKey(String? keyBase64) async {
    if (state.contactKeyBase64 == keyBase64) return;
    state = state.copyWith(contactKeyBase64: keyBase64);
    await _persist();
  }

  Future<void> setMessageTemplate(String text) async {
    final normalized =
        text.trim().isEmpty ? 'SOS - preciso de ajuda! {gps}' : text.trim();
    if (state.messageTemplate == normalized) return;
    state = state.copyWith(messageTemplate: normalized);
    await _persist();
  }

  Future<void> setIncludeGps(bool value) async {
    if (state.includeGps == value) return;
    state = state.copyWith(includeGps: value);
    await _persist();
  }

  Future<void> setHoldDuration(int seconds) async {
    final clamped = seconds.clamp(3, 5);
    if (state.holdDurationSeconds == clamped) return;
    state = state.copyWith(holdDurationSeconds: clamped);
    await _persist();
  }
}

final sosSettingsProvider =
    StateNotifierProvider<SosSettingsNotifier, SosSettings>(
      (ref) => SosSettingsNotifier(),
    );
