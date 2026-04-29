part of '../channels_list_screen.dart';

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
