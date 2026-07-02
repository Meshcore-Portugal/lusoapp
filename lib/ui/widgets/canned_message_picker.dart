import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../providers/canned_messages_provider.dart';
import '../../providers/sos_settings_provider.dart';
import '../../services/sos_service.dart';

/// Compact icon-button + bottom sheet for picking a canned message.
///
/// Place this just before the send button in any chat composer. When the user
/// picks a message, [onPick] is called with its raw text — the host should
/// either insert it into the composer, send it directly, or both.
///
/// If the user activates the emergency SOS chip (by holding it), the
/// configured SOS is sent via [SosService] directly, without calling [onPick].
class CannedMessagePicker extends ConsumerWidget {
  const CannedMessagePicker({super.key, required this.onPick, this.tooltip});

  final ValueChanged<String> onPick;
  final String? tooltip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final messages = ref.watch(cannedMessagesProvider);
    final holdSeconds = ref.watch(sosSettingsProvider).holdDurationSeconds;
    return IconButton(
      tooltip: tooltip ?? context.l10n.cannedMessagesPickerTooltip,
      icon: Icon(Icons.bolt, color: theme.colorScheme.primary),
      onPressed:
          messages.isEmpty
              ? null
              : () => _showPicker(context, ref, messages, holdSeconds),
    );
  }

  Future<void> _showPicker(
    BuildContext context,
    WidgetRef ref,
    List<CannedMessage> messages,
    int holdSeconds,
  ) async {
    final picked = await showModalBottomSheet<CannedMessage>(
      context: context,
      isScrollControlled: true,
      builder:
          (ctx) =>
              _CannedPickerSheet(messages: messages, holdSeconds: holdSeconds),
    );
    if (picked == null) return;

    if (picked.isEmergency) {
      // Send the configured SOS instead of inserting text into the composer.
      final result = await ref.read(sosServiceProvider).sendConfiguredSos();
      if (!context.mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      switch (result.outcome) {
        case SosSendOutcome.sent:
          messenger.showSnackBar(
            SnackBar(content: Text(context.l10n.settingsSosSent)),
          );
        case SosSendOutcome.notConnected:
          messenger.showSnackBar(
            SnackBar(content: Text(context.l10n.settingsSosRadioNotConnected)),
          );
        case SosSendOutcome.missingContact:
          messenger.showSnackBar(
            SnackBar(content: Text(context.l10n.settingsSosMissingContact)),
          );
        case SosSendOutcome.permissionDenied:
        case SosSendOutcome.locationDisabled:
        case SosSendOutcome.failed:
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                result.detail?.isNotEmpty == true
                    ? context.l10n.settingsSosSendFailedDetail(result.detail!)
                    : context.l10n.settingsSosSendFailed,
              ),
            ),
          );
      }
    } else {
      onPick(picked.text);
    }
  }
}

class _CannedPickerSheet extends StatelessWidget {
  const _CannedPickerSheet({required this.messages, required this.holdSeconds});

  final List<CannedMessage> messages;
  final int holdSeconds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasEmergency = messages.any((m) => m.isEmergency);
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
            if (hasEmergency) ...[
              const SizedBox(height: 4),
              Text(
                context.l10n.cannedMessagesSosHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
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
                        if (isEmerg) {
                          return _SosHoldChip(
                            label: cm.displayLabel,
                            color: color,
                            holdSeconds: holdSeconds,
                            onComplete: () => Navigator.pop(context, cm),
                          );
                        }
                        return ActionChip(
                          backgroundColor: color.withAlpha(30),
                          side: BorderSide(color: color.withAlpha(80)),
                          label: Text(
                            cm.displayLabel,
                            style: TextStyle(color: color),
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

// ---------------------------------------------------------------------------
// Hold-to-send chip for emergency (SOS) canned messages
// ---------------------------------------------------------------------------

class _SosHoldChip extends StatefulWidget {
  const _SosHoldChip({
    required this.label,
    required this.color,
    required this.holdSeconds,
    required this.onComplete,
  });

  final String label;
  final Color color;
  final int holdSeconds;
  final VoidCallback onComplete;

  @override
  State<_SosHoldChip> createState() => _SosHoldChipState();
}

class _SosHoldChipState extends State<_SosHoldChip>
    with SingleTickerProviderStateMixin {
  late AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: Duration(seconds: widget.holdSeconds),
    )..addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        widget.onComplete();
      }
    });
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _start(TapDownDetails _) => _anim.forward();

  void _cancel([TapUpDetails? _]) {
    if (_anim.status != AnimationStatus.completed) _anim.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color;
    return GestureDetector(
      onTapDown: _start,
      onTapUp: _cancel,
      onTapCancel: () => _cancel(),
      child: AnimatedBuilder(
        animation: _anim,
        builder: (context, _) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: color.withAlpha((30 + (80 * _anim.value).round())),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withAlpha(80), width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: _anim.value,
                        strokeWidth: 2,
                        color: color,
                        backgroundColor: color.withAlpha(40),
                      ),
                      Icon(Icons.sos, size: 10, color: color),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  widget.label,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
