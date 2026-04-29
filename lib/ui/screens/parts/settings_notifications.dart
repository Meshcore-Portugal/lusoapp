part of '../settings_screen.dart';

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
