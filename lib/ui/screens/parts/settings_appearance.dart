part of '../settings_screen.dart';

// ---------------------------------------------------------------------------
// Appearance card — theme mode, accent colour, mention pill colours
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
              spacing: 10,
              runSpacing: 10,
              children:
                  _swatches.map((c) {
                    final selected = c == current;
                    return GestureDetector(
                      onTap: () => Navigator.pop(ctx, c),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
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
                                      color: c.withValues(alpha: 0.55),
                                      blurRadius: 8,
                                      spreadRadius: 1,
                                    ),
                                  ]
                                  : null,
                        ),
                        child:
                            selected
                                ? const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 18,
                                )
                                : null,
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
    final accent = ref.watch(accentColorProvider);

    // A tappable colour pill used for mention colour rows.
    Widget pillButton(Color color, VoidCallback onTap) {
      final fg = color.computeLuminance() > 0.45 ? Colors.black : Colors.white;
      return GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: theme.colorScheme.outlineVariant,
              width: 1,
            ),
          ),
          child: Text(
            '@nome',
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ───────────────────────────────────────────────────
            Row(
              children: [
                Icon(Icons.palette_outlined, color: theme.colorScheme.primary),
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

            // ── Theme mode ───────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                context.l10n.settingsTheme,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<ThemeMode>(
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  textStyle: theme.textTheme.labelMedium,
                  visualDensity: VisualDensity.compact,
                ),
                segments: [
                  ButtonSegment(
                    value: ThemeMode.system,
                    icon: const Icon(Icons.brightness_auto_outlined, size: 16),
                    label: Text(context.l10n.settingsThemeSystem),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    icon: const Icon(Icons.light_mode_outlined, size: 16),
                    label: Text(context.l10n.settingsThemeLight),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    icon: const Icon(Icons.dark_mode_outlined, size: 16),
                    label: Text(context.l10n.settingsThemeDark),
                  ),
                ],
                selected: {themeMode},
                onSelectionChanged:
                    (s) => ref.read(themeModeProvider.notifier).set(s.first),
              ),
            ),
            const SizedBox(height: 14),
            const Divider(height: 1),

            // ── Accent colour ────────────────────────────────────────────
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              title: Text(context.l10n.settingsAccent),
              subtitle: Text(
                accent == null
                    ? context.l10n.settingsAccentDefault
                    : context.l10n.settingsAccentCustom,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (accent != null)
                    IconButton(
                      tooltip: context.l10n.settingsAccentReset,
                      icon: Icon(
                        Icons.restart_alt,
                        size: 20,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      onPressed:
                          () =>
                              ref.read(accentColorProvider.notifier).set(null),
                    ),
                  GestureDetector(
                    onTap: () async {
                      final picked = await _pickColor(
                        context,
                        accent ?? AppTheme.primary,
                      );
                      if (picked != null) {
                        await ref
                            .read(accentColorProvider.notifier)
                            .set(picked);
                      }
                    },
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: accent ?? AppTheme.primary,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // ── Mention pill colours ─────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
              child: Text(
                context.l10n.settingsMentionColors,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              title: Text(context.l10n.settingsSelfMention),
              trailing: pillButton(selfColor, () async {
                final picked = await _pickColor(context, selfColor);
                if (picked != null) {
                  await ref
                      .read(selfMentionColorProvider.notifier)
                      .setColor(picked);
                }
              }),
            ),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              title: Text(context.l10n.settingsOtherMention),
              trailing: pillButton(otherColor, () async {
                final picked = await _pickColor(context, otherColor);
                if (picked != null) {
                  await ref
                      .read(otherMentionColorProvider.notifier)
                      .setColor(picked);
                }
              }),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}
