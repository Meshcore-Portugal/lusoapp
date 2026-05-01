import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../l10n/l10n.dart';
import '../../protocol/protocol.dart';
import '../../providers/radio_providers.dart';
import '../../services/notification_service.dart';
import '../../services/storage_service.dart';
import '../../transport/radio_transport.dart';

/// App settings screen.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _version = info.version);
    });
  }

  @override
  Widget build(BuildContext context) {
    final selfInfo = ref.watch(selfInfoProvider);
    final connectionState = ref.watch(connectionProvider);
    final autoReconnect = ref.watch(autoReconnectProvider);
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Identity
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.badge, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        context.l10n.settingsIdentity,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    title: Text(context.l10n.commonName),
                    subtitle: Text(selfInfo?.name ?? 'Não conectado'),
                    trailing: const Icon(Icons.edit),
                    onTap: () => _editName(context, ref),
                  ),
                  if (selfInfo != null)
                    ListTile(
                      title: Text(context.l10n.settingsPublicKey),
                      subtitle: Text(
                        selfInfo.publicKey
                            .map((b) => b.toRadixString(16).padLeft(2, '0'))
                            .join(),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.copy, size: 18),
                        tooltip: context.l10n.settingsCopyPublicKey,
                        onPressed: () {
                          final hex =
                              selfInfo.publicKey
                                  .map(
                                    (b) => b.toRadixString(16).padLeft(2, '0'),
                                  )
                                  .join();
                          Clipboard.setData(ClipboardData(text: hex));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Chave pública copiada'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                    ),
                  if (selfInfo != null)
                    ListTile(
                      leading: const Icon(Icons.qr_code),
                      title: Text(context.l10n.settingsShareContact),
                      subtitle: Text(context.l10n.settingsShareContactDesc),
                      onTap: () => _showOwnQrCode(context, selfInfo),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Private key backup
          const _KeyBackupCard(),
          const SizedBox(height: 16),

          // Connection
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.link, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        context.l10n.settingsConnection,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    title: Text(context.l10n.commonStatus),
                    subtitle: Text(
                      _connectionStateText(context, connectionState),
                    ),
                    leading: Icon(
                      connectionState == TransportState.connected
                          ? Icons.check_circle
                          : Icons.cancel,
                      color:
                          connectionState == TransportState.connected
                              ? Colors.green
                              : Colors.red,
                    ),
                  ),
                  SwitchListTile(
                    title: Text(context.l10n.settingsAutoReconnect),
                    subtitle: Text(context.l10n.settingsAutoReconnectDesc),
                    secondary: const Icon(Icons.autorenew),
                    value: autoReconnect,
                    onChanged:
                        (v) => ref.read(autoReconnectProvider.notifier).set(v),
                  ),
                  if (connectionState == TransportState.connected) ...[
                    ListTile(
                      title: Text(context.l10n.settingsRadioConfig),
                      subtitle: Text(context.l10n.settingsRadioConfigDesc),
                      leading: const Icon(Icons.settings_input_antenna),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/settings/radio'),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _confirmAndReboot(context),
                            icon: const Icon(Icons.restart_alt),
                            label: Text(context.l10n.settingsReboot),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Shutdown não disponível neste firmware',
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.power_settings_new),
                            label: Text(context.l10n.settingsShutdown),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Notifications
          const _NotificationsCard(),
          const SizedBox(height: 16),

          // Appearance
          const _AppearanceCard(),
          const SizedBox(height: 16),

          // About
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        context.l10n.settingsAbout,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const ListTile(
                    title: Text('LusoAPP'),
                    subtitle: Text(
                      'MeshCore Portugal\nCódigo fonte inicial criado por\nPaulo Pereira aka GZ7d0',
                    ),
                  ),
                  ListTile(
                    title: Text(context.l10n.settingsVersion),
                    subtitle: Text(_version.isEmpty ? '…' : _version),
                  ),
                  ListTile(
                    title: Text(context.l10n.settingsProtocol),
                    subtitle: Text(context.l10n.settingsProtocolName),
                  ),
                  ListTile(
                    title: Text(context.l10n.settingsLicense),
                    subtitle: Text(context.l10n.settingsLicenseMIT),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _connectionStateText(BuildContext context, TransportState state) {
    return switch (state) {
      TransportState.connected => context.l10n.settingsConnected,
      TransportState.connecting => context.l10n.commonConnecting,
      TransportState.scanning => context.l10n.commonSearching,
      TransportState.error => context.l10n.settingsConnectionError,
      TransportState.disconnected => context.l10n.settingsDisconnected,
    };
  }

  Future<void> _confirmAndReboot(BuildContext context) async {
    final service = ref.read(radioServiceProvider);
    if (service == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Rádio não ligado')));
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(context.l10n.settingsRebootTitle),
            content: Text(context.l10n.settingsRebootContent),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(context.l10n.commonCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(context.l10n.settingsReboot),
              ),
            ],
          ),
    );

    if (ok != true || !mounted) return;

    try {
      await service.reboot();
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.settingsRebootSent)));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.settingsRebootFail)));
    }
  }

  void _showOwnQrCode(BuildContext context, SelfInfo selfInfo) {
    final uri = MeshCoreUri.buildContactUri(
      name: selfInfo.name,
      publicKey: selfInfo.publicKey,
      type: 1,
    );
    showDialog<void>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('O meu QR Code'),
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
                    selfInfo.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tipo: Companheiro',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(context.l10n.commonClose),
              ),
            ],
          ),
    );
  }

  void _editName(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController(
      text: ref.read(selfInfoProvider)?.name ?? '',
    );

    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Alterar Nome'),
            content: TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Nome do no',
                hintText: 'Ex: CT1XXX-MC',
              ),
              maxLength: 32,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(context.l10n.commonCancel),
              ),
              FilledButton(
                onPressed: () {
                  final name = controller.text.trim();
                  if (name.isNotEmpty) {
                    ref.read(radioServiceProvider)?.setAdvertName(name);
                    final current = ref.read(selfInfoProvider);
                    if (current != null) {
                      ref.read(selfInfoProvider.notifier).state = SelfInfo(
                        publicKey: current.publicKey,
                        name: name,
                        radioConfig: current.radioConfig,
                        advType: current.advType,
                        txPower: current.txPower,
                        maxTxPower: current.maxTxPower,
                        latitude: current.latitude,
                        longitude: current.longitude,
                      );
                    }
                  }
                  Navigator.pop(ctx);
                },
                child: Text(context.l10n.commonSave),
              ),
            ],
          ),
    );
  }
}

// ---------------------------------------------------------------------------
// Appearance card — mention pill colours
// ---------------------------------------------------------------------------

class _AppearanceCard extends ConsumerWidget {
  const _AppearanceCard();

  static const _swatches = [
    Color.fromARGB(0xFF, 0xFF, 0x6B, 0x00), // orange  (default other)
    Color.fromARGB(0xFF, 0xFF, 0xB3, 0x47), // amber   (default self)
    Color.fromARGB(0xFF, 0xE5, 0x39, 0x35), // red
    Color.fromARGB(0xFF, 0xE9, 0x1E, 0x63), // pink
    Color.fromARGB(0xFF, 0x8E, 0x24, 0xAA), // purple
    Color.fromARGB(0xFF, 0x39, 0x49, 0xAB), // indigo
    Color.fromARGB(0xFF, 0x1E, 0x88, 0xE5), // blue
    Color.fromARGB(0xFF, 0x03, 0x9B, 0xE5), // light blue
    Color.fromARGB(0xFF, 0x00, 0xAC, 0xC1), // cyan
    Color.fromARGB(0xFF, 0x00, 0x89, 0x7B), // teal
    Color.fromARGB(0xFF, 0x43, 0xA0, 0x47), // green
    Color.fromARGB(0xFF, 0x7C, 0xB3, 0x42), // light green
    Color.fromARGB(0xFF, 0xFD, 0xD8, 0x35), // yellow
    Color.fromARGB(0xFF, 0xF4, 0x51, 0x1E), // deep orange
    Color.fromARGB(0xFF, 0x6D, 0x4C, 0x41), // brown
    Color.fromARGB(0xFF, 0x54, 0x6E, 0x7A), // blue grey
  ];

  Future<Color?> _pickColor(BuildContext context, Color current) {
    return showDialog<Color>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(context.l10n.settingsChooseColor),
            content: Wrap(
              spacing: 8,
              runSpacing: 8,
              children:
                  _swatches.map((c) {
                    final selected = c == current;
                    return GestureDetector(
                      onTap: () => Navigator.pop(ctx, c),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: selected ? Colors.white : Colors.transparent,
                            width: 3,
                          ),
                          boxShadow:
                              selected
                                  ? [
                                    BoxShadow(
                                      color: c.withValues(alpha: 0.47),
                                      blurRadius: 6,
                                    ),
                                  ]
                                  : null,
                        ),
                      ),
                    );
                  }).toList(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(AppLocalizations.of(ctx).commonCancel),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final selfColor = ref.watch(selfMentionColorProvider);
    final otherColor = ref.watch(otherMentionColorProvider);
    final themeMode = ref.watch(themeModeProvider);

    Widget colorRow(
      String label,
      Color color,
      Future<void> Function(Color) onPick,
    ) {
      final textColor =
          color.computeLuminance() > 0.45 ? Colors.black : Colors.white;
      return ListTile(
        title: Text(label),
        subtitle: Text(
          '@[nome]',
          style: theme.textTheme.labelSmall?.copyWith(color: color),
        ),
        trailing: GestureDetector(
          onTap: () async {
            final picked = await _pickColor(context, color);
            if (picked != null) await onPick(picked);
          },
          child: Container(
            width: 48,
            height: 32,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Center(
              child: Text(
                '@',
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.palette, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  context.l10n.settingsAppearance,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 3-segment theme selector. Persisted immediately via ThemeModeNotifier.
            // System option follows the device brightness setting automatically.
            // No extra padding — the card's own 16px margin is sufficient, and
            // full width prevents the "Sistema" label from wrapping to two lines.
            SegmentedButton<ThemeMode>(
              style: SegmentedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              segments: const [
                ButtonSegment(
                  value: ThemeMode.dark,
                  icon: Icon(Icons.dark_mode),
                  label: Text('Escuro'),
                ),
                ButtonSegment(
                  value: ThemeMode.system,
                  icon: Icon(Icons.brightness_auto),
                  label: Text('Sistema'),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  icon: Icon(Icons.light_mode),
                  label: Text('Claro'),
                ),
              ],
              selected: {themeMode},
              onSelectionChanged: (selection) => ref
                  .read(themeModeProvider.notifier)
                  .setMode(selection.first),
            ),
            const SizedBox(height: 4),
            const Divider(height: 16),
            colorRow(
              context.l10n.settingsSelfMention,
              selfColor,
              (c) => ref.read(selfMentionColorProvider.notifier).setColor(c),
            ),
            colorRow(
              context.l10n.settingsOtherMention,
              otherColor,
              (c) => ref.read(otherMentionColorProvider.notifier).setColor(c),
            ),
          ],
        ),
      ),
    );
  }
}

/// Card that shows notification toggle controls.
class _NotificationsCard extends ConsumerStatefulWidget {
  const _NotificationsCard();

  @override
  ConsumerState<_NotificationsCard> createState() => _NotificationsCardState();
}

class _NotificationsCardState extends ConsumerState<_NotificationsCard> {
  bool _permissionGranted = false;

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    final granted = await NotificationService.instance.isPermissionGranted();
    if (mounted) setState(() => _permissionGranted = granted);
  }

  Future<void> _requestPermission() async {
    final granted = await NotificationService.instance.requestPermission();
    if (mounted) setState(() => _permissionGranted = granted);
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(notificationSettingsProvider);
    final notifier = ref.read(notificationSettingsProvider.notifier);
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.notifications, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  context.l10n.settingsNotifications,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),

            // Master enable
            SwitchListTile(
              title: Text(context.l10n.settingsEnableNotifications),
              subtitle: Text(context.l10n.settingsEnableNotificationsDesc),
              value: settings.enabled,
              onChanged: (v) => notifier.update(settings.copyWith(enabled: v)),
            ),

            // Permission warning banner
            if (!_permissionGranted)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        context.l10n.settingsNotificationPermissionDenied,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _requestPermission,
                      child: Text(context.l10n.settingsAllow),
                    ),
                  ],
                ),
              ),

            const Divider(height: 8),

            // Sub-toggles — only enabled when master is on
            SwitchListTile(
              title: Text(context.l10n.settingsPrivateMessages),
              subtitle: const Text(
                'Notificar quando receber uma mensagem direta',
              ),
              value: settings.enabled && settings.privateMessages,
              onChanged:
                  settings.enabled
                      ? (v) =>
                          notifier.update(settings.copyWith(privateMessages: v))
                      : null,
            ),
            SwitchListTile(
              title: Text(context.l10n.settingsChannelMessages),
              subtitle: const Text('Notificar mensagens em canais'),
              value: settings.enabled && settings.channelMessages,
              onChanged:
                  settings.enabled
                      ? (v) =>
                          notifier.update(settings.copyWith(channelMessages: v))
                      : null,
            ),
            SwitchListTile(
              title: Text(context.l10n.settingsBackgroundOnly),
              subtitle: const Text(
                'Só notificar quando a app não está em primeiro plano',
              ),
              value: settings.onlyWhenBackground,
              onChanged:
                  settings.enabled
                      ? (v) => notifier.update(
                        settings.copyWith(onlyWhenBackground: v),
                      )
                      : null,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
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
          const SnackBar(
            content: Text(
              'Exportação falhou. O firmware pode não ter suporte activado.',
            ),
          ),
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
          const SnackBar(
            content: Text('Chave privada guardada com sucesso.'),
            duration: Duration(seconds: 3),
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
          subject: 'MeshCore — cópia da chave privada',
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
            title: const Text('Colar chave privada'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cola aqui a chave privada de uma cópia anterior (128 caracteres hex).',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  maxLines: 3,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                  decoration: const InputDecoration(
                    labelText: 'Chave privada (hex)',
                    hintText: '0a1b2c3d…',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                child: const Text('Continuar'),
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
          const SnackBar(
            content: Text(
              'Chave inválida — deve ter exactamente 128 caracteres hexadecimais.',
            ),
            duration: Duration(seconds: 4),
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
        const SnackBar(
          content: Text('Cópia guardada neste dispositivo.'),
          duration: Duration(seconds: 3),
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
            content: const Text(
              'Esta operação vai substituir a chave privada actual do rádio. '
              'O rádio vai reiniciar automaticamente após a importação.\n\n'
              'Tens a certeza?',
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
                ? 'Chave restaurada com sucesso. O rádio irá reiniciar.'
                : 'Restauro falhou. Firmware pode não ter suporte activado.',
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
            content: const Text(
              'A cópia da chave privada guardada neste dispositivo será eliminada. '
              'O rádio não é afectado.',
            ),
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
                'A chave privada identifica exclusivamente o teu rádio. '
                'Faz uma cópia para conseguires restaurar a identidade após reset.',
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
                      tooltip: 'Copiar chave completa',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _storedHex!));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Chave privada copiada'),
                            duration: Duration(seconds: 2),
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
                'Liga ao rádio para fazer cópia de segurança da chave.',
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
                      label: const Text('Guardar do rádio'),
                    ),
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _loadFromText,
                    icon: const Icon(Icons.paste, size: 18),
                    label: const Text('Colar chave'),
                  ),
                  // ── Share/send ───────────────────────────────────────────
                  if (_storedHex != null)
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _shareBackup,
                      icon: const Icon(Icons.share, size: 18),
                      label: const Text('Partilhar cópia'),
                    ),
                  // ── Send to radio ────────────────────────────────────────
                  if (_storedHex != null && isConnected)
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _restoreToRadio,
                      icon: const Icon(Icons.restore, size: 18),
                      label: const Text('Restaurar no rádio'),
                    ),
                  // ── Danger ───────────────────────────────────────────────
                  if (_storedHex != null)
                    TextButton.icon(
                      onPressed: _loading ? null : _deleteBackup,
                      style: TextButton.styleFrom(
                        foregroundColor: theme.colorScheme.error,
                      ),
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Apagar cópia local'),
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
