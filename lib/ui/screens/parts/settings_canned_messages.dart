part of '../settings_screen.dart';

// ---------------------------------------------------------------------------
// Canned messages card — manage the user's quick-reply library
// ---------------------------------------------------------------------------

class _CannedMessagesCard extends ConsumerWidget {
  const _CannedMessagesCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final messages = ref.watch(cannedMessagesProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bolt, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.l10n.cannedMessagesTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: context.l10n.cannedMessagesAdd,
                  icon: const Icon(Icons.add),
                  onPressed: () => _showEditor(context, ref, null),
                ),
                PopupMenuButton<String>(
                  tooltip: '',
                  icon: const Icon(Icons.more_vert),
                  itemBuilder:
                      (_) => [
                        PopupMenuItem(
                          value: 'reset',
                          child: Row(
                            children: [
                              const Icon(Icons.restart_alt, size: 18),
                              const SizedBox(width: 8),
                              Text(context.l10n.cannedMessagesReset),
                            ],
                          ),
                        ),
                      ],
                  onSelected: (v) async {
                    if (v == 'reset') {
                      final ok = await _confirmReset(context);
                      if (ok == true) {
                        await ref
                            .read(cannedMessagesProvider.notifier)
                            .resetToDefaults();
                      }
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              context.l10n.cannedMessagesSubtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            if (messages.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  context.l10n.cannedMessagesEmpty,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: messages.length,
                onReorder:
                    (a, b) =>
                        ref.read(cannedMessagesProvider.notifier).reorder(a, b),
                itemBuilder: (context, i) {
                  final cm = messages[i];
                  return _CannedMessageTile(
                    key: ValueKey(cm.id),
                    index: i,
                    message: cm,
                    onEdit: () => _showEditor(context, ref, cm),
                    onDelete: () async {
                      final ok = await _confirmDelete(context, cm);
                      if (ok == true) {
                        await ref
                            .read(cannedMessagesProvider.notifier)
                            .remove(cm.id);
                      }
                    },
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showEditor(
    BuildContext context,
    WidgetRef ref,
    CannedMessage? existing,
  ) async {
    final result = await showModalBottomSheet<_CannedEditResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CannedMessageEditor(existing: existing),
    );
    if (result == null) return;
    final notifier = ref.read(cannedMessagesProvider.notifier);
    if (existing == null) {
      await notifier.add(
        text: result.text,
        label: result.label,
        isEmergency: result.isEmergency,
      );
    } else {
      await notifier.update(
        existing.id,
        text: result.text,
        label: result.label,
        isEmergency: result.isEmergency,
      );
    }
  }

  Future<bool?> _confirmDelete(BuildContext context, CannedMessage cm) {
    return showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(context.l10n.cannedMessagesDeleteTitle),
            content: Text(
              context.l10n.cannedMessagesDeleteConfirm(cm.displayLabel),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(context.l10n.commonCancel),
              ),
              FilledButton.tonal(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(context.l10n.commonDelete),
              ),
            ],
          ),
    );
  }

  Future<bool?> _confirmReset(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(context.l10n.cannedMessagesResetTitle),
            content: Text(context.l10n.cannedMessagesResetConfirm),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(context.l10n.commonCancel),
              ),
              FilledButton.tonal(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(context.l10n.commonReset),
              ),
            ],
          ),
    );
  }
}

class _CannedMessageTile extends StatelessWidget {
  const _CannedMessageTile({
    super.key,
    required this.index,
    required this.message,
    required this.onEdit,
    required this.onDelete,
  });

  final int index;
  final CannedMessage message;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent =
        message.isEmergency
            ? theme.colorScheme.error
            : theme.colorScheme.primary;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withAlpha(20),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withAlpha(60), width: 1),
      ),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Icon(
                Icons.drag_handle,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (message.isEmergency)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Icon(Icons.sos, size: 18, color: accent),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.displayLabel,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (message.label != null && message.label!.isNotEmpty)
                  Text(
                    message.text,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.edit_outlined, size: 18),
            onPressed: onEdit,
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Editor sheet
// ---------------------------------------------------------------------------

class _CannedEditResult {
  _CannedEditResult({
    required this.text,
    required this.label,
    required this.isEmergency,
  });
  final String text;
  final String? label;
  final bool isEmergency;
}

class _CannedMessageEditor extends StatefulWidget {
  const _CannedMessageEditor({this.existing});
  final CannedMessage? existing;

  @override
  State<_CannedMessageEditor> createState() => _CannedMessageEditorState();
}

class _CannedMessageEditorState extends State<_CannedMessageEditor> {
  late final TextEditingController _textCtrl;
  late final TextEditingController _labelCtrl;
  late bool _isEmergency;

  @override
  void initState() {
    super.initState();
    _textCtrl = TextEditingController(text: widget.existing?.text ?? '');
    _labelCtrl = TextEditingController(text: widget.existing?.label ?? '');
    _isEmergency = widget.existing?.isEmergency ?? false;
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _labelCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEdit = widget.existing != null;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isEdit
                ? context.l10n.cannedMessagesEditTitle
                : context.l10n.cannedMessagesAddTitle,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _labelCtrl,
            maxLength: 24,
            decoration: InputDecoration(
              labelText: context.l10n.cannedMessagesLabelHint,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _textCtrl,
            maxLength: 140,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: context.l10n.cannedMessagesTextHint,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _isEmergency,
            onChanged: (v) => setState(() => _isEmergency = v),
            title: Row(
              children: [
                Icon(Icons.sos, color: theme.colorScheme.error, size: 20),
                const SizedBox(width: 6),
                Text(context.l10n.cannedMessagesEmergencyToggle),
              ],
            ),
            subtitle: Text(
              context.l10n.cannedMessagesEmergencyDesc,
              style: theme.textTheme.bodySmall,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(context.l10n.commonCancel),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () {
                  final text = _textCtrl.text.trim();
                  if (text.isEmpty) return;
                  final label = _labelCtrl.text.trim();
                  Navigator.pop(
                    context,
                    _CannedEditResult(
                      text: text,
                      label: label.isEmpty ? null : label,
                      isEmergency: _isEmergency,
                    ),
                  );
                },
                child: Text(context.l10n.commonSave),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
