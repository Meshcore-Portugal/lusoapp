import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../l10n/l10n.dart';
import '../../protocol/protocol.dart';
import '../../providers/radio_providers.dart';
import 'discover_contacts_screen.dart';

/// Drill-down page for radio configuration and telemetry.
///
/// Accessed from Settings → Rádio. Shows config summary, device info,
/// LoRa parameter form, and telemetry in a single scrollable page.
class RadioSettingsScreen extends ConsumerStatefulWidget {
  const RadioSettingsScreen({super.key});

  @override
  ConsumerState<RadioSettingsScreen> createState() =>
      _RadioSettingsScreenState();
}

class _RadioSettingsScreenState extends ConsumerState<RadioSettingsScreen> {
  final _formKey = GlobalKey<FormState>();

  final _freqController = TextEditingController();
  final _txPowerController = TextEditingController();

  int? _bandwidthHz;
  int? _spreadingFactor;
  int? _codingRate;

  bool _dirty = false;
  bool _saving = false;
  String _appVersion = '';

  static const _bandwidths = [
    (label: '7.8 kHz', hz: 7800),
    (label: '10.4 kHz', hz: 10400),
    (label: '15.6 kHz', hz: 15600),
    (label: '20.8 kHz', hz: 20800),
    (label: '31.25 kHz', hz: 31250),
    (label: '41.7 kHz', hz: 41700),
    (label: '62.5 kHz', hz: 62500),
    (label: '125 kHz', hz: 125000),
    (label: '250 kHz', hz: 250000),
    (label: '500 kHz', hz: 500000),
  ];

  static const _spreadingFactors = [5, 6, 7, 8, 9, 10, 11, 12];
  static const _codingRates = [
    (label: '4/5', val: 5),
    (label: '4/6', val: 6),
    (label: '4/7', val: 7),
    (label: '4/8', val: 8),
  ];

  // 433.375 MHz and 869.618 MHz are the MeshCore community defaults for PT/EU.
  // freqKHz is stored in MHz×1000 units (same as RadioConfig.frequencyHz).
  static const _bandPresets = [
    (
      label: '433 MHz',
      freqKHz: 433375,
      bandwidthHz: 62500,
      sf: 9,
      cr: 6,
      txPower: 10,
    ),
    (
      label: '868 MHz',
      freqKHz: 869618,
      bandwidthHz: 62500,
      sf: 7,
      cr: 6,
      txPower: 27,
    ),
  ];

  /// Returns the index of the matching band preset, or null if the current
  /// form values don't match any preset (i.e. user has custom settings).
  int? get _activePresetIndex {
    final freqKHz =
        ((double.tryParse(_freqController.text) ?? 0) * 1e3).round();
    final txPower = int.tryParse(_txPowerController.text);
    for (var i = 0; i < _bandPresets.length; i++) {
      final p = _bandPresets[i];
      if (freqKHz == p.freqKHz &&
          _bandwidthHz == p.bandwidthHz &&
          _spreadingFactor == p.sf &&
          _codingRate == p.cr &&
          txPower == p.txPower) {
        return i;
      }
    }
    return null;
  }

  void _applyPreset(int index) {
    final p = _bandPresets[index];
    setState(() {
      _freqController.text = (p.freqKHz / 1e3).toStringAsFixed(4);
      _bandwidthHz = p.bandwidthHz;
      _spreadingFactor = p.sf;
      _codingRate = p.cr;
      _txPowerController.text = '${p.txPower}';
      _dirty = true;
    });
  }

  @override
  void initState() {
    super.initState();
    final config = ref.read(radioConfigProvider);
    _populateFrom(config);
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _appVersion = info.version);
    });
  }

  void _populateFrom(RadioConfig? config) {
    if (config == null) return;
    _freqController.text = (config.frequencyHz / 1e3).toStringAsFixed(4);
    _txPowerController.text = '${config.txPowerDbm}';
    _bandwidthHz = config.bandwidthHz;
    _spreadingFactor = config.spreadingFactor;
    _codingRate = config.codingRate;
  }

  @override
  void dispose() {
    _freqController.dispose();
    _txPowerController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final l10n = context.l10n;
    final service = ref.read(radioServiceProvider);
    if (service == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.commonRadioDisconnected)));
      return;
    }

    setState(() => _saving = true);

    final freqHz = ((double.tryParse(_freqController.text) ?? 0) * 1e3).round();
    final txPower = int.tryParse(_txPowerController.text) ?? 0;

    final config = RadioConfig(
      frequencyHz: freqHz,
      bandwidthHz: _bandwidthHz ?? 125000,
      spreadingFactor: _spreadingFactor ?? 9,
      codingRate: _codingRate ?? 5,
      txPowerDbm: txPower,
    );

    await service.setRadioParams(config);
    await service.setTxPower(txPower);

    ref.read(radioConfigProvider.notifier).state = config;

    setState(() {
      _saving = false;
      _dirty = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.radioSettingsSaved)));
    }
  }

  void _markDirty() => setState(() => _dirty = true);

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(radioConfigProvider);
    final deviceInfo = ref.watch(deviceInfoProvider);
    final selfInfo = ref.watch(selfInfoProvider);
    final contacts = ref.watch(contactsProvider);
    final channels = ref.watch(channelsProvider);
    final discovered = ref.watch(discoveredContactsProvider);
    final theme = Theme.of(context);

    // Keep form in sync with radio-pushed config while user hasn't edited.
    if (!_dirty && config != null) {
      final freqText = (config.frequencyHz / 1e3).toStringAsFixed(4);
      if (_freqController.text != freqText) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_dirty && mounted) _populateFrom(config);
        });
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.radioSettingsTitle)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          onChanged: _markDirty,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ----- Active config summary -----
              if (config != null) _ConfigSummaryCard(config: config),
              if (config != null) const SizedBox(height: 16),

              // ----- Device info -----
              if (deviceInfo != null || selfInfo != null)
                _DeviceInfoCard(
                  selfInfo: selfInfo,
                  deviceInfo: deviceInfo,
                  contactCount: contacts.length,
                  activeChannelCount: channels.where((c) => !c.isEmpty).length,
                  discoveredCount: discovered.length,
                  appVersion: _appVersion,
                ),
              if (deviceInfo != null || selfInfo != null)
                const SizedBox(height: 16),

              // ----- LoRa parameters -----
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.radioSettingsLoRa,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // ----- Band presets -----
                      Text(
                        context.l10n.radioSettingsBandPresetsTitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      SegmentedButton<int>(
                        emptySelectionAllowed: true,
                        segments: [
                          for (var i = 0; i < _bandPresets.length; i++)
                            ButtonSegment(
                              value: i,
                              label: Text(_bandPresets[i].label),
                              icon: const Icon(Icons.radio, size: 16),
                            ),
                        ],
                        selected: {
                          if (_activePresetIndex != null) _activePresetIndex!,
                        },
                        onSelectionChanged: (sel) {
                          if (sel.isNotEmpty) _applyPreset(sel.first);
                        },
                      ),
                      const SizedBox(height: 16),

                      // Frequency
                      TextFormField(
                        controller: _freqController,
                        decoration: InputDecoration(
                          labelText: context.l10n.radioSettingsFrequency,
                          helperText: context.l10n.radioSettingsFrequencyHint,
                          border: const OutlineInputBorder(),
                          suffixText: 'MHz',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) {
                            return context.l10n.radioSettingsFrequencyRequired;
                          }
                          final d = double.tryParse(v);
                          if (d == null || d < 150 || d > 2500) {
                            return context.l10n.radioSettingsFrequencyInvalid;
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 16),

                      // Bandwidth
                      DropdownButtonFormField<int>(
                        key: ValueKey('bw_$_bandwidthHz'),
                        initialValue: _bandwidthHz,
                        decoration: InputDecoration(
                          labelText: context.l10n.radioSettingsBandwidth,
                          border: const OutlineInputBorder(),
                        ),
                        items:
                            _bandwidths
                                .map(
                                  (b) => DropdownMenuItem(
                                    value: b.hz,
                                    child: Text(b.label),
                                  ),
                                )
                                .toList(),
                        onChanged: (v) {
                          setState(() {
                            _bandwidthHz = v;
                            _dirty = true;
                          });
                        },
                        validator:
                            (v) =>
                                v == null
                                    ? context
                                        .l10n
                                        .radioSettingsBandwidthRequired
                                    : null,
                      ),

                      const SizedBox(height: 16),

                      // Spreading Factor
                      DropdownButtonFormField<int>(
                        key: ValueKey('sf_$_spreadingFactor'),
                        initialValue: _spreadingFactor,
                        decoration: InputDecoration(
                          labelText: context.l10n.radioSettingsSpreadingFactor,
                          border: const OutlineInputBorder(),
                        ),
                        items:
                            _spreadingFactors
                                .map(
                                  (sf) => DropdownMenuItem(
                                    value: sf,
                                    child: Text('SF$sf'),
                                  ),
                                )
                                .toList(),
                        onChanged: (v) {
                          setState(() {
                            _spreadingFactor = v;
                            _dirty = true;
                          });
                        },
                        validator:
                            (v) =>
                                v == null
                                    ? context.l10n.radioSettingsSFRequired
                                    : null,
                      ),

                      const SizedBox(height: 16),

                      // Coding Rate
                      DropdownButtonFormField<int>(
                        key: ValueKey('cr_$_codingRate'),
                        initialValue: _codingRate,
                        decoration: InputDecoration(
                          labelText: context.l10n.radioSettingsCodingRate,
                          border: const OutlineInputBorder(),
                        ),
                        items:
                            _codingRates
                                .map(
                                  (cr) => DropdownMenuItem(
                                    value: cr.val,
                                    child: Text(cr.label),
                                  ),
                                )
                                .toList(),
                        onChanged: (v) {
                          setState(() {
                            _codingRate = v;
                            _dirty = true;
                          });
                        },
                        validator:
                            (v) =>
                                v == null
                                    ? context.l10n.radioSettingsCRRequired
                                    : null,
                      ),

                      const SizedBox(height: 16),

                      // TX Power
                      TextFormField(
                        controller: _txPowerController,
                        decoration: InputDecoration(
                          labelText: context.l10n.radioSettingsTxPower,
                          helperText:
                              deviceInfo != null
                                  ? '${context.l10n.radioSettingsMax} ${selfInfo?.maxTxPower ?? "?"} ${context.l10n.radioSettingsDbm}'
                                  : null,
                          border: const OutlineInputBorder(),
                          suffixText: 'dBm',
                        ),
                        keyboardType: TextInputType.number,
                        validator: (v) {
                          if (v == null || v.isEmpty) {
                            return context.l10n.radioSettingsPowerRequired;
                          }
                          final i = int.tryParse(v);
                          if (i == null || i < 1 || i > 30) {
                            return context.l10n.radioSettingsPowerInvalid;
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Save button
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon:
                    _saving
                        ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Icon(Icons.save),
                label: Text(
                  _saving ? context.l10n.commonSaving : context.l10n.commonSave,
                ),
              ),

              if (config != null) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed:
                      _dirty
                          ? () {
                            setState(() {
                              _populateFrom(config);
                              _dirty = false;
                            });
                          }
                          : null,
                  icon: const Icon(Icons.undo),
                  label: Text(context.l10n.radioSettingsResetValues),
                ),
              ],

              // ----- Advert auto-add settings -----
              const SizedBox(height: 24),
              const _AdvertAutoAddCard(),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Compact config summary card
// ---------------------------------------------------------------------------

class _ConfigSummaryCard extends StatelessWidget {
  const _ConfigSummaryCard({required this.config});
  final RadioConfig config;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final freqMHz = config.frequencyHz / 1e3;
    final bwKHz = config.bandwidthHz / 1e3;

    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.radio,
                  size: 18,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
                const SizedBox(width: 8),
                Text(
                  context.l10n.radioSettingsActiveConfig,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _ConfigRow(
              label: context.l10n.radioSettingsFreqLabel,
              value: '${freqMHz.toStringAsFixed(4)} MHz',
            ),
            _ConfigRow(
              label: context.l10n.radioSettingsBandwidth,
              value: '${bwKHz % 1 == 0 ? bwKHz.toInt() : bwKHz} kHz',
            ),
            _ConfigRow(
              label: context.l10n.radioSettingsSpreadingFactor,
              value: 'SF${config.spreadingFactor}',
            ),
            _ConfigRow(
              label: context.l10n.radioSettingsCodingRate,
              value: _crLabel(config.codingRate),
            ),
            _ConfigRow(
              label: context.l10n.radioSettingsTxPower,
              value: '${config.txPowerDbm} dBm',
            ),
          ],
        ),
      ),
    );
  }

  String _crLabel(int cr) {
    switch (cr) {
      case 5:
        return '4/5';
      case 6:
        return '4/6';
      case 7:
        return '4/7';
      case 8:
        return '4/8';
      default:
        return 'CR$cr';
    }
  }
}

// ---------------------------------------------------------------------------
// Device info card
// ---------------------------------------------------------------------------

class _DeviceInfoCard extends ConsumerWidget {
  const _DeviceInfoCard({
    required this.selfInfo,
    required this.deviceInfo,
    required this.contactCount,
    required this.activeChannelCount,
    required this.discoveredCount,
    required this.appVersion,
  });

  final SelfInfo? selfInfo;
  final DeviceInfo? deviceInfo;
  final int contactCount;
  final int activeChannelCount;
  final int discoveredCount;
  final String appVersion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final maxChannels = deviceInfo?.maxChannels;
    final maxContacts = deviceInfo?.maxContacts;
    final (storageUsed, storageTotal) = ref.watch(storageProvider);

    String _kbStr(int bytes) {
      if (bytes < 1024) return '${bytes}b';
      return '${(bytes / 1024).toStringAsFixed(0)}kb';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.radioSettingsDevice,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),

            // Radio identity rows
            if (selfInfo != null)
              _InfoRow(label: l10n.commonName, value: selfInfo!.name),
            if (deviceInfo != null) ...[
              _InfoRow(
                label: l10n.radioSettingsModel,
                value: deviceInfo!.model ?? deviceInfo!.deviceName,
              ),
              _InfoRow(
                label: l10n.radioSettingsFirmware,
                value:
                    deviceInfo!.versionString ??
                    'v${deviceInfo!.firmwareVersion}',
              ),
            ],

            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),

            // Capacity indicators row
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _CapacityRow(
                        label: l10n.radioSettingsChannels,
                        used: activeChannelCount,
                        max: maxChannels,
                      ),
                      const SizedBox(height: 4),
                      _CapacityRow(
                        label: l10n.radioSettingsContacts,
                        used: contactCount,
                        max: maxContacts,
                      ),
                      const SizedBox(height: 4),
                      _CapacityRow(
                        label: l10n.radioSettingsDiscovered,
                        used: discoveredCount,
                        max: null,
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Storage
            if (storageUsed != null && storageTotal != null) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    Icons.sd_storage,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.radioSettingsStorage,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withAlpha(140),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value:
                                      storageTotal > 0
                                          ? storageUsed / storageTotal
                                          : 0,
                                  minHeight: 6,
                                  backgroundColor:
                                      theme.colorScheme.surfaceContainerHighest,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${_kbStr(storageUsed)} / ${_kbStr(storageTotal)}',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],

            // App version
            if (appVersion.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 8),
              _InfoRow(label: l10n.radioSettingsAppVersion, value: appVersion),
            ],
          ],
        ),
      ),
    );
  }
}

class _CapacityRow extends StatelessWidget {
  const _CapacityRow({
    required this.label,
    required this.used,
    required this.max,
  });

  final String label;
  final int used;
  final int? max;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valueText = max != null ? '$used/$max' : '$used';
    return Row(
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withAlpha(140),
            ),
          ),
        ),
        Text(
          valueText,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _ConfigRow extends StatelessWidget {
  const _ConfigRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onPrimaryContainer;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(color: color),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withAlpha(140),
              ),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Advert auto-add card
// ---------------------------------------------------------------------------

class _AdvertAutoAddCard extends ConsumerStatefulWidget {
  const _AdvertAutoAddCard();

  @override
  ConsumerState<_AdvertAutoAddCard> createState() => _AdvertAutoAddCardState();
}

class _AdvertAutoAddCardState extends ConsumerState<_AdvertAutoAddCard> {
  final _maxHopsCtrl = TextEditingController();
  bool _maxHopsInitialized = false;

  @override
  void dispose() {
    _maxHopsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final s = ref.watch(advertAutoAddProvider);
    final n = ref.read(advertAutoAddProvider.notifier);

    // Sync max-hops field once after the settings are loaded.
    if (!_maxHopsInitialized) {
      _maxHopsInitialized = true;
      _maxHopsCtrl.text = s.maxHops != null ? '${s.maxHops}' : '';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Title ──────────────────────────────────────────────────────
            Row(
              children: [
                Icon(
                  Icons.person_add_alt_1,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.radioSettingsAutoAddTitle,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── Auto Add All ───────────────────────────────────────────────
            RadioListTile<bool>(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(
                l10n.radioSettingsAutoAddAll,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                l10n.radioSettingsAutoAddAllDesc,
                style: theme.textTheme.bodySmall,
              ),
              value: true,
              groupValue: s.addAll,
              onChanged: (_) => n.setAddAll(true),
            ),

            // ── Auto Add Selected ──────────────────────────────────────────
            RadioListTile<bool>(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(
                l10n.radioSettingsAutoAddSelected,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                l10n.radioSettingsAutoAddSelectedDesc,
                style: theme.textTheme.bodySmall,
              ),
              value: false,
              groupValue: s.addAll,
              onChanged: (_) => n.setAddAll(false),
            ),

            // Per-type checkboxes — only relevant in "selected" mode.
            AnimatedOpacity(
              opacity: s.addAll ? 0.4 : 1.0,
              duration: const Duration(milliseconds: 200),
              child: Column(
                children: [
                  _TypeCheckTile(
                    icon: Icons.person,
                    label: l10n.radioSettingsAutoAddCompanion,
                    value: s.addChat,
                    onChanged: s.addAll ? null : n.setChat,
                  ),
                  _TypeCheckTile(
                    icon: Icons.cell_tower,
                    label: l10n.radioSettingsAutoAddRepeater,
                    value: s.addRepeater,
                    onChanged: s.addAll ? null : n.setRepeater,
                  ),
                  _TypeCheckTile(
                    icon: Icons.meeting_room,
                    label: l10n.radioSettingsAutoAddRoom,
                    value: s.addRoom,
                    onChanged: s.addAll ? null : n.setRoom,
                  ),
                  _TypeCheckTile(
                    icon: Icons.sensors,
                    label: l10n.radioSettingsAutoAddSensor,
                    value: s.addSensor,
                    onChanged: s.addAll ? null : n.setSensor,
                  ),
                ],
              ),
            ),

            const Divider(height: 24),

            // ── Overwrite Oldest ───────────────────────────────────────────
            _DescCheckTile(
              title: l10n.radioSettingsOverwriteOldest,
              subtitle: l10n.radioSettingsOverwriteOldestDesc,
              value: s.overwriteOldest,
              onChanged: n.setOverwriteOldest,
            ),

            const SizedBox(height: 12),

            // ── Auto Add Max Hops ──────────────────────────────────────────
            Text(
              l10n.radioSettingsAutoAddMaxHops,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.radioSettingsAutoAddMaxHopsDesc,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _maxHopsCtrl,
              decoration: InputDecoration(
                hintText: l10n.radioSettingsAutoAddMaxHopsHint,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              keyboardType: TextInputType.number,
              onChanged: (v) {
                final parsed = int.tryParse(v.trim());
                if (v.trim().isEmpty) {
                  n.setMaxHops(null);
                } else if (parsed != null && parsed >= 0 && parsed <= 63) {
                  n.setMaxHops(parsed);
                }
              },
            ),

            const Divider(height: 24),

            // ── Pull To Refresh ────────────────────────────────────────────
            _DescCheckTile(
              title: l10n.radioSettingsPullToRefresh,
              subtitle: l10n.radioSettingsPullToRefreshDesc,
              value: s.pullToRefresh,
              onChanged: n.setPullToRefresh,
            ),

            // ── Show Public Keys ───────────────────────────────────────────
            _DescCheckTile(
              title: l10n.radioSettingsShowPublicKeys,
              subtitle: l10n.radioSettingsShowPublicKeysDesc,
              value: s.showPublicKeys,
              onChanged: n.setShowPublicKeys,
            ),
          ],
        ),
      ),
    );
  }
}

/// Checkbox tile for per-type auto-add (with icon).
class _TypeCheckTile extends StatelessWidget {
  const _TypeCheckTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      dense: true,
      contentPadding: const EdgeInsets.only(left: 8),
      secondary: Icon(icon, size: 20),
      title: Text(label),
      value: value,
      onChanged: onChanged != null ? (v) => onChanged!(v ?? false) : null,
      controlAffinity: ListTileControlAffinity.trailing,
    );
  }
}

/// Checkbox tile with a title and subtitle description line.
class _DescCheckTile extends StatelessWidget {
  const _DescCheckTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      onChanged: (v) => onChanged(v ?? false),
      controlAffinity: ListTileControlAffinity.trailing,
    );
  }
}
