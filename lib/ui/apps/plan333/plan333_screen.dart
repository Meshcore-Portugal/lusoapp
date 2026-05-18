import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../../l10n/l10n.dart';
import '../../../providers/radio_providers.dart';
import '../../../services/notification_service.dart';
import '../../../services/plan333_service.dart';
import '../../../transport/radio_transport.dart';
import '../../theme.dart';


part 'parts/plan333_status_card.dart';
part 'parts/plan333_debug_card.dart';
part 'parts/plan333_config_cards.dart';
part 'parts/plan333_channel_cards.dart';
part 'parts/plan333_qsl_cards.dart';
part 'parts/plan333_notifications_card.dart';
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
    final debugNow = ref.watch(plan333DebugNowProvider);
    final effectiveNow = debugNow ?? _now;

    final meshActive = Plan333Service.isMeshEventActive(effectiveNow);
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
            nextMesh: nextMesh,
            config: config,
            autoState: autoState,
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

          // ── 4. CQ log ────────────────────────────────────────────────────
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
