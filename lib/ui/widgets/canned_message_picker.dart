import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../providers/canned_messages_provider.dart';

/// Compact icon-button + bottom sheet for picking a canned message.
///
/// Place this just before the send button in any chat composer. When the user
/// picks a message, [onPick] is called with its raw text — the host should
/// either insert it into the composer, send it directly, or both.
class CannedMessagePicker extends ConsumerWidget {
  const CannedMessagePicker({super.key, required this.onPick, this.tooltip});

  final ValueChanged<String> onPick;
  final String? tooltip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final messages = ref.watch(cannedMessagesProvider);
    return IconButton(
      tooltip: tooltip ?? context.l10n.cannedMessagesPickerTooltip,
      icon: Icon(Icons.bolt, color: theme.colorScheme.primary),
      onPressed:
          messages.isEmpty ? null : () => _showPicker(context, ref, messages),
    );
  }

  Future<void> _showPicker(
    BuildContext context,
    WidgetRef ref,
    List<CannedMessage> messages,
  ) async {
    final picked = await showModalBottomSheet<CannedMessage>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _CannedPickerSheet(messages: messages),
    );
    if (picked != null) onPick(picked.text);
  }
}

class _CannedPickerSheet extends StatelessWidget {
  const _CannedPickerSheet({required this.messages});
  final List<CannedMessage> messages;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Row(
              children: [
                Icon(Icons.bolt, color: theme.colorScheme.primary, size: 20),
                const SizedBox(width: 6),
                Text(
                  context.l10n.cannedMessagesPickerTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              context.l10n.cannedMessagesPickerSubtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children:
                      messages.map((cm) {
                        final isEmerg = cm.isEmergency;
                        final color =
                            isEmerg
                                ? theme.colorScheme.error
                                : theme.colorScheme.primary;
                        return ActionChip(
                          backgroundColor: color.withAlpha(30),
                          side: BorderSide(color: color.withAlpha(80)),
                          avatar:
                              isEmerg
                                  ? Icon(Icons.sos, size: 16, color: color)
                                  : null,
                          label: Text(
                            cm.displayLabel,
                            style: TextStyle(
                              color: color,
                              fontWeight: isEmerg ? FontWeight.bold : null,
                            ),
                          ),
                          onPressed: () => Navigator.pop(context, cm),
                        );
                      }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
