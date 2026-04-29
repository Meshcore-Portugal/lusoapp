part of '../plan333_screen.dart';

// ============================================================================
// Debug automation test card (debug builds only)
// ============================================================================

class _DebugAutomationCard extends ConsumerWidget {
  const _DebugAutomationCard({
    required this.debugNow,
    required this.onSimulate,
  });

  /// Currently active simulated time, or null when real clock is in use.
  final DateTime? debugNow;

  /// Called with a new simulated DateTime to freeze the screen display,
  /// or null to restore the real clock.
  final void Function(DateTime?) onSimulate;

  static DateTime _nextSaturdayAt(int hour, int minute) {
    final now = DateTime.now();
    var d = DateTime(now.year, now.month, now.day, hour, minute);
    if (d.isBefore(now)) d = d.add(const Duration(days: 1));
    while (d.weekday != DateTime.saturday) {
      d = d.add(const Duration(days: 1));
    }
    return d;
  }

  static String _hm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  /// Sets the screen simulated time AND triggers one automation pass at that
  /// time so sent-counters advance exactly as they would in production.
  void _activate(
    BuildContext context,
    WidgetRef ref,
    DateTime sim,
    String label,
  ) {
    onSimulate(sim);
    ref.read(plan333AutoSendProvider.notifier).debugRunAutomationAt(sim);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Debug: a simular $label  (${_hm(sim)})'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final autoState = ref.watch(plan333AutoSendProvider);
    final isSimulating = debugNow != null;

    // Pre-compute preset DateTimes (next Saturday at each slot).
    final cq1 = _nextSaturdayAt(21, 3);
    final cq2 = _nextSaturdayAt(21, 23);
    final cq3 = _nextSaturdayAt(21, 43);

    bool isActive(DateTime candidate) =>
        debugNow != null &&
        debugNow!.hour == candidate.hour &&
        debugNow!.minute == candidate.minute;

    final cardColor =
        isSimulating
            ? theme.colorScheme.errorContainer.withAlpha(180)
            : theme.colorScheme.secondaryContainer.withAlpha(140);

    return Card(
      color: cardColor,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ────────────────────────────────────────────────────
            Row(
              children: [
                Icon(
                  isSimulating ? Icons.schedule : Icons.bug_report_outlined,
                  color:
                      isSimulating
                          ? theme.colorScheme.error
                          : theme.colorScheme.primary,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isSimulating
                        ? 'DEBUG  ·  A simular ${_hm(debugNow!)}'
                        : 'Debug: Simular Evento 3-3-3',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isSimulating ? theme.colorScheme.error : null,
                    ),
                  ),
                ),
                if (isSimulating)
                  TextButton(
                    onPressed: () => onSimulate(null),
                    child: const Text('Hora real'),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              isSimulating
                  ? 'Ecrã e automação usam a hora simulada. Prima «Hora real» para repor.'
                  : 'Seleciona uma janela para simular o ecrã do evento e disparar a automação.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),

            // ── Phase preset buttons ───────────────────────────────────────
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _DebugPhaseButton(
                  label: 'CQ slot 1\n${_hm(cq1)}',
                  active: isActive(cq1),
                  color: const Color(0xFF00E676),
                  onTap: () => _activate(context, ref, cq1, 'CQ slot 1'),
                ),
                _DebugPhaseButton(
                  label: 'CQ slot 2\n${_hm(cq2)}',
                  active: isActive(cq2),
                  color: const Color(0xFF00E676),
                  onTap: () => _activate(context, ref, cq2, 'CQ slot 2'),
                ),
                _DebugPhaseButton(
                  label: 'CQ slot 3\n${_hm(cq3)}',
                  active: isActive(cq3),
                  color: const Color(0xFF00E676),
                  onTap: () => _activate(context, ref, cq3, 'CQ slot 3'),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // ── Automation state + reset ──────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Automação: CQ ${autoState.cqSentCount}/3'
                    '${autoState.lastCqTime != null ? '  · último CQ ${_hm(autoState.lastCqTime!)}' : ''}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed:
                      () =>
                          ref
                              .read(plan333AutoSendProvider.notifier)
                              .debugResetAutomationState(),
                  icon: const Icon(Icons.restart_alt, size: 15),
                  label: const Text('Reset'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// Tappable animated chip used inside _DebugAutomationCard.
class _DebugPhaseButton extends StatelessWidget {
  const _DebugPhaseButton({
    required this.label,
    required this.active,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool active;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: active ? color.withAlpha(55) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? color : color.withAlpha(80),
            width: active ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: active ? color : color.withAlpha(180),
            fontSize: 12,
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

