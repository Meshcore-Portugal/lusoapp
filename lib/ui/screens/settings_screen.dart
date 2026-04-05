import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../protocol/protocol.dart';
import '../../providers/radio_providers.dart';
import '../../services/notification_service.dart';
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
                        'Identidade',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    title: const Text('Nome do Nó'),
                    subtitle: Text(selfInfo?.name ?? 'Não conectado'),
                    trailing: const Icon(Icons.edit),
                    onTap: () => _editName(context, ref),
                  ),
                  if (selfInfo != null)
                    ListTile(
                      title: const Text('Chave Pública'),
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
                        tooltip: 'Copiar chave pública',
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
                      title: const Text('Partilhar o meu contacto'),
                      subtitle: const Text('Mostra QR Code para partilhar'),
                      onTap: () => _showOwnQrCode(context, selfInfo),
                    ),
                ],
              ),
            ),
          ),
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
                        'Ligação',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    title: const Text('Estado'),
                    subtitle: Text(_connectionStateText(connectionState)),
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
                  if (connectionState == TransportState.connected) ...[
                    ListTile(
                      title: const Text('Configuração do Rádio'),
                      subtitle: const Text('LoRa, telemetria e dispositivo'),
                      leading: const Icon(Icons.settings_input_antenna),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/settings/radio'),
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
                        'Sobre',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const ListTile(
                    title: Text('MeshCore PT'),
                    subtitle: Text('Comunidade Portuguesa MeshCore'),
                  ),
                  ListTile(
                    title: const Text('Versão'),
                    subtitle: Text(_version.isEmpty ? '…' : _version),
                  ),
                  const ListTile(
                    title: Text('Protocolo'),
                    subtitle: Text('Companion Radio Protocol v3'),
                  ),
                  const ListTile(title: Text('Licença'), subtitle: Text('MIT')),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _connectionStateText(TransportState state) {
    switch (state) {
      case TransportState.connected:
        return 'Ligado';
      case TransportState.connecting:
        return 'A ligar...';
      case TransportState.scanning:
        return 'A procurar...';
      case TransportState.error:
        return 'Erro de ligacao';
      case TransportState.disconnected:
        return 'Desligado';
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
                child: const Text('Fechar'),
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
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () {
                  final name = controller.text.trim();
                  if (name.isNotEmpty) {
                    ref.read(radioServiceProvider)?.setAdvertName(name);
                    // Update local state immediately — the radio sends only
                    // respOk after SET_ADVERT_NAME, not a new SelfInfo, so we
                    // must refresh the provider ourselves.
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
                child: const Text('Guardar'),
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
            title: const Text('Escolher cor'),
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
                child: const Text('Cancelar'),
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

    Widget colorRow(String label, Color color, Future<void> Function(Color) onPick) {
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
              border: Border.all(
                color: theme.colorScheme.outlineVariant,
              ),
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
                  'Aparência',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            colorRow(
              'Menção própria (@[Você])',
              selfColor,
              (c) => ref.read(selfMentionColorProvider.notifier).setColor(c),
            ),
            colorRow(
              'Menção de outros (@[Nome])',
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
                  'Notificações',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),

            // Master enable
            SwitchListTile(
              title: const Text('Activar notificações'),
              subtitle: const Text('Mostrar alertas para novas mensagens'),
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
                        'Permissão de notificação não concedida.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _requestPermission,
                      child: const Text('Permitir'),
                    ),
                  ],
                ),
              ),

            const Divider(height: 8),

            // Sub-toggles — only enabled when master is on
            SwitchListTile(
              title: const Text('Mensagens privadas'),
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
              title: const Text('Mensagens de canal'),
              subtitle: const Text('Notificar mensagens em canais'),
              value: settings.enabled && settings.channelMessages,
              onChanged:
                  settings.enabled
                      ? (v) =>
                          notifier.update(settings.copyWith(channelMessages: v))
                      : null,
            ),
            SwitchListTile(
              title: const Text('Apenas em segundo plano'),
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
