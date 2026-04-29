part of '../plan333_screen.dart';


// ============================================================================
// Notifications card
// ============================================================================

class _NotificationsCard extends StatefulWidget {
  const _NotificationsCard({required this.enabled, required this.onChanged});
  final bool enabled;
  final void Function(bool) onChanged;

  @override
  State<_NotificationsCard> createState() => _NotificationsCardState();
}

class _NotificationsCardState extends State<_NotificationsCard> {
  bool _testBusy = false;
  bool _countBusy = false;
  String? _testResult;
  int? _pendingCount;

  Future<void> _runTest() async {
    setState(() {
      _testBusy = true;
      _testResult = null;
    });
    try {
      final result =
          await NotificationService.instance.showPlan333TestNotification();
      if (mounted) setState(() => _testResult = result);
    } catch (e) {
      if (mounted) setState(() => _testResult = 'Erro: $e');
    } finally {
      if (mounted) setState(() => _testBusy = false);
    }
  }

  Future<void> _checkPending() async {
    setState(() {
      _countBusy = true;
      _pendingCount = null;
    });
    try {
      final n = await NotificationService.instance.pendingPlan333Count();
      if (mounted) setState(() => _pendingCount = n);
    } catch (e) {
      if (mounted) setState(() => _pendingCount = -1);
    } finally {
      if (mounted) setState(() => _countBusy = false);
    }
  }

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
                Icon(
                  Icons.notifications_active,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  context.l10n.plan333Alerts,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.l10n.plan333AlertToggle),
              subtitle: Text(context.l10n.plan333AlertDesc),
              value: widget.enabled,
              onChanged: widget.onChanged,
            ),
            if (widget.enabled)
              Text(
                context.l10n.plan333AlertsActive,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),

            // ── Debug test panel ────────────────────────────────────────
            if (kDebugMode) ...[
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.bug_report_outlined,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Debug notificações',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  // Fire an immediate notification now.
                  FilledButton.icon(
                    onPressed: _testBusy ? null : _runTest,
                    icon:
                        _testBusy
                            ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.black87,
                              ),
                            )
                            : const Icon(
                              Icons.notifications_outlined,
                              size: 16,
                            ),
                    label: const Text('Testar agora'),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                  ),
                  // Check how many are scheduled.
                  OutlinedButton.icon(
                    onPressed: _countBusy ? null : _checkPending,
                    icon:
                        _countBusy
                            ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Icon(Icons.schedule_outlined, size: 16),
                    label: const Text('Ver agendadas'),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                  ),
                ],
              ),
              if (_testResult != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      _testResult == 'OK'
                          ? Icons.check_circle_outline
                          : Icons.error_outline,
                      size: 14,
                      color:
                          _testResult == 'OK'
                              ? const Color(0xFF00E676)
                              : theme.colorScheme.error,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _testResult == 'OK'
                            ? 'Notificação enviada'
                            : _testResult!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color:
                              _testResult == 'OK'
                                  ? const Color(0xFF00E676)
                                  : theme.colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (_pendingCount != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      _pendingCount! > 0
                          ? Icons.check_circle_outline
                          : Icons.warning_amber_outlined,
                      size: 14,
                      color:
                          _pendingCount! > 0
                              ? const Color(0xFF40C4FF)
                              : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _pendingCount! < 0
                          ? 'Erro ao consultar'
                          : _pendingCount! == 0
                          ? 'Nenhuma notificação agendada'
                          : '$_pendingCount notificação(ões) agendada(s)',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            _pendingCount! > 0
                                ? const Color(0xFF40C4FF)
                                : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

