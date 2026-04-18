import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../l10n/l10n.dart';
import '../../providers/radio_providers.dart';
import '../../services/notification_service.dart';
import '../../services/plan333_service.dart';
import '../../transport/radio_transport.dart';
import '../theme.dart';

// ignore_for_file: lines_longer_than_80_chars

/// Plano 3-3-3 — Portuguese emergency communications protocol screen.
///
/// The primary focus is the **Mesh 3-3-3** weekly event (MeshCore on the mesh
/// network).  CB/PMR 446 information is shown as a secondary reference.
class Plan333Screen extends ConsumerStatefulWidget {
  const Plan333Screen({super.key});

  @override
  ConsumerState<Plan333Screen> createState() => _Plan333ScreenState();
}

class _Plan333ScreenState extends ConsumerState<Plan333Screen> {
  late Timer _ticker;
  DateTime _now = DateTime.now();

  // Station-name / city / locality controllers (used in config card)
  final _nameCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _localityCtrl = TextEditingController();
  bool _configDirty = false;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncControllers());
  }

  /// Populate text-field controllers from stored config (runs once after build).
  void _syncControllers() {
    final cfg = ref.read(plan333ConfigProvider);
    _nameCtrl.text = cfg.stationName;
    _cityCtrl.text = cfg.city;
    _localityCtrl.text = cfg.locality;
  }

  @override
  void dispose() {
    _ticker.cancel();
    _nameCtrl.dispose();
    _cityCtrl.dispose();
    _localityCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveConfig() async {
    final cfg = ref
        .read(plan333ConfigProvider)
        .copyWith(
          stationName: _nameCtrl.text.trim(),
          city: _cityCtrl.text.trim(),
          locality: _localityCtrl.text.trim(),
        );
    await ref.read(plan333ConfigProvider.notifier).update(cfg);
    if (mounted) setState(() => _configDirty = false);
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(plan333ConfigProvider);
    final autoState = ref.watch(plan333AutoSendProvider);
    final connState = ref.watch(connectionProvider);
    final cbEnabled = ref.watch(plan333EnabledProvider);
    final qslLogCount = ref.watch(qslLogProvider).length;
    final debugNow = ref.watch(plan333DebugNowProvider);
    final effectiveNow = debugNow ?? _now;

    final meshActive = Plan333Service.isMeshEventActive(effectiveNow);
    final qslActive = Plan333Service.isMeshQslActive(effectiveNow);
    final nextMesh = Plan333Service.nextMeshEvent(effectiveNow);

    final radioConnected = connState == TransportState.connected;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 1. Mesh 3-3-3 status (PRIMARY) ──────────────────────────────
          _MeshStatusCard(
            now: effectiveNow,
            meshActive: meshActive,
            qslActive: qslActive,
            nextMesh: nextMesh,
            config: config,
            autoState: autoState,
            qslLogCount: qslLogCount,
            radioConnected: radioConnected,
            onSendCq:
                () => ref.read(plan333AutoSendProvider.notifier).sendManualCq(),
            onAbort:
                () => ref.read(plan333AutoSendProvider.notifier).abortSession(),
          ),
          const SizedBox(height: 16),

          if (kDebugMode) ...[
            _DebugAutomationCard(
              debugNow: ref.watch(plan333DebugNowProvider),
              onSimulate: (dt) {
                ref.read(plan333DebugNowProvider.notifier).state = dt;
              },
            ),
            const SizedBox(height: 16),
          ],

          // ── 2. Configuração ──────────────────────────────────────────────
          _ConfigCard(
            config: config,
            nameCtrl: _nameCtrl,
            cityCtrl: _cityCtrl,
            localityCtrl: _localityCtrl,
            dirty: _configDirty,
            onDirty: () => setState(() => _configDirty = true),
            onSave: _saveConfig,
            onAutoSendChanged: (v) async {
              final updated = config.copyWith(autoSendCq: v);
              await ref.read(plan333ConfigProvider.notifier).update(updated);
            },
          ),
          const SizedBox(height: 16),

          // ── 3. Message formats ───────────────────────────────────────────
          _FormatsCard(config: config),
          const SizedBox(height: 16),

          // ── 3b. MeshCore channel config reference ─────────────────────────
          const _MeshCoreChannelCard(),
          const SizedBox(height: 16),

          // ── 4. QSL log ───────────────────────────────────────────────────
          const _QslCard(),
          const SizedBox(height: 16),

          // ── 5. Notifications ─────────────────────────────────────────────
          _NotificationsCard(
            enabled: cbEnabled,
            onChanged:
                (v) => ref.read(plan333EnabledProvider.notifier).setEnabled(v),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ============================================================================
// Mesh 3-3-3 status card
// ============================================================================

class _MeshStatusCard extends StatelessWidget {
  const _MeshStatusCard({
    required this.now,
    required this.meshActive,
    required this.qslActive,
    required this.nextMesh,
    required this.config,
    required this.autoState,
    required this.qslLogCount,
    required this.radioConnected,
    required this.onSendCq,
    required this.onAbort,
  });

  final DateTime now;
  final bool meshActive;
  final bool qslActive;
  final DateTime nextMesh;
  final Plan333Config config;
  final Plan333AutoSendState autoState;
  final int qslLogCount;
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
              Row(
                children: [
                  _PhaseChip(
                    label: context.l10n.plan333PhaseCQ,
                    active: !qslActive,
                    color: const Color(0xFF00E676),
                  ),
                  const SizedBox(width: 8),
                  _PhaseChip(
                    label: context.l10n.plan333PhaseQSL,
                    active: qslActive,
                    color: const Color(0xFF40C4FF),
                  ),
                ],
              ),
              const SizedBox(height: 14),

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

              // QSL auto-send status (visible during QSL phase)
              if (qslActive && config.autoSendCq) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      context.l10n.plan333QslSent,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${autoState.qslSentCount}/$qslLogCount',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF40C4FF),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (autoState.lastQslTime != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        '${context.l10n.plan333LastSent} ${_fmtTime(autoState.lastQslTime!)})',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (qslLogCount == 0)
                      Text(
                        '  ${context.l10n.plan333NoQslLog}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ],
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
    final qslPhase = _nextSaturdayAt(21, 35);

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
                _DebugPhaseButton(
                  label: 'QSL fase\n${_hm(qslPhase)}',
                  active: isActive(qslPhase),
                  color: const Color(0xFF40C4FF),
                  onTap: () => _activate(context, ref, qslPhase, 'QSL fase'),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // ── Automation state + reset ──────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Automação: CQ ${autoState.cqSentCount}/3  ·  QSL ${autoState.qslSentCount}'
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
            const Divider(height: 20),
            _PhraseRow(
              label: context.l10n.plan333FormatQSL,
              phase: context.l10n.plan333FormatQSLPhase,
              phrase: context.l10n.plan333FormatQSLTemplate,
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

// ============================================================================
// MeshCore channel config button → opens a bottom sheet
// ============================================================================

class _MeshCoreChannelCard extends ConsumerWidget {
  const _MeshCoreChannelCard();

  void _showSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => const _ChannelSetupSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channels = ref.watch(channelsProvider);
    final alreadySet = channels.any(
      (c) => c.name == Plan333Service.meshCoreHashtag,
    );
    if (alreadySet) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => _showSheet(context),
        icon: const Icon(Icons.lock_outline, size: 18),
        label: Text(context.l10n.plan333ConfigureChannel),
        style: OutlinedButton.styleFrom(
          foregroundColor: theme.colorScheme.primary,
          side: BorderSide(color: theme.colorScheme.primary.withAlpha(120)),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          alignment: Alignment.centerLeft,
        ),
      ),
    );
  }
}

class _ChannelSetupSheet extends ConsumerStatefulWidget {
  const _ChannelSetupSheet();

  @override
  ConsumerState<_ChannelSetupSheet> createState() => _ChannelSetupSheetState();
}

class _ChannelSetupSheetState extends ConsumerState<_ChannelSetupSheet> {
  bool _loading = false;
  String? _resultMessage;
  bool _resultOk = false;

  Future<void> _configure() async {
    final l10n = context.l10n;
    final service = ref.read(radioServiceProvider);
    final channels = ref.read(channelsProvider);
    final config = ref.read(plan333ConfigProvider);

    if (service == null) return;

    setState(() {
      _loading = true;
      _resultMessage = null;
    });

    try {
      // Find the slot: existing #plano333 slot → first empty slot → slot 1.
      int slot =
          channels
              .where((c) => c.name == Plan333Service.meshCoreHashtag)
              .map((c) => c.index)
              .firstOrNull ??
          channels.where((c) => c.isEmpty).map((c) => c.index).firstOrNull ??
          1;

      await service.setChannel(
        slot,
        Plan333Service.meshCoreHashtag,
        Plan333Service.meshCoreSecretBytes,
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await service.requestChannel(slot);

      // Auto-update the event channel index in config.
      if (config.meshChannelIndex != slot && mounted) {
        await ref
            .read(plan333ConfigProvider.notifier)
            .update(config.copyWith(meshChannelIndex: slot));
      }

      if (mounted) {
        setState(() {
          _loading = false;
          _resultOk = true;
          _resultMessage = l10n.plan333ChannelAdded(slot);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _resultOk = false;
          _resultMessage = 'Erro: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connState = ref.watch(connectionProvider);
    final channels = ref.watch(channelsProvider);
    final isConnected = connState == TransportState.connected;
    final alreadySet = channels.any(
      (c) => c.name == Plan333Service.meshCoreHashtag,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.lock_outline, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                context.l10n.plan333ChannelSheetTitle,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            context.l10n.plan333ChannelSheetDesc,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),

          // ── Configure button ────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _loading || !isConnected ? null : _configure,
              icon:
                  _loading
                      ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black87,
                        ),
                      )
                      : Icon(
                        alreadySet ? Icons.sync : Icons.add_circle_outline,
                        size: 18,
                      ),
              label: Text(
                !isConnected
                    ? context.l10n.commonRadioDisconnected
                    : _loading
                    ? context.l10n.commonConfiguring
                    : alreadySet
                    ? context.l10n.commonReconfigRadio
                    : context.l10n.commonAdd2Radio,
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor:
                    alreadySet ? theme.colorScheme.secondary : null,
              ),
            ),
          ),

          if (_resultMessage != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  _resultOk ? Icons.check_circle : Icons.error_outline,
                  size: 14,
                  color:
                      _resultOk
                          ? const Color(0xFF00E676)
                          : theme.colorScheme.error,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _resultMessage!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color:
                          _resultOk
                              ? const Color(0xFF00E676)
                              : theme.colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 12),

          // ── Credentials (reference / manual) ───────────────────────────
          const _ChannelConfigRow(
            label: 'Hashtag',
            value: Plan333Service.meshCoreHashtag,
            copyable: true,
          ),
          const Divider(height: 20),
          const _ChannelConfigRow(
            label: 'Secret Key',
            value: Plan333Service.meshCoreSecretKey,
            monospace: true,
            copyable: true,
          ),
          const SizedBox(height: 12),
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () {
              Clipboard.setData(
                const ClipboardData(text: Plan333Service.reportUrl),
              );
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(context.l10n.commonReportUrlCopied),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.bar_chart,
                    size: 14,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${context.l10n.commonReport} ${Plan333Service.reportUrl}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.copy_outlined,
                    size: 14,
                    color: theme.colorScheme.primary,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChannelConfigRow extends StatelessWidget {
  const _ChannelConfigRow({
    required this.label,
    required this.value,
    this.monospace = false,
    this.copyable = false,
  });

  final String label;
  final String value;
  final bool monospace;
  final bool copyable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: monospace ? 'monospace' : null,
              fontWeight: FontWeight.w600,
              color: AppTheme.primary,
            ),
          ),
        ),
        if (copyable)
          InkWell(
            onTap: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('$label copiado'),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.copy, size: 14),
            ),
          ),
      ],
    );
  }
}

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

// ============================================================================
// QSL log card
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
            // ── Header row ───────────────────────────────────────────────
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
                    tooltip: 'Adicionar QSL',
                    color: AppTheme.primary,
                    onPressed: () => _showAddDialog(context, ref),
                  ),
                ],
              ),
            ),

            // ── Empty state ───────────────────────────────────────────────
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

            // ── Log entries ───────────────────────────────────────────────
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
    lines.writeln('Estações ouvidas / QSL (${log.length}):');
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
// Single QSL row
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
// Add QSL dialog
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
            // Hops picker
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

// ============================================================================
// Shared small widgets
// ============================================================================

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color, this.border = false});
  final String label;
  final Color color;
  final bool border;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(border ? 0 : 30),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: border ? color.withAlpha(80) : color.withAlpha(120),
        ),
      ),
      child: Text(
        label,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _PhaseChip extends StatelessWidget {
  const _PhaseChip({
    required this.label,
    required this.active,
    required this.color,
  });
  final String label;
  final bool active;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: active ? color.withAlpha(40) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: active ? color.withAlpha(140) : Colors.grey.withAlpha(80),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: active ? color : Colors.grey,
          fontSize: 11,
          fontWeight: active ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }
}

class _PhraseRow extends StatelessWidget {
  const _PhraseRow({
    required this.label,
    required this.phase,
    required this.phrase,
  });
  final String label;
  final String phase;
  final String phrase;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: AppTheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            Text(
              phase,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        _InlinePhrase(text: phrase),
      ],
    );
  }
}

class _InlinePhrase extends StatelessWidget {
  const _InlinePhrase({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SelectableText(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
          ),
          InkWell(
            onTap: () {
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Copiado'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            child: const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Icon(Icons.copy, size: 16),
            ),
          ),
        ],
      ),
    );
  }
}
