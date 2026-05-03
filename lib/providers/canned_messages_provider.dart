import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A user-configurable canned message.
///
/// Stored as JSON in SharedPreferences under [_kStorageKey].
class CannedMessage extends Equatable {
  factory CannedMessage.fromJson(Map<String, dynamic> json) => CannedMessage(
    id: json['id'] as String,
    text: json['text'] as String,
    label: json['label'] as String?,
    isEmergency: json['isEmergency'] as bool? ?? false,
  );
  const CannedMessage({
    required this.id,
    required this.text,
    this.label,
    this.isEmergency = false,
  });

  /// Stable identifier (used as React-style key, also for delete/edit).
  final String id;

  /// The message body that gets inserted into the composer / sent.
  final String text;

  /// Optional short display label for the chip (defaults to first 24 chars of [text]).
  final String? label;

  /// When true, the widget SOS button will broadcast this message to channel 0.
  /// Only one canned message should be flagged emergency at a time — the
  /// notifier enforces this when toggling.
  final bool isEmergency;

  String get displayLabel {
    if (label != null && label!.isNotEmpty) return label!;
    return text.length <= 24 ? text : '${text.substring(0, 24)}…';
  }

  CannedMessage copyWith({String? text, String? label, bool? isEmergency}) {
    return CannedMessage(
      id: id,
      text: text ?? this.text,
      label: label ?? this.label,
      isEmergency: isEmergency ?? this.isEmergency,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    if (label != null) 'label': label,
    'isEmergency': isEmergency,
  };

  @override
  List<Object?> get props => [id, text, label, isEmergency];
}

const _kStorageKey = 'canned_messages_v1';

/// Default seed library shipped on first launch — covers common ham/mesh use.
List<CannedMessage> _defaultLibrary() => [
  const CannedMessage(
    id: 'sos',
    text: 'SOS — preciso de ajuda!',
    label: '🆘 SOS',
    isEmergency: true,
  ),
  const CannedMessage(id: 'qrt', text: 'QRT — vou desligar', label: 'QRT'),
  const CannedMessage(
    id: 'qrx',
    text: 'QRX — aguarda um momento',
    label: 'QRX',
  ),
  const CannedMessage(id: '73', text: '73! Boa propagação 📡', label: '73'),
  const CannedMessage(
    id: 'cq',
    text: 'CQ CQ CQ — alguém na escuta?',
    label: 'CQ',
  ),
  const CannedMessage(id: 'ok', text: 'Estou OK ✅', label: 'OK'),
  const CannedMessage(
    id: 'qth',
    text: 'QTH? Qual a tua localização?',
    label: 'QTH?',
  ),
  const CannedMessage(
    id: 'eta',
    text: 'ETA: a chegar em ~10 min',
    label: 'ETA 10 min',
  ),
];

class CannedMessagesNotifier extends StateNotifier<List<CannedMessage>> {
  CannedMessagesNotifier() : super(const []);

  /// Load from storage; if nothing stored, seed with [_defaultLibrary].
  Future<void> loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kStorageKey);
      if (raw == null) {
        state = _defaultLibrary();
        await _persist();
        return;
      }
      final decoded = jsonDecode(raw) as List;
      state =
          decoded
              .map((e) => CannedMessage.fromJson(e as Map<String, dynamic>))
              .toList();
    } catch (_) {
      state = _defaultLibrary();
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonEncode(state.map((c) => c.toJson()).toList());
      await prefs.setString(_kStorageKey, raw);
    } catch (_) {}
  }

  String _newId() =>
      'cm_${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';

  Future<void> add({
    required String text,
    String? label,
    bool isEmergency = false,
  }) async {
    final cm = CannedMessage(
      id: _newId(),
      text: text,
      label: label?.isEmpty == true ? null : label,
      isEmergency: isEmergency,
    );
    if (isEmergency) {
      // Demote any previous emergency.
      state = [...state.map((m) => m.copyWith(isEmergency: false)), cm];
    } else {
      state = [...state, cm];
    }
    await _persist();
  }

  Future<void> update(
    String id, {
    required String text,
    String? label,
    required bool isEmergency,
  }) async {
    state =
        state.map((m) {
          if (m.id == id) {
            return m.copyWith(
              text: text,
              label: label,
              isEmergency: isEmergency,
            );
          }
          // Demote others if this one is now emergency.
          if (isEmergency && m.isEmergency) {
            return m.copyWith(isEmergency: false);
          }
          return m;
        }).toList();
    // If we just promoted this one, ensure no other ones remain emergency.
    if (isEmergency) {
      state =
          state
              .map((m) => m.id == id ? m : m.copyWith(isEmergency: false))
              .toList();
    }
    await _persist();
  }

  Future<void> remove(String id) async {
    state = state.where((m) => m.id != id).toList();
    await _persist();
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    final list = List<CannedMessage>.from(state);
    if (newIndex > oldIndex) newIndex--;
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    state = list;
    await _persist();
  }

  Future<void> resetToDefaults() async {
    state = _defaultLibrary();
    await _persist();
  }

  /// Returns the message flagged as emergency (the one fired by the widget
  /// SOS button), or null if none is set.
  CannedMessage? get emergency {
    for (final m in state) {
      if (m.isEmergency) return m;
    }
    return null;
  }
}

final cannedMessagesProvider =
    StateNotifierProvider<CannedMessagesNotifier, List<CannedMessage>>(
      (ref) => CannedMessagesNotifier(),
    );
