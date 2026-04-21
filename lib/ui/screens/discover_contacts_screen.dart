import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/l10n.dart';
import '../../protocol/protocol.dart';
import '../../providers/radio_providers.dart';

/// Contacts heard via mesh adverts (whether or not stored on the radio).
/// The contacts screen shows only radio-stored contacts; this screen shows
/// everything heard on the mesh so the user can decide what to save.
final discoveredContactsProvider = Provider<List<Contact>>((ref) {
  final allContacts = ref.watch(contactsProvider);

  // Show every contact heard via an advert this session (lastAdvertTimestamp > 0).
  final discovered =
      allContacts.where((c) => c.lastAdvertTimestamp > 0).toList();

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
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.l10n.discoverTitle),
            Text(
              context.l10n.discoverSubtitle,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
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
                hintText: context.l10n.discoverSearchHint,
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
                ? context.l10n.discoverEmpty
                : context.l10n.discoverNone,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface.withAlpha(120),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hasAny && query.isNotEmpty
                ? context.l10n.discoverEmptyHint
                : context.l10n.discoverNoneHint,
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
    final lastSeen =
        ts > 0 ? _formatTimestamp(context, ts) : context.l10n.discoverNever;

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
          '${context.l10n.discoverHeard}: $lastSeen  |  ${context.l10n.commonPath}: ${_pathLabel(context, contact.pathLen)}  |  ${context.l10n.commonHops}: ${contact.pathLen}',
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
                                  '${_typeLabel(context, contact.type)}  •  ${contact.shortId}',
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
                        context.l10n.discoverAnnouncedName,
                        contact.name.isNotEmpty
                            ? contact.name
                            : context.l10n.discoverNoName,
                        theme,
                      ),
                      const SizedBox(height: 8),
                      _infoRow(
                        context.l10n.commonType,
                        _typeLabel(context, contact.type),
                        theme,
                      ),
                      const SizedBox(height: 8),
                      _infoRow(
                        context.l10n.discoverHeard,
                        _formatTimestamp(
                          context,
                          contact.lastModified ?? contact.lastAdvertTimestamp,
                        ),
                        theme,
                      ),
                      const SizedBox(height: 8),
                      _infoRow(
                        context.l10n.commonPath,
                        '${contact.pathLen} ${contact.pathLen == 1 ? context.l10n.commonSingularHop : context.l10n.commonPluralHops}',
                        theme,
                      ),
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
                        label: Text(context.l10n.discoverSaveToRadio),
                      ),
                      const SizedBox(height: 8),
                      if (contact.type == 0x01)
                        FilledButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            context.push('/chat/${_hex32(contact.publicKey)}');
                          },
                          icon: const Icon(Icons.chat),
                          label: Text(context.l10n.discoverSendMessage),
                        ),
                      if (contact.type == 0x03)
                        FilledButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            context.push('/room/${_hex32(contact.publicKey)}');
                          },
                          icon: const Icon(Icons.meeting_room),
                          label: Text(context.l10n.discoverJoinRoom),
                        ),
                      if (contact.type != 0x01 && contact.type != 0x03)
                        FilledButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _saveToRadio(context, ref);
                          },
                          icon: const Icon(Icons.person_add),
                          label: Text(context.l10n.discoverAddAndSave),
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
          SnackBar(
            content: Text(
              context.l10n.contactsSavedToRadio(contact.displayName),
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.contactsSaveToRadioError)),
        );
      }
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.contactsSaveTimeout)));
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

  String _typeLabel(BuildContext context, int type) {
    switch (type) {
      case 1:
        return context.l10n.discoverTypeCompanion;
      case 2:
        return context.l10n.commonRepeater;
      case 3:
        return context.l10n.commonRoom;
      case 4:
        return context.l10n.commonSensor;
      default:
        return context.l10n.discoverTypeUnknown;
    }
  }

  String _pathLabel(BuildContext context, int pathLen) {
    if (pathLen == 0) return context.l10n.commonDirect;
    if (pathLen == 1) return context.l10n.discoverPathNear;
    return '$pathLen ${context.l10n.commonPluralHops}';
  }

  String _formatTimestamp(BuildContext context, int ts) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return context.l10n.discoverJustNow;
    if (diff.inMinutes < 60) {
      return context.l10n.discoverMinutesAgo(diff.inMinutes);
    }
    if (diff.inHours < 24) return context.l10n.discoverHoursAgo(diff.inHours);
    return context.l10n.discoverDaysAgo(diff.inDays);
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
