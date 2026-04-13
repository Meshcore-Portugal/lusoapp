import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../protocol/protocol.dart';
import '../../providers/radio_providers.dart';
import '../theme.dart';

/// Contacts discovered via mesh adverts but not (yet) saved to the radio.
final discoveredContactsProvider = Provider<List<Contact>>((ref) {
  final allContacts = ref.watch(contactsProvider);
  final service = ref.watch(radioServiceProvider);

  // Advert-only contacts are those in local cache but not confirmed on radio.
  if (service == null || service.contacts.isEmpty) {
    return []; // No radio connected or no radio contacts yet.
  }

  final radioKeys = service.contacts.map((c) => _hex32(c.publicKey)).toSet();
  final discovered =
      allContacts
          .where((c) => !radioKeys.contains(_hex32(c.publicKey)))
          .toList();

  // Sort by last heard (newest first).
  discovered.sort(
    (a, b) => (b.lastModified ?? b.lastAdvertTimestamp).compareTo(
      a.lastModified ?? a.lastAdvertTimestamp,
    ),
  );

  return discovered;
});

String _hex32(Uint8List key) =>
    key.take(32).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// Discover new contacts via mesh advertisements.
class DiscoverContactsScreen extends ConsumerStatefulWidget {
  const DiscoverContactsScreen({super.key});

  @override
  ConsumerState<DiscoverContactsScreen> createState() =>
      _DiscoverContactsScreenState();
}

class _DiscoverContactsScreenState
    extends ConsumerState<DiscoverContactsScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      setState(() => _query = _searchCtrl.text.toLowerCase().trim());
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final discovered = ref.watch(discoveredContactsProvider);
    final theme = Theme.of(context);

    List<Contact> filtered = discovered;
    if (_query.isNotEmpty) {
      filtered =
          discovered
              .where(
                (c) =>
                    c.name.toLowerCase().contains(_query) ||
                    c.displayName.toLowerCase().contains(_query) ||
                    c.shortId.toLowerCase().contains(_query),
              )
              .toList();
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Descobrir'),
            Text(
              'Anúncios Recentes',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Procurar contactos descobertos...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon:
                    _query.isNotEmpty
                        ? IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => _searchCtrl.clear(),
                        )
                        : null,
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 8,
                  horizontal: 12,
                ),
              ),
            ),
          ),

          // Content
          Expanded(
            child:
                filtered.isEmpty
                    ? _EmptyState(hasAny: discovered.isNotEmpty, query: _query)
                    : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: filtered.length,
                      itemBuilder:
                          (context, i) =>
                              _DiscoveredContactTile(contact: filtered[i]),
                    ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasAny, required this.query});
  final bool hasAny;
  final String query;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasAny && query.isNotEmpty
                ? Icons.search_off
                : Icons.signal_cellular_off,
            size: 64,
            color: theme.colorScheme.onSurface.withAlpha(60),
          ),
          const SizedBox(height: 16),
          Text(
            hasAny && query.isNotEmpty
                ? 'Nenhum contacto encontrado'
                : 'Nenhum contacto descoberto',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface.withAlpha(120),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hasAny && query.isNotEmpty
                ? 'Tente uma busca diferente'
                : 'Contactos aparecem enquanto transmitem na rede',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _DiscoveredContactTile extends ConsumerWidget {
  const _DiscoveredContactTile({required this.contact});
  final Contact contact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final ts = contact.lastModified ?? contact.lastAdvertTimestamp;
    final lastSeen = ts > 0 ? _formatTimestamp(ts) : 'Nunca';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _avatarColor(contact).withAlpha(40),
          child: Icon(
            _avatarIcon(contact),
            color: _avatarColor(contact),
            size: 20,
          ),
        ),
        title: Text(
          contact.displayName,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          'Ouvido: $lastSeen  |  Caminho: ${_pathLabel(contact.pathLen)}  |  Saltos: ${contact.pathLen}',
          style: theme.textTheme.bodySmall,
        ),
        trailing: const Icon(Icons.arrow_forward, size: 18),
        onTap: () => _showAddSheet(context, ref),
      ),
    );
  }

  void _showAddSheet(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurface.withAlpha(40),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: _avatarColor(
                              contact,
                            ).withAlpha(40),
                            child: Icon(
                              _avatarIcon(contact),
                              color: _avatarColor(contact),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  contact.displayName,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  '${_typeLabel(contact.type)}  •  ${contact.shortId}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurface
                                        .withAlpha(130),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 8),

                      // Info section
                      _infoRow(
                        'Nome Anunciado',
                        contact.name.isNotEmpty ? contact.name : 'Sem nome',
                        theme,
                      ),
                      const SizedBox(height: 8),
                      _infoRow('Tipo', _typeLabel(contact.type), theme),
                      const SizedBox(height: 8),
                      _infoRow(
                        'Ouvido',
                        _formatTimestamp(
                          contact.lastModified ?? contact.lastAdvertTimestamp,
                        ),
                        theme,
                      ),
                      const SizedBox(height: 8),
                      _infoRow('Caminho', '${contact.pathLen} saltos', theme),
                      const SizedBox(height: 16),
                      const Divider(),
                    ],
                  ),
                ),

                // Action buttons
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _saveToRadio(context, ref);
                        },
                        icon: const Icon(Icons.save),
                        label: const Text('Guardar no rádio'),
                      ),
                      const SizedBox(height: 8),
                      if (contact.type == 0x01)
                        FilledButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            context.push('/chat/${_hex32(contact.publicKey)}');
                          },
                          icon: const Icon(Icons.chat),
                          label: const Text('Enviar mensagem'),
                        ),
                      if (contact.type == 0x03)
                        FilledButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            context.push('/room/${_hex32(contact.publicKey)}');
                          },
                          icon: const Icon(Icons.meeting_room),
                          label: const Text('Entrar na sala'),
                        ),
                      if (contact.type != 0x01 && contact.type != 0x03)
                        FilledButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _saveToRadio(context, ref);
                          },
                          icon: const Icon(Icons.person_add),
                          label: const Text('Adicionar e guardar'),
                        ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _saveToRadio(BuildContext context, WidgetRef ref) async {
    final service = ref.read(radioServiceProvider);
    if (service == null) return;

    try {
      final respFuture = service.responses
          .firstWhere((r) => r is OkResponse || r is ErrorResponse)
          .timeout(const Duration(seconds: 5));

      await service.addUpdateContact(contact);
      final resp = await respFuture;

      if (!context.mounted) return;
      if (resp is OkResponse) {
        await service.requestContacts();
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${contact.displayName} guardado no rádio')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro ao guardar contacto no rádio')),
        );
      }
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Timeout: rádio não respondeu')),
      );
    }
  }

  Widget _infoRow(String label, String value, ThemeData theme) {
    return Row(
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
          ),
        ),
      ],
    );
  }

  String _typeLabel(int type) {
    switch (type) {
      case 1:
        return 'Companheiro';
      case 2:
        return 'Repetidor';
      case 3:
        return 'Sala';
      case 4:
        return 'Sensor';
      default:
        return 'Desconhecido';
    }
  }

  String _pathLabel(int pathLen) {
    if (pathLen == 0) return 'Directo';
    if (pathLen == 1) return 'Próximo';
    return '$pathLen hops';
  }

  String _formatTimestamp(int ts) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Agora';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m atrás';
    if (diff.inHours < 24) return '${diff.inHours}h atrás';
    return '${diff.inDays}d atrás';
  }

  IconData _avatarIcon(Contact c) =>
      _isTimekeeper(c) ? Icons.access_time_rounded : _typeIcon(c.type);

  Color _avatarColor(Contact c) =>
      _isTimekeeper(c) ? Colors.teal : _typeColor(c.type);

  bool _isTimekeeper(Contact c) =>
      c.name.toLowerCase().contains('timekeeper') ||
      (c.displayName.toLowerCase().contains('timekeeper'));

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
}
