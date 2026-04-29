part of '../settings_screen.dart';

// ---------------------------------------------------------------------------
// GPS sharing card — user-controlled push of phone location to the radio.
// Defaults to OFF. The user is in charge.
// ---------------------------------------------------------------------------

class _GpsSharingCard extends ConsumerWidget {
  const _GpsSharingCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings = ref.watch(gpsSharingProvider);
    final connected = ref.watch(connectionProvider) == TransportState.connected;

    final statusColor =
        settings.isEnabled
            ? (settings.isAuto ? Colors.green : Colors.orange)
            : theme.colorScheme.onSurfaceVariant;
    final statusLabel = switch (settings.mode) {
      GpsSharingMode.off => context.l10n.gpsSharingStatusOff,
      GpsSharingMode.manual => context.l10n.gpsSharingStatusManual,
      GpsSharingMode.auto => context.l10n.gpsSharingStatusAuto,
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.my_location, color: statusColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.l10n.gpsSharingTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withAlpha(40),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: statusColor.withAlpha(120)),
                  ),
                  child: Text(
                    statusLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              context.l10n.gpsSharingSubtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),

            // Mode segmented control
            SegmentedButton<GpsSharingMode>(
              segments: [
                ButtonSegment(
                  value: GpsSharingMode.off,
                  label: Text(context.l10n.gpsSharingModeOff),
                  icon: const Icon(Icons.location_off),
                ),
                ButtonSegment(
                  value: GpsSharingMode.manual,
                  label: Text(context.l10n.gpsSharingModeManual),
                  icon: const Icon(Icons.touch_app),
                ),
                ButtonSegment(
                  value: GpsSharingMode.auto,
                  label: Text(context.l10n.gpsSharingModeAuto),
                  icon: const Icon(Icons.autorenew),
                ),
              ],
              selected: {settings.mode},
              onSelectionChanged: (sel) async {
                final m = sel.first;
                await ref.read(gpsSharingProvider.notifier).setMode(m);
                // Keep the radio's advert-location-policy in lock-step with
                // the app mode so the user only has one knob to think about:
                //   Off    → radio also stops broadcasting location
                //   Manual → radio starts broadcasting (uses last pushed fix)
                //   Auto   → radio starts broadcasting (auto-refreshed by app)
                await _syncRadioPolicyWithMode(ref, m);
                if (!context.mounted) return;
                if (m == GpsSharingMode.off) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(context.l10n.gpsSharingClearedOnRadio),
                    ),
                  );
                }
              },
            ),
            const SizedBox(height: 14),

            // Precision chips
            Text(
              context.l10n.gpsSharingPrecisionTitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _precisionChip(
                  context,
                  ref,
                  GpsSharingPrecision.exact,
                  context.l10n.gpsSharingPrecisionExact,
                  '~1 m',
                  settings.precision,
                ),
                _precisionChip(
                  context,
                  ref,
                  GpsSharingPrecision.rounded100m,
                  context.l10n.gpsSharingPrecisionRough,
                  '±100 m',
                  settings.precision,
                ),
                _precisionChip(
                  context,
                  ref,
                  GpsSharingPrecision.rounded1km,
                  context.l10n.gpsSharingPrecisionVague,
                  '±1 km',
                  settings.precision,
                ),
              ],
            ),

            // Auto-only: interval picker + move-aware threshold
            if (settings.mode == GpsSharingMode.auto) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      context.l10n.gpsSharingIntervalLabel,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  Text(
                    '${settings.intervalMinutes} min',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Slider(
                min: 1,
                max: 60,
                divisions: 59,
                value: settings.intervalMinutes.toDouble().clamp(1, 60),
                label: '${settings.intervalMinutes} min',
                onChanged:
                    (v) => ref
                        .read(gpsSharingProvider.notifier)
                        .setIntervalMinutes(v.round()),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      context.l10n.gpsSharingMinMoveLabel,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  Text(
                    settings.minMoveMeters == 0
                        ? context.l10n.gpsSharingMinMoveAlways
                        : '${settings.minMoveMeters} m',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Slider(
                min: 0,
                max: 1000,
                divisions: 20,
                value: settings.minMoveMeters.toDouble().clamp(0, 1000),
                label:
                    settings.minMoveMeters == 0
                        ? context.l10n.gpsSharingMinMoveAlways
                        : '${settings.minMoveMeters} m',
                onChanged:
                    (v) => ref
                        .read(gpsSharingProvider.notifier)
                        .setMinMoveMeters(v.round()),
              ),
              Text(
                context.l10n.gpsSharingMinMoveHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],

            // Interactive switch for the radio's stored adv-loc-policy byte
            // (`CMD_SET_OTHER_PARAMS` / 0x26). Off = never broadcast location
            // in adverts, On = include lat/lon in every advert.
            //
            // The switch is normally driven automatically by the mode chips
            // above (see `_syncRadioPolicyWithMode`). It's kept visible as an
            // advanced override for users who, e.g., want Manual app pushes
            // without the radio actually retransmitting them in adverts.
            if (ref.watch(selfInfoProvider)?.advLocPolicy != null) ...[
              const SizedBox(height: 10),
              const _AdvLocPolicyRow(),
            ],

            // Last shared status
            if (settings.lastSharedAtEpoch != null) ...[
              const SizedBox(height: 8),
              _LastSharedRow(settings: settings),
            ],

            const SizedBox(height: 12),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed:
                        settings.isEnabled && connected
                            ? () => _shareNow(context, ref)
                            : null,
                    icon: const Icon(Icons.upload),
                    label: Text(context.l10n.gpsSharingShareNow),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: connected ? () => _clearNow(context, ref) : null,
                  icon: const Icon(Icons.location_disabled),
                  label: Text(context.l10n.gpsSharingClearNow),
                ),
              ],
            ),

            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer.withAlpha(60),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: theme.colorScheme.error.withAlpha(80),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.privacy_tip_outlined,
                    size: 18,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      context.l10n.gpsSharingPrivacyDisclaimer,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _precisionChip(
    BuildContext context,
    WidgetRef ref,
    GpsSharingPrecision value,
    String label,
    String hint,
    GpsSharingPrecision current,
  ) {
    final selected = current == value;
    return ChoiceChip(
      selected: selected,
      label: Text('$label · $hint'),
      onSelected:
          (_) => ref.read(gpsSharingProvider.notifier).setPrecision(value),
    );
  }

  /// Mirror the chosen [mode] onto the radio's `adv_loc_policy` byte so the
  /// app and the radio always agree on whether location should be broadcast.
  /// No-op when disconnected, when self-info isn't loaded yet, or when the
  /// policy already matches.
  static Future<void> _syncRadioPolicyWithMode(
    WidgetRef ref,
    GpsSharingMode mode,
  ) async {
    final svc = ref.read(radioServiceProvider);
    final self = ref.read(selfInfoProvider);
    if (svc == null || self == null) return;
    final desired = mode == GpsSharingMode.off ? 0 : 1;
    if (self.advLocPolicy == desired) return;
    await svc.setOtherParams(
      manualAddContacts: self.manualAddContacts ?? 0,
      telemetryMode: self.telemetryMode ?? 0,
      advLocPolicy: desired,
      multiAcks: self.multiAcks ?? 0,
    );
    ref.read(selfInfoProvider.notifier).state = self.copyWith(
      advLocPolicy: desired,
    );
  }

  Future<void> _shareNow(BuildContext context, WidgetRef ref) async {
    final svc = ref.read(gpsSharingServiceProvider);
    final res = await svc.shareNow();
    if (!context.mounted) return;
    _showOutcome(context, res);
  }

  Future<void> _clearNow(BuildContext context, WidgetRef ref) async {
    final svc = ref.read(gpsSharingServiceProvider);
    final res = await svc.clearOnRadio();
    if (!context.mounted) return;
    _showOutcome(context, res);
  }

  void _showOutcome(BuildContext context, GpsShareResult res) {
    final l10n = context.l10n;
    final (msg, isError) = switch (res.outcome) {
      GpsShareOutcome.ok => (
        l10n.gpsSharingOutcomeOk(
          (res.lat ?? 0).toStringAsFixed(4),
          (res.lon ?? 0).toStringAsFixed(4),
        ),
        false,
      ),
      GpsShareOutcome.cleared => (l10n.gpsSharingOutcomeCleared, false),
      GpsShareOutcome.disabled => (l10n.gpsSharingOutcomeDisabled, true),
      GpsShareOutcome.noPermission => (l10n.gpsSharingOutcomeNoPerm, true),
      GpsShareOutcome.serviceDisabled => (
        l10n.gpsSharingOutcomeServiceOff,
        true,
      ),
      GpsShareOutcome.noFix => (l10n.gpsSharingOutcomeNoFix, true),
      GpsShareOutcome.notConnected => (
        l10n.gpsSharingOutcomeDisconnected,
        true,
      ),
      GpsShareOutcome.failed => (l10n.gpsSharingOutcomeFailed, true),
      GpsShareOutcome.skippedNoMovement => (
        l10n.gpsSharingOutcomeSkipped,
        false,
      ),
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
        content: Text(
          msg,
          style: isError ? const TextStyle(color: Colors.white) : null,
        ),
      ),
    );
  }
}

class _LastSharedRow extends StatelessWidget {
  const _LastSharedRow({required this.settings});
  final GpsSharingSettings settings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ts = DateTime.fromMillisecondsSinceEpoch(
      settings.lastSharedAtEpoch! * 1000,
    );
    final ago = DateTime.now().difference(ts);
    final agoStr =
        ago.inMinutes < 1
            ? context.l10n.commonJustNow
            : ago.inMinutes < 60
            ? context.l10n.commonMinutesAgo(ago.inMinutes)
            : context.l10n.commonHoursAgo(ago.inHours);

    final lat = settings.lastSharedLat?.toStringAsFixed(4) ?? '—';
    final lon = settings.lastSharedLon?.toStringAsFixed(4) ?? '—';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.green.withAlpha(30),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.withAlpha(80)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline, size: 18, color: Colors.green),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.l10n.gpsSharingLastShared(agoStr, lat, lon),
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// Interactive control for the radio's advert-location-policy byte.
///
/// Reads the current value from `selfInfoProvider` and writes via
/// `CMD_SET_OTHER_PARAMS` (0x26). Because that command is a write-all
/// frame, we round-trip the radio's current `manualAddContacts`,
/// `telemetryMode` and `multiAcks` bytes unchanged — only the policy is
/// modified.
class _AdvLocPolicyRow extends ConsumerStatefulWidget {
  const _AdvLocPolicyRow();

  @override
  ConsumerState<_AdvLocPolicyRow> createState() => _AdvLocPolicyRowState();
}

class _AdvLocPolicyRowState extends ConsumerState<_AdvLocPolicyRow> {
  bool _busy = false;

  Future<void> _toggle(bool on) async {
    final self = ref.read(selfInfoProvider);
    final svc = ref.read(radioServiceProvider);
    if (self == null || svc == null) return;
    final newPolicy = on ? 1 : 0;
    if (self.advLocPolicy == newPolicy) return;
    setState(() => _busy = true);
    try {
      await svc.setOtherParams(
        manualAddContacts: self.manualAddContacts ?? 0,
        telemetryMode: self.telemetryMode ?? 0,
        advLocPolicy: newPolicy,
        multiAcks: self.multiAcks ?? 0,
      );
      // Optimistic update — the radio doesn't push a fresh SELF_INFO after
      // SET_OTHER_PARAMS, so reflect the change immediately. The next
      // app-start refresh will reconcile if the radio rejected it.
      ref.read(selfInfoProvider.notifier).state = self.copyWith(
        advLocPolicy: newPolicy,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final policy = ref.watch(selfInfoProvider)?.advLocPolicy ?? 0;
    final on = policy == 1;
    final subtitle = switch (policy) {
      0 => l10n.gpsSharingAdvPolicyNever,
      1 => l10n.gpsSharingAdvPolicyAlways,
      _ => l10n.gpsSharingAdvPolicyUnknown(policy),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            Icons.router_outlined,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.gpsSharingAdvPolicyTitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (_busy)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Switch(value: on, onChanged: _toggle),
        ],
      ),
    );
  }
}
