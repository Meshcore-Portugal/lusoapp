import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A single repeater command + response transcript entry.
class RepeaterHistoryEntry {
  const RepeaterHistoryEntry({required this.command, required this.response});
  final String command;
  final String response;

  Map<String, dynamic> toJson() => {'c': command, 'r': response};
  static RepeaterHistoryEntry fromJson(Map<String, dynamic> j) =>
      RepeaterHistoryEntry(
        command: (j['c'] as String?) ?? '',
        response: (j['r'] as String?) ?? '',
      );
}

/// Persists per-repeater command-line history in `SharedPreferences`.
/// Each repeater is keyed by its full public-key hex.
class RepeaterHistoryStore {
  const RepeaterHistoryStore(this.contactKeyHex);

  final String contactKeyHex;

  /// Cap stored entries to keep the prefs payload bounded.
  static const int maxEntries = 500;

  String get _key => 'repeater_history_$contactKeyHex';

  Future<List<RepeaterHistoryEntry>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final e in decoded)
          if (e is Map)
            RepeaterHistoryEntry.fromJson(Map<String, dynamic>.from(e)),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(List<RepeaterHistoryEntry> entries) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tail =
          entries.length > maxEntries
              ? entries.sublist(entries.length - maxEntries)
              : entries;
      await prefs.setString(
        _key,
        jsonEncode(tail.map((e) => e.toJson()).toList()),
      );
    } catch (_) {
      // Best-effort persistence.
    }
  }

  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }
}
