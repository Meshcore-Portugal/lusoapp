import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../l10n/l10n.dart';
import '../../protocol/protocol.dart';
import '../../providers/radio_providers.dart';
import 'qr_scanner_screen.dart';


part 'parts/channels_create_sheets.dart';
part 'parts/channels_edit_sheet.dart';
part 'parts/channels_list_widgets.dart';
part 'parts/channels_qr_dialog.dart';
// ---------------------------------------------------------------------------
// Channel type enum (used only in the add/create flow)
// ---------------------------------------------------------------------------

enum _ChannelType { publicChannel, hashtag, privateCreate, privateJoin }

// Well-known public channel key (from the MeshCore companion protocol spec)
const _kPublicKeyHex = '8b3387e9c5cdea6ac9e5edbaa115cd72';

Uint8List _publicChannelSecret() {
  return Uint8List.fromList(
    List.generate(
      16,
      (i) => int.parse(_kPublicKeyHex.substring(i * 2, i * 2 + 2), radix: 16),
    ),
  );
}

/// Derives the 16-byte hashtag channel key (delegates to shared protocol implementation).
Uint8List _hashtagKey(String name) => hashtagChannelKey(name);

String _toHex(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List? _fromHex(String hex) {
  final clean = hex.replaceAll(RegExp(r'\s+'), '');
  if (clean.length != 32) return null;
  try {
    return Uint8List.fromList(
      List.generate(
        16,
        (i) => int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16),
      ),
    );
  } catch (_) {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Filter options
// ---------------------------------------------------------------------------

enum _Filter { todos, naoLidos }

// ---------------------------------------------------------------------------
// Main screen
// ---------------------------------------------------------------------------

/// Channels list screen with filter chips and last-message preview.
class ChannelsListScreen extends ConsumerStatefulWidget {
  const ChannelsListScreen({super.key});

  @override
  ConsumerState<ChannelsListScreen> createState() => _ChannelsListScreenState();
}

class _ChannelsListScreenState extends ConsumerState<ChannelsListScreen> {
  _Filter _filter = _Filter.todos;

  @override
  void initState() {
    super.initState();
    // Eagerly load persisted messages for all known channels so the list
    // shows last-message previews without requiring a channel visit first.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadAllChannelMessages(ref.read(channelsProvider));
    });
  }

  void _loadAllChannelMessages(List<ChannelInfo> channels) {
    for (final ch in channels) {
      if (ch.name.isNotEmpty) {
        ref.read(messagesProvider.notifier).ensureLoadedForChannel(ch.index);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final channels = ref.watch(channelsProvider);

    // Also trigger when channels arrive from the radio after the screen opens.
    ref.listen<List<ChannelInfo>>(channelsProvider, (_, next) {
      _loadAllChannelMessages(next);
    });
    final unread = ref.watch(unreadCountsProvider);
    // Watch overall message count so the sort updates when messages arrive;
    // the actual per-channel lookup is O(1) via the notifier partition.
    ref.watch(messagesProvider.select((msgs) => msgs.length));
    final maxChannels = ref.watch(deviceInfoProvider)?.maxChannels ?? 8;

    final configured = channels.where((c) => c.name.isNotEmpty).toList();
    final unreadChannelCount =
        configured.where((c) => unread.forChannel(c.index) > 0).length;

    final filtered =
        _filter == _Filter.naoLidos
            ? configured.where((c) => unread.forChannel(c.index) > 0).toList()
            : List<ChannelInfo>.from(configured);

    final notifier = ref.read(messagesProvider.notifier);
    filtered.sort((a, b) {
      int lastTs(ChannelInfo ch) {
        final msgs = notifier.forChannel(ch.index);
        return msgs.fold(0, (ts, m) => m.timestamp > ts ? m.timestamp : ts);
      }

      final ta = lastTs(a);
      final tb = lastTs(b);
      if (ta != tb) return tb.compareTo(ta); // newest message first
      return a.index.compareTo(b.index); // tie-break by slot index
    });

    final usedIndices = configured.map((c) => c.index).toSet();

    void openTypePicker() {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder:
            (ctx) => _TypePickerSheet(
              onTypeSelected: (type) {
                Navigator.pop(ctx);
                _openCreateSheet(
                  type: type,
                  maxChannels: maxChannels,
                  usedIndices: usedIndices,
                );
              },
              onScanQr: () {
                Navigator.pop(ctx);
                _scanQrToCreate(
                  maxChannels: maxChannels,
                  usedIndices: usedIndices,
                );
              },
            ),
      );
    }

    void openEditSheet(ChannelInfo channel) {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder:
            (_) => _EditChannelSheet(
              channel: channel,
              onSave: (idx, name, secret) async {
                final service = ref.read(radioServiceProvider);
                if (service == null) return;
                await service.setChannel(idx, name, secret);
                await Future.delayed(const Duration(milliseconds: 200));
                await service.requestChannel(idx);
              },
              onDelete: (idx) async {
                final service = ref.read(radioServiceProvider);
                if (service == null) return;
                // Delete = SET_CHANNEL with empty name and all-zero 16-byte secret
                await service.setChannel(idx, '', Uint8List(16));
                await Future.delayed(const Duration(milliseconds: 200));
                await service.requestChannel(idx);
              },
            ),
      );
    }

    return Stack(
      children: [
        Column(
          children: [
            _FilterBar(
              filter: _filter,
              totalCount: configured.length,
              unreadCount: unreadChannelCount,
              onChanged: (f) => setState(() => _filter = f),
            ),
            Expanded(
              child:
                  configured.isEmpty
                      ? _EmptyState(
                        onRefresh: () {
                          final service = ref.read(radioServiceProvider);
                          if (service == null) return;
                          for (var i = 0; i < maxChannels; i++) {
                            service.requestChannel(i);
                          }
                        },
                      )
                      : filtered.isEmpty
                      ? _NoUnreadState(
                        onClearFilter:
                            () => setState(() => _filter = _Filter.todos),
                      )
                      : RefreshIndicator(
                        onRefresh: () async {
                          final service = ref.read(radioServiceProvider);
                          if (service == null) return;
                          for (var i = 0; i < maxChannels; i++) {
                            await service.requestChannel(i);
                            await Future.delayed(
                              const Duration(milliseconds: 100),
                            );
                          }
                        },
                        child: ListView.builder(
                          padding: const EdgeInsets.only(top: 4, bottom: 80),
                          itemCount: filtered.length,
                          itemBuilder:
                              (context, index) => _ChannelTile(
                                channel: filtered[index],
                                onEdit: () => openEditSheet(filtered[index]),
                              ),
                        ),
                      ),
            ),
          ],
        ),

        // FAB — opens type picker
        Positioned(
          bottom: 16,
          right: 16,
          child: FloatingActionButton(
            heroTag: 'channels_fab',
            onPressed: openTypePicker,
            tooltip: context.l10n.commonAdd,
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }

  void _openCreateSheet({
    required _ChannelType type,
    required int maxChannels,
    required Set<int> usedIndices,
    String? prefillName,
    Uint8List? prefillSecret,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder:
          (_) => _CreateChannelSheet(
            type: type,
            maxChannels: maxChannels,
            usedIndices: usedIndices,
            prefillName: prefillName,
            prefillSecret: prefillSecret,
            onSave: (idx, name, secret) async {
              final service = ref.read(radioServiceProvider);
              if (service == null) return;
              await service.setChannel(idx, name, secret);
              await Future.delayed(const Duration(milliseconds: 200));
              await service.requestChannel(idx);
            },
          ),
    );
  }

  Future<void> _scanQrToCreate({
    required int maxChannels,
    required Set<int> usedIndices,
  }) async {
    final raw = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const QrScannerScreen(title: 'Ler QR de Canal'),
      ),
    );
    if (raw == null || !mounted) return;

    final result = MeshCoreUri.parse(raw);
    if (result is MeshCoreChannelUri) {
      _openCreateSheet(
        type: _ChannelType.privateJoin,
        maxChannels: maxChannels,
        usedIndices: usedIndices,
        prefillName: result.name,
        prefillSecret: result.secret,
      );
    } else if (result is MeshCoreContactUri) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'QR de contacto detectado. Use o ecrã de Contactos para o adicionar.',
            ),
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('QR Code MeshCore inválido ou não reconhecido.'),
          ),
        );
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Type picker sheet — matches official app layout
