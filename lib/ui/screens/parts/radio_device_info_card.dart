part of '../radio_settings_screen.dart';

// Device info card
// ---------------------------------------------------------------------------

class _DeviceInfoCard extends ConsumerWidget {
  const _DeviceInfoCard({
    required this.selfInfo,
    required this.deviceInfo,
    required this.contactCount,
    required this.activeChannelCount,
    required this.discoveredCount,
    required this.appVersion,
  });

  final SelfInfo? selfInfo;
  final DeviceInfo? deviceInfo;
  final int contactCount;
  final int activeChannelCount;
  final int discoveredCount;
  final String appVersion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final maxChannels = deviceInfo?.maxChannels;
    final maxContacts = deviceInfo?.maxContacts;
    final (storageUsed, storageTotal) = ref.watch(storageProvider);

    String kbStr(int bytes) {
      if (bytes < 1024) return '${bytes}b';
      return '${(bytes / 1024).toStringAsFixed(0)}kb';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.radioSettingsDevice,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),

            // Radio identity rows
            if (selfInfo != null)
              _InfoRow(label: l10n.commonName, value: selfInfo!.name),
            if (deviceInfo != null) ...[
              _InfoRow(
                label: l10n.radioSettingsModel,
                value: deviceInfo!.model ?? deviceInfo!.deviceName,
              ),
              _InfoRow(
                label: l10n.radioSettingsFirmware,
                value:
                    deviceInfo!.versionString ??
                    'v${deviceInfo!.firmwareVersion}',
              ),
            ],

            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),

            // Capacity indicators row
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _CapacityRow(
                        label: l10n.radioSettingsChannels,
                        used: activeChannelCount,
                        max: maxChannels,
                      ),
                      const SizedBox(height: 4),
                      _CapacityRow(
                        label: l10n.radioSettingsContacts,
                        used: contactCount,
                        max: maxContacts,
                      ),
                      const SizedBox(height: 4),
                      _CapacityRow(
                        label: l10n.radioSettingsDiscovered,
                        used: discoveredCount,
                        max: null,
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Storage
            if (storageUsed != null && storageTotal != null) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    Icons.sd_storage,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.radioSettingsStorage,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withAlpha(140),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value:
                                      storageTotal > 0
                                          ? storageUsed / storageTotal
                                          : 0,
                                  minHeight: 6,
                                  backgroundColor:
                                      theme.colorScheme.surfaceContainerHighest,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${kbStr(storageUsed)} / ${kbStr(storageTotal)}',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],

            // App version
            if (appVersion.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 8),
              _InfoRow(label: l10n.radioSettingsAppVersion, value: appVersion),
            ],
          ],
        ),
      ),
    );
  }
}

class _CapacityRow extends StatelessWidget {
  const _CapacityRow({
    required this.label,
    required this.used,
    required this.max,
  });

  final String label;
  final int used;
  final int? max;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valueText = max != null ? '$used/$max' : '$used';
    return Row(
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withAlpha(140),
            ),
          ),
        ),
        Text(
          valueText,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _ConfigRow extends StatelessWidget {
  const _ConfigRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onPrimaryContainer;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(color: color),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withAlpha(140),
              ),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
