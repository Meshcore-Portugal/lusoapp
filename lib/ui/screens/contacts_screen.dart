import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../l10n/l10n.dart';
import '../../protocol/protocol.dart';
import '../../providers/radio_providers.dart';
import '../../transport/transport.dart';
import '../theme.dart';
import '../widgets/path_sheet.dart';
import 'qr_scanner_screen.dart';

/// Best available "last-heard" timestamp for [contact].
/// Prefers [lastModified] (our radio's clock — updated whenever we hear
/// from them) over [lastAdvertTimestamp] (the remote node's own clock —
/// may be wildly wrong on nodes without GPS/NTP sync).
int _bestTs(Contact contact) {
  final lm = contact.lastModified ?? 0;
  return lm > 0 ? lm : contact.lastAdvertTimestamp;
}

/// Contacts list screen with filter tabs.
class ContactsScreen extends ConsumerStatefulWidget {
  const ContactsScreen({super.key});

  @override
  ConsumerState<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends ConsumerState<ContactsScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  bool _multiSelectMode = false;
  final Set<String> _selectedContactKeys = <String>{};

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

  void _toggleSelection(String keyHex) {
    setState(() {
      if (_selectedContactKeys.contains(keyHex)) {
        _selectedContactKeys.remove(keyHex);
        if (_selectedContactKeys.isEmpty) {
          _multiSelectMode = false;
        }
      } else {
        _selectedContactKeys.add(keyHex);
        _multiSelectMode = true;
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedContactKeys.clear();
      _multiSelectMode = false;
    });
  }

  void _enterMultiSelectMode() {
    setState(() {
      _multiSelectMode = true;
      _selectedContactKeys.clear();
    });
  }

  Future<void> _confirmBulkDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(context.l10n.contactsRemoveTitle),
            content: Text(
              'Remover ${_selectedContactKeys.length} contacto(s)?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(context.l10n.commonCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error,
                ),
                child: Text(context.l10n.commonRemove),
              ),
            ],
          ),
    );

    if (confirmed != true) return;

    final service = ref.read(radioServiceProvider);
    if (service == null) return;

    // Find contacts matching the selected keys
    final contacts = ref.read(contactsProvider);
    final contactsToDelete = <Contact>[];
    for (final contact in contacts) {
      final keyHex =
          contact.publicKey
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join();
      if (_selectedContactKeys.contains(keyHex)) {
        contactsToDelete.add(contact);
      }
    }

    if (!context.mounted) return;

    try {
      int deletedCount = 0;
      int errorCount = 0;

      // Remove locally first
      for (final contact in contactsToDelete) {
        ref.read(contactsProvider.notifier).remove(contact.publicKey);
      }

      // Send delete commands to radio
      for (final contact in contactsToDelete) {
        try {
          final respFuture = service.responses
              .firstWhere((r) => r is OkResponse || r is ErrorResponse)
              .timeout(const Duration(seconds: 5));

          await service.removeContact(contact.publicKey);
          final resp = await respFuture;

          if (resp is OkResponse) {
            deletedCount++;
          } else {
            errorCount++;
          }
        } catch (_) {
          errorCount++;
        }
      }

      if (!context.mounted) return;

      // Show results
      final message =
          errorCount > 0
              ? 'Removidos $deletedCount contacto(s), $errorCount erro(s)'
              : 'Removidos $deletedCount contacto(s)';

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));

      // Clear selection and re-sync
      _clearSelection();
      await service.requestContacts();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erro ao remover contactos')),
      );
    }
  }

  static String _hex6(Uint8List key) {
    final n = key.length < 6 ? key.length : 6;
    return key
        .sublist(0, n)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  static String _radioKeyHex(Uint8List key) =>
      key.take(32).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(contactFilterProvider);
    final sort = ref.watch(contactSortProvider);
    final allContacts = ref.watch(contactsProvider);
    final radioKeys = ref.watch(radioContactsSnapshotProvider);
    final transportState = ref.watch(connectionProvider);
    final contactsSynced = ref.watch(contactsSyncedProvider);
    // Watch the stable per-contact last-message timestamp map instead of the
    // full messages list — channel messages no longer cause this screen to
    // rebuild and re-sort (#3 perf fix).
    final lastMsgTs = ref.watch(contactLastMsgTsProvider);
    final autoAddSettings = ref.watch(advertAutoAddProvider);

    // Only show contacts actually stored on the radio. Advert-heard contacts
    // that haven't been saved to the radio appear in the discover screen only.
    // Fall back to the full cache while disconnected or while the initial
    // sync is still in progress (so the list isn't blank during connect).
    final isConnected = transportState == TransportState.connected;
    final contacts =
        (!isConnected || !contactsSynced)
            ? allContacts // Not yet synced — show cached list
            : allContacts
                .where((c) => radioKeys.contains(_radioKeyHex(c.publicKey)))
                .toList();

    final chatContacts = contacts.where((c) => c.isChat).toList();
    final repeaters = contacts.where((c) => c.isRepeater).toList();
    final rooms = contacts.where((c) => c.isRoom).toList();
    final sensors = contacts.where((c) => c.isSensor).toList();
    final favoriteContacts = contacts.where((c) => c.isFavorite).toList();

    List<Contact> filtered;
    switch (filter) {
      case ContactFilter.companheiros:
        filtered = chatContacts;
      case ContactFilter.repetidores:
        filtered = repeaters;
      case ContactFilter.salas:
        filtered = rooms;
      case ContactFilter.sensores:
        filtered = sensors;
      case ContactFilter.favoritos:
        filtered = favoriteContacts;
      case ContactFilter.todos:
        filtered = contacts;
    }

    if (_query.isNotEmpty) {
      filtered = filtered.where((c) => c.searchKey.contains(_query)).toList();
    }

    // lastMsgTs is already computed by contactLastMsgTsProvider — no scan here.

    filtered = [...filtered];
    switch (sort) {
      case ContactSort.nome:
        filtered.sort(
          (a, b) => a.displayName.toLowerCase().compareTo(
            b.displayName.toLowerCase(),
          ),
        );
      case ContactSort.ouvidoRecentemente:
        filtered.sort((a, b) => _bestTs(b).compareTo(_bestTs(a)));
      case ContactSort.ultimaMensagem:
        filtered.sort((a, b) {
          final aMsg = lastMsgTs[_hex6(a.publicKey)] ?? 0;
          final bMsg = lastMsgTs[_hex6(b.publicKey)] ?? 0;
          // Contacts with a known message timestamp sort by message time.
          // Contacts with no messages (aMsg==0) fall back to last-heard time
          // so they sort consistently below the contacts with messages.
          final aTs = aMsg > 0 ? aMsg : _bestTs(a);
          final bTs = bMsg > 0 ? bMsg : _bestTs(b);
          return bTs.compareTo(aTs);
        });
    }

    return Stack(
      children: [
        Column(
          children: [
            // Multi-select toolbar
            if (_multiSelectMode)
              Container(
                color: Theme.of(context).colorScheme.primaryContainer,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${_selectedContactKeys.length} selecionado(s)',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: context.l10n.contactsRemoveSelected,
                          onPressed: () => _confirmBulkDelete(context, ref),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: context.l10n.contactsCancelSelection,
                          onPressed: _clearSelection,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            // Filter chips bar
            ContactFilterBar(
              filter: filter,
              counts: (
                todos: contacts.length,
                favoritos: favoriteContacts.length,
                companheiros: chatContacts.length,
                repetidores: repeaters.length,
                salas: rooms.length,
                sensores: sensors.length,
              ),
              onChanged: (f) => ref.read(contactFilterProvider.notifier).set(f),
            ),

            // Search bar + sort button
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: context.l10n.contactsSearchHint,
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
                  // Advert button — always visible
                  PopupMenuButton<_AdvertType>(
                    icon: const Icon(Icons.broadcast_on_personal),
                    tooltip: context.l10n.contactsSendAdvert,
                    onSelected: (type) {
                      final svc = ref.read(radioServiceProvider);
                      switch (type) {
                        case _AdvertType.zeroHop:
                          svc?.sendAdvert(flood: false);
                        case _AdvertType.flood:
                          svc?.sendAdvert(flood: true);
                      }
                    },
                    itemBuilder:
                        (_) => [
                          PopupMenuItem(
                            value: _AdvertType.zeroHop,
                            child: ListTile(
                              leading: const Icon(Icons.wifi_tethering),
                              title: Text(context.l10n.contactsAdvertZeroHop),
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                            ),
                          ),
                          PopupMenuItem(
                            value: _AdvertType.flood,
                            child: ListTile(
                              leading: const Icon(Icons.broadcast_on_home),
                              title: Text(context.l10n.contactsAdvertFlood),
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                            ),
                          ),
                        ],
                  ),
                  PopupMenuButton<ContactSort>(
                    icon: Icon(
                      Icons.sort,
                      color:
                          sort != ContactSort.ouvidoRecentemente
                              ? Theme.of(context).colorScheme.primary
                              : null,
                    ),
                    tooltip: context.l10n.contactsSort,
                    initialValue: sort,
                    onSelected:
                        (s) => ref.read(contactSortProvider.notifier).set(s),
                    itemBuilder:
                        (_) => [
                          PopupMenuItem(
                            value: ContactSort.nome,
                            child: Text(context.l10n.contactsSortNameAZ),
                          ),
                          PopupMenuItem(
                            value: ContactSort.ouvidoRecentemente,
                            child: Text(context.l10n.contactsSortLastHeard),
                          ),
                          PopupMenuItem(
                            value: ContactSort.ultimaMensagem,
                            child: Text(context.l10n.contactsSortLastMessage),
                          ),
                        ],
                  ),
                  PopupMenuButton<_ContactsToolbarAction>(
                    icon: const Icon(Icons.more_vert),
                    tooltip: context.l10n.contactsMoreOptions,
                    onSelected: (action) {
                      switch (action) {
                        case _ContactsToolbarAction.discover:
                          context.push('/discover');
                        case _ContactsToolbarAction.multiSelect:
                          _enterMultiSelectMode();
                      }
                    },
                    itemBuilder:
                        (_) => [
                          PopupMenuItem(
                            value: _ContactsToolbarAction.discover,
                            child: ListTile(
                              leading: const Icon(Icons.explore),
                              title: Text(context.l10n.contactsDiscover),
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                            ),
                          ),
                          PopupMenuItem(
                            value: _ContactsToolbarAction.multiSelect,
                            enabled: !_multiSelectMode,
                            child: ListTile(
                              leading: const Icon(Icons.checklist),
                              title: Text(context.l10n.contactsMultiSelect),
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                            ),
                          ),
                        ],
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child:
                  filtered.isEmpty
                      ? _EmptyState(filter: filter)
                      : Builder(
                        builder: (context) {
                          final list = ListView.builder(
                            padding: const EdgeInsets.only(bottom: 80),
                            itemCount: filtered.length,
                            itemBuilder: (context, i) {
                              final contact = filtered[i];
                              final keyHex =
                                  contact.publicKey
                                      .map(
                                        (b) =>
                                            b.toRadixString(16).padLeft(2, '0'),
                                      )
                                      .join();
                              final isSelected = _selectedContactKeys.contains(
                                keyHex,
                              );
                              return _ContactTile(
                                contact: contact,
                                isMultiSelectMode: _multiSelectMode,
                                isSelected: isSelected,
                                showPublicKey: autoAddSettings.showPublicKeys,
                                onSelected:
                                    _multiSelectMode
                                        ? () => _toggleSelection(keyHex)
                                        : null,
                                onLongPress: null,
                              );
                            },
                          );
                          if (!autoAddSettings.pullToRefresh) return list;
                          return RefreshIndicator(
                            onRefresh:
                                () async =>
                                    ref
                                        .read(radioServiceProvider)
                                        ?.requestContacts(),
                            child: list,
                          );
                        },
                      ),
            ),
          ],
        ),

        // FAB
        Positioned(
          bottom: 16,
          right: 16,
          child: FloatingActionButton(
            heroTag: 'contacts_fab',
            onPressed: () {
              showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder:
                    (_) => _AddContactSheet(
                      onAdvert: () {
                        ref.read(radioServiceProvider)?.sendAdvert(flood: true);
                      },
                      onAddManual: (contact) async {
                        await ref
                            .read(radioServiceProvider)
                            ?.addUpdateContact(contact);
                        await Future.delayed(const Duration(milliseconds: 300));
                        await ref.read(radioServiceProvider)?.requestContacts();
                      },
                    ),
              );
            },
            tooltip: context.l10n.contactsAddContact,
            child: const Icon(Icons.person_add),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Filter bar
// ---------------------------------------------------------------------------

typedef ContactFilterCounts =
    ({
      int todos,
      int favoritos,
      int companheiros,
      int repetidores,
      int salas,
      int sensores,
    });

class ContactFilterBar extends StatelessWidget {
  const ContactFilterBar({
    super.key,
    required this.filter,
    required this.counts,
    required this.onChanged,
  });

  final ContactFilter filter;
  final ContactFilterCounts counts;
  final ValueChanged<ContactFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        spacing: 8,
        children: [
          _chip(
            ContactFilter.todos,
            context.l10n.contactsAll,
            Icons.people,
            counts.todos,
          ),
          _chip(
            ContactFilter.favoritos,
            context.l10n.contactsFavorites,
            Icons.star,
            counts.favoritos,
          ),
          _chip(
            ContactFilter.companheiros,
            context.l10n.contactsCompanions,
            Icons.person,
            counts.companheiros,
          ),
          _chip(
            ContactFilter.repetidores,
            context.l10n.contactsRepeaters,
            Icons.cell_tower,
            counts.repetidores,
          ),
          _chip(
            ContactFilter.salas,
            context.l10n.contactsTypeRoom,
            Icons.meeting_room,
            counts.salas,
          ),
          _chip(
            ContactFilter.sensores,
            context.l10n.contactsSensors,
            Icons.sensors,
            counts.sensores,
          ),
        ],
      ),
    );
  }

  Widget _chip(ContactFilter f, String label, IconData icon, int count) {
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
  const _EmptyState({required this.filter});
  final ContactFilter filter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, msg) = switch (filter) {
      ContactFilter.companheiros => (
        Icons.person_off,
        context.l10n.contactsEmptyCompanions,
      ),
      ContactFilter.repetidores => (
        Icons.cell_tower,
        context.l10n.contactsEmptyRepeaters,
      ),
      ContactFilter.salas => (
        Icons.meeting_room,
        context.l10n.contactsEmptyRooms,
      ),
      ContactFilter.sensores => (
        Icons.sensors_off,
        context.l10n.contactsEmptySensors,
      ),
      ContactFilter.todos => (
        Icons.contacts_outlined,
        context.l10n.contactsEmpty,
      ),
      ContactFilter.favoritos => (
        Icons.star_border,
        context.l10n.contactsEmptyFavorites,
      ),
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
            context.l10n.contactsEmptyHint,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Advert type enum (used by the toolbar advert popup)
// ---------------------------------------------------------------------------

enum _AdvertType { zeroHop, flood }

enum _ContactsToolbarAction { discover, multiSelect }

// ---------------------------------------------------------------------------
// Contact tile
// ---------------------------------------------------------------------------

class _ContactTile extends ConsumerWidget {
  const _ContactTile({
    required this.contact,
    this.isMultiSelectMode = false,
    this.isSelected = false,
    this.showPublicKey = true,
    this.onSelected,
    this.onLongPress,
  });

  final Contact contact;
  final bool isMultiSelectMode;
  final bool isSelected;
  final bool showPublicKey;
  final VoidCallback? onSelected;
  final VoidCallback? onLongPress;

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
        (contact.isChat || contact.isRoom)
            ? ref.watch(
              unreadCountsProvider.select((u) => u.forContact(prefix6)),
            )
            : 0;

    final isFavorite = contact.isFavorite;

    final ts = _bestTs(contact);
    final lastSeen = ts > 0 ? _formatTimestamp(ts) : 'Nunca';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      color:
          isSelected && isMultiSelectMode
              ? Theme.of(context).colorScheme.primaryContainer
              : null,
      child: ListTile(
        leading:
            isMultiSelectMode
                ? Checkbox(
                  value: isSelected,
                  onChanged: (_) => onSelected?.call(),
                )
                : Badge(
                  isLabelVisible: unreadCount > 0,
                  label: Text(unreadCount > 99 ? '99+' : '$unreadCount'),
                  child: CircleAvatar(
                    backgroundColor: _avatarColor(contact).withAlpha(40),
                    child: Icon(
                      _avatarIcon(contact),
                      color: _avatarColor(contact),
                      size: 20,
                    ),
                  ),
                ),
        title: Text(
          contact.displayName,
          style: TextStyle(
            fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.w600,
          ),
        ),
        subtitle: Text(() {
          final base =
              'Visto: $lastSeen  |  Caminho: ${contactPathLabel(contact.pathLen)}';
          final namePrefix =
              contact.customName != null
                  ? '${contact.name.isNotEmpty ? contact.name : contact.shortId}  •  '
                  : '';
          final keyPart = showPublicKey ? '  •  ${contact.shortId}' : '';
          return '$namePrefix$base$keyPart';
        }(), style: theme.textTheme.bodySmall),
        trailing:
            isFavorite
                ? const Icon(Icons.star, color: Colors.amber, size: 20)
                : null,
        onTap:
            isMultiSelectMode
                ? () => onSelected?.call()
                : (contact.isChat
                    ? () => context.push('/chat/$keyHex')
                    : contact.isRoom
                    ? () => context.push('/room/$keyHex')
                    : null),
        onLongPress:
            isMultiSelectMode
                ? null
                : onLongPress ??
                    (() => _showOptionsSheet(context, ref, isFavorite, keyHex)),
      ),
    );
  }

  Future<void> _showRenameDialog(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController(
      text: contact.customName ?? contact.name,
    );
    final hasCustom = contact.customName != null;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return AlertDialog(
          title: Text(context.l10n.contactsRenameTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Nome anunciado: ${contact.name.isNotEmpty ? contact.name : contact.shortId}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withAlpha(140),
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: context.l10n.contactsCustomName,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(context.l10n.commonCancel),
            ),
            if (hasCustom)
              TextButton(
                onPressed: () {
                  ref
                      .read(contactsProvider.notifier)
                      .setCustomName(contact.publicKey, null);
                  Navigator.pop(ctx);
                },
                child: Text(
                  context.l10n.commonClear,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            FilledButton(
              onPressed: () {
                final trimmed = ctrl.text.trim();
                ref
                    .read(contactsProvider.notifier)
                    .setCustomName(
                      contact.publicKey,
                      trimmed.isEmpty || trimmed == contact.name
                          ? null
                          : trimmed,
                    );
                Navigator.pop(ctx);
              },
              child: Text(context.l10n.commonSave),
            ),
          ],
        );
      },
    );
    // Defer dispose until after the dialog close animation completes.
    // Calling dispose() immediately after showDialog() returns can crash
    // because Flutter may still rebuild the TextField during the close animation.
    WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.dispose());
  }

  void _showAdminSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RepeaterAdminSheet(contact: contact),
    );
  }

  void _showPathSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ContactPathSheet(contact: contact),
    );
  }

  void _showContactQrCode(BuildContext context) {
    final uri = MeshCoreUri.buildContactUri(
      name: contact.name.isNotEmpty ? contact.name : contact.shortId,
      publicKey: contact.publicKey,
      type: contact.type,
    );
    showDialog<void>(
      context: context,
      builder:
          (ctx) => _ContactQrDialog(
            uri: uri,
            displayName: contact.displayName,
            typeLabel: _typeLabel(contact.type),
          ),
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
        return 'Tipo desconhecido';
    }
  }

  /// Flip the favourite bit on [contact] and push the updated flags byte to
  /// the radio. Optimistically updates the local contact list so the UI
  /// reflects the change immediately — the radio's OkResponse is not awaited.
  void _toggleFavorite(WidgetRef ref) {
    final updated = contact.withFavorite(!contact.isFavorite);
    ref
        .read(contactsProvider.notifier)
        .setFavorite(contact.publicKey, updated.isFavorite);
    final service = ref.read(radioServiceProvider);
    if (service == null) return;
    unawaited(service.addUpdateContact(updated).catchError((_) {}));
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

  void _showOptionsSheet(
    BuildContext context,
    WidgetRef ref,
    bool isFavorite,
    String keyHex,
  ) {
    final theme = Theme.of(context);

    // A contact is "on radio" when it appears in the service's confirmed
    // contact list (populated by GET_CONTACTS). Advert-only contacts
    // (heard via pushNewAdvert) are cached locally but not on the radio.
    final service = ref.read(radioServiceProvider);
    final isOnRadio =
        service == null ||
        service.contacts.any(
          (c) =>
              c.publicKey
                  .map((b) => b.toRadixString(16).padLeft(2, '0'))
                  .join() ==
              keyHex,
        );

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: _avatarColor(contact).withAlpha(40),
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
                                color: theme.colorScheme.onSurface.withAlpha(
                                  130,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                // Save to radio — only shown for locally-cached (advert-only) contacts
                if (!isOnRadio)
                  ListTile(
                    leading: const Icon(Icons.save_outlined),
                    title: Text(context.l10n.contactsSaveToRadioTitle),
                    subtitle: Text(context.l10n.contactsNotSavedHint),
                    onTap: () {
                      Navigator.pop(ctx);
                      _saveToRadio(context, ref);
                    },
                  ),
                // Favourite
                ListTile(
                  leading: Icon(
                    isFavorite ? Icons.star : Icons.star_border,
                    color: isFavorite ? Colors.amber : null,
                  ),
                  title: Text(
                    isFavorite
                        ? context.l10n.contactsRemoveFavorites
                        : context.l10n.contactsAddFavorites,
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _toggleFavorite(ref);
                  },
                ),
                // QR
                ListTile(
                  leading: const Icon(Icons.qr_code),
                  title: Text(context.l10n.contactsShareQR),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showContactQrCode(context);
                  },
                ),
                // Rename
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: Text(context.l10n.commonRename),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showRenameDialog(context, ref);
                  },
                ),
                // Type-specific action
                if (contact.isChat)
                  ListTile(
                    leading: const Icon(Icons.chat),
                    title: Text(context.l10n.contactsPrivateMessage),
                    onTap: () {
                      Navigator.pop(ctx);
                      context.push('/chat/$keyHex');
                    },
                  ),
                if (contact.isRoom)
                  ListTile(
                    leading: const Icon(Icons.meeting_room),
                    title: Text(context.l10n.contactsJoinRoom),
                    onTap: () {
                      Navigator.pop(ctx);
                      context.push('/room/$keyHex');
                    },
                  ),
                if (contact.isRepeater)
                  ListTile(
                    leading: const Icon(Icons.admin_panel_settings),
                    title: Text(context.l10n.contactsRemoteAdmin),
                    onTap: () {
                      Navigator.pop(ctx);
                      _showAdminSheet(context, ref);
                    },
                  ),
                // Path management — available for all node types
                ListTile(
                  leading: const Icon(Icons.route),
                  title: Text(context.l10n.contactsManagePath),
                  subtitle: Text(
                    '${context.l10n.contactsCurrentPath} ${contactPathLabel(contact.pathLen)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withAlpha(130),
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showPathSheet(context);
                  },
                ),
                const Divider(),
                // Delete
                ListTile(
                  leading: Icon(
                    Icons.delete_outline,
                    color: theme.colorScheme.error,
                  ),
                  title: Text(
                    context.l10n.contactsRemoveContact,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _confirmDelete(context, ref);
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(context.l10n.contactsRemoveContact),
            content: Text(
              'Remover "${contact.displayName}" ${context.l10n.contactsRemoveFromListSuffix}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(context.l10n.commonCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error,
                ),
                child: Text(context.l10n.commonRemove),
              ),
            ],
          ),
    );
    if (confirmed == true) {
      final service = ref.read(radioServiceProvider);
      // Remove locally first so advert-cached contacts disappear immediately.
      ref.read(contactsProvider.notifier).remove(contact.publicKey);

      if (service == null) return;

      try {
        final respFuture = service.responses
            .firstWhere((r) => r is OkResponse || r is ErrorResponse)
            .timeout(const Duration(seconds: 5));

        await service.removeContact(contact.publicKey);
        final resp = await respFuture;

        if (!context.mounted) return;
        if (resp is ErrorResponse) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Erro ao remover no rádio (código ${resp.errorCode})',
              ),
            ),
          );
        }
      } catch (_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.contactsRemoveTimeout)),
        );
      } finally {
        // Always re-sync from the radio so local and radio tables converge.
        await service.requestContacts();
      }
    }
  }

  bool _isTimekeeper(Contact c) =>
      c.name.toLowerCase().contains('timekeeper') ||
      (c.customName?.toLowerCase().contains('timekeeper') ?? false);

  IconData _avatarIcon(Contact c) =>
      _isTimekeeper(c) ? Icons.access_time_rounded : _typeIcon(c.type);

  Color _avatarColor(Contact c) =>
      _isTimekeeper(c) ? Colors.teal : _typeColor(c.type);

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
    if (diff.inMinutes < 60) return '${diff.inMinutes}m atrás';
    if (diff.inHours < 24) return '${diff.inHours}h atrás';
    return '${diff.inDays}d atrás';
  }
}

// ---------------------------------------------------------------------------
// Add / Discover contact bottom sheet
// ---------------------------------------------------------------------------

class _AddContactSheet extends StatefulWidget {
  const _AddContactSheet({required this.onAdvert, required this.onAddManual});

  final VoidCallback onAdvert;
  final Future<void> Function(Contact contact) onAddManual;

  @override
  State<_AddContactSheet> createState() => _AddContactSheetState();
}

class _AddContactSheetState extends State<_AddContactSheet> {
  final _pubKeyCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  String? _pubKeyError;
  String? _nameError;
  bool _saving = false;
  int _contactType = 0x01; // 0x01=chat, 0x02=repeater, 0x03=room

  @override
  void dispose() {
    _pubKeyCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Uint8List? _parsePublicKey(String hex) {
    final clean = hex.replaceAll(RegExp(r'\s+'), '');
    if (clean.length != 64) return null;
    try {
      return Uint8List.fromList(
        List.generate(
          32,
          (i) => int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _scanQr() async {
    final raw = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const QrScannerScreen(title: 'Ler QR de Contacto'),
      ),
    );
    if (raw == null || !mounted) return;

    final result = MeshCoreUri.parse(raw);
    if (result is MeshCoreContactUri) {
      _nameCtrl.text = result.name;
      _pubKeyCtrl.text =
          result.publicKey
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join();
      setState(() {
        _nameError = null;
        _pubKeyError = null;
      });
    } else if (result is MeshCoreChannelUri) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'QR de canal detectado. Use o ecrã de Canais para o adicionar.',
            ),
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('QR Code MeshCore inválido ou não reconhecido.'),
          ),
        );
      }
    }
  }

  Future<void> _addManual() async {
    setState(() {
      final pubKey = _parsePublicKey(_pubKeyCtrl.text.trim());
      _pubKeyError =
          pubKey == null
              ? 'Introduza 64 caracteres hexadecimais (32 bytes)'
              : null;
      _nameError =
          _nameCtrl.text.trim().isEmpty ? 'O nome é obrigatório' : null;
    });
    if (_pubKeyError != null || _nameError != null) return;

    final pubKey = _parsePublicKey(_pubKeyCtrl.text.trim())!;
    final contact = Contact(
      publicKey: pubKey,
      type: _contactType,
      flags: 0,
      pathLen: 0,
      name: _nameCtrl.text.trim(),
      lastAdvertTimestamp: 0,
    );

    setState(() => _saving = true);
    try {
      await widget.onAddManual(contact);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withAlpha(40),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            context.l10n.contactsAddContact,
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            'Envie um anúncio para que outros nós o descubram automaticamente, ou adicione manualmente através da chave pública.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withAlpha(160),
            ),
          ),
          const SizedBox(height: 16),

          // Discover via advert
          OutlinedButton.icon(
            onPressed: () {
              widget.onAdvert();
              Navigator.of(context).pop();
            },
            icon: const Icon(Icons.broadcast_on_home),
            label: Text(context.l10n.contactsSendAdvertAuto),
          ),
          const SizedBox(height: 8),

          // Scan QR code
          OutlinedButton.icon(
            onPressed: _scanQr,
            icon: const Icon(Icons.qr_code_scanner),
            label: Text(context.l10n.contactsReadQR),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(context.l10n.contactsOrManual),
                ),
                const Expanded(child: Divider()),
              ],
            ),
          ),

          // Manual public key entry
          TextField(
            controller: _pubKeyCtrl,
            decoration: InputDecoration(
              labelText: context.l10n.contactsPublicKeyLabel,
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.vpn_key_outlined),
              errorText: _pubKeyError,
            ),
            maxLength: 64,
            keyboardType: TextInputType.text,
          ),
          const SizedBox(height: 8),

          TextField(
            controller: _nameCtrl,
            decoration: InputDecoration(
              labelText: context.l10n.contactsDisplayName,
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.badge_outlined),
              errorText: _nameError,
            ),
            maxLength: 31,
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 12),

          // Type selector
          Row(
            children: [
              for (final entry in const [
                (0x01, 'Chat', Icons.chat_bubble_outline),
                (0x02, 'Repetidor', Icons.router_outlined),
                (0x03, 'Sala', Icons.meeting_room_outlined),
              ])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _TypeChip(
                      label: entry.$2,
                      icon: entry.$3,
                      selected: _contactType == entry.$1,
                      onTap: () => setState(() => _contactType = entry.$1),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          FilledButton.icon(
            onPressed: _saving ? null : _addManual,
            icon:
                _saving
                    ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Icon(Icons.person_add),
            label: Text(_saving ? 'A adicionar...' : 'Adicionar contacto'),
          ),
        ],
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color =
        selected
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurface.withAlpha(80);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color:
              selected
                  ? theme.colorScheme.primary.withAlpha(30)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color:
                selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 4),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Path management sheet → lives in lib/ui/widgets/path_sheet.dart
// Repeater remote-admin bottom sheet
// ---------------------------------------------------------------------------

class _RepeaterAdminSheet extends ConsumerStatefulWidget {
  const _RepeaterAdminSheet({required this.contact});
  final Contact contact;

  @override
  ConsumerState<_RepeaterAdminSheet> createState() =>
      _RepeaterAdminSheetState();
}

class _RepeaterAdminSheetState extends ConsumerState<_RepeaterAdminSheet> {
  final _passCtrl = TextEditingController();
  bool _obscure = true;
  bool _waiting = false;
  String? _loginError;
  String? _lastResponse;
  bool _pendingCommand = false;
  String? _pendingLabel;

  String get _prefixHex =>
      widget.contact.publicKey
          .take(6)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();

  @override
  void initState() {
    super.initState();
    // Reset any stale login result so the listener starts clean.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(loginResultProvider.notifier).state = null;
    });
  }

  @override
  void dispose() {
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final password = _passCtrl.text;
    final service = ref.read(radioServiceProvider);
    if (service == null) return;

    ref.read(loginResultProvider.notifier).state = null;
    setState(() {
      _waiting = true;
      _loginError = null;
    });

    // Listen for the radio response directly so we can catch ErrorResponse
    // (e.g. ERR_NOT_FOUND when the contact isn't in the radio's table) and
    // show a useful message instead of spinning forever.
    final completer = Completer<String?>(); // null = success, non-null = error
    late StreamSubscription<CompanionResponse> sub;
    sub = service.responses.listen((r) {
      if (completer.isCompleted) return;
      if (r is LoginSuccessPush) {
        completer.complete(null);
      } else if (r is LoginFailPush) {
        completer.complete('Falhou — verifique a palavra-passe');
      } else if (r is ErrorResponse) {
        final msg =
            r.errorCode == 2
                ? 'Contacto não encontrado no rádio — force um advert deste nó'
                : 'Erro do rádio (código ${r.errorCode})';
        completer.complete(msg);
      }
    });

    await service.login(widget.contact.publicKey, password);

    // Timeout after 10 s if radio never replies.
    final error = await completer.future
        .timeout(
          const Duration(seconds: 10),
          onTimeout: () => 'Sem resposta do rádio (timeout)',
        )
        .whenComplete(sub.cancel);

    if (!mounted) return;
    if (error == null) {
      // Success — loginResultProvider listener handles the UI transition.
      ref.read(loginResultProvider.notifier).state = true;
    } else {
      setState(() {
        _waiting = false;
        _loginError = error;
      });
    }
  }

  Future<void> _requestStatus() async {
    final service = ref.read(radioServiceProvider);
    await service?.sendStatusRequest(widget.contact.publicKey);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pedido de estado enviado...')),
      );
    }
  }

  Future<void> _sendAdminCommand(String command, String label) async {
    final service = ref.read(radioServiceProvider);
    if (service == null) return;

    setState(() {
      _pendingCommand = true;
      _pendingLabel = label;
      _lastResponse = null;
    });

    final prefix = Uint8List.fromList(
      widget.contact.publicKey.take(6).toList(),
    );

    final completer = Completer<String>();
    late StreamSubscription<CompanionResponse> sub;
    sub = service.responses.listen((r) {
      if (completer.isCompleted) return;
      if (r is PrivateMessageResponse && r.message.senderKey != null) {
        final key = r.message.senderKey!;
        if (key.length >= 6 &&
            key[0] == prefix[0] &&
            key[1] == prefix[1] &&
            key[2] == prefix[2] &&
            key[3] == prefix[3] &&
            key[4] == prefix[4] &&
            key[5] == prefix[5]) {
          completer.complete(r.message.text.trim());
        }
      }
    });

    await service.sendAdminCommand(widget.contact.publicKey, command);

    final response = await completer.future
        .timeout(
          const Duration(seconds: 15),
          onTimeout: () => '(sem resposta do nó)',
        )
        .whenComplete(sub.cancel);

    if (!mounted) return;
    setState(() {
      _pendingCommand = false;
      _pendingLabel = null;
      _lastResponse = response;
    });

    if (command == 'start ota' &&
        response.toLowerCase().startsWith('ok - mac:')) {
      _showOtaDialog(response);
    }
  }

  void _showOtaDialog(String response) {
    showDialog<void>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('OTA Iniciado'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.system_update_alt,
                  size: 48,
                  color: Colors.blue,
                ),
                const SizedBox(height: 12),
                Text(
                  response,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Ligue-se ao nó via BLE DFU (ex: nRF Connect) para actualizar o firmware.',
                  style: TextStyle(fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    // Listen for login success from loginResultProvider (set by _login() on success).
    ref.listen<bool?>(loginResultProvider, (_, result) {
      if (result == true && mounted) {
        setState(() {
          _waiting = false;
          _loginError = null;
        });
      }
    });

    final loginResult = ref.watch(loginResultProvider);
    final loggedIn = loginResult == true;

    final stats = ref.watch(
      repeaterStatusProvider.select((m) => m[_prefixHex]),
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withAlpha(40),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.cell_tower, color: AppTheme.primary, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Admin: ${widget.contact.name.isNotEmpty ? widget.contact.name : widget.contact.shortId}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'ID: ${widget.contact.shortId}  |  Saltos: ${widget.contact.pathLen}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const Divider(height: 20),

            if (!loggedIn) ...[
              Text(
                'Autenticação',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _passCtrl,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: 'Palavra-passe (opcional)',
                  hintText: 'Deixar em branco se sem palavra-passe',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock_outline),
                  errorText: _loginError,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _waiting ? null : _login,
                icon:
                    _waiting
                        ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Icon(Icons.login),
                label: Text(_waiting ? 'A ligar...' : 'Entrar'),
              ),
            ] else ...[
              // ── Auth status row ──────────────────────────────────────
              Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    'Autenticado',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: _pendingCommand ? null : _requestStatus,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Estado'),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // ── Pending indicator ─────────────────────────────────────
              if (_pendingCommand) ...[
                Row(
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'A enviar: $_pendingLabel...',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],

              // ── Last CLI response ─────────────────────────────────────
              if (_lastResponse != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.terminal,
                        size: 14,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _lastResponse!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],

              // ── Remote actions ────────────────────────────────────────
              const Divider(height: 20),
              Text(
                'Acções Remotas',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              _AdminTile(
                icon: Icons.broadcast_on_home,
                title: 'Anúncio Flood',
                subtitle: 'Força o nó a enviar um anúncio flood',
                enabled: !_pendingCommand,
                onTap: () => _sendAdminCommand('advert', 'Anúncio Flood'),
              ),
              _AdminTile(
                icon: Icons.wifi_tethering,
                title: 'Anúncio Zero-Hop',
                subtitle: 'Anúncio só para vizinhos directos',
                enabled: !_pendingCommand,
                onTap:
                    () =>
                        _sendAdminCommand('advert.zerohop', 'Anúncio Zero-Hop'),
              ),
              _AdminTile(
                icon: Icons.schedule,
                title: 'Sincronizar Relógio',
                subtitle: 'Envia o timestamp actual para o nó',
                enabled: !_pendingCommand,
                onTap: () => _sendAdminCommand('clock sync', 'Sync Clock'),
              ),
              _AdminTile(
                icon: Icons.system_update_alt,
                title: 'Iniciar OTA',
                subtitle: 'Inicia actualização OTA — NRF DFU / ESP32',
                enabled: !_pendingCommand,
                onTap: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder:
                        (ctx) => AlertDialog(
                          title: Text(context.l10n.contactsConfirmOTATitle),
                          content: const Text(
                            'O rádio vai entrar em modo de actualização OTA e ficará '
                            'temporariamente inacessível.\n\n'
                            'Tens a certeza?',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Cancelar'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.orange,
                              ),
                              child: const Text('Iniciar OTA'),
                            ),
                          ],
                        ),
                  );
                  if (ok == true) await _sendAdminCommand('start ota', 'OTA');
                },
              ),

              // ── Stats ─────────────────────────────────────────────────
              if (stats != null) ...[
                const Divider(height: 20),
                _StatsCard(stats: stats, theme: theme),
              ] else ...[
                const SizedBox(height: 4),
                Text(
                  'Prima "Estado" para obter as estatísticas do repetidor.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Admin action tile
// ---------------------------------------------------------------------------

class _AdminTile extends StatelessWidget {
  const _AdminTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        icon,
        size: 22,
        color:
            enabled
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurface.withAlpha(60),
      ),
      title: Text(
        title,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w500,
          color: enabled ? null : theme.colorScheme.onSurface.withAlpha(80),
        ),
      ),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      onTap: enabled ? onTap : null,
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.stats, required this.theme});
  final RepeaterStats stats;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final ts =
        '${stats.receivedAt.hour.toString().padLeft(2, '0')}:'
        '${stats.receivedAt.minute.toString().padLeft(2, '0')}:'
        '${stats.receivedAt.second.toString().padLeft(2, '0')}';

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Estatísticas',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  'Actualizado: $ts',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const Divider(height: 12),
            _row(
              'Bateria',
              '${stats.batteryVolts.toStringAsFixed(2)} V',
              theme,
            ),
            _row('Uptime', stats.uptimeFormatted, theme),
            _row(
              'SNR (último)',
              '${stats.lastSnrDb.toStringAsFixed(1)} dB',
              theme,
            ),
            _row('RSSI (último)', '${stats.lastRssi} dBm', theme),
            _row('Ruído', '${stats.noiseFloor} dBm', theme),
            const Divider(height: 12),
            _row(
              'RX / TX',
              '${stats.packetsRecv} / ${stats.packetsSent}',
              theme,
            ),
            _row(
              'Flood RX/TX',
              '${stats.recvFlood} / ${stats.sentFlood}',
              theme,
            ),
            _row(
              'Directo RX/TX',
              '${stats.recvDirect} / ${stats.sentDirect}',
              theme,
            ),
            _row('Tempo no ar (TX)', '${stats.airTimeSecs}s', theme),
            if (stats.rxAirTimeSecs != null)
              _row('Tempo no ar (RX)', '${stats.rxAirTimeSecs}s', theme),
            _row('Duplicados', '${stats.directDups + stats.floodDups}', theme),
            if (stats.errEvents > 0)
              _row(
                'Erros',
                '${stats.errEvents}',
                theme,
                valueColor: theme.colorScheme.error,
              ),
          ],
        ),
      ),
    );
  }

  Widget _row(
    String label,
    String value,
    ThemeData theme, {
    Color? valueColor,
  }) {
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

// ---------------------------------------------------------------------------
// QR code dialog with system share
// ---------------------------------------------------------------------------

class _ContactQrDialog extends StatefulWidget {
  const _ContactQrDialog({
    required this.uri,
    required this.displayName,
    required this.typeLabel,
  });

  final String uri;
  final String displayName;
  final String typeLabel;

  @override
  State<_ContactQrDialog> createState() => _ContactQrDialogState();
}

class _ContactQrDialogState extends State<_ContactQrDialog> {
  final _qrKey = GlobalKey();
  bool _sharing = false;
  bool _sharingText = false;

  Future<void> _shareQr() async {
    setState(() => _sharing = true);
    try {
      final boundary =
          _qrKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final pngBytes = byteData.buffer.asUint8List();

      final xFile = XFile.fromData(
        pngBytes,
        name: '${widget.displayName}.png',
        mimeType: 'image/png',
      );
      await SharePlus.instance.share(
        ShareParams(
          files: [xFile],
          text: widget.uri,
          subject: 'Contacto MeshCore: ${widget.displayName}',
        ),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _shareText() async {
    setState(() => _sharingText = true);
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: widget.uri,
          subject: 'Contacto MeshCore: ${widget.displayName}',
        ),
      );
    } finally {
      if (mounted) setState(() => _sharingText = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('QR Code do contacto'),
      content: SizedBox(
        width: 260,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RepaintBoundary(
              key: _qrKey,
              child: QrImageView(
                data: widget.uri,
                size: 240,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              widget.displayName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(widget.typeLabel, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.commonClose),
        ),
        TextButton.icon(
          onPressed: _sharingText ? null : _shareText,
          icon:
              _sharingText
                  ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : const Icon(Icons.text_fields),
          label: Text(context.l10n.channelsShareText),
        ),
        FilledButton.icon(
          onPressed: _sharing ? null : _shareQr,
          icon:
              _sharing
                  ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : const Icon(Icons.share),
          label: Text(context.l10n.channelsShareQR),
        ),
      ],
    );
  }
}
