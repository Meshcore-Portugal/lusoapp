part of '../plan333_screen.dart';

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
