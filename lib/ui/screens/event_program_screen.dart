import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../providers/radio_providers.dart';

// ---------------------------------------------------------------------------
// Event data — edit here or flip _showEventProgram in connect_screen.dart
// ---------------------------------------------------------------------------

const _accentColor = Color(0xFFFF8C00); // matches badge colour

class _Slot {
  const _Slot(this.time, this.title, {this.highlight = false});
  final String time;
  final String title;
  final bool highlight;
}

const _morning = <_Slot>[
  _Slot('09:45 – 10:00', 'Boas Vindas / Abertura'),
  _Slot(
    '10:00 – 10:30',
    'O que é o MeshCore, a origem e o futuro',
    highlight: true,
  ),
  _Slot('10:30 – 11:00', 'Coffee Break / Conferência de Imprensa'),
  _Slot('11:00 – 11:30', 'Comunicar a 100 km é fácil, e o Plano 3-3-3'),
  _Slot('11:30 – 12:45', 'Mais de 300 Repetidores em Portugal'),
  _Slot('13:00 – 14:20', 'Almoço', highlight: true),
];

const _afternoon = <_Slot>[
  _Slot('14:30 – 15:00', 'MeshCore e o Radioamadorismo'),
  _Slot('15:15 – 15:45', 'MeshCore nas ULPC'),
  _Slot('16:00 – 16:30', 'Convidado Surpresa', highlight: true),
  _Slot(
    '16:45 – 17:45',
    'Encerramento do Evento com sorteio de prémios',
    highlight: true,
  ),
];

const _workshops = <String>[
  'Montagem de um repetidor MeshCore',
  'Rede privada para uso por famílias ou grupos',
  'Antenas: escolha, construção e calibração',
  'Estação de Radioamador: CS5MC  (HF, VHF e UHF)',
];

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

// Well-known 16-byte secret for the public event channel.
// "techsummit2026" in UTF-8 (14 bytes) + 2 zero padding bytes.
final _eventChannelSecret = Uint8List.fromList([
  0x74,
  0x65,
  0x63,
  0x68,
  0x73,
  0x75,
  0x6d,
  0x6d,
  0x69,
  0x74,
  0x32,
  0x30,
  0x32,
  0x36,
  0x00,
  0x00,
]);

class EventProgramScreen extends ConsumerWidget {
  const EventProgramScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final channels = ref.watch(channelsProvider);
    final service = ref.watch(radioServiceProvider);
    final maxChannels = ref.watch(deviceInfoProvider)?.maxChannels ?? 8;

    final hasEventChannel = channels.any(
      (c) => c.name.trim().toLowerCase() == '#techsummit2026',
    );
    final usedIndices =
        channels.where((c) => c.name.isNotEmpty).map((c) => c.index).toSet();
    final nextFreeIndex = List.generate(
      maxChannels,
      (i) => i,
    ).firstWhere((i) => !usedIndices.contains(i), orElse: () => -1);

    Future<void> addEventChannel() async {
      if (service == null || nextFreeIndex < 0) return;
      await service.setChannel(
        nextFreeIndex,
        '#techsummit2026',
        _eventChannelSecret,
      );
      await Future.delayed(const Duration(milliseconds: 200));
      await service.requestChannel(nextFreeIndex);
    }

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // ── Header ──────────────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 160,
            pinned: true,
            backgroundColor: theme.colorScheme.surface,
            flexibleSpace: FlexibleSpaceBar(
              background: _HeaderBanner(theme: theme),
              collapseMode: CollapseMode.pin,
            ),
          ),

          // ── Channel banner (shown only when channel is missing) ─────────
          if (!hasEventChannel && service != null)
            SliverToBoxAdapter(
              child: _ChannelBanner(
                noFreeSlot: nextFreeIndex < 0,
                onAdd: addEventChannel,
                theme: theme,
              ),
            ),

          // ── Programme ───────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionHeader(
                    icon: Icons.wb_sunny_outlined,
                    label: context.l10n.eventMorning,
                    theme: theme,
                  ),
                  const SizedBox(height: 8),
                  _ProgramBlock(slots: _morning, theme: theme),
                  const SizedBox(height: 24),
                  _SectionHeader(
                    icon: Icons.wb_twilight,
                    label: context.l10n.eventAfternoon,
                    theme: theme,
                  ),
                  const SizedBox(height: 8),
                  _ProgramBlock(slots: _afternoon, theme: theme),
                  const SizedBox(height: 28),
                  _SectionHeader(
                    icon: Icons.build_outlined,
                    label: context.l10n.eventWorkshops,
                    theme: theme,
                  ),
                  const SizedBox(height: 12),
                  _WorkshopBlock(theme: theme),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header banner
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Channel missing banner
// ---------------------------------------------------------------------------

class _ChannelBanner extends StatefulWidget {
  const _ChannelBanner({
    required this.onAdd,
    required this.noFreeSlot,
    required this.theme,
  });

  final Future<void> Function() onAdd;
  final bool noFreeSlot;
  final ThemeData theme;

  @override
  State<_ChannelBanner> createState() => _ChannelBannerState();
}

class _ChannelBannerState extends State<_ChannelBanner> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _accentColor.withAlpha(20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _accentColor.withAlpha(100)),
      ),
      child: Row(
        children: [
          const Icon(Icons.tag, color: _accentColor, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              widget.noFreeSlot
                  ? context.l10n.eventChannelNoSlots
                  : context.l10n.eventChannelNotFound,
              style: widget.theme.textTheme.bodySmall?.copyWith(
                color: widget.theme.colorScheme.onSurface,
              ),
            ),
          ),
          if (!widget.noFreeSlot) ...[
            const SizedBox(width: 8),
            _loading
                ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _accentColor,
                  ),
                )
                : TextButton(
                  style: TextButton.styleFrom(foregroundColor: _accentColor),
                  onPressed: () async {
                    setState(() => _loading = true);
                    await widget.onAdd();
                    if (mounted) setState(() => _loading = false);
                  },
                  child: Text(context.l10n.eventAddChannel),
                ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header banner
// ---------------------------------------------------------------------------

class _HeaderBanner extends StatelessWidget {
  const _HeaderBanner({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [const Color(0xFF1A1A2E), _accentColor.withAlpha(40)],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Antenna icon in accent circle
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _accentColor.withAlpha(30),
                  border: Border.all(
                    color: _accentColor.withAlpha(100),
                    width: 1.5,
                  ),
                ),
                child: const Icon(
                  Icons.podcasts,
                  color: _accentColor,
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _accentColor.withAlpha(30),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: _accentColor.withAlpha(80)),
                      ),
                      child: Text(
                        context.l10n.eventSummitTitle.toUpperCase(),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: _accentColor,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      context.l10n.eventSummitSubtitle,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${context.l10n.eventTitle}  ·  ${context.l10n.eventDateLabel}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section header
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.label,
    required this.theme,
  });

  final IconData icon;
  final String label;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: _accentColor),
        const SizedBox(width: 8),
        Text(
          label.toUpperCase(),
          style: theme.textTheme.labelMedium?.copyWith(
            color: _accentColor,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Divider(color: _accentColor.withAlpha(60), thickness: 1),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Programme block (timeline style)
// ---------------------------------------------------------------------------

class _ProgramBlock extends StatelessWidget {
  const _ProgramBlock({required this.slots, required this.theme});
  final List<_Slot> slots;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < slots.length; i++)
          _SlotRow(slot: slots[i], isLast: i == slots.length - 1, theme: theme),
      ],
    );
  }
}

class _SlotRow extends StatelessWidget {
  const _SlotRow({
    required this.slot,
    required this.isLast,
    required this.theme,
  });

  final _Slot slot;
  final bool isLast;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final dotColor = slot.highlight ? _accentColor : theme.colorScheme.outline;
    final textColor =
        slot.highlight
            ? theme.colorScheme.onSurface
            : theme.colorScheme.onSurfaceVariant;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline rail
          SizedBox(
            width: 14,
            child: Column(
              children: [
                const SizedBox(height: 6),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: dotColor,
                    boxShadow:
                        slot.highlight
                            ? [
                              BoxShadow(
                                color: _accentColor.withAlpha(80),
                                blurRadius: 6,
                              ),
                            ]
                            : null,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 1.5,
                      color: theme.colorScheme.outlineVariant.withAlpha(100),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Content
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    slot.time,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: _accentColor.withAlpha(200),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    slot.title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: textColor,
                      fontWeight:
                          slot.highlight ? FontWeight.w600 : FontWeight.normal,
                    ),
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

// ---------------------------------------------------------------------------
// Workshops block
// ---------------------------------------------------------------------------

class _WorkshopBlock extends StatelessWidget {
  const _WorkshopBlock({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final ws in _workshops)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withAlpha(60),
              ),
            ),
            child: ListTile(
              dense: true,
              leading: const Icon(
                Icons.construction,
                color: _accentColor,
                size: 20,
              ),
              title: Text(
                ws,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
