import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../protocol/protocol.dart';
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
  final _nameCtrl     = TextEditingController();
  final _cityCtrl     = TextEditingController();
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
    _nameCtrl.text     = cfg.stationName;
    _cityCtrl.text     = cfg.city;
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
    final cfg = ref.read(plan333ConfigProvider).copyWith(
          stationName: _nameCtrl.text.trim(),
          city: _cityCtrl.text.trim(),
          locality: _localityCtrl.text.trim(),
        );
    await ref.read(plan333ConfigProvider.notifier).update(cfg);
    if (mounted) setState(() => _configDirty = false);
  }

  @override
  Widget build(BuildContext context) {
    final config      = ref.watch(plan333ConfigProvider);
    final autoState   = ref.watch(plan333AutoSendProvider);
    final connState   = ref.watch(connectionProvider);
    final cbEnabled   = ref.watch(plan333EnabledProvider);
    final channels    = ref.watch(channelsProvider);

    final meshActive  = Plan333Service.isMeshEventActive(_now);
    final qslActive   = Plan333Service.isMeshQslActive(_now);
    final nextMesh    = Plan333Service.nextMeshEvent(_now);
    final cbActive    = Plan333Service.isWindowActive(_now);
    final nextCb      = Plan333Service.nextWindowTime(_now);
    final cbRemaining = nextCb.difference(_now);
    final cbProgress  = Plan333Service.windowProgress(_now);
    final satTraining = Plan333Service.nextSaturdayTraining(_now);

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
            onSendCq: () =>
                ref.read(plan333AutoSendProvider.notifier).sendManualCq(),
          ),
          const SizedBox(height: 16),

          // ── 2. Configuração ──────────────────────────────────────────────
          _ConfigCard(
            config: config,
            channels: channels,
            nameCtrl: _nameCtrl,
            cityCtrl: _cityCtrl,
            localityCtrl: _localityCtrl,
            dirty: _configDirty,
            onDirty: () => setState(() => _configDirty = true),
            onSave: _saveConfig,
            onChannelChanged: (idx) async {
              final updated = config.copyWith(meshChannelIndex: idx);
              await ref.read(plan333ConfigProvider.notifier).update(updated);
            },
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
          _MeshCoreChannelCard(),
          const SizedBox(height: 16),

          // ── 4. CB / PMR (secondary) ──────────────────────────────────────
          _CbPmrCard(
            cbActive: cbActive,
            nextCb: nextCb,
            remaining: cbRemaining,
            progress: cbProgress,
            satTraining: satTraining,
            now: _now,
          ),
          const SizedBox(height: 16),

          // ── 5. Notifications ─────────────────────────────────────────────
          _NotificationsCard(
            enabled: cbEnabled,
            onChanged: (v) =>
                ref.read(plan333EnabledProvider.notifier).setEnabled(v),
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
    final theme   = Theme.of(context);
    final accent  = meshActive ? const Color(0xFF00E676) : AppTheme.primary;
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
                  _Pill(
                    label: '● EVENTO ACTIVO',
                    color: const Color(0xFF00E676),
                  )
                else
                  _Pill(
                    label: _daysLabel(remaining),
                    color: theme.colorScheme.onSurfaceVariant,
                    border: true,
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
                  Text('CQ enviados:',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(width: 8),
                  ...List.generate(3, (i) {
                    final sent = i < autoState.cqSentCount;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(
                        sent ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                        color: sent
                            ? const Color(0xFF00E676)
                            : theme.colorScheme.onSurfaceVariant,
                        size: 20,
                      ),
                    );
                  }),
                  if (autoState.lastCqTime != null)
                    Text(
                      '(último: ${_fmtTime(autoState.lastCqTime!)})',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
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
                  Text(
                    _fmtDate(nextMesh),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
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
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],

            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 8),
            // Report link teaser
            Row(
              children: [
                Icon(Icons.bar_chart, size: 14,
                    color: theme.colorScheme.onSurfaceVariant),
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
        icon: Icon(
          allSent ? Icons.check_circle : Icons.send,
          size: 18,
        ),
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
    required this.channels,
    required this.nameCtrl,
    required this.cityCtrl,
    required this.localityCtrl,
    required this.dirty,
    required this.onDirty,
    required this.onSave,
    required this.onChannelChanged,
    required this.onAutoSendChanged,
  });

  final Plan333Config config;
  final List<ChannelInfo> channels;
  final TextEditingController nameCtrl;
  final TextEditingController cityCtrl;
  final TextEditingController localityCtrl;
  final bool dirty;
  final VoidCallback onDirty;
  final VoidCallback onSave;
  final void Function(int) onChannelChanged;
  final void Function(bool) onAutoSendChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeChannels =
        channels.where((c) => !c.isEmpty).toList();

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
                Text('Configuração do Evento',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
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

            // Channel dropdown
            DropdownButtonFormField<int>(
              value: _resolveChannel(activeChannels, config.meshChannelIndex),
              decoration: const InputDecoration(
                labelText: 'Canal MeshCore',
              ),
              items: activeChannels.isEmpty
                  ? [
                      const DropdownMenuItem(
                        value: 0,
                        child: Text('Canal 0 (rádio não ligado)'),
                      ),
                    ]
                  : activeChannels.map((ch) {
                      final label =
                          ch.name.isNotEmpty ? ch.name : 'Canal ${ch.index}';
                      return DropdownMenuItem(
                        value: ch.index,
                        child: Text(label),
                      );
                    }).toList(),
              onChanged: (v) {
                if (v != null) onChannelChanged(v);
              },
            ),
            const SizedBox(height: 4),

            // Auto-send toggle
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Envio automático de CQ'),
              subtitle:
                  const Text('Envia até 3 CQs automaticamente durante o evento'),
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

  int _resolveChannel(List<ChannelInfo> active, int preferred) {
    if (active.isEmpty) return 0;
    if (active.any((c) => c.index == preferred)) return preferred;
    return active.first.index;
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
    final cq = config.isConfigured
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
                Icon(Icons.chat_bubble_outline,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Formatos de Mensagem',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
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
            _PhraseRow(
              label: 'QSL (confirmação)',
              phase: 'Opcional 21:30–22:00',
              phrase:
                  'QSL, [Nome estação recebida], [N] hops, [local]\n'
                  'Ex: QSL, Daytona, 5 hops, Tomar',
            ),
            const Divider(height: 20),

            // Meshtastic note (secondary)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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

class _MeshCoreChannelCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
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
    final service   = ref.read(radioServiceProvider);
    final channels  = ref.read(channelsProvider);
    final config    = ref.read(plan333ConfigProvider);

    if (service == null) return;

    setState(() { _loading = true; _resultMessage = null; });

    try {
      // Find the slot: existing #plano333 slot → first empty slot → slot 1.
      int slot = channels
          .where((c) => c.name == Plan333Service.meshCoreHashtag)
          .map((c) => c.index)
          .firstOrNull
          ?? channels
              .where((c) => c.isEmpty)
              .map((c) => c.index)
              .firstOrNull
          ?? 1;

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
    final theme       = Theme.of(context);
    final connState   = ref.watch(connectionProvider);
    final channels    = ref.watch(channelsProvider);
    final isConnected = connState == TransportState.connected;
    final alreadySet  = channels.any(
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
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Adiciona o canal ao rádio ligado ou consulte os dados manualmente.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),

          // ── Configure button ────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _loading || !isConnected ? null : _configure,
              icon: _loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black87),
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
                  color: _resultOk
                      ? const Color(0xFF00E676)
                      : theme.colorScheme.error,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _resultMessage!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: _resultOk
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
          _ChannelConfigRow(
            label: 'Hashtag',
            value: Plan333Service.meshCoreHashtag,
            copyable: true,
          ),
          const Divider(height: 20),
          _ChannelConfigRow(
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
                  const ClipboardData(text: Plan333Service.reportUrl));
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
                  Icon(Icons.bar_chart,
                      size: 14, color: theme.colorScheme.primary),
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
                  Icon(Icons.copy_outlined,
                      size: 14, color: theme.colorScheme.primary),
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
          child: Text(label,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
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
// CB / PMR section (secondary, compact)
// ============================================================================

class _CbPmrCard extends StatelessWidget {
  const _CbPmrCard({
    required this.cbActive,
    required this.nextCb,
    required this.remaining,
    required this.progress,
    required this.satTraining,
    required this.now,
  });

  final bool cbActive;
  final DateTime nextCb;
  final Duration remaining;
  final double progress;
  final DateTime satTraining;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = cbActive ? const Color(0xFFFFAB40) : AppTheme.primary;
    final nextLabel =
        '${nextCb.hour.toString().padLeft(2, '0')}:${nextCb.minute.toString().padLeft(2, '0')}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Compact header
            Row(
              children: [
                Icon(Icons.radio, color: color, size: 20),
                const SizedBox(width: 8),
                Text('CB / PMR 446',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: color,
                    )),
                const Spacer(),
                if (cbActive)
                  _Pill(label: '● À ESCUTA AGORA', color: color)
                else
                  Text(
                    'Próx. $nextLabel  •  em ${_fmt(remaining)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),

            if (!cbActive) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  backgroundColor: theme.colorScheme.outlineVariant,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
            ],

            const SizedBox(height: 10),

            // Frequencies — inline, compact
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                _FreqChip(label: 'CB Canal 3 AM', freq: '26.985 MHz'),
                _FreqChip(label: 'PMR 446 Canal 3', freq: '446.031 MHz'),
              ],
            ),

            const SizedBox(height: 8),

            // Times chips
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: Plan333Service.windowHours.map((h) {
                final label = '${h.toString().padLeft(2, '0')}:00';
                final isNext = nextCb.hour == h && nextCb.day == now.day;
                return _TimeChip(label: label, highlight: isNext);
              }).toList(),
            ),

            const SizedBox(height: 6),
            Text(
              '±3 min  •  Treino: Sábados 21:00  •  Sem tom (PMR)',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

// ============================================================================
// Notifications card
// ============================================================================

class _NotificationsCard extends StatelessWidget {
  const _NotificationsCard(
      {required this.enabled, required this.onChanged});
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
                Icon(Icons.notifications_active,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Alertas CB/PMR',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Lembretes de janela CB/PMR'),
              subtitle:
                  const Text('Notificação 3 min antes de cada janela (8×/dia)'),
              value: enabled,
              onChanged: onChanged,
            ),
            if (enabled)
              Text(
                'Inclui lembrete do treino de sábado às 20:55.',
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
            color: border ? color.withAlpha(80) : color.withAlpha(120)),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: color, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _PhaseChip extends StatelessWidget {
  const _PhaseChip(
      {required this.label, required this.active, required this.color});
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
            color: active ? color.withAlpha(140) : Colors.grey.withAlpha(80)),
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

class _FreqChip extends StatelessWidget {
  const _FreqChip({required this.label, required this.freq});
  final String label;
  final String freq;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(width: 4),
        Text(freq,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: AppTheme.primary,
              fontFamily: 'monospace',
            )),
      ],
    );
  }
}

class _TimeChip extends StatelessWidget {
  const _TimeChip({required this.label, required this.highlight});
  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Chip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
          color: highlight ? AppTheme.primary : theme.colorScheme.onSurface,
        ),
      ),
      padding: EdgeInsets.zero,
      labelPadding: const EdgeInsets.symmetric(horizontal: 6),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      side: BorderSide(
        color: highlight ? AppTheme.primary : theme.colorScheme.outline,
      ),
      backgroundColor: highlight ? AppTheme.primary.withAlpha(30) : null,
    );
  }
}

class _PhraseRow extends StatelessWidget {
  const _PhraseRow(
      {required this.label, required this.phase, required this.phrase});
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
            Text(label,
                style: theme.textTheme.labelMedium?.copyWith(
                    color: AppTheme.primary, fontWeight: FontWeight.bold)),
            const Spacer(),
            Text(phase,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
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
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontFamily: 'monospace'),
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
