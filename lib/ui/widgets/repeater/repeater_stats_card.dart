import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';
import '../../../protocol/models.dart';

/// Card that renders the latest [RepeaterStats] received from the node.
class RepeaterStatsCard extends StatelessWidget {
  const RepeaterStatsCard({super.key, required this.stats});

  final RepeaterStats stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final ts =
        '${stats.receivedAt.hour.toString().padLeft(2, '0')}:'
        '${stats.receivedAt.minute.toString().padLeft(2, '0')}:'
        '${stats.receivedAt.second.toString().padLeft(2, '0')}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  l10n.contactsStats,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  '${l10n.commonUpdated} $ts',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const Divider(height: 16),
            _Kv(
              label: 'Bateria',
              value: '${stats.batteryVolts.toStringAsFixed(2)} V',
            ),
            _Kv(label: l10n.contactsUptime, value: stats.uptimeFormatted),
            _Kv(
              label: l10n.contactsSnrLast,
              value: '${stats.lastSnrDb.toStringAsFixed(1)} dB',
            ),
            _Kv(label: l10n.contactsRssiLast, value: '${stats.lastRssi} dBm'),
            _Kv(label: l10n.contactsNoise, value: '${stats.noiseFloor} dBm'),
            const Divider(height: 16),
            _Kv(
              label: l10n.contactsRxTx,
              value: '${stats.packetsRecv} / ${stats.packetsSent}',
            ),
            _Kv(
              label: l10n.contactsFloodRxTx,
              value: '${stats.recvFlood} / ${stats.sentFlood}',
            ),
            _Kv(
              label: l10n.contactsDirectRxTx,
              value: '${stats.recvDirect} / ${stats.sentDirect}',
            ),
            _Kv(label: l10n.contactsAirtimeTx, value: '${stats.airTimeSecs}s'),
            if (stats.rxAirTimeSecs != null)
              _Kv(
                label: l10n.contactsAirtimeRx,
                value: '${stats.rxAirTimeSecs}s',
              ),
            _Kv(
              label: l10n.contactsDuplicates,
              value: '${stats.directDups + stats.floodDups}',
            ),
            if (stats.errEvents > 0)
              _Kv(
                label: l10n.telemetryErrors,
                value: '${stats.errEvents}',
                valueColor: theme.colorScheme.error,
              ),
          ],
        ),
      ),
    );
  }
}

class _Kv extends StatelessWidget {
  const _Kv({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}
