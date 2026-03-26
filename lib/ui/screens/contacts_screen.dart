import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../protocol/protocol.dart';
import '../../providers/radio_providers.dart';

// Filter tabs
enum _Filter { todos, companheiros, repetidores, salas, sensores }

/// Contacts list screen with filter tabs.
class ContactsScreen extends ConsumerStatefulWidget {
  const ContactsScreen({super.key});

  @override
  ConsumerState<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends ConsumerState<ContactsScreen> {
  _Filter _filter = _Filter.todos;

  @override
  Widget build(BuildContext context) {
    final contacts = ref.watch(contactsProvider);

    final chatContacts = contacts.where((c) => c.isChat).toList();
    final repeaters = contacts.where((c) => c.isRepeater).toList();
    final rooms = contacts.where((c) => c.isRoom).toList();
    final sensors = contacts.where((c) => c.isSensor).toList();

    List<Contact> filtered;
    switch (_filter) {
      case _Filter.companheiros:
        filtered = chatContacts;
      case _Filter.repetidores:
        filtered = repeaters;
      case _Filter.salas:
        filtered = rooms;
      case _Filter.sensores:
        filtered = sensors;
      case _Filter.todos:
        filtered = contacts;
    }

    return Column(
      children: [
        // Filter chips bar
        _FilterBar(
          filter: _filter,
          counts: (
            todos: contacts.length,
            companheiros: chatContacts.length,
            repetidores: repeaters.length,
            salas: rooms.length,
            sensores: sensors.length,
          ),
          onChanged: (f) => setState(() => _filter = f),
        ),

        // Content
        Expanded(
          child:
              filtered.isEmpty
                  ? _EmptyState(
                    filter: _filter,
                    onAdvert:
                        () => ref
                            .read(radioServiceProvider)
                            ?.sendAdvert(flood: true),
                  )
                  : RefreshIndicator(
                    onRefresh:
                        () async =>
                            ref.read(radioServiceProvider)?.requestContacts(),
                    child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder:
                          (context, i) => _ContactTile(contact: filtered[i]),
                    ),
                  ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Filter bar
// ---------------------------------------------------------------------------

typedef _Counts =
    ({int todos, int companheiros, int repetidores, int salas, int sensores});

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.filter,
    required this.counts,
    required this.onChanged,
  });

  final _Filter filter;
  final _Counts counts;
  final ValueChanged<_Filter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        spacing: 8,
        children: [
          _chip(_Filter.todos, 'Todos', Icons.people, counts.todos),
          _chip(
            _Filter.companheiros,
            'Companheiros',
            Icons.person,
            counts.companheiros,
          ),
          _chip(
            _Filter.repetidores,
            'Repetidores',
            Icons.cell_tower,
            counts.repetidores,
          ),
          _chip(_Filter.salas, 'Salas', Icons.meeting_room, counts.salas),
          _chip(_Filter.sensores, 'Sensores', Icons.sensors, counts.sensores),
        ],
      ),
    );
  }

  Widget _chip(_Filter f, String label, IconData icon, int count) {
    final selected = filter == f;
    return FilterChip(
      selected: selected,
      avatar: Icon(icon, size: 16),
      label: Text(count > 0 ? '$label ($count)' : label),
      onSelected: (_) => onChanged(f),
      showCheckmark: false,
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filter, required this.onAdvert});
  final _Filter filter;
  final VoidCallback onAdvert;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, msg) = switch (filter) {
      _Filter.companheiros => (Icons.person_off, 'Sem companheiros na rede'),
      _Filter.repetidores => (Icons.cell_tower, 'Sem repetidores na rede'),
      _Filter.salas => (Icons.meeting_room, 'Sem salas na rede'),
      _Filter.sensores => (Icons.sensors_off, 'Sem sensores na rede'),
      _Filter.todos => (Icons.contacts_outlined, 'Sem contactos'),
    };

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 64,
            color: theme.colorScheme.onSurface.withAlpha(60),
          ),
          const SizedBox(height: 16),
          Text(
            msg,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface.withAlpha(120),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Os contactos aparecem quando o radio os descobre',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onAdvert,
            icon: const Icon(Icons.broadcast_on_home),
            label: const Text('Enviar Anúncio'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Contact tile
// ---------------------------------------------------------------------------

class _ContactTile extends ConsumerWidget {
  const _ContactTile({required this.contact});
  final Contact contact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final keyHex =
        contact.publicKey
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join();

    // First 6 bytes of the public key as hex — matches incoming senderKey.
    final prefix6 =
        contact.publicKey
            .take(6)
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join();

    final unreadCount =
        contact.isChat
            ? ref.watch(
              unreadCountsProvider.select((u) => u.forContact(prefix6)),
            )
            : 0;

    final lastSeen =
        contact.lastAdvertTimestamp > 0
            ? _formatTimestamp(contact.lastAdvertTimestamp)
            : 'Nunca';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: ListTile(
        leading: Badge(
          isLabelVisible: unreadCount > 0,
          label: Text(unreadCount > 99 ? '99+' : '$unreadCount'),
          child: CircleAvatar(
            backgroundColor: _typeColor(contact.type).withAlpha(40),
            child: Icon(
              _typeIcon(contact.type),
              color: _typeColor(contact.type),
              size: 20,
            ),
          ),
        ),
        title: Text(
          contact.name.isNotEmpty ? contact.name : contact.shortId,
          style: TextStyle(
            fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.w600,
          ),
        ),
        subtitle: Text(
          'Visto: $lastSeen  |  Saltos: ${contact.pathLen}',
          style: theme.textTheme.bodySmall,
        ),
        trailing:
            contact.isChat
                ? IconButton(
                  icon: const Icon(Icons.chat),
                  onPressed: () => context.go('/chat/$keyHex'),
                )
                : null,
        onTap: contact.isChat ? () => context.go('/chat/$keyHex') : null,
      ),
    );
  }

  IconData _typeIcon(int type) {
    switch (type) {
      case 1:
        return Icons.person;
      case 2:
        return Icons.cell_tower;
      case 3:
        return Icons.meeting_room;
      case 4:
        return Icons.sensors;
      default:
        return Icons.device_unknown;
    }
  }

  Color _typeColor(int type) {
    switch (type) {
      case 1:
        return Colors.blue;
      case 2:
        return Colors.orange;
      case 3:
        return Colors.purple;
      case 4:
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }

  String _formatTimestamp(int ts) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Agora';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m atras';
    if (diff.inHours < 24) return '${diff.inHours}h atras';
    return '${diff.inDays}d atras';
  }
}
