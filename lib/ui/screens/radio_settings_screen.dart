import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../l10n/l10n.dart';
import '../../protocol/protocol.dart';
import '../../providers/radio_providers.dart';
import 'discover_contacts_screen.dart';

part 'parts/radio_summary_card.dart';
part 'parts/radio_device_info_card.dart';
part 'parts/radio_advert_card.dart';

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

