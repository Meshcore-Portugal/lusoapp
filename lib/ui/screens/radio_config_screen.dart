import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../protocol/protocol.dart';
import '../../providers/radio_providers.dart';

/// Screen for viewing and editing the radio LoRa configuration.
class RadioConfigScreen extends ConsumerStatefulWidget {
  const RadioConfigScreen({super.key});

  @override
  ConsumerState<RadioConfigScreen> createState() => _RadioConfigScreenState();
}

class _RadioConfigScreenState extends ConsumerState<RadioConfigScreen> {
  final _formKey = GlobalKey<FormState>();

  // Form field controllers
  final _freqController = TextEditingController();
  final _txPowerController = TextEditingController();

  // Dropdown state
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
    _freqController.text = (config.frequencyHz / 1e6).toStringAsFixed(4);
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

    final freqHz = ((double.tryParse(_freqController.text) ?? 0) * 1e6).round();
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

    // If the radio just pushed a fresh config and we haven't dirtied the form,
    // keep the form in sync.
    if (!_dirty && config != null) {
      final freqText = (config.frequencyHz / 1e6).toStringAsFixed(4);
      if (_freqController.text != freqText) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_dirty && mounted) _populateFrom(config);
        });
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        onChanged: _markDirty,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ---------------------------------------------------------------
            // Device info card
            // ---------------------------------------------------------------
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

            // ---------------------------------------------------------------
            // LoRa parameters card
            // ---------------------------------------------------------------
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
                        if (d == null || d < 100 || d > 1100) {
                          return 'Frequência inválida (100–1100 MHz)';
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
                          (v) => v == null ? 'Selecciona o coding rate' : null,
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
              // Reset to current radio values
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
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helper widget
// ---------------------------------------------------------------------------

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
