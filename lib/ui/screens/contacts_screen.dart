import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../protocol/protocol.dart';
import '../../providers/radio_providers.dart';
import 'qr_scanner_screen.dart';

// Filter tabs
enum _Filter { todos, favoritos, companheiros, repetidores, salas, sensores }

/// Contacts list screen with filter tabs.
class ContactsScreen extends ConsumerStatefulWidget {
  const ContactsScreen({super.key});

  @override
  ConsumerState<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends ConsumerState<ContactsScreen> {
  _Filter _filter = _Filter.todos;
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
    final contacts = ref.watch(contactsProvider);
    final favorites = ref.watch(favoritesProvider);

    final chatContacts = contacts.where((c) => c.isChat).toList();
    final repeaters = contacts.where((c) => c.isRepeater).toList();
    final rooms = contacts.where((c) => c.isRoom).toList();
    final sensors = contacts.where((c) => c.isSensor).toList();
    final favoriteContacts =
        contacts
            .where(
              (c) => favorites.contains(
                c.publicKey
                    .map((b) => b.toRadixString(16).padLeft(2, '0'))
                    .join(),
              ),
            )
            .toList();

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
      case _Filter.favoritos:
        filtered = favoriteContacts;
      case _Filter.todos:
        filtered = contacts;
    }

    if (_query.isNotEmpty) {
      filtered =
          filtered
              .where(
                (c) =>
                    c.name.toLowerCase().contains(_query) ||
                    c.shortId.toLowerCase().contains(_query),
              )
              .toList();
    }

    return Stack(
      children: [
        Column(
          children: [
            // Filter chips bar
            _FilterBar(
              filter: _filter,
              counts: (
                todos: contacts.length,
                favoritos: favoriteContacts.length,
                companheiros: chatContacts.length,
                repetidores: repeaters.length,
                salas: rooms.length,
                sensores: sensors.length,
              ),
              onChanged: (f) => setState(() => _filter = f),
            ),

            // Search bar
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: TextField(
                controller: _searchCtrl,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Pesquisar contactos...',
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
                                ref
                                    .read(radioServiceProvider)
                                    ?.requestContacts(),
                        child: ListView.builder(
                          padding: const EdgeInsets.only(bottom: 80),
                          itemCount: filtered.length,
                          itemBuilder:
                              (context, i) =>
                                  _ContactTile(contact: filtered[i]),
                        ),
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
            tooltip: 'Adicionar contacto',
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

typedef _Counts =
    ({
      int todos,
      int favoritos,
      int companheiros,
      int repetidores,
      int salas,
      int sensores,
    });

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
          _chip(_Filter.favoritos, 'Favoritos', Icons.star, counts.favoritos),
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
      _Filter.favoritos => (Icons.star_border, 'Sem favoritos'),
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

    final isFavorite = ref.watch(
      favoritesProvider.select((s) => s.contains(keyHex)),
    );

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
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                isFavorite ? Icons.star : Icons.star_border,
                color: isFavorite ? Colors.amber : null,
              ),
              tooltip:
                  isFavorite
                      ? 'Remover dos favoritos'
                      : 'Adicionar aos favoritos',
              onPressed:
                  () => ref.read(favoritesProvider.notifier).toggle(keyHex),
            ),
            IconButton(
              icon: const Icon(Icons.qr_code),
              tooltip: 'Partilhar via QR',
              onPressed: () => _showContactQrCode(context),
            ),
            if (contact.isChat)
              IconButton(
                icon: const Icon(Icons.chat),
                tooltip: 'Mensagem privada',
                onPressed: () => context.push('/chat/$keyHex'),
              ),
            if (contact.isRepeater)
              IconButton(
                icon: const Icon(Icons.admin_panel_settings),
                tooltip: 'Admin remoto',
                onPressed: () => _showAdminSheet(context, ref),
              ),
          ],
        ),
        onTap: contact.isChat ? () => context.push('/chat/$keyHex') : null,
        onLongPress: () => _confirmDelete(context, ref),
      ),
    );
  }

  void _showAdminSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RepeaterAdminSheet(contact: contact),
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
          (ctx) => AlertDialog(
            title: const Text('QR Code do contacto'),
            content: SizedBox(
              width: 260,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  QrImageView(
                    data: uri,
                    size: 240,
                    backgroundColor: Colors.white,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    contact.name.isNotEmpty ? contact.name : contact.shortId,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _typeLabel(contact.type),
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Fechar'),
              ),
            ],
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

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Remover contacto'),
            content: Text(
              'Remover "${contact.name.isNotEmpty ? contact.name : contact.shortId}" da lista de contactos?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error,
                ),
                child: const Text('Remover'),
              ),
            ],
          ),
    );
    if (confirmed == true) {
      final service = ref.read(radioServiceProvider);
      if (service == null) return;
      await service.removeContact(contact.publicKey);
      await Future.delayed(const Duration(milliseconds: 300));
      await service.requestContacts();
    }
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
      type: 1, // chat
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
          Text('Adicionar contacto', style: theme.textTheme.titleLarge),
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
            label: const Text('Enviar Anúncio (descoberta automática)'),
          ),
          const SizedBox(height: 8),

          // Scan QR code
          OutlinedButton.icon(
            onPressed: _scanQr,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Ler QR Code'),
          ),

          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Expanded(child: Divider()),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('ou adicionar manualmente'),
                ),
                Expanded(child: Divider()),
              ],
            ),
          ),

          // Manual public key entry
          TextField(
            controller: _pubKeyCtrl,
            decoration: InputDecoration(
              labelText: 'Chave pública (hex, 64 chars)',
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
              labelText: 'Nome de exibição',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.badge_outlined),
              errorText: _nameError,
            ),
            maxLength: 31,
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 8),

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

// ---------------------------------------------------------------------------
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
    final password = _passCtrl.text; // empty string = no-password repeater
    ref.read(loginResultProvider.notifier).state = null;
    setState(() {
      _waiting = true;
      _loginError = null;
    });
    final service = ref.read(radioServiceProvider);
    await service?.login(widget.contact.publicKey, password);
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    // Listen for login result push.
    ref.listen<bool?>(loginResultProvider, (_, result) {
      if (result == null || !mounted) return;
      setState(() {
        _waiting = false;
        if (result) {
          _loginError = null;
        } else {
          _loginError = 'Falhou — verifique a palavra-passe';
        }
      });
    });

    final loginResult = ref.watch(loginResultProvider);
    final loggedIn = loginResult == true;

    final stats = ref.watch(
      repeaterStatusProvider.select((m) => m[_prefixHex]),
    );

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
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.cell_tower, color: Colors.orange, size: 22),
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
                  onPressed: _requestStatus,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Pedir estado'),
                ),
              ],
            ),
            if (stats != null) ...[
              const SizedBox(height: 12),
              _StatsCard(stats: stats, theme: theme),
            ] else ...[
              const SizedBox(height: 8),
              Text(
                'Prima "Pedir estado" para obter as estatísticas do repetidor.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ],
      ),
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
