part of '../settings_screen.dart';

/// Card that shows MeshRing controls (issue #58) — the master enable switch
/// and the minimum interval between rings. Per-contact "priority" membership
/// is managed from the contacts screen, not here.
class _MeshRingCard extends ConsumerWidget {
  const _MeshRingCard();

  static const List<int> _intervalChoicesMinutes = [1, 2, 5, 10, 15, 30];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(meshRingSettingsProvider);
    final notifier = ref.read(meshRingSettingsProvider.notifier);
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.phone_in_talk, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  context.l10n.settingsMeshRing,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),

            SwitchListTile(
              title: Text(context.l10n.settingsMeshRingEnable),
              subtitle: Text(context.l10n.settingsMeshRingEnableDesc),
              value: settings.enabled,
              onChanged: (v) => notifier.update(settings.copyWith(enabled: v)),
            ),

            ListTile(
              title: Text(context.l10n.settingsMeshRingInterval),
              subtitle: Text(context.l10n.settingsMeshRingIntervalDesc),
              enabled: settings.enabled,
              trailing: DropdownButton<int>(
                value: settings.minIntervalMinutes,
                onChanged:
                    settings.enabled
                        ? (v) {
                          if (v != null) {
                            notifier.update(
                              settings.copyWith(minIntervalMinutes: v),
                            );
                          }
                        }
                        : null,
                items: [
                  for (final minutes in _intervalChoicesMinutes)
                    DropdownMenuItem(value: minutes, child: Text('$minutes min')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
