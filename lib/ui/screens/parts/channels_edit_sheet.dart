part of '../channels_list_screen.dart';

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

