part of '../map_screen.dart';

/// Bottom sheet shown when tapping a contact marker on the map.
class _ContactInfoSheet extends ConsumerWidget {
  const _ContactInfoSheet({required this.contact});
  final Contact contact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final keyHex =
        contact.publicKey
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join();

    final typeLabel =
        contact.isChat
            ? 'Companheiro'
            : contact.isRepeater
            ? 'Repetidor'
            : contact.isRoom
            ? 'Sala'
            : 'Sensor';

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon + type chip on one line
          Row(
            children: [
              Icon(
                _iconData(contact),
                color: theme.colorScheme.primary,
                size: 28,
              ),
              const SizedBox(width: 10),
              Chip(
                label: Text(typeLabel),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 4),

          // Full name — wraps freely, no truncation
          Text(
            contact.name,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            softWrap: true,
          ),
          const SizedBox(height: 12),

          // Details
          _DetailRow(
            icon: Icons.fingerprint,
            label: 'ID',
            value: contact.shortId,
            monospace: true,
            theme: theme,
          ),
          if (contact.latitude != null && contact.longitude != null)
            _DetailRow(
              icon: Icons.location_on_outlined,
              label: 'GPS',
              value:
                  '${contact.latitude!.toStringAsFixed(5)},  '
                  '${contact.longitude!.toStringAsFixed(5)}',
              theme: theme,
            ),
          const SizedBox(height: 12),

          // Per-contact map opt-in: user can hide this node from the map
          // even though its adverts include coordinates.
          _MapVisibilityToggle(contact: contact),

          const SizedBox(height: 8),

          // Action button — only for chat contacts
          if (contact.isChat)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.chat),
                label: Text(context.l10n.commonSendMessage),
                onPressed: () {
                  Navigator.pop(context);
                  context.push('/chat/$keyHex');
                },
              ),
            ),
        ],
      ),
    );
  }

  IconData _iconData(Contact c) {
    if (c.isChat) return Icons.person;
    if (c.isRepeater) return Icons.cell_tower;
    if (c.isRoom) return Icons.meeting_room;
    return Icons.sensors;
  }
}

/// A labelled detail row used in the contact bottom sheet.
class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.theme,
    this.monospace = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final ThemeData theme;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          SizedBox(
            width: 36,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontFamily: monospace ? 'monospace' : null,
              ),
              softWrap: true,
            ),
          ),
        ],
      ),
    );
  }
}

/// Switch + label that flips a contact's "show on map" preference.
class _MapVisibilityToggle extends ConsumerWidget {
  const _MapVisibilityToggle({required this.contact});
  final Contact contact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final hidden = ref
        .watch(mapHiddenContactsProvider)
        .contains(
          contact.publicKey
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join(),
        );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text(context.l10n.mapVisibilityShowTitle),
        subtitle: Text(
          context.l10n.mapVisibilityShowSubtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        value: !hidden,
        onChanged: (show) {
          ref
              .read(mapHiddenContactsProvider.notifier)
              .setHidden(contact.publicKey, !show);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Cluster data model
// ---------------------------------------------------------------------------

class _ContactCluster {
  const _ContactCluster({required this.members, required this.center});
  final List<Contact> members;
  final LatLng center;
  bool get isSingle => members.length == 1;
}

// ---------------------------------------------------------------------------
