part of '../settings_screen.dart';

// Private key backup card
// ---------------------------------------------------------------------------

class _KeyBackupCard extends ConsumerStatefulWidget {
  const _KeyBackupCard();

  @override
  ConsumerState<_KeyBackupCard> createState() => _KeyBackupCardState();
}

class _KeyBackupCardState extends ConsumerState<_KeyBackupCard> {
  String? _storedHex;
  bool _loading = false;

  String? get _pubKeyHex6 {
    final selfInfo = ref.read(selfInfoProvider);
    if (selfInfo == null) return null;
    return selfInfo.publicKey
        .take(6)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  @override
  void initState() {
    super.initState();
    _loadStoredKey();
  }

  Future<void> _loadStoredKey() async {
    final hex6 = _pubKeyHex6;
    if (hex6 == null) return;
    final stored = await StorageService.instance.loadPrivateKeyBackup(hex6);
    if (mounted) setState(() => _storedHex = stored);
  }

  Future<void> _exportFromRadio() async {
    setState(() => _loading = true);
    try {
      final hex =
          await ref.read(connectionProvider.notifier).exportPrivateKey();
      if (!mounted) return;
      if (hex == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.settingsKeyExportFailed)),
        );
        return;
      }
      final hex6 = _pubKeyHex6;
      if (hex6 != null) {
        await StorageService.instance.savePrivateKeyBackup(hex6, hex);
      }
      if (mounted) {
        setState(() => _storedHex = hex);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.settingsKeySavedSuccess),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Share the stored backup as a plain-text file for cross-device transfer.
  Future<void> _shareBackup() async {
    final hex = _storedHex;
    if (hex == null) return;
    setState(() => _loading = true);
    try {
      final name = 'meshcore_key_${_pubKeyHex6 ?? 'backup'}.txt';
      final bytes = Uint8List.fromList(hex.codeUnits);
      final file = XFile.fromData(bytes, name: name, mimeType: 'text/plain');
      await SharePlus.instance.share(
        ShareParams(
          files: [file],
          subject: context.l10n.settingsKeyShareSubject,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Prompt for a hex key, validate it, and return the clean 128-char hex,
  /// or null if the user cancelled or the input was invalid.
  Future<String?> _promptForHex() async {
    final controller = TextEditingController();
    final raw = await showDialog<String>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(AppLocalizations.of(ctx).settingsPasteKeyTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(ctx).settingsPasteKeyHint,
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  maxLines: 3,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(ctx).settingsKeyHexLabel,
                    hintText: '0a1b2c3d…',
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(AppLocalizations.of(ctx).commonCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                child: Text(AppLocalizations.of(ctx).commonContinue),
              ),
            ],
          ),
    );
    controller.dispose();
    if (raw == null || raw.isEmpty) return null;

    final clean = raw.toLowerCase().replaceAll(RegExp(r'\s'), '');
    if (clean.length != 128 || !RegExp(r'^[0-9a-f]+$').hasMatch(clean)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.settingsKeyInvalidHex),
            duration: const Duration(seconds: 4),
          ),
        );
      }
      return null;
    }
    return clean;
  }

  /// Paste a hex key, validate it, and save it locally (no radio needed).
  Future<void> _loadFromText() async {
    final hex = await _promptForHex();
    if (hex == null || !mounted) return;
    final hex6 = _pubKeyHex6;
    if (hex6 != null) {
      await StorageService.instance.savePrivateKeyBackup(hex6, hex);
    }
    if (mounted) {
      setState(() => _storedHex = hex);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.settingsKeyCopySaved),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// Send the locally-stored key to the radio.
  Future<void> _restoreToRadio() async {
    final hex = _storedHex;
    if (hex == null) return;

    // Confirm before overwriting the radio's key
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(
              AppLocalizations.of(ctx).settingsRestorePrivateKeyTitle,
            ),
            content: Text(
              AppLocalizations.of(ctx).settingsRestorePrivateKeyContent,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(AppLocalizations.of(ctx).commonCancel),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(AppLocalizations.of(ctx).settingsRestoreToRadio),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _loading = true);
    try {
      final ok = await ref
          .read(connectionProvider.notifier)
          .importPrivateKey(hex);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? context.l10n.settingsKeyImportedSuccess
                : context.l10n.settingsKeyRestoreFailed,
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteBackup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(AppLocalizations.of(ctx).settingsDeleteBackupTitle),
            content: Text(AppLocalizations.of(ctx).settingsDeleteBackupContent),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(AppLocalizations.of(ctx).commonCancel),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(AppLocalizations.of(ctx).commonDelete),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;
    final hex6 = _pubKeyHex6;
    if (hex6 != null) {
      await StorageService.instance.clearPrivateKeyBackup(hex6);
    }
    if (mounted) setState(() => _storedHex = null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selfInfo = ref.watch(selfInfoProvider);
    final isConnected =
        ref.watch(connectionProvider) == TransportState.connected;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.key, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.l10n.settingsPrivateKeyCopy,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                context.l10n.settingsPrivateKeyDesc,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_storedHex != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lock_outline, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${_storedHex!.substring(0, 16)}…',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 18),
                      tooltip: context.l10n.settingsCopyKeyTooltip,
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _storedHex!));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(context.l10n.settingsKeyCopied),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (selfInfo == null) ...[
              Text(
                context.l10n.settingsKeyConnectToBackup,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ] else ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  // ── Save to device ───────────────────────────────────────
                  if (isConnected)
                    FilledButton.icon(
                      onPressed: _loading ? null : _exportFromRadio,
                      icon:
                          _loading
                              ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                              : const Icon(Icons.download, size: 18),
                      label: Text(context.l10n.settingsSaveFromRadio),
                    ),
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _loadFromText,
                    icon: const Icon(Icons.paste, size: 18),
                    label: Text(context.l10n.settingsPasteKey),
                  ),
                  // ── Share/send ───────────────────────────────────────────
                  if (_storedHex != null)
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _shareBackup,
                      icon: const Icon(Icons.share, size: 18),
                      label: Text(context.l10n.settingsShareCopy),
                    ),
                  // ── Send to radio ────────────────────────────────────────
                  if (_storedHex != null && isConnected)
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _restoreToRadio,
                      icon: const Icon(Icons.restore, size: 18),
                      label: Text(context.l10n.settingsRestoreToRadio),
                    ),
                  // ── Danger ───────────────────────────────────────────────
                  if (_storedHex != null)
                    TextButton.icon(
                      onPressed: _loading ? null : _deleteBackup,
                      style: TextButton.styleFrom(
                        foregroundColor: theme.colorScheme.error,
                      ),
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: Text(context.l10n.settingsDeleteLocalCopy),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
