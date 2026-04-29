part of '../plan333_screen.dart';

// ============================================================================
// Config card
// ============================================================================

class _ConfigCard extends StatelessWidget {
  const _ConfigCard({
    required this.config,
    required this.nameCtrl,
    required this.cityCtrl,
    required this.localityCtrl,
    required this.dirty,
    required this.onDirty,
    required this.onSave,
    required this.onAutoSendChanged,
  });

  final Plan333Config config;
  final TextEditingController nameCtrl;
  final TextEditingController cityCtrl;
  final TextEditingController localityCtrl;
  final bool dirty;
  final VoidCallback onDirty;
  final VoidCallback onSave;
  final void Function(bool) onAutoSendChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.settings, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  context.l10n.plan333ConfigTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (dirty)
                  FilledButton(
                    onPressed: onSave,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(80, 32),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    child: Text(context.l10n.commonSave),
                  ),
              ],
            ),
            const SizedBox(height: 14),

            // Station name
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(
                labelText: context.l10n.plan333StationName,
                hintText: context.l10n.plan333StationNameHint,
              ),
              onChanged: (_) => onDirty(),
            ),
            const SizedBox(height: 10),

            // City + Locality
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: cityCtrl,
                    decoration: InputDecoration(
                      labelText: context.l10n.plan333City,
                      hintText: context.l10n.plan333CityHint,
                    ),
                    onChanged: (_) => onDirty(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: localityCtrl,
                    decoration: InputDecoration(
                      labelText: context.l10n.plan333Locality,
                      hintText: context.l10n.plan333LocalityHint,
                    ),
                    onChanged: (_) => onDirty(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Auto-send toggle
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.l10n.plan333AutoSend),
              subtitle: Text(context.l10n.plan333AutoSendDesc),
              value: config.autoSendCq,
              onChanged: onAutoSendChanged,
            ),

            // CQ preview
            if (config.isConfigured) ...[
              const Divider(height: 16),
              Text(
                context.l10n.plan333CqMessageLabel,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              _InlinePhrase(text: config.cqMessage),
            ],
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Message formats card
// ============================================================================

class _FormatsCard extends StatelessWidget {
  const _FormatsCard({required this.config});
  final Plan333Config config;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cq =
        config.isConfigured
            ? config.cqMessage
            : context.l10n.plan333FormatCqTemplate;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.chat_bubble_outline,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  context.l10n.plan333FormatTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // CQ format (filled from config if available)
            _PhraseRow(
              label: context.l10n.plan333FormatPresence,
              phase: context.l10n.plan333FormatPresencePhase,
              phrase: cq,
            ),
            // const Divider(height: 20),

            // MeshCore instructions
            // Container(
            //   padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            //   decoration: BoxDecoration(
            //     color: theme.colorScheme.surfaceContainerHighest,
            //     borderRadius: BorderRadius.circular(8),
            //     border: Border.all(color: theme.colorScheme.outlineVariant),
            //   ),
            //   child: Text(
            //     'MeshCore: canal #plano333 · presença 21:00–21:30 · '
            //     'QSL 21:30–22:00 · relatório em meshcore.pt/pt/projects/plano333',
            //     style: theme.textTheme.bodySmall?.copyWith(
            //       color: theme.colorScheme.onSurfaceVariant,
            //     ),
            //   ),
            // ),
          ],
        ),
      ),
    );
  }
}

