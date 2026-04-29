part of '../plan333_screen.dart';

// ============================================================================
// Mesh 3-3-3 status card
// ============================================================================

class _MeshStatusCard extends StatelessWidget {
  const _MeshStatusCard({
    required this.now,
    required this.meshActive,
    required this.nextMesh,
    required this.config,
    required this.autoState,
    required this.radioConnected,
    required this.onSendCq,
    required this.onAbort,
  });

  final DateTime now;
  final bool meshActive;
  final DateTime nextMesh;
  final Plan333Config config;
  final Plan333AutoSendState autoState;
  final bool radioConnected;
  final VoidCallback onSendCq;
  final VoidCallback onAbort;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = meshActive ? const Color(0xFF00E676) : AppTheme.primary;
    final remaining = nextMesh.difference(now);

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: accent.withAlpha(meshActive ? 200 : 80),
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.hub, color: accent, size: 22),
                const SizedBox(width: 8),
                Text(
                  context.l10n.plan333CardTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: accent,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                if (meshActive)
                  Flexible(
                    child: _Pill(
                      label: context.l10n.plan333EventActive,
                      color: const Color(0xFF00E676),
                    ),
                  )
                else
                  Flexible(
                    child: _Pill(
                      label: _daysLabel(remaining),
                      color: theme.colorScheme.onSurfaceVariant,
                      border: true,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // State description
            if (meshActive) ...[
              // CQ sent status — 3 dots
              Row(
                children: [
                  Text(
                    context.l10n.plan333CqSent,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ...List.generate(3, (i) {
                    final sent = i < autoState.cqSentCount;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(
                        sent
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color:
                            sent
                                ? const Color(0xFF00E676)
                                : theme.colorScheme.onSurfaceVariant,
                        size: 20,
                      ),
                    );
                  }),
                  if (autoState.lastCqTime != null)
                    Text(
                      '${context.l10n.plan333LastSent} ${_fmtTime(autoState.lastCqTime!)})',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 12),

              // Send button
              _SendButton(
                config: config,
                autoState: autoState,
                radioConnected: radioConnected,
                onTap: onSendCq,
              ),
              const SizedBox(height: 8),

              // Abort / aborted indicator
              if (autoState.aborted)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer.withAlpha(140),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.block,
                        size: 16,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          context.l10n.plan333AbortedMessage,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else if (config.autoSendCq && meshActive)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onAbort,
                    icon: const Icon(Icons.stop_circle_outlined, size: 16),
                    label: Text(context.l10n.plan333AbortAutoSend),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                      side: BorderSide(color: theme.colorScheme.error),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
            ] else ...[
              // Countdown to next event
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Flexible(
                    child: Text(
                      _fmtDate(nextMesh),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'em ${_fmtRemaining(remaining)}',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                context.l10n.plan333EventSchedule,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],

            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 8),
            // Report link teaser
            Row(
              children: [
                Icon(
                  Icons.bar_chart,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${context.l10n.plan333ReportPrefix} ${Plan333Service.reportUrl}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _daysLabel(Duration d) {
    if (d.inMinutes < 60) return 'em ${d.inMinutes}m';
    if (d.inHours < 24) return 'em ${d.inHours}h ${(d.inMinutes % 60)}m';
    return 'em ${d.inDays}d ${d.inHours % 24}h';
  }

  String _fmtDate(DateTime d) {
    const days = ['', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];
    return '${days[d.weekday]} ${d.day}/${d.month} ${d.hour.toString().padLeft(2, '0')}:00';
  }

  String _fmtRemaining(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
    return '${m}m ${(d.inSeconds % 60).toString().padLeft(2, '0')}s';
  }

  String _fmtTime(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

// ── Send button ──────────────────────────────────────────────────────────────

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.config,
    required this.autoState,
    required this.radioConnected,
    required this.onTap,
  });

  final Plan333Config config;
  final Plan333AutoSendState autoState;
  final bool radioConnected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final allSent = autoState.cqSentCount >= 3;
    final canSend = config.isConfigured && radioConnected && !allSent;
    final Color color;
    final String label;

    if (allSent) {
      color = const Color(0xFF00E676);
      label = context.l10n.plan333AllSent;
    } else if (!config.isConfigured) {
      color = Colors.grey;
      label = context.l10n.plan333ConfigureFirst;
    } else if (!radioConnected) {
      color = AppTheme.primary;
      label = context.l10n.plan333RadioOff;
    } else {
      color = const Color(0xFF00E676);
      label = context.l10n.plan333SendCqButton(autoState.cqSentCount + 1);
    }

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: canSend ? onTap : null,
        icon: Icon(allSent ? Icons.check_circle : Icons.send, size: 18),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: canSend ? color.withAlpha(200) : null,
          foregroundColor: canSend ? Colors.black87 : null,
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }
}

