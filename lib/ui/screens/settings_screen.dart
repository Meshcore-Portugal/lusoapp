import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../l10n/l10n.dart';
import '../../protocol/protocol.dart';
import '../../providers/canned_messages_provider.dart';
import '../../providers/gps_sharing_provider.dart';
import '../../providers/radio_providers.dart';
import '../../providers/sos_settings_provider.dart';
import '../../services/gps_sharing_service.dart';
import '../../services/notification_service.dart';
import '../../services/sos_service.dart';
import '../../services/storage_service.dart';
import '../../transport/radio_transport.dart';
import '../theme.dart';

part 'parts/settings_appearance.dart';
part 'parts/settings_canned_messages.dart';
part 'parts/settings_sos.dart';
part 'parts/settings_gps_sharing.dart';
part 'parts/settings_notifications.dart';
part 'parts/settings_keybackup.dart';
part 'parts/settings_prune_config.dart';

String _sanitizeUtf16Ui(String s) {
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c >= 0xD800 && c <= 0xDFFF) {
      final buf = StringBuffer();
      for (var j = 0; j < s.length; j++) {
        final u = s.codeUnitAt(j);
        if (u >= 0xD800 && u <= 0xDBFF) {
          if (j + 1 < s.length) {
            final u2 = s.codeUnitAt(j + 1);
            if (u2 >= 0xDC00 && u2 <= 0xDFFF) {
              buf.write(s[j]);
              buf.write(s[j + 1]);
              j++;
              continue;
            }
          }
          buf.writeCharCode(0xFFFD);
        } else if (u >= 0xDC00 && u <= 0xDFFF) {
          buf.writeCharCode(0xFFFD);
        } else {
          buf.write(s[j]);
        }
      }
      return buf.toString();
    }
  }
  return s;
}

String _safeUiText(String? value, {required String fallback}) {
  final sanitized = _sanitizeUtf16Ui(value ?? '').trim();
  return sanitized.isEmpty ? fallback : sanitized;
}

/// App settings screen.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _version = info.version);
    });
  }

  @override
  Widget build(BuildContext context) {
    final selfInfo = ref.watch(selfInfoProvider);
    final connectionState = ref.watch(connectionProvider);
    final autoReconnect = ref.watch(autoReconnectProvider);
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Identity
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.badge, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        context.l10n.settingsIdentity,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    title: Text(context.l10n.commonName),
                    subtitle: Text(
                      _safeUiText(selfInfo?.name, fallback: 'Não conectado'),
                    ),
                    trailing: const Icon(Icons.edit),
                    onTap: () => _editName(context, ref),
                  ),
                  if (selfInfo != null)
                    ListTile(
                      title: Text(context.l10n.settingsPublicKey),
                      subtitle: Text(
                        selfInfo.publicKey
                            .map((b) => b.toRadixString(16).padLeft(2, '0'))
                            .join(),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.copy, size: 18),
                        tooltip: context.l10n.settingsCopyPublicKey,
                        onPressed: () {
                          final hex =
                              selfInfo.publicKey
                                  .map(
                                    (b) => b.toRadixString(16).padLeft(2, '0'),
                                  )
                                  .join();
                          Clipboard.setData(ClipboardData(text: hex));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                context.l10n.settingsPublicKeyCopied,
                              ),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                    ),
                  if (selfInfo != null)
                    ListTile(
                      leading: const Icon(Icons.qr_code),
                      title: Text(context.l10n.settingsShareContact),
                      subtitle: Text(context.l10n.settingsShareContactDesc),
                      onTap: () => _showOwnQrCode(context, selfInfo),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Private key backup
          const _KeyBackupCard(),
          const SizedBox(height: 16),

          // Connection
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.link, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        context.l10n.settingsConnection,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    title: Text(context.l10n.commonStatus),
                    subtitle: Text(
                      _connectionStateText(context, connectionState),
                    ),
                    leading: Icon(
                      connectionState == TransportState.connected
                          ? Icons.check_circle
                          : Icons.cancel,
                      color:
                          connectionState == TransportState.connected
                              ? Colors.green
                              : Colors.red,
                    ),
                  ),
                  SwitchListTile(
                    title: Text(context.l10n.settingsAutoReconnect),
                    subtitle: Text(context.l10n.settingsAutoReconnectDesc),
                    secondary: const Icon(Icons.autorenew),
                    value: autoReconnect,
                    onChanged:
                        (v) => ref.read(autoReconnectProvider.notifier).set(v),
                  ),
                  if (connectionState == TransportState.connected) ...[
                    ListTile(
                      title: Text(context.l10n.settingsRadioConfig),
                      subtitle: Text(context.l10n.settingsRadioConfigDesc),
                      leading: const Icon(Icons.settings_input_antenna),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/settings/radio'),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _confirmAndReboot(context),
                            icon: const Icon(Icons.restart_alt),
                            label: Text(context.l10n.settingsReboot),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    context.l10n.settingsShutdownUnavailable,
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.power_settings_new),
                            label: Text(context.l10n.settingsShutdown),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Notifications
          const _NotificationsCard(),
          const SizedBox(height: 16),

          // Appearance
          const _AppearanceCard(),
          const SizedBox(height: 16),

          // Canned messages
          const _CannedMessagesCard(),
          const SizedBox(height: 16),

          // SOS
          const _SosSettingsCard(),
          const SizedBox(height: 16),

          // GPS sharing
          const _GpsSharingCard(),
          const SizedBox(height: 16),

          // Prune configuration
          const _PruneConfigCard(),
          const SizedBox(height: 16),

          // About
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        context.l10n.settingsAbout,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    title: Text(context.l10n.settingsAppName),
                    subtitle: Text(
                      '${context.l10n.settingsAppSubtitle}\n${context.l10n.settingsCredit}',
                    ),
                  ),
                  ListTile(
                    title: Text(context.l10n.settingsVersion),
                    subtitle: Text(_version.isEmpty ? '…' : _version),
                  ),
                  ListTile(
                    title: Text(context.l10n.settingsProtocol),
                    subtitle: Text(context.l10n.settingsProtocolName),
                  ),
                  ListTile(
                    title: Text(context.l10n.settingsLicense),
                    subtitle: Text(context.l10n.settingsLicenseMIT),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _connectionStateText(BuildContext context, TransportState state) {
    return switch (state) {
      TransportState.connected => context.l10n.settingsConnected,
      TransportState.connecting => context.l10n.commonConnecting,
      TransportState.scanning => context.l10n.commonSearching,
      TransportState.error => context.l10n.settingsConnectionError,
      TransportState.disconnected => context.l10n.settingsDisconnected,
    };
  }

  Future<void> _confirmAndReboot(BuildContext context) async {
    final service = ref.read(radioServiceProvider);
    if (service == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.commonRadioDisconnected)),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(context.l10n.settingsRebootTitle),
            content: Text(context.l10n.settingsRebootContent),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(context.l10n.commonCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(context.l10n.settingsReboot),
              ),
            ],
          ),
    );

    if (ok != true || !mounted) return;

    try {
      await service.reboot();
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.settingsRebootSent)));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.settingsRebootFail)));
    }
  }

  void _showOwnQrCode(BuildContext context, SelfInfo selfInfo) {
    final uri = MeshCoreUri.buildContactUri(
      name: selfInfo.name,
      publicKey: selfInfo.publicKey,
      type: 1,
    );
    showDialog<void>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(context.l10n.settingsOwnQrCodeTitle),
            content: SizedBox(
              width: 260,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  QrImageView(
                    data: uri,
                    size: 240,
                    backgroundColor: Colors.white,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    selfInfo.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.l10n.contactsTypeCompanion,
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(context.l10n.commonClose),
              ),
            ],
          ),
    );
  }

  void _editName(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController(
      text: ref.read(selfInfoProvider)?.name ?? '',
    );

    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(context.l10n.settingsEditNameTitle),
            content: TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: context.l10n.settingsNodeNameLabel,
                hintText: context.l10n.settingsNodeNameHint,
              ),
              maxLength: 32,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(context.l10n.commonCancel),
              ),
              FilledButton(
                onPressed: () {
                  final name = controller.text.trim();
                  if (name.isNotEmpty) {
                    ref.read(radioServiceProvider)?.setAdvertName(name);
                    final current = ref.read(selfInfoProvider);
                    if (current != null) {
                      ref.read(selfInfoProvider.notifier).state = current
                          .copyWith(name: name);
                    }
                  }
                  Navigator.pop(ctx);
                },
                child: Text(context.l10n.commonSave),
              ),
            ],
          ),
    );
  }
}
