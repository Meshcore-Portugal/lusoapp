part of '../plan333_screen.dart';


// ============================================================================
// CQ log card (stations heard)
// ============================================================================

class _QslCard extends ConsumerWidget {
  const _QslCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final log = ref.watch(qslLogProvider);
    final config = ref.watch(plan333ConfigProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row ──────────────────────────────────────────────────
            Row(
              children: [
                const Icon(Icons.verified_outlined, color: AppTheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.l10n.plan333StationsHeard,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 2,
                runSpacing: 2,
                children: [
                  if (log.isNotEmpty) ...[
                    // Share button
                    IconButton(
                      icon: const Icon(Icons.share_outlined),
                      tooltip: context.l10n.plan333ShareLog,
                      onPressed: () => _share(log, config),
                    ),
                    // Clear button
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: context.l10n.plan333ClearLog,
                      onPressed: () => _confirmClear(context, ref),
                    ),
                  ],
                  // Debug inject button (debug builds only)
                  if (kDebugMode)
                    IconButton(
                      icon: const Icon(Icons.bug_report_outlined),
                      tooltip: 'Injectar CQ de teste',
                      onPressed: () {
                        final r = Plan333Service.tryParseCq(
                          'CQ Plano 333, Daytona, Tomar, Nabão',
                          pathLen: 3,
                        );
                        if (r != null) {
                          ref.read(qslLogProvider.notifier).add(r);
                        }
                      },
                    ),
                  // Add button
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    tooltip: context.l10n.plan333AddQslTitle,
                    color: AppTheme.primary,
                    onPressed: () => _showAddDialog(context, ref),
                  ),
                ],
              ),
            ),

            // ── Empty state ─────────────────────────────────────────────────
            if (log.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  context.l10n.plan333NoStationsYet,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),

            // ── Log entries ─────────────────────────────────────────────────
            if (log.isNotEmpty) ...[
              const Divider(height: 16),
              for (var i = 0; i < log.length; i++) ...[
                _QslRow(
                  record: log[i],
                  onDelete: () => ref.read(qslLogProvider.notifier).remove(i),
                  theme: theme,
                ),
                if (i < log.length - 1) const Divider(height: 12),
              ],
            ],
          ],
        ),
      ),
    );
  }

  void _showAddDialog(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder:
          (_) => _AddQslDialog(
            onSave: (r) => ref.read(qslLogProvider.notifier).add(r),
          ),
    );
  }

  void _confirmClear(BuildContext context, WidgetRef ref) {
    showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(context.l10n.plan333ClearQslTitle),
            content: Text(context.l10n.plan333ClearQslContent),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: () {
                  ref.read(qslLogProvider.notifier).clearAll();
                  Navigator.pop(ctx);
                },
                child: const Text('Limpar'),
              ),
            ],
          ),
    );
  }

  void _share(List<QslRecord> log, Plan333Config config) {
    final now = DateTime.now();
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final station = config.stationName.isNotEmpty ? config.stationName : '?';
    final location = config.city.isNotEmpty ? config.city : '';

    final lines = StringBuffer();
    lines.writeln('=== Mesh 3-3-3 — $dateStr ===');
    if (location.isNotEmpty) {
      lines.writeln('Estação: $station | $location');
    } else {
      lines.writeln('Estação: $station');
    }
    lines.writeln('Estações ouvidas (${log.length}):');
    for (var i = 0; i < log.length; i++) {
      final r = log[i];
      final loc = r.location.isNotEmpty ? ' | ${r.location}' : '';
      final notes = r.notes.isNotEmpty ? ' (${r.notes})' : '';
      lines.writeln('${i + 1}. ${r.stationName} | ${r.hopsLabel}$loc$notes');
    }
    lines.writeln('73! de $station');
    lines.write('#MeshCore #Plano333');

    SharePlus.instance.share(ShareParams(text: lines.toString()));
  }
}

// ---------------------------------------------------------------------------
// Single station row
// ---------------------------------------------------------------------------

class _QslRow extends StatelessWidget {
  const _QslRow({
    required this.record,
    required this.onDelete,
    required this.theme,
  });

  final QslRecord record;
  final VoidCallback onDelete;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.check_circle_outline,
          size: 16,
          color: Color(0xFF00E676),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                record.stationName,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                [
                  record.hopsLabel,
                  if (record.location.isNotEmpty) record.location,
                  if (record.notes.isNotEmpty) record.notes,
                ].join('  ·  '),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        InkWell(
          onTap: onDelete,
          borderRadius: BorderRadius.circular(12),
          child: const Padding(
            padding: EdgeInsets.all(4),
            child: Icon(Icons.close, size: 16),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Add station dialog
// ---------------------------------------------------------------------------

class _AddQslDialog extends StatefulWidget {
  const _AddQslDialog({required this.onSave});
  final void Function(QslRecord) onSave;

  @override
  State<_AddQslDialog> createState() => _AddQslDialogState();
}

class _AddQslDialogState extends State<_AddQslDialog> {
  final _stationCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  int _hops = 0; // 0 = Direct

  @override
  void dispose() {
    _stationCtrl.dispose();
    _locationCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.plan333AddQslTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _stationCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: context.l10n.plan333StationLabel,
                hintText: context.l10n.plan333StationHint,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Hops: '),
                const SizedBox(width: 8),
                DropdownButton<int>(
                  value: _hops,
                  items: [
                    const DropdownMenuItem(value: 0, child: Text('Direto')),
                    for (var h = 1; h <= 10; h++)
                      DropdownMenuItem(value: h, child: Text('$h')),
                  ],
                  onChanged: (v) => setState(() => _hops = v ?? 0),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _locationCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: context.l10n.plan333LocationLabel,
                hintText: context.l10n.plan333LocationHint,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesCtrl,
              decoration: InputDecoration(
                labelText: context.l10n.plan333NotesLabel,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _stationCtrl.text.trim().isEmpty ? null : _save,
          child: const Text('Guardar'),
        ),
      ],
    );
  }

  void _save() {
    final station = _stationCtrl.text.trim();
    if (station.isEmpty) return;
    widget.onSave(
      QslRecord(
        stationName: station,
        hops: _hops,
        location: _locationCtrl.text.trim(),
        timestamp: DateTime.now(),
        notes: _notesCtrl.text.trim(),
      ),
    );
    Navigator.pop(context);
  }
}
