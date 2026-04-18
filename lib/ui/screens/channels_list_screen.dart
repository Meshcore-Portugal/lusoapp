import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../l10n/l10n.dart';
import '../../protocol/protocol.dart';
import '../../providers/radio_providers.dart';
import 'qr_scanner_screen.dart';

// ---------------------------------------------------------------------------
// Channel type enum (used only in the add/create flow)
// ---------------------------------------------------------------------------

enum _ChannelType { publicChannel, hashtag, privateCreate, privateJoin }

// Well-known public channel key (from the MeshCore companion protocol spec)
const _kPublicKeyHex = '8b3387e9c5cdea6ac9e5edbaa115cd72';

Uint8List _publicChannelSecret() {
  return Uint8List.fromList(
    List.generate(
      16,
      (i) => int.parse(_kPublicKeyHex.substring(i * 2, i * 2 + 2), radix: 16),
    ),
  );
}

/// Derives the 16-byte hashtag channel key (delegates to shared protocol implementation).
Uint8List _hashtagKey(String name) => hashtagChannelKey(name);

String _toHex(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List? _fromHex(String hex) {
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

// ---------------------------------------------------------------------------
// Filter options
// ---------------------------------------------------------------------------

enum _Filter { todos, naoLidos }

// ---------------------------------------------------------------------------
// Main screen
// ---------------------------------------------------------------------------

/// Channels list screen with filter chips and last-message preview.
class ChannelsListScreen extends ConsumerStatefulWidget {
  const ChannelsListScreen({super.key});

  @override
  ConsumerState<ChannelsListScreen> createState() => _ChannelsListScreenState();
}

class _ChannelsListScreenState extends ConsumerState<ChannelsListScreen> {
  _Filter _filter = _Filter.todos;

  @override
  void initState() {
    super.initState();
    // Eagerly load persisted messages for all known channels so the list
    // shows last-message previews without requiring a channel visit first.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadAllChannelMessages(ref.read(channelsProvider));
    });
  }

  void _loadAllChannelMessages(List<ChannelInfo> channels) {
    for (final ch in channels) {
      if (ch.name.isNotEmpty) {
        ref.read(messagesProvider.notifier).ensureLoadedForChannel(ch.index);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final channels = ref.watch(channelsProvider);

    // Also trigger when channels arrive from the radio after the screen opens.
    ref.listen<List<ChannelInfo>>(channelsProvider, (_, next) {
      _loadAllChannelMessages(next);
    });
    final unread = ref.watch(unreadCountsProvider);
    final allMessages = ref.watch(messagesProvider);
    final maxChannels = ref.watch(deviceInfoProvider)?.maxChannels ?? 8;

    final configured = channels.where((c) => c.name.isNotEmpty).toList();
    final unreadChannelCount =
        configured.where((c) => unread.forChannel(c.index) > 0).length;

    final filtered =
        _filter == _Filter.naoLidos
            ? configured.where((c) => unread.forChannel(c.index) > 0).toList()
            : List<ChannelInfo>.from(configured);

    filtered.sort((a, b) {
      int lastTs(ChannelInfo ch) => allMessages
          .where((m) => m.channelIndex == ch.index)
          .fold(0, (ts, m) => m.timestamp > ts ? m.timestamp : ts);

      final ta = lastTs(a);
      final tb = lastTs(b);
      if (ta != tb) return tb.compareTo(ta); // newest message first
      return a.index.compareTo(b.index); // tie-break by slot index
    });

    final usedIndices = configured.map((c) => c.index).toSet();

    void openTypePicker() {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder:
            (ctx) => _TypePickerSheet(
              onTypeSelected: (type) {
                Navigator.pop(ctx);
                _openCreateSheet(
                  type: type,
                  maxChannels: maxChannels,
                  usedIndices: usedIndices,
                );
              },
              onScanQr: () {
                Navigator.pop(ctx);
                _scanQrToCreate(
                  maxChannels: maxChannels,
                  usedIndices: usedIndices,
                );
              },
            ),
      );
    }

    void openEditSheet(ChannelInfo channel) {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder:
            (_) => _EditChannelSheet(
              channel: channel,
              onSave: (idx, name, secret) async {
                final service = ref.read(radioServiceProvider);
                if (service == null) return;
                await service.setChannel(idx, name, secret);
                await Future.delayed(const Duration(milliseconds: 200));
                await service.requestChannel(idx);
              },
              onDelete: (idx) async {
                final service = ref.read(radioServiceProvider);
                if (service == null) return;
                // Delete = SET_CHANNEL with empty name and all-zero 16-byte secret
                await service.setChannel(idx, '', Uint8List(16));
                await Future.delayed(const Duration(milliseconds: 200));
                await service.requestChannel(idx);
              },
            ),
      );
    }

    return Stack(
      children: [
        Column(
          children: [
            _FilterBar(
              filter: _filter,
              totalCount: configured.length,
              unreadCount: unreadChannelCount,
              onChanged: (f) => setState(() => _filter = f),
            ),
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
                                onEdit: () => openEditSheet(filtered[index]),
                              ),
                        ),
                      ),
            ),
          ],
        ),

        // FAB — opens type picker
        Positioned(
          bottom: 16,
          right: 16,
          child: FloatingActionButton(
            heroTag: 'channels_fab',
            onPressed: openTypePicker,
            tooltip: context.l10n.commonAdd,
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }

  void _openCreateSheet({
    required _ChannelType type,
    required int maxChannels,
    required Set<int> usedIndices,
    String? prefillName,
    Uint8List? prefillSecret,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder:
          (_) => _CreateChannelSheet(
            type: type,
            maxChannels: maxChannels,
            usedIndices: usedIndices,
            prefillName: prefillName,
            prefillSecret: prefillSecret,
            onSave: (idx, name, secret) async {
              final service = ref.read(radioServiceProvider);
              if (service == null) return;
              await service.setChannel(idx, name, secret);
              await Future.delayed(const Duration(milliseconds: 200));
              await service.requestChannel(idx);
            },
          ),
    );
  }

  Future<void> _scanQrToCreate({
    required int maxChannels,
    required Set<int> usedIndices,
  }) async {
    final raw = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const QrScannerScreen(title: 'Ler QR de Canal'),
      ),
    );
    if (raw == null || !mounted) return;

    final result = MeshCoreUri.parse(raw);
    if (result is MeshCoreChannelUri) {
      _openCreateSheet(
        type: _ChannelType.privateJoin,
        maxChannels: maxChannels,
        usedIndices: usedIndices,
        prefillName: result.name,
        prefillSecret: result.secret,
      );
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
}

// ---------------------------------------------------------------------------
// Type picker sheet — matches official app layout
// ---------------------------------------------------------------------------

class _TypePickerSheet extends StatelessWidget {
  const _TypePickerSheet({
    required this.onTypeSelected,
    required this.onScanQr,
  });

  final void Function(_ChannelType) onTypeSelected;
  final VoidCallback onScanQr;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _TypeOption(
              icon: Icons.add_circle_outline,
              title: 'Criar Canal Privado',
              subtitle: 'Seguro com uma chave secreta.',
              onTap: () => onTypeSelected(_ChannelType.privateCreate),
            ),
            _TypeOption(
              icon: Icons.lock_outline,
              title: 'Entrar num Canal Privado',
              subtitle: 'Introduza manualmente uma chave secreta.',
              onTap: () => onTypeSelected(_ChannelType.privateJoin),
            ),
            _TypeOption(
              icon: Icons.public,
              title: 'Entrar no Canal Público',
              subtitle: 'Qualquer pessoa pode entrar neste canal.',
              onTap: () => onTypeSelected(_ChannelType.publicChannel),
            ),
            _TypeOption(
              icon: Icons.tag,
              title: 'Entrar num Canal Hashtag',
              subtitle: 'Qualquer pessoa pode entrar em canais hashtag.',
              onTap: () => onTypeSelected(_ChannelType.hashtag),
            ),
            _TypeOption(
              icon: Icons.qr_code_scanner,
              title: 'Ler QR Code',
              subtitle: 'Digitalizar o QR Code de um canal.',
              onTap: onScanQr,
              isLast: true,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _TypeOption extends StatelessWidget {
  const _TypeOption({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.isLast = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          leading: Icon(icon, color: theme.colorScheme.primary),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: subtitle != null ? Text(subtitle!) : null,
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
        if (!isLast) const Divider(height: 1, indent: 56),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Create channel sheet (type-aware)
// ---------------------------------------------------------------------------

class _CreateChannelSheet extends StatefulWidget {
  const _CreateChannelSheet({
    required this.type,
    required this.maxChannels,
    required this.usedIndices,
    required this.onSave,
    this.prefillName,
    this.prefillSecret,
  });

  final _ChannelType type;
  final int maxChannels;
  final Set<int> usedIndices;
  final Future<void> Function(int index, String name, Uint8List secret) onSave;
  final String? prefillName;
  final Uint8List? prefillSecret;

  @override
  State<_CreateChannelSheet> createState() => _CreateChannelSheetState();
}

class _CreateChannelSheetState extends State<_CreateChannelSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _secretCtrl;
  late int _selectedIndex;
  bool _saving = false;
  String? _nameError;
  String? _secretError;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.prefillName ?? '');

    // Determine initial secret value based on type
    String initSecret = '';
    if (widget.prefillSecret != null) {
      initSecret = _toHex(widget.prefillSecret!);
    } else if (widget.type == _ChannelType.publicChannel) {
      initSecret = _kPublicKeyHex;
    } else if (widget.type == _ChannelType.privateCreate) {
      initSecret = _toHex(_generateRandomSecret());
    }
    _secretCtrl = TextEditingController(text: initSecret);

    // Auto-pick first free slot
    _selectedIndex = List.generate(
      widget.maxChannels,
      (i) => i,
    ).firstWhere((i) => !widget.usedIndices.contains(i), orElse: () => 0);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _secretCtrl.dispose();
    super.dispose();
  }

  static Uint8List _generateRandomSecret() {
    final rng = Random.secure();
    return Uint8List.fromList(List.generate(16, (_) => rng.nextInt(256)));
  }

  void _regenerateSecret() {
    setState(() {
      _secretCtrl.text = _toHex(_generateRandomSecret());
    });
  }

  /// Returns the resolved 16-byte secret for the current type and form state.
  Uint8List? _resolveSecret() {
    switch (widget.type) {
      case _ChannelType.publicChannel:
        return _publicChannelSecret();
      case _ChannelType.hashtag:
        final name = _nameCtrl.text.trim();
        if (name.isEmpty) return null;
        return _hashtagKey(name);
      case _ChannelType.privateCreate:
        return _fromHex(_secretCtrl.text.trim());
      case _ChannelType.privateJoin:
        return _fromHex(_secretCtrl.text.trim());
    }
  }

  String _derivedKeyHex() {
    switch (widget.type) {
      case _ChannelType.publicChannel:
        return _kPublicKeyHex;
      case _ChannelType.hashtag:
        final name = _nameCtrl.text.trim();
        return name.isEmpty ? '' : _toHex(_hashtagKey(name));
      case _ChannelType.privateCreate:
        return _secretCtrl.text;
      case _ChannelType.privateJoin:
        return _secretCtrl.text;
    }
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final secret = _resolveSecret();

    setState(() {
      _nameError = name.isEmpty ? 'O nome é obrigatório' : null;
      _secretError =
          widget.type == _ChannelType.privateJoin && secret == null
              ? 'Introduza 32 caracteres hexadecimais (16 bytes)'
              : null;
    });

    if (_nameError != null || _secretError != null || secret == null) return;

    // For hashtag channels: prefix name with '#' if not already present
    final finalName =
        widget.type == _ChannelType.hashtag
            ? (name.startsWith('#') ? name : '#$name')
            : name;

    setState(() => _saving = true);
    try {
      await widget.onSave(_selectedIndex, finalName, secret);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final keyHex = _derivedKeyHex();

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Title row with type icon
            Row(
              children: [
                Icon(_typeIcon(widget.type), color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _typeTitle(widget.type),
                    style: theme.textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _typeSubtitle(widget.type),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withAlpha(160),
              ),
            ),
            const SizedBox(height: 20),

            // Slot selector
            InputDecorator(
              decoration: InputDecoration(
                labelText: context.l10n.channelsSlotPosition,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(
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
                      child: Text(
                        '${context.l10n.channelsSlot} $i${inUse ? " (${context.l10n.channelsSlotInUse})" : ""}',
                      ),
                    );
                  }),
                  onChanged: (v) => setState(() => _selectedIndex = v!),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Channel name field
            TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                labelText: _nameLabelForType(context, widget.type),
                hintText: _nameHintForType(context, widget.type),
                border: const OutlineInputBorder(),
                prefixIcon:
                    widget.type == _ChannelType.hashtag
                        ? const Icon(Icons.tag)
                        : const Icon(Icons.label_outline),
                errorText: _nameError,
              ),
              maxLength: widget.type == _ChannelType.hashtag ? 30 : 31,
              textCapitalization: TextCapitalization.none,
              onChanged:
                  widget.type == _ChannelType.hashtag
                      ? (_) => setState(() {})
                      : null,
            ),
            const SizedBox(height: 8),

            // Secret input — only shown for privateJoin
            if (widget.type == _ChannelType.privateJoin) ...[
              TextField(
                controller: _secretCtrl,
                decoration: InputDecoration(
                  labelText: context.l10n.channelsSecretKey,
                  hintText: context.l10n.channelsSecretKeyHint,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.key),
                  errorText: _secretError,
                ),
                maxLength: 32,
                keyboardType: TextInputType.text,
              ),
            ],

            // Key info card — shown for all types except privateJoin
            if (widget.type != _ChannelType.privateJoin &&
                keyHex.isNotEmpty) ...[
              _KeyInfoCard(
                label: _keyLabelForType(context, widget.type),
                info: _keyInfoForType(context, widget.type),
                secretHex: keyHex,
                onRegenerate:
                    widget.type == _ChannelType.privateCreate
                        ? _regenerateSecret
                        : null,
              ),
            ],

            const SizedBox(height: 20),
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
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  static IconData _typeIcon(_ChannelType t) => switch (t) {
    _ChannelType.publicChannel => Icons.public,
    _ChannelType.hashtag => Icons.tag,
    _ChannelType.privateCreate => Icons.add_circle_outline,
    _ChannelType.privateJoin => Icons.lock_outline,
  };

  static String _typeTitle(_ChannelType t) => switch (t) {
    _ChannelType.publicChannel => 'Canal Público',
    _ChannelType.hashtag => 'Canal Hashtag',
    _ChannelType.privateCreate => 'Criar Canal Privado',
    _ChannelType.privateJoin => 'Entrar em Canal Privado',
  };

  static String _typeSubtitle(_ChannelType t) => switch (t) {
    _ChannelType.publicChannel =>
      'Qualquer pessoa pode entrar. Mensagens públicas.',
    _ChannelType.hashtag =>
      'Canal público por tópico. A chave é derivada automaticamente do nome.',
    _ChannelType.privateCreate =>
      'Canal privado com chave aleatória. Partilhe o QR Code para convidar.',
    _ChannelType.privateJoin =>
      'Introduza a chave secreta de um canal privado existente.',
  };

  String _nameLabelForType(BuildContext context, _ChannelType t) => switch (t) {
    _ChannelType.hashtag => context.l10n.channelsHashtagName,
    _ => context.l10n.channelsChannelName,
  };

  String _nameHintForType(BuildContext context, _ChannelType t) => switch (t) {
    _ChannelType.hashtag => context.l10n.channelsHashtagHint,
    _ChannelType.publicChannel => context.l10n.channelsNameHintGeneral,
    _ChannelType.privateCreate => context.l10n.channelsNameHintPrivate,
    _ChannelType.privateJoin => context.l10n.channelsChannelName,
  };

  String _keyLabelForType(BuildContext context, _ChannelType t) => switch (t) {
    _ChannelType.publicChannel => context.l10n.channelsPublicKey,
    _ChannelType.hashtag => context.l10n.channelsDerivedKey,
    _ChannelType.privateCreate => context.l10n.channelsRandomKey,
    _ChannelType.privateJoin => '',
  };

  String _keyInfoForType(BuildContext context, _ChannelType t) => switch (t) {
    _ChannelType.publicChannel => context.l10n.channelsPublicKeyInfo,
    _ChannelType.hashtag => context.l10n.channelsHashtagKeyInfo,
    _ChannelType.privateCreate => context.l10n.channelsRandomKeyInfo,
    _ChannelType.privateJoin => '',
  };
}

// ---------------------------------------------------------------------------
// Key info card — read-only display with copy and optional regenerate
// ---------------------------------------------------------------------------

class _KeyInfoCard extends StatelessWidget {
  const _KeyInfoCard({
    required this.label,
    required this.info,
    required this.secretHex,
    this.onRegenerate,
  });

  final String label;
  final String info;
  final String secretHex;
  final VoidCallback? onRegenerate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.key, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (onRegenerate != null)
                IconButton(
                  icon: const Icon(Icons.casino_outlined, size: 18),
                  tooltip: context.l10n.channelsRegenerateKey,
                  onPressed: onRegenerate,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.copy, size: 16),
                tooltip: context.l10n.commonCopy,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: secretHex));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(context.l10n.commonMessageCopied),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            secretHex,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 0.5,
            ),
          ),
          if (info.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              info,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withAlpha(140),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Edit channel sheet (rename + delete + QR share)
// ---------------------------------------------------------------------------

class _EditChannelSheet extends ConsumerStatefulWidget {
  const _EditChannelSheet({
    required this.channel,
    required this.onSave,
    required this.onDelete,
  });

  final ChannelInfo channel;
  final Future<void> Function(int index, String name, Uint8List secret) onSave;
  final Future<void> Function(int index) onDelete;

  @override
  ConsumerState<_EditChannelSheet> createState() => _EditChannelSheetState();
}

class _EditChannelSheetState extends ConsumerState<_EditChannelSheet> {
  late final TextEditingController _nameCtrl;
  bool _saving = false;
  bool _deleting = false;
  String? _nameError;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.channel.name);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    setState(() {
      _nameError = name.isEmpty ? 'O nome é obrigatório' : null;
    });
    if (_nameError != null) return;

    final secret = widget.channel.secret;
    if (secret == null || secret.length != 16) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Chave do canal não disponível. Recrie o canal para o renomear.',
          ),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await widget.onSave(widget.channel.index, name, secret);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmDelete() async {
    final isPublic =
        widget.channel.secret != null &&
        _toHex(widget.channel.secret!) == _kPublicKeyHex;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        if (isPublic) {
          return AlertDialog(
            icon: Icon(
              Icons.warning_amber_rounded,
              color: Theme.of(ctx).colorScheme.error,
              size: 40,
            ),
            title: Text(context.l10n.channelsRemovePublicTitle),
            content: const Text(
              'Está prestes a remover o Canal Público.\n\n'
              'Este é o canal principal partilhado por toda a comunidade MeshCore. '
              'Sem ele não poderá receber ou enviar mensagens públicas.\n\n'
              'Tem mesmo a certeza?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(context.l10n.commonCancel),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(context.l10n.channelsRemoveAnyway),
              ),
            ],
          );
        }

        return AlertDialog(
          title: Text(context.l10n.channelsRemoveTitle),
          content: Text(
            'Tem a certeza que quer remover "${widget.channel.name}"?\n\n'
            'Esta acção não pode ser desfeita. Para recuperar o canal terá de conhecer a chave secreta.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.l10n.commonCancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(context.l10n.commonRemove),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      await widget.onDelete(widget.channel.index);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  void _showQrCode(BuildContext context) {
    final secret = widget.channel.secret;
    if (secret == null) return;
    final uri = MeshCoreUri.buildChannelUri(
      name: widget.channel.name,
      secret: secret,
    );
    showDialog<void>(
      context: context,
      builder:
          (ctx) => _ChannelQrDialog(
            uri: uri,
            displayName: '${widget.channel.index}: ${widget.channel.name}',
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final secret = widget.channel.secret;
    final isMuted = ref.watch(
      mutedChannelsProvider.select((s) => s.contains(widget.channel.index)),
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.edit_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Editar canal',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                Chip(
                  label: Text('Slot ${widget.channel.index}'),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Mute toggle
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: Icon(
                isMuted
                    ? Icons.notifications_off_outlined
                    : Icons.notifications_outlined,
                color:
                    isMuted
                        ? theme.colorScheme.onSurface.withAlpha(140)
                        : theme.colorScheme.primary,
              ),
              title: Text(
                isMuted
                    ? context.l10n.channelsMuteTitle
                    : context.l10n.channelsUnmuteTitle,
              ),
              subtitle: Text(
                isMuted
                    ? context.l10n.channelsMuteSubtitleOn
                    : context.l10n.channelsMuteSubtitleOff,
              ),
              value: isMuted,
              onChanged:
                  (_) => ref
                      .read(mutedChannelsProvider.notifier)
                      .toggle(widget.channel.index),
            ),
            const Divider(height: 16),

            // Channel name
            TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                labelText: context.l10n.channelsChannelName,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.label_outline),
                errorText: _nameError,
              ),
              maxLength: 31,
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 8),

            // Key info (read-only)
            if (secret != null)
              _KeyInfoCard(
                label: 'Chave actual',
                info: '',
                secretHex: _toHex(secret),
              ),

            // QR share button
            if (secret != null && widget.channel.name.isNotEmpty) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.qr_code),
                label: Text(context.l10n.channelsShowQR),
                onPressed: () => _showQrCode(context),
              ),
            ],

            const SizedBox(height: 20),

            // Delete + Save row
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                      side: BorderSide(color: theme.colorScheme.error),
                    ),
                    onPressed: (_saving || _deleting) ? null : _confirmDelete,
                    icon:
                        _deleting
                            ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: theme.colorScheme.error,
                              ),
                            )
                            : const Icon(Icons.delete_outline),
                    label: Text(_deleting ? 'A remover...' : 'Remover'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: (_saving || _deleting) ? null : _save,
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
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
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
          _chip(_Filter.todos, context.l10n.commonAll, Icons.forum, totalCount),
          _chip(
            _Filter.naoLidos,
            context.l10n.commonUnread,
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
            context.l10n.channelsEmpty,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface.withAlpha(120),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.channelsEmptyHint,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh),
            label: Text(context.l10n.channelsRefresh),
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
            context.l10n.channelsAllRead,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface.withAlpha(120),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.channelsAllReadHint,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          TextButton.icon(
            onPressed: onClearFilter,
            icon: const Icon(Icons.list),
            label: Text(context.l10n.channelsSeeAll),
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
    final isMuted = ref.watch(
      mutedChannelsProvider.select((s) => s.contains(channel.index)),
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
        onLongPress: onEdit,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              // Leading: index badge with unread indicator (greyed when muted)
              Badge(
                isLabelVisible: hasUnread && !isMuted,
                label: Text(unreadCount > 99 ? '99+' : '$unreadCount'),
                child: CircleAvatar(
                  backgroundColor:
                      hasUnread && !isMuted
                          ? theme.colorScheme.primaryContainer
                          : theme.colorScheme.surfaceContainerHighest,
                  child:
                      isMuted
                          ? Icon(
                            Icons.notifications_off_outlined,
                            size: 18,
                            color: theme.colorScheme.onSurface.withAlpha(120),
                          )
                          : Text(
                            '${channel.index}',
                            style: TextStyle(
                              color:
                                  hasUnread
                                      ? theme.colorScheme.onPrimaryContainer
                                      : theme.colorScheme.onSurface.withAlpha(
                                        180,
                                      ),
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
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            channel.name,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight:
                                  hasUnread && !isMuted
                                      ? FontWeight.bold
                                      : FontWeight.w500,
                              color:
                                  isMuted
                                      ? theme.colorScheme.onSurface.withAlpha(
                                        120,
                                      )
                                      : null,
                            ),
                          ),
                        ),
                        if (isMuted)
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Text(
                              context.l10n.channelsMuteLabel,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurface.withAlpha(
                                  100,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _previewText(context, lastMessage),
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

              // Options button
              IconButton(
                icon: const Icon(Icons.more_vert, size: 18),
                tooltip: context.l10n.channelsOptionsFabTooltip,
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
                      _formatTimestamp(context, lastMessage.timestamp),
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

  String _previewText(BuildContext context, ChatMessage? msg) {
    if (msg == null) return context.l10n.commonNoMessages;
    final l10n = context.l10n;
    if (msg.isOutgoing) return '${l10n.commonSentByMe}: ${msg.text}';
    if (msg.senderName != null && msg.senderName!.isNotEmpty) {
      return '${msg.senderName}: ${msg.text}';
    }
    return msg.text;
  }

  String _formatTimestamp(BuildContext context, int ts) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return context.l10n.telemetryNow;
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${dt.day}/${dt.month}';
  }
}

// ---------------------------------------------------------------------------
// Channel QR code dialog with QR image share + plain text share
// ---------------------------------------------------------------------------

class _ChannelQrDialog extends StatefulWidget {
  const _ChannelQrDialog({required this.uri, required this.displayName});

  final String uri;
  final String displayName;

  @override
  State<_ChannelQrDialog> createState() => _ChannelQrDialogState();
}

class _ChannelQrDialogState extends State<_ChannelQrDialog> {
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
          subject: 'Canal MeshCore: ${widget.displayName}',
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
          subject: 'Canal MeshCore: ${widget.displayName}',
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
      title: Text(context.l10n.channelsQRTitle),
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
            Text(
              'Partilhe este QR Code para dar acesso ao canal',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
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
