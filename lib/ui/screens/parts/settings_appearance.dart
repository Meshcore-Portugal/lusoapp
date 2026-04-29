part of '../settings_screen.dart';

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
            const SizedBox(height: 4),
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

