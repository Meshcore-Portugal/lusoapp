import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../protocol/protocol.dart';
import '../../providers/radio_providers.dart';
import 'telemetry_screen.dart';

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

  @override
  void initState() {
    super.initState();
    final config = ref.read(radioConfigProvider);
    _populateFrom(config);
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
    final service = ref.read(radioServiceProvider);
    if (service == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Rádio não ligado')));
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
      ).showSnackBar(const SnackBar(content: Text('Configuração guardada')));
    }
  }

  void _markDirty() => setState(() => _dirty = true);

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(radioConfigProvider);
    final deviceInfo = ref.watch(deviceInfoProvider);
    final selfInfo = ref.watch(selfInfoProvider);
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
      appBar: AppBar(title: const Text('Configuração do Rádio')),
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
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Dispositivo',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (selfInfo != null)
                          _InfoRow(label: 'Nome', value: selfInfo.name),
                        if (deviceInfo != null) ...[
                          _InfoRow(
                            label: 'Modelo',
                            value: deviceInfo.model ?? deviceInfo.deviceName,
                          ),
                          _InfoRow(
                            label: 'Firmware',
                            value:
                                deviceInfo.versionString ??
                                'v${deviceInfo.firmwareVersion}',
                          ),
                          if (deviceInfo.storageUsed != null &&
                              deviceInfo.storageTotal != null)
                            _InfoRow(
                              label: 'Armazenamento',
                              value:
                                  '${deviceInfo.storageUsed} / ${deviceInfo.storageTotal} bytes',
                            ),
                        ],
                      ],
                    ),
                  ),
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
                        'Parâmetros LoRa',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Frequency
                      TextFormField(
                        controller: _freqController,
                        decoration: const InputDecoration(
                          labelText: 'Frequência (MHz)',
                          helperText: 'Ex: 868.1250',
                          border: OutlineInputBorder(),
                          suffixText: 'MHz',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) {
                            return 'Insere a frequência';
                          }
                          final d = double.tryParse(v);
                          if (d == null || d < 150 || d > 2500) {
                            return 'Frequência inválida (150–2500 MHz)';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 16),

                      // Bandwidth
                      DropdownButtonFormField<int>(
                        key: ValueKey('bw_$_bandwidthHz'),
                        initialValue: _bandwidthHz,
                        decoration: const InputDecoration(
                          labelText: 'Largura de banda',
                          border: OutlineInputBorder(),
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
                                    ? 'Selecciona a largura de banda'
                                    : null,
                      ),

                      const SizedBox(height: 16),

                      // Spreading Factor
                      DropdownButtonFormField<int>(
                        key: ValueKey('sf_$_spreadingFactor'),
                        initialValue: _spreadingFactor,
                        decoration: const InputDecoration(
                          labelText: 'Spreading Factor',
                          border: OutlineInputBorder(),
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
                                    ? 'Selecciona o spreading factor'
                                    : null,
                      ),

                      const SizedBox(height: 16),

                      // Coding Rate
                      DropdownButtonFormField<int>(
                        key: ValueKey('cr_$_codingRate'),
                        initialValue: _codingRate,
                        decoration: const InputDecoration(
                          labelText: 'Coding Rate',
                          border: OutlineInputBorder(),
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
                                v == null ? 'Selecciona o coding rate' : null,
                      ),

                      const SizedBox(height: 16),

                      // TX Power
                      TextFormField(
                        controller: _txPowerController,
                        decoration: InputDecoration(
                          labelText: 'Potência TX',
                          helperText:
                              deviceInfo != null
                                  ? 'Máx: ${selfInfo?.maxTxPower ?? "?"} dBm'
                                  : null,
                          border: const OutlineInputBorder(),
                          suffixText: 'dBm',
                        ),
                        keyboardType: TextInputType.number,
                        validator: (v) {
                          if (v == null || v.isEmpty) {
                            return 'Insere a potência';
                          }
                          final i = int.tryParse(v);
                          if (i == null || i < 1 || i > 30) {
                            return 'Potência inválida (1–30 dBm)';
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
                label: Text(_saving ? 'A guardar...' : 'Guardar'),
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
                  label: const Text('Repor valores actuais'),
                ),
              ],

              // ----- Advert auto-add settings -----
              const SizedBox(height: 24),
              const _AdvertAutoAddCard(),

              // ----- Telemetry section -----
              const SizedBox(height: 32),
              Text(
                'Telemetria',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              // Embed telemetry as a non-scrollable column (parent scrolls).
              const _EmbeddedTelemetry(),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Embedded telemetry — wraps TelemetryScreen content without its own scroll
// ---------------------------------------------------------------------------

class _EmbeddedTelemetry extends StatelessWidget {
  const _EmbeddedTelemetry();

  @override
  Widget build(BuildContext context) {
    // TelemetryScreen is a ConsumerWidget with a ListView.
    // We embed it with constrained height so it doesn't conflict with the
    // parent scroll. SizedBox with a generous height lets it render fully.
    return const SizedBox(height: 600, child: TelemetryScreen());
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
                  'Configuração Activa',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _ConfigRow(
              label: 'Frequência',
              value: '${freqMHz.toStringAsFixed(4)} MHz',
            ),
            _ConfigRow(
              label: 'Largura de Banda',
              value: '${bwKHz % 1 == 0 ? bwKHz.toInt() : bwKHz} kHz',
            ),
            _ConfigRow(
              label: 'Spreading Factor',
              value: 'SF${config.spreadingFactor}',
            ),
            _ConfigRow(
              label: 'Coding Rate',
              value: _crLabel(config.codingRate),
            ),
            _ConfigRow(label: 'Potência TX', value: '${config.txPowerDbm} dBm'),
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

class _AdvertAutoAddCard extends ConsumerWidget {
  const _AdvertAutoAddCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final s = ref.watch(advertAutoAddProvider);
    final n = ref.read(advertAutoAddProvider.notifier);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.person_add_alt_1,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Adição automática de contactos',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Quando um nó envia um advert e o rádio está em modo manual, '
              'a app pode adicioná-lo automaticamente à tabela de contactos do rádio.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            _AutoAddTile(
              icon: Icons.person,
              label: 'Companheiro (Chat)',
              value: s.addChat,
              onChanged: n.setChat,
            ),
            _AutoAddTile(
              icon: Icons.cell_tower,
              label: 'Repetidor',
              value: s.addRepeater,
              onChanged: n.setRepeater,
            ),
            _AutoAddTile(
              icon: Icons.meeting_room,
              label: 'Sala (Room)',
              value: s.addRoom,
              onChanged: n.setRoom,
            ),
            _AutoAddTile(
              icon: Icons.sensors,
              label: 'Sensor',
              value: s.addSensor,
              onChanged: n.setSensor,
            ),
          ],
        ),
      ),
    );
  }
}

class _AutoAddTile extends StatelessWidget {
  const _AutoAddTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      secondary: Icon(icon, size: 20),
      title: Text(label),
      value: value,
      onChanged: onChanged,
    );
  }
}
