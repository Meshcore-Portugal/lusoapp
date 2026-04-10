import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../providers/radio_providers.dart';
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

    final meshActive = Plan333Service.isMeshEventActive(_now);
    final qslActive = Plan333Service.isMeshQslActive(_now);
    final nextMesh = Plan333Service.nextMeshEvent(_now);

    final radioConnected = connState == TransportState.connected;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 1. Mesh 3-3-3 status (PRIMARY) ──────────────────────────────
          _MeshStatusCard(
            now: _now,
            meshActive: meshActive,
            qslActive: qslActive,
            nextMesh: nextMesh,
            config: config,
            autoState: autoState,
            radioConnected: radioConnected,
            onSendCq:
                () => ref.read(plan333AutoSendProvider.notifier).sendManualCq(),
          ),
          const SizedBox(height: 16),

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
    required this.radioConnected,
    required this.onSendCq,
  });

  final DateTime now;
  final bool meshActive;
  final bool qslActive;
  final DateTime nextMesh;
  final Plan333Config config;
  final Plan333AutoSendState autoState;
  final bool radioConnected;
  final VoidCallback onSendCq;

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
                  'MESH 3-3-3',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: accent,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                if (meshActive)
                  const Flexible(
                    child: _Pill(
                      label: '● EVENTO ACTIVO',
                      color: Color(0xFF00E676),
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
                    label: 'CQ 21:00–22:00',
                    active: !qslActive,
                    color: const Color(0xFF00E676),
                  ),
                  const SizedBox(width: 8),
                  _PhaseChip(
                    label: 'QSL 21:30–22:00',
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
                    'CQ enviados:',
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
                      '(último: ${_fmtTime(autoState.lastCqTime!)})',
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
                'Sábados 21:00–22:00  •  CQ Presenças MeshCore',
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
                    'Relatório em ${Plan333Service.reportUrl}',
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
      label = '✓  3 CQs enviados';
    } else if (!config.isConfigured) {
      color = Colors.grey;
      label = 'Configure os dados primeiro';
    } else if (!radioConnected) {
      color = AppTheme.primary;
      label = 'Rádio desligado — não é possível enviar';
    } else {
      color = const Color(0xFF00E676);
      label = 'ENVIAR CQ  (${autoState.cqSentCount + 1}/3)';
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
                  'Configuração do Evento',
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
                    child: const Text('Guardar'),
                  ),
              ],
            ),
            const SizedBox(height: 14),

            // Station name
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Nome de estação *',
                hintText: 'Ex: Mike 05',
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
                    decoration: const InputDecoration(
                      labelText: 'Cidade *',
                      hintText: 'Ex: Lisboa',
                    ),
                    onChanged: (_) => onDirty(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: localityCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Localidade',
                      hintText: 'Ex: Olaias',
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
              title: const Text('Envio automático de CQ'),
              subtitle: const Text(
                'Envia até 3 CQs automaticamente durante o evento',
              ),
              value: config.autoSendCq,
              onChanged: onAutoSendChanged,
            ),

            // CQ preview
            if (config.isConfigured) ...[
              const Divider(height: 16),
              Text(
                'Mensagem CQ:',
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
            : 'CQ Plano 333, [Nome], [Cidade], [Localidade]';

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
                  'Formatos de Mensagem',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // CQ format (filled from config if available)
            _PhraseRow(
              label: 'Presença (CQ)',
              phase: 'MeshCore 21:00–22:00',
              phrase: cq,
            ),
            const Divider(height: 20),
            const _PhraseRow(
              label: 'QSL (confirmação)',
              phase: 'Opcional 21:30–22:00',
              phrase:
                  'QSL, [Nome estação recebida], [N] hops, [local]\n'
                  'Ex: QSL, Daytona, 5 hops, Tomar',
            ),
            const Divider(height: 20),

            // Meshtastic note (secondary)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Text(
                'Meshtastic: presença 21:00–21:30, QSL 21:30–22:00. '
                'Relatório em Telegram.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
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
        label: const Text('Configurar Canal MeshCore  (#plano333)'),
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
      if (config.meshChannelIndex != slot) {
        await ref
            .read(plan333ConfigProvider.notifier)
            .update(config.copyWith(meshChannelIndex: slot));
      }

      if (mounted) {
        setState(() {
          _loading = false;
          _resultOk = true;
          _resultMessage = 'Canal #plano333 adicionado no slot $slot';
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
                'Canal MeshCore  #plano333',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Adiciona o canal ao rádio ligado ou consulte os dados manualmente.',
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
                    ? 'Rádio não ligado'
                    : _loading
                    ? 'A configurar...'
                    : alreadySet
                    ? 'Re-configurar no Rádio'
                    : 'Adicionar ao Rádio',
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
                const SnackBar(
                  content: Text('URL do relatório copiado'),
                  duration: Duration(seconds: 2),
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
                      'Relatório: ${Plan333Service.reportUrl}',
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

class _NotificationsCard extends StatelessWidget {
  const _NotificationsCard({required this.enabled, required this.onChanged});
  final bool enabled;
  final void Function(bool) onChanged;

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
                  'Alertas Mesh 3-3-3',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Lembrete do evento de sábado'),
              subtitle: const Text(
                'Alertas 10 e 5 min antes do Mesh 3-3-3 (Sábados 21:00)',
              ),
              value: enabled,
              onChanged: onChanged,
            ),
            if (enabled)
              Text(
                'Alertas ativos às 20:50 e 20:55.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
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
                Text(
                  'QSL Recebidos',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (log.isNotEmpty) ...[
                  // Share button
                  IconButton(
                    icon: const Icon(Icons.share_outlined),
                    tooltip: 'Partilhar log',
                    onPressed: () => _share(log, config),
                  ),
                  // Clear button
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Limpar log',
                    onPressed: () => _confirmClear(context, ref),
                  ),
                ],
                // Add button
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  tooltip: 'Adicionar QSL',
                  color: AppTheme.primary,
                  onPressed: () => _showAddDialog(context, ref),
                ),
              ],
            ),

            // ── Empty state ───────────────────────────────────────────────
            if (log.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Nenhum QSL registado. Toca em + para adicionar.',
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
                  onDelete: () =>
                      ref.read(qslLogProvider.notifier).remove(i),
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
      builder: (_) => _AddQslDialog(
        onSave: (r) => ref.read(qslLogProvider.notifier).add(r),
      ),
    );
  }

  void _confirmClear(BuildContext context, WidgetRef ref) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Limpar QSL?'),
        content: const Text('Todos os QSL registados serão apagados.'),
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
    final station =
        config.stationName.isNotEmpty ? config.stationName : '?';
    final location =
        config.city.isNotEmpty ? config.city : '';

    final lines = StringBuffer();
    lines.writeln('=== Mesh 3-3-3 — $dateStr ===');
    if (location.isNotEmpty) {
      lines.writeln('Estação: $station | $location');
    } else {
      lines.writeln('Estação: $station');
    }
    lines.writeln('QSL recebidos (${log.length}):');
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
        const Icon(Icons.check_circle_outline, size: 16, color: Color(0xFF00E676)),
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
      title: const Text('Adicionar QSL'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _stationCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Estação *',
                hintText: 'ex: Daytona',
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
              decoration: const InputDecoration(
                labelText: 'Localização',
                hintText: 'ex: Tomar',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesCtrl,
              decoration: const InputDecoration(
                labelText: 'Notas (opcional)',
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
