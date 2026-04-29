part of '../radio_settings_screen.dart';

// Advert auto-add card
// ---------------------------------------------------------------------------

class _AdvertAutoAddCard extends ConsumerStatefulWidget {
  const _AdvertAutoAddCard();

  @override
  ConsumerState<_AdvertAutoAddCard> createState() => _AdvertAutoAddCardState();
}

class _AdvertAutoAddCardState extends ConsumerState<_AdvertAutoAddCard> {
  final _maxHopsCtrl = TextEditingController();
  bool _maxHopsInitialized = false;

  @override
  void dispose() {
    _maxHopsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final s = ref.watch(advertAutoAddProvider);
    final n = ref.read(advertAutoAddProvider.notifier);

    // Sync max-hops field once after the settings are loaded.
    if (!_maxHopsInitialized) {
      _maxHopsInitialized = true;
      _maxHopsCtrl.text = s.maxHops != null ? '${s.maxHops}' : '';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Title ──────────────────────────────────────────────────────
            Row(
              children: [
                Icon(
                  Icons.person_add_alt_1,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.radioSettingsAutoAddTitle,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── Auto Add All ───────────────────────────────────────────────
            RadioListTile<bool>(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(
                l10n.radioSettingsAutoAddAll,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                l10n.radioSettingsAutoAddAllDesc,
                style: theme.textTheme.bodySmall,
              ),
              value: true,
              groupValue: s.addAll,
              onChanged: (_) => n.setAddAll(true),
            ),

            // ── Auto Add Selected ──────────────────────────────────────────
            RadioListTile<bool>(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(
                l10n.radioSettingsAutoAddSelected,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                l10n.radioSettingsAutoAddSelectedDesc,
                style: theme.textTheme.bodySmall,
              ),
              value: false,
              groupValue: s.addAll,
              onChanged: (_) => n.setAddAll(false),
            ),

            // Per-type checkboxes — only relevant in "selected" mode.
            AnimatedOpacity(
              opacity: s.addAll ? 0.4 : 1.0,
              duration: const Duration(milliseconds: 200),
              child: Column(
                children: [
                  _TypeCheckTile(
                    icon: Icons.person,
                    label: l10n.radioSettingsAutoAddCompanion,
                    value: s.addChat,
                    onChanged: s.addAll ? null : n.setChat,
                  ),
                  _TypeCheckTile(
                    icon: Icons.cell_tower,
                    label: l10n.radioSettingsAutoAddRepeater,
                    value: s.addRepeater,
                    onChanged: s.addAll ? null : n.setRepeater,
                  ),
                  _TypeCheckTile(
                    icon: Icons.meeting_room,
                    label: l10n.radioSettingsAutoAddRoom,
                    value: s.addRoom,
                    onChanged: s.addAll ? null : n.setRoom,
                  ),
                  _TypeCheckTile(
                    icon: Icons.sensors,
                    label: l10n.radioSettingsAutoAddSensor,
                    value: s.addSensor,
                    onChanged: s.addAll ? null : n.setSensor,
                  ),
                ],
              ),
            ),

            const Divider(height: 24),

            // ── Overwrite Oldest ───────────────────────────────────────────
            _DescCheckTile(
              title: l10n.radioSettingsOverwriteOldest,
              subtitle: l10n.radioSettingsOverwriteOldestDesc,
              value: s.overwriteOldest,
              onChanged: n.setOverwriteOldest,
            ),

            const SizedBox(height: 12),

            // ── Auto Add Max Hops ──────────────────────────────────────────
            Text(
              l10n.radioSettingsAutoAddMaxHops,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.radioSettingsAutoAddMaxHopsDesc,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _maxHopsCtrl,
              decoration: InputDecoration(
                hintText: l10n.radioSettingsAutoAddMaxHopsHint,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              keyboardType: TextInputType.number,
              onChanged: (v) {
                final parsed = int.tryParse(v.trim());
                if (v.trim().isEmpty) {
                  n.setMaxHops(null);
                } else if (parsed != null && parsed >= 0 && parsed <= 63) {
                  n.setMaxHops(parsed);
                }
              },
            ),

            const Divider(height: 24),

            // ── Pull To Refresh ────────────────────────────────────────────
            _DescCheckTile(
              title: l10n.radioSettingsPullToRefresh,
              subtitle: l10n.radioSettingsPullToRefreshDesc,
              value: s.pullToRefresh,
              onChanged: n.setPullToRefresh,
            ),

            // ── Show Public Keys ───────────────────────────────────────────
            _DescCheckTile(
              title: l10n.radioSettingsShowPublicKeys,
              subtitle: l10n.radioSettingsShowPublicKeysDesc,
              value: s.showPublicKeys,
              onChanged: n.setShowPublicKeys,
            ),
          ],
        ),
      ),
    );
  }
}

/// Checkbox tile for per-type auto-add (with icon).
class _TypeCheckTile extends StatelessWidget {
  const _TypeCheckTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      dense: true,
      contentPadding: const EdgeInsets.only(left: 8),
      secondary: Icon(icon, size: 20),
      title: Text(label),
      value: value,
      onChanged: onChanged != null ? (v) => onChanged!(v ?? false) : null,
      controlAffinity: ListTileControlAffinity.trailing,
    );
  }
}

/// Checkbox tile with a title and subtitle description line.
class _DescCheckTile extends StatelessWidget {
  const _DescCheckTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      onChanged: (v) => onChanged(v ?? false),
      controlAffinity: ListTileControlAffinity.trailing,
    );
  }
}
