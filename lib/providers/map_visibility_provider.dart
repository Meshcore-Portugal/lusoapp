import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores the set of contact public-key prefixes that the user has chosen
/// to **hide** from the map view, even when the contact's adverts include
/// GPS coordinates.
///
/// Keys are stored as full lowercase hex of the 32-byte public key. This
/// keeps the per-contact opt-in stable across renames.
class MapHiddenContactsNotifier extends StateNotifier<Set<String>> {
  MapHiddenContactsNotifier() : super(const <String>{});

  static const _kStorageKey = 'map_hidden_contacts_v1';

  Future<void> loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_kStorageKey) ?? const <String>[];
      state = list.map((e) => e.toLowerCase()).toSet();
    } catch (_) {
      // Corrupt list — fall back to empty.
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_kStorageKey, state.toList());
    } catch (_) {}
  }

  bool isHidden(Uint8List publicKey) => state.contains(_hex(publicKey));

  Future<void> setHidden(Uint8List publicKey, bool hidden) async {
    final key = _hex(publicKey);
    final next = {...state};
    if (hidden) {
      if (!next.add(key)) return;
    } else {
      if (!next.remove(key)) return;
    }
    state = next;
    await _persist();
  }

  Future<void> clearAll() async {
    if (state.isEmpty) return;
    state = const <String>{};
    await _persist();
  }

  static String _hex(Uint8List key) =>
      key.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

final mapHiddenContactsProvider =
    StateNotifierProvider<MapHiddenContactsNotifier, Set<String>>(
      (ref) => MapHiddenContactsNotifier(),
    );
