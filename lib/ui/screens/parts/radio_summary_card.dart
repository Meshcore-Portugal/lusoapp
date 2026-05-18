part of '../radio_settings_screen.dart';

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
