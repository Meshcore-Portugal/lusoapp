import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../protocol/protocol.dart';
import '../../providers/radio_providers.dart';
import 'qr_scanner_screen.dart';

// Filter options
enum _Filter { todos, naoLidos }

/// Channels list screen with filter chips and last-message preview.
class ChannelsListScreen extends ConsumerStatefulWidget {
  const ChannelsListScreen({super.key});

  @override
  ConsumerState<ChannelsListScreen> createState() => _ChannelsListScreenState();
}

class _ChannelsListScreenState extends ConsumerState<ChannelsListScreen> {
  _Filter _filter = _Filter.todos;

  @override
  Widget build(BuildContext context) {
    final channels = ref.watch(channelsProvider);
    final unread = ref.watch(unreadCountsProvider);

    // Only show slots that have a name configured.
    final configured = channels.where((c) => c.name.isNotEmpty).toList();

    // Count channels with unread messages.
    final unreadChannelCount =
        configured.where((c) => unread.forChannel(c.index) > 0).length;

    // Apply filter.
    final filtered =
        _filter == _Filter.naoLidos
            ? configured.where((c) => unread.forChannel(c.index) > 0).toList()
            : List<ChannelInfo>.from(configured);

    // Sort: unread-first, then by index.
    filtered.sort((a, b) {
      final ua = unread.forChannel(a.index);
      final ub = unread.forChannel(b.index);
      if (ua != ub) return ub.compareTo(ua);
      return a.index.compareTo(b.index);
    });

    final maxChannels = ref.watch(deviceInfoProvider)?.maxChannels ?? 8;
    final usedIndices = configured.map((c) => c.index).toSet();

    void openAddSheet({ChannelInfo? existing}) {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder:
            (_) => _AddEditChannelSheet(
              existing: existing,
              maxChannels: maxChannels,
              usedIndices: usedIndices,
              onSave: (index, name, secret) async {
                final service = ref.read(radioServiceProvider);
                if (service == null) return;
                await service.setChannel(index, name, secret);
                await Future.delayed(const Duration(milliseconds: 200));
                await service.requestChannel(index);
              },
            ),
      );
    }

    return Stack(
      children: [
        Column(
          children: [
            // Filter chips bar
            _FilterBar(
              filter: _filter,
              totalCount: configured.length,
              unreadCount: unreadChannelCount,
              onChanged: (f) => setState(() => _filter = f),
            ),

            // Content
            Expanded(
              child:
                  configured.isEmpty
                      ? _EmptyState(
                        onRefresh: () {
                          final service = ref.read(radioServiceProvider);
                          if (service == null) return;
                          for (var i = 0; i < maxChannels; i++) {
                            service.requestChannel(i);
                          }
                        },
                      )
                      : filtered.isEmpty
                      ? _NoUnreadState(
                        onClearFilter:
                            () => setState(() => _filter = _Filter.todos),
                      )
                      : RefreshIndicator(
                        onRefresh: () async {
                          final service = ref.read(radioServiceProvider);
                          if (service == null) return;
                          for (var i = 0; i < maxChannels; i++) {
                            await service.requestChannel(i);
                            await Future.delayed(
                              const Duration(milliseconds: 100),
                            );
                          }
                        },
                        child: ListView.builder(
                          padding: const EdgeInsets.only(top: 4, bottom: 80),
                          itemCount: filtered.length,
                          itemBuilder:
                              (context, index) => _ChannelTile(
                                channel: filtered[index],
                                onEdit:
                                    () =>
                                        openAddSheet(existing: filtered[index]),
                              ),
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
            heroTag: 'channels_fab',
            onPressed: () => openAddSheet(),
            tooltip: 'Adicionar canal',
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Filter bar
// ---------------------------------------------------------------------------

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.filter,
    required this.totalCount,
    required this.unreadCount,
    required this.onChanged,
  });

  final _Filter filter;
  final int totalCount;
  final int unreadCount;
  final ValueChanged<_Filter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        spacing: 8,
        children: [
          _chip(_Filter.todos, 'Todos', Icons.forum, totalCount),
          _chip(
            _Filter.naoLidos,
            'Não lidos',
            Icons.mark_chat_unread,
            unreadCount,
          ),
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
// Empty states
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onRefresh});
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.forum_outlined,
            size: 64,
            color: theme.colorScheme.onSurface.withAlpha(60),
          ),
          const SizedBox(height: 16),
          Text(
            'Sem canais',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface.withAlpha(120),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Os canais configurados no rádio aparecem aqui',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Actualizar Canais'),
          ),
        ],
      ),
    );
  }
}

class _NoUnreadState extends StatelessWidget {
  const _NoUnreadState({required this.onClearFilter});
  final VoidCallback onClearFilter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.mark_chat_read_outlined,
            size: 64,
            color: theme.colorScheme.onSurface.withAlpha(60),
          ),
          const SizedBox(height: 16),
          Text(
            'Tudo lido',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface.withAlpha(120),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Sem mensagens não lidas nos canais',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          TextButton.icon(
            onPressed: onClearFilter,
            icon: const Icon(Icons.list),
            label: const Text('Ver todos os canais'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Channel tile
// ---------------------------------------------------------------------------

class _ChannelTile extends ConsumerWidget {
  const _ChannelTile({required this.channel, required this.onEdit});
  final ChannelInfo channel;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final unreadCount = ref.watch(
      unreadCountsProvider.select((u) => u.forChannel(channel.index)),
    );

    final allMessages = ref.watch(messagesProvider);
    final channelMessages =
        allMessages.where((m) => m.channelIndex == channel.index).toList();

    final lastMessage =
        channelMessages.isNotEmpty ? channelMessages.last : null;

    final hasUnread = unreadCount > 0;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/channels/${channel.index}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              // Leading: index badge with unread count
              Badge(
                isLabelVisible: hasUnread,
                label: Text(unreadCount > 99 ? '99+' : '$unreadCount'),
                child: CircleAvatar(
                  backgroundColor:
                      hasUnread
                          ? theme.colorScheme.primaryContainer
                          : theme.colorScheme.surfaceContainerHighest,
                  child: Text(
                    '${channel.index}',
                    style: TextStyle(
                      color:
                          hasUnread
                              ? theme.colorScheme.onPrimaryContainer
                              : theme.colorScheme.onSurface.withAlpha(180),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 12),

              // Channel name + last message preview
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      channel.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight:
                            hasUnread ? FontWeight.bold : FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _previewText(lastMessage),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            hasUnread
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurface.withAlpha(140),
                        fontWeight: hasUnread ? FontWeight.w600 : null,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // QR share button (only if secret is available)
              if (channel.secret != null)
                IconButton(
                  icon: const Icon(Icons.qr_code, size: 18),
                  tooltip: 'Partilhar canal via QR',
                  onPressed: () => _showChannelQrCode(context),
                  visualDensity: VisualDensity.compact,
                ),

              // Edit button
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18),
                tooltip: 'Editar canal',
                onPressed: onEdit,
                visualDensity: VisualDensity.compact,
              ),

              // Trailing: timestamp + total count
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (lastMessage != null)
                    Text(
                      _formatTimestamp(lastMessage.timestamp),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color:
                            hasUnread
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurface.withAlpha(120),
                        fontWeight: hasUnread ? FontWeight.bold : null,
                      ),
                    ),
                  if (channelMessages.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${channelMessages.length} msg',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurface.withAlpha(100),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _previewText(ChatMessage? msg) {
    if (msg == null) return 'Sem mensagens';
    if (msg.isOutgoing) return 'Eu: ${msg.text}';
    if (msg.senderName != null && msg.senderName!.isNotEmpty) {
      return '${msg.senderName}: ${msg.text}';
    }
    return msg.text;
  }

  String _formatTimestamp(int ts) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Agora';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${dt.day}/${dt.month}';
  }

  void _showChannelQrCode(BuildContext context) {
    final secret = channel.secret;
    if (secret == null) return;
    final uri = MeshCoreUri.buildChannelUri(name: channel.name, secret: secret);
    showDialog<void>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('QR Code do canal'),
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
                    '${channel.index}: ${channel.name}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Partilhe este QR Code para dar acesso ao canal',
                    textAlign: TextAlign.center,
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
}

// ---------------------------------------------------------------------------
// Add / Edit channel bottom sheet
// ---------------------------------------------------------------------------

class _AddEditChannelSheet extends StatefulWidget {
  const _AddEditChannelSheet({
    required this.maxChannels,
    required this.usedIndices,
    required this.onSave,
    this.existing,
  });

  final ChannelInfo? existing;
  final int maxChannels;
  final Set<int> usedIndices;
  final Future<void> Function(int index, String name, Uint8List secret) onSave;

  @override
  State<_AddEditChannelSheet> createState() => _AddEditChannelSheetState();
}

class _AddEditChannelSheetState extends State<_AddEditChannelSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _secretCtrl;
  late int _selectedIndex;
  bool _saving = false;
  String? _nameError;
  String? _secretError;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameCtrl = TextEditingController(text: existing?.name ?? '');
    // Secret is write-only on the radio; show empty for edit
    _secretCtrl = TextEditingController();
    if (existing != null) {
      _selectedIndex = existing.index;
    } else {
      // Auto-pick first free slot
      _selectedIndex = List.generate(
        widget.maxChannels,
        (i) => i,
      ).firstWhere((i) => !widget.usedIndices.contains(i), orElse: () => 0);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _secretCtrl.dispose();
    super.dispose();
  }

  Future<void> _scanQr() async {
    final raw = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const QrScannerScreen(title: 'Ler QR de Canal'),
      ),
    );
    if (raw == null || !mounted) return;

    final result = MeshCoreUri.parse(raw);
    if (result is MeshCoreChannelUri) {
      _nameCtrl.text = result.name;
      _secretCtrl.text =
          result.secret.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      setState(() {
        _nameError = null;
        _secretError = null;
      });
    } else if (result is MeshCoreContactUri) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'QR de contacto detectado. Use o ecrã de Contactos para o adicionar.',
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

  void _generateSecret() {
    final rng = Random.secure();
    final bytes = List.generate(16, (_) => rng.nextInt(256));
    _secretCtrl.text =
        bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Uint8List? _parseSecret(String hex) {
    if (hex.isEmpty) {
      // Generate random secret when field is blank
      final rng = Random.secure();
      return Uint8List.fromList(List.generate(16, (_) => rng.nextInt(256)));
    }
    final clean = hex.replaceAll(RegExp(r'\s+'), '');
    if (clean.length != 32) return null;
    try {
      return Uint8List.fromList(
        List.generate(
          16,
          (i) => int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _save() async {
    setState(() {
      _nameError =
          _nameCtrl.text.trim().isEmpty ? 'O nome é obrigatório' : null;
      final secretRaw = _secretCtrl.text.trim();
      _secretError =
          secretRaw.isNotEmpty && _parseSecret(secretRaw) == null
              ? 'Introduza 32 caracteres hexadecimais (16 bytes) ou deixe em branco para gerar'
              : null;
    });
    if (_nameError != null || _secretError != null) return;

    final secret = _parseSecret(_secretCtrl.text.trim())!;
    setState(() => _saving = true);
    try {
      await widget.onSave(_selectedIndex, _nameCtrl.text.trim(), secret);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
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
            isEdit ? 'Editar canal' : 'Adicionar canal',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 20),

          // Index selector (only when adding)
          if (!isEdit) ...[
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Índice do canal',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: _selectedIndex,
                  isExpanded: true,
                  items: List.generate(widget.maxChannels, (i) {
                    final inUse = widget.usedIndices.contains(i);
                    return DropdownMenuItem(
                      value: i,
                      child: Text('Canal $i${inUse ? " (em uso)" : ""}'),
                    );
                  }),
                  onChanged: (v) => setState(() => _selectedIndex = v!),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ] else ...[
            // Read-only index display when editing
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Índice do canal',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.numbers),
              ),
              child: Text('Canal $_selectedIndex'),
            ),
            const SizedBox(height: 16),
          ],

          // Channel name
          TextField(
            controller: _nameCtrl,
            decoration: InputDecoration(
              labelText: 'Nome do canal',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.label_outline),
              errorText: _nameError,
            ),
            maxLength: 31,
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 8),

          // Secret (key)
          TextField(
            controller: _secretCtrl,
            decoration: InputDecoration(
              labelText: 'Chave (hex, 32 chars)',
              hintText: 'Deixe em branco para gerar aleatoriamente',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.key),
              errorText: _secretError,
              suffixIcon: IconButton(
                icon: const Icon(Icons.casino_outlined),
                tooltip: 'Gerar chave aleatória',
                onPressed: _generateSecret,
              ),
            ),
            maxLength: 32,
            keyboardType: TextInputType.text,
          ),
          const SizedBox(height: 8),

          // Info text for edit mode
          if (isEdit)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Deixe a chave em branco para gerar uma nova aleatoriamente.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withAlpha(150),
                ),
              ),
            ),

          const SizedBox(height: 8),

          // Scan QR to fill form
          OutlinedButton.icon(
            onPressed: _scanQr,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Ler QR Code de canal'),
          ),

          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon:
                _saving
                    ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Icon(Icons.save),
            label: Text(_saving ? 'A guardar...' : 'Guardar'),
          ),
        ],
      ),
    );
  }
}
