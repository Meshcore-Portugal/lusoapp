part of '../map_screen.dart';

// Cluster list bottom sheet
// ---------------------------------------------------------------------------

class _ClusterListSheet extends StatelessWidget {
  const _ClusterListSheet({required this.cluster, required this.onContactTap});

  final _ContactCluster cluster;
  final void Function(Contact) onContactTap;

  static Color _typeColor(Contact c) {
    if (c.isChat) return Colors.blue.shade600;
    if (c.isRepeater) return Colors.orange.shade700;
    if (c.isRoom) return Colors.purple.shade600;
    return Colors.teal.shade600;
  }

  static IconData _typeIcon(Contact c) {
    if (c.isChat) return Icons.person;
    if (c.isRepeater) return Icons.cell_tower;
    if (c.isRoom) return Icons.meeting_room;
    return Icons.sensors;
  }

  static String _typeLabel(Contact c) {
    if (c.isChat) return 'Companheiro';
    if (c.isRepeater) return 'Repetidor';
    if (c.isRoom) return 'Sala';
    return 'Sensor';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.65,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              '${cluster.members.length} ${context.l10n.mapNodesAtLocation}',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final contact in cluster.members)
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: _typeColor(contact),
                      child: Icon(
                        _typeIcon(contact),
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      contact.name,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      '${_typeLabel(contact)}  ·  ${contact.shortId}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => onContactTap(contact),
                  ),
              ],
            ),
          ),
          SizedBox(height: MediaQuery.of(context).viewInsets.bottom + 16),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Trace result overlay card
// ---------------------------------------------------------------------------

/// Formats a distance in metres as a human-readable string.
String _formatDist(double m) {
  if (m >= 1000) return '${(m / 1000).toStringAsFixed(1)} km';
  return '${m.round()} m';
}

