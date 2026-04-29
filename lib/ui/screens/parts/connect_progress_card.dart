part of '../connect_screen.dart';

// ---------------------------------------------------------------------------
// Connecting progress card
// ---------------------------------------------------------------------------

class _ConnectingCard extends StatelessWidget {
  const _ConnectingCard({
    required this.target,
    required this.stepLabel,
    required this.stepIndex,
    required this.totalSteps,
    required this.theme,
    required this.contactCount,
    required this.channelCount,
    required this.cachedContactCount,
    required this.cachedChannelCount,
  });

  final _ConnectTarget? target;
  final String stepLabel;
  final int stepIndex;
  final int totalSteps;
  final ThemeData theme;
  final int contactCount;
  final int channelCount;
  final int cachedContactCount;
  final int cachedChannelCount;

  static const _stepLabels = [
    'A ligar...',
    'A aguardar rádio...',
    'Informação do dispositivo',
    'Contactos',
    'Canais',
    'Concluído',
  ];

  @override
  Widget build(BuildContext context) {
    // Step 0 means we just started the transport connection — use indeterminate
    // bar. Steps 1–5 show determinate progress.
    final progress = stepIndex == 0 ? null : stepIndex / totalSteps;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Device name + icon
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircleAvatar(
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Icon(
                    target?.icon ?? Icons.bluetooth,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    target?.device.name ?? 'A ligar...',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: progress, minHeight: 6),
            ),
            const SizedBox(height: 12),

            // Current step label (animated crossfade)
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(
                stepLabel.isNotEmpty ? stepLabel : 'A ligar...',
                key: ValueKey(stepLabel),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withAlpha(180),
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 20),

            // Step checklist
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(_stepLabels.length - 1, (i) {
                // Step indices 1–5 correspond to label indices 1–5
                final done = stepIndex > i;
                final active = stepIndex == i + 1;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child:
                            done
                                ? Icon(
                                  Icons.check_circle,
                                  key: const ValueKey('done'),
                                  size: 18,
                                  color: theme.colorScheme.primary,
                                )
                                : active
                                ? SizedBox(
                                  key: const ValueKey('active'),
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: theme.colorScheme.primary,
                                  ),
                                )
                                : Icon(
                                  Icons.radio_button_unchecked,
                                  key: const ValueKey('pending'),
                                  size: 18,
                                  color: theme.colorScheme.onSurface.withAlpha(
                                    80,
                                  ),
                                ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _stepLabels[i + 1],
                        style: theme.textTheme.bodySmall?.copyWith(
                          color:
                              done
                                  ? theme.colorScheme.primary
                                  : active
                                  ? theme.colorScheme.onSurface
                                  : theme.colorScheme.onSurface.withAlpha(100),
                          fontWeight:
                              active ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      // Show count badge for contacts (i==2) and channels (i==3)
                      if ((i == 2 && contactCount > 0) ||
                          (i == 3 && channelCount > 0)) ...[
                        const SizedBox(width: 6),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: Builder(
                            builder: (context) {
                              final live = i == 2 ? contactCount : channelCount;
                              final cached =
                                  i == 2
                                      ? cachedContactCount
                                      : cachedChannelCount;
                              final newCount = (live - cached).clamp(0, live);
                              final badgeColor = (done
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.primaryContainer)
                                  .withAlpha(40);
                              final borderColor =
                                  done
                                      ? theme.colorScheme.primary.withAlpha(120)
                                      : theme.colorScheme.primary.withAlpha(80);
                              final baseStyle = theme.textTheme.labelSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 10,
                                  );
                              return Container(
                                key: ValueKey('${i}_$live'),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: badgeColor,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: borderColor,
                                    width: 0.8,
                                  ),
                                ),
                                child:
                                    cached > 0 && newCount > 0
                                        ? Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              '$cached',
                                              style: baseStyle?.copyWith(
                                                color: theme
                                                    .colorScheme
                                                    .onSurface
                                                    .withAlpha(110),
                                              ),
                                            ),
                                            Text(
                                              ' +$newCount',
                                              style: baseStyle?.copyWith(
                                                color:
                                                    theme.colorScheme.primary,
                                              ),
                                            ),
                                          ],
                                        )
                                        : Text(
                                          '$live',
                                          style: baseStyle?.copyWith(
                                            color:
                                                done
                                                    ? theme.colorScheme.primary
                                                    : theme
                                                        .colorScheme
                                                        .onSurface
                                                        .withAlpha(160),
                                          ),
                                        ),
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}
