part of '../radio_providers.dart';

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
    _load(null); // load global defaults on startup (before any radio connects)
  }

  final RadioService? Function() _getService;

  /// The device ID of the currently connected radio; null before first connect.
  String? _radioId;

  // Legacy global key (all radios shared one setting before per-radio scoping).
  static const _keyV1 = 'advert_autoadd_v1';
  // Per-radio key prefix:  advert_autoadd_v2_<sanitizedId>_<field>
  static const _keyV2Prefix = 'advert_autoadd_v2_';

  /// Returns the storage key prefix for [radioId] (scoped) or the legacy
  /// global prefix when [radioId] is null.
  String _prefix(String? radioId) =>
      radioId != null
          ? '$_keyV2Prefix${StorageService.sanitizeId(radioId)}'
          : _keyV1;

  Future<void> _load(String? radioId) async {
    final prefs = await SharedPreferences.getInstance();
    final p = '${_prefix(radioId)}_';
    const legacy = '${_keyV1}_';

    // Helper: read scoped key, fall back to legacy global (migration path),
    // then fall back to the provided default.
    bool b(String field, bool def) =>
        prefs.getBool('$p$field') ??
        (radioId != null ? prefs.getBool('$legacy$field') : null) ??
        def;
    int? i(String field) =>
        prefs.getInt('$p$field') ??
        (radioId != null ? prefs.getInt('$legacy$field') : null);

    state = AdvertAutoAddSettings(
      addAll: b('addAll', true),
      addChat: b('chat', true),
      addRepeater: b('repeater', true),
      addRoom: b('room', true),
      addSensor: b('sensor', true),
      overwriteOldest: b('overwriteOldest', false),
      maxHops: i('maxHops'),
      pullToRefresh: b('pullToRefresh', true),
      showPublicKeys: b('showPublicKeys', true),
    );
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final p = '${_prefix(_radioId)}_';
    final futures = <Future<void>>[
      prefs.setBool('${p}addAll', state.addAll),
      prefs.setBool('${p}chat', state.addChat),
      prefs.setBool('${p}repeater', state.addRepeater),
      prefs.setBool('${p}room', state.addRoom),
      prefs.setBool('${p}sensor', state.addSensor),
      prefs.setBool('${p}overwriteOldest', state.overwriteOldest),
      prefs.setBool('${p}pullToRefresh', state.pullToRefresh),
      prefs.setBool('${p}showPublicKeys', state.showPublicKeys),
    ];
    if (state.maxHops != null) {
      futures.add(prefs.setInt('${p}maxHops', state.maxHops!));
    } else {
      futures.add(prefs.remove('${p}maxHops'));
    }
    await Future.wait(futures);
  }

  /// Called when connecting to a specific radio.
  /// Loads per-radio settings (with legacy migration fallback) and marks all
  /// subsequent saves as scoped to this radio.
  Future<void> loadForRadio(String deviceId) async {
    _radioId = deviceId;
    await _load(deviceId);
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
