import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../protocol/cayenne_lpp.dart';
import '../../../protocol/companion_decoder.dart';
import '../../../l10n/l10n.dart';
import '../../../providers/radio_providers.dart';

part 'parts/telemetry_battery_card.dart';
part 'parts/telemetry_network_card.dart';
part 'parts/telemetry_entry_card.dart';
part 'parts/telemetry_radio_stats_cards.dart';

/// Telemetry dashboard — battery history chart, CayenneLPP sensor readings,
/// and network statistics.
class TelemetryScreen extends ConsumerStatefulWidget {
  const TelemetryScreen({super.key});

  @override
  ConsumerState<TelemetryScreen> createState() => _TelemetryScreenState();
}

class _TelemetryScreenState extends ConsumerState<TelemetryScreen> {
  final _rfSectionKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final scrollToRf = ref.read(telemetryScrollToRfProvider);
      if (scrollToRf) {
        ref.read(telemetryScrollToRfProvider.notifier).state = false;
        final ctx = _rfSectionKey.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeInOut,
            alignment: 0.0,
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final batteryMv = ref.watch(batteryProvider);
    final battHistoryRaw = ref.watch(batteryHistoryProvider);
    final stats = ref.watch(networkStatsProvider);
    final telemetry = ref.watch(telemetryProvider);
    final statsCore = ref.watch(radioStatsCoreProvider);
    final statsRadio = ref.watch(radioStatsRadioProvider);
    final statsPackets = ref.watch(radioStatsPacketsProvider);
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ---- Battery section ----
        _SectionHeader(
          label: context.l10n.telemetryBattery,
          icon: Icons.battery_charging_full,
        ),
        const SizedBox(height: 8),
        _BatteryCard(
          currentMv: batteryMv,
          history: battHistoryRaw,
          theme: theme,
        ),
        const SizedBox(height: 20),

        // ---- Network stats section ----
        _SectionHeader(
          label: context.l10n.telemetryNetStats,
          icon: Icons.bar_chart,
        ),
        const SizedBox(height: 8),
        _NetworkStatsCard(stats: stats, theme: theme),
        const SizedBox(height: 20),

        // ---- Radio core stats section ----
        _SectionHeader(
          label: context.l10n.telemetryRadioState,
          icon: Icons.memory,
        ),
        const SizedBox(height: 8),
        if (statsCore == null)
          _EmptyHint(
            icon: Icons.hourglass_empty,
            message: context.l10n.telemetryRadioWaiting,
            theme: theme,
          )
        else
          _RadioCoreStatsCard(stats: statsCore, theme: theme),
        const SizedBox(height: 20),

        // ---- Radio RF stats section ----
        _SectionHeader(
          key: _rfSectionKey,
          label: context.l10n.telemetryRadioRF,
          icon: Icons.cell_tower,
        ),
        const SizedBox(height: 8),
        if (statsRadio == null)
          _EmptyHint(
            icon: Icons.hourglass_empty,
            message: context.l10n.telemetryRFWaiting,
            theme: theme,
          )
        else
          _RadioRfStatsCard(stats: statsRadio, theme: theme),
        const SizedBox(height: 20),

        // ---- Packet counters section ----
        _SectionHeader(
          label: context.l10n.telemetryPacketCounters,
          icon: Icons.swap_horiz,
        ),
        const SizedBox(height: 8),
        if (statsPackets == null)
          _EmptyHint(
            icon: Icons.hourglass_empty,
            message: context.l10n.telemetryCountersWaiting,
            theme: theme,
          )
        else
          _RadioPacketStatsCard(stats: statsPackets, theme: theme),
        const SizedBox(height: 20),

        // ---- CayenneLPP sensor readings ----
        _SectionHeader(
          label: context.l10n.telemetrySensors,
          icon: Icons.sensors,
        ),
        const SizedBox(height: 8),
        if (telemetry.isEmpty)
          _EmptyHint(
            icon: Icons.sensors_off,
            message: context.l10n.telemetryNoData,
            theme: theme,
          )
        else
          for (final entry in telemetry)
            _TelemetryEntryCard(entry: entry, theme: theme),
      ],
    );
  }
}

