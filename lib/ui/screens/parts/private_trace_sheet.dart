part of '../private_chat_screen.dart';

// ---------------------------------------------------------------------------
// Trace result bottom sheet
// ---------------------------------------------------------------------------

class _TraceResultSheet extends StatelessWidget {
  const _TraceResultSheet({required this.result, required this.theme});

  final TraceResult result;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final ts =
        '${result.timestamp.hour.toString().padLeft(2, '0')}:'
        '${result.timestamp.minute.toString().padLeft(2, '0')}:'
        '${result.timestamp.second.toString().padLeft(2, '0')}';

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(Icons.route, color: theme.colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Rota encontrada — $ts',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  '${result.hopCount} hop${result.hopCount != 1 ? 's' : ''}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 16),
          if (result.hops.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Rota directa (sem repetidores)',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            for (int i = 0; i < result.hops.length; i++)
              _TraceHopTile(index: i + 1, hop: result.hops[i], theme: theme),
          ListTile(
            leading: Icon(
              Icons.arrow_downward,
              color: Colors.green.shade600,
              size: 20,
            ),
            title: Text(context.l10n.privateReceivedOnRadio),
            trailing: Text(
              '${result.finalSnrDb.toStringAsFixed(1)} dB',
              style: theme.textTheme.labelLarge?.copyWith(
                color: Colors.green.shade600,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }
}

class _TraceHopTile extends StatelessWidget {
  const _TraceHopTile({
    required this.index,
    required this.hop,
    required this.theme,
  });

  final int index;
  final TraceHop hop;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final snrColor =
        hop.snrDb > 5
            ? Colors.green.shade600
            : hop.snrDb > 0
            ? Colors.orange.shade700
            : Colors.red.shade600;

    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 14,
        backgroundColor: theme.colorScheme.primaryContainer,
        child: Text(
          '$index',
          style: TextStyle(
            color: theme.colorScheme.onPrimaryContainer,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      title: Text(
        hop.name ?? hop.hashHex,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontFamily: hop.name == null ? 'monospace' : null,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle:
          hop.hasGps
              ? Text(
                '${hop.latitude!.toStringAsFixed(5)}, ${hop.longitude!.toStringAsFixed(5)}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
              : Text(
                'Sem GPS',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outlineVariant,
                ),
              ),
      trailing: Text(
        '${hop.snrDb.toStringAsFixed(1)} dB',
        style: theme.textTheme.labelLarge?.copyWith(
          color: snrColor,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

