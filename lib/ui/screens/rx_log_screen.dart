import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../l10n/l10n.dart';
import '../../providers/radio_providers.dart';

/// RX log app: captures raw 0x88 RX frames and exports to PCAP.
class RxLogScreen extends ConsumerWidget {
  const RxLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(rxLogProvider);
    final theme = Theme.of(context);

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          color: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
          child: Row(
            children: [
              Icon(
                Icons.memory,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                '${entries.length} ${context.l10n.rxLogPacketCount}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: context.l10n.rxLogClearLog,
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed:
                    entries.isEmpty ? null : () => _confirmClear(context, ref),
              ),
              IconButton(
                tooltip: context.l10n.rxLogExportPcap,
                icon: const Icon(Icons.share_outlined, size: 20),
                onPressed:
                    entries.isEmpty
                        ? null
                        : () => _exportPcapng(context, entries),
              ),
            ],
          ),
        ),
        Expanded(
          child:
              entries.isEmpty
                  ? _EmptyState(theme: theme)
                  : ListView.builder(
                    reverse: true,
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final e = entries[index];
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.waves, size: 18),
                        title: Text(
                          _typeLabel(e.payloadType),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          '${_fmtTime(e.receivedAt)}  |  SNR ${e.snr.toStringAsFixed(1)} dB  |  RSSI ${e.rssi} dBm  |  ${e.rawPacket.length} B',
                          style: theme.textTheme.bodySmall,
                        ),
                        trailing:
                            e.packetHashHex != null
                                ? Text(
                                  e.packetHashHex!.substring(0, 6),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontFamily: 'monospace',
                                  ),
                                )
                                : null,
                      );
                    },
                  ),
        ),
      ],
    );
  }

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(context.l10n.rxLogClearTitle),
            content: Text(context.l10n.rxLogClearConfirm),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(context.l10n.commonCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(context.l10n.commonClear),
              ),
            ],
          ),
    );

    if (ok == true) {
      ref.read(rxLogProvider.notifier).clear();
    }
  }

  Future<void> _exportPcapng(
    BuildContext context,
    List<RxLogEntry> entries,
  ) async {
    if (entries.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.rxLogEmpty)));
      return;
    }

    final pcapngBytes = _buildPcapng(entries);
    final filename =
        'meshcore_rx_${DateTime.now().toIso8601String().replaceAll(':', '-')}.pcapng';

    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              pcapngBytes,
              name: filename,
              mimeType: 'application/octet-stream',
            ),
          ],
          text: 'MeshCore RX Log (.pcapng) - wireshark-meshcore',
          subject: 'MeshCore RX Log',
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.rxLogExportFail)));
    }
  }

  Uint8List _buildPcapng(List<RxLogEntry> entries) {
    const linkTypeMeshcore = 147; // DLT_USER0
    const snaplen = 65535;

    final out = BytesBuilder(copy: false);

    // Section Header Block body: <IHHq>
    final shbBody = ByteData(16);
    shbBody.setUint32(0, 0x1a2b3c4d, Endian.little);
    shbBody.setUint16(4, 1, Endian.little);
    shbBody.setUint16(6, 0, Endian.little);
    shbBody.setUint32(8, 0xFFFFFFFF, Endian.little);
    shbBody.setUint32(12, 0xFFFFFFFF, Endian.little);
    _writePcapngBlock(out, 0x0A0D0D0A, shbBody.buffer.asUint8List());

    // Interface Description Block body: <HHI>
    final idbBody = ByteData(8);
    idbBody.setUint16(0, linkTypeMeshcore, Endian.little);
    idbBody.setUint16(2, 0, Endian.little);
    idbBody.setUint32(4, snaplen, Endian.little);
    _writePcapngBlock(out, 0x00000001, idbBody.buffer.asUint8List());

    for (final e in entries) {
      final tsUs = e.receivedAt.millisecondsSinceEpoch * 1000;
      final tsHigh = (tsUs ~/ 0x100000000) & 0xFFFFFFFF;
      final tsLow = tsUs & 0xFFFFFFFF;

      // meshcore_json2pcap compatible radio header: <BBHh>
      final snrInt = (e.snr * 100).round().clamp(-32768, 32767);
      final radioHeader = ByteData(6);
      radioHeader.setUint8(0, 0); // version
      radioHeader.setUint8(1, 0); // pad
      radioHeader.setUint16(2, 6, Endian.little); // header length
      radioHeader.setInt16(4, snrInt, Endian.little); // SNR * 100

      final frame =
          BytesBuilder(copy: false)
            ..add(radioHeader.buffer.asUint8List())
            ..add(e.rawPacket);
      final frameBytes = frame.toBytes();

      // Enhanced Packet Block body: <IIIII> + packet_data
      final epbPrefix = ByteData(20);
      epbPrefix.setUint32(0, 0, Endian.little); // interface id
      epbPrefix.setUint32(4, tsHigh, Endian.little);
      epbPrefix.setUint32(8, tsLow, Endian.little);
      epbPrefix.setUint32(12, frameBytes.length, Endian.little);
      epbPrefix.setUint32(16, frameBytes.length, Endian.little);

      final epbBody =
          BytesBuilder(copy: false)
            ..add(epbPrefix.buffer.asUint8List())
            ..add(frameBytes);
      _writePcapngBlock(out, 0x00000006, epbBody.toBytes());
    }

    return out.toBytes();
  }

  void _writePcapngBlock(BytesBuilder out, int blockType, Uint8List body) {
    final pad = (4 - (body.length % 4)) % 4;
    final totalLen = 12 + body.length + pad;

    final header =
        ByteData(8)
          ..setUint32(0, blockType, Endian.little)
          ..setUint32(4, totalLen, Endian.little);
    out.add(header.buffer.asUint8List());
    out.add(body);
    if (pad > 0) out.add(Uint8List(pad));

    final trailer = ByteData(4)..setUint32(0, totalLen, Endian.little);
    out.add(trailer.buffer.asUint8List());
  }

  String _fmtTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String _typeLabel(int? type) {
    if (type == null) return 'Tipo desconhecido';
    switch (type) {
      case 0x04:
        return 'Advert';
      case 0x05:
        return 'Group Text';
      case 0x02:
        return 'Private Text';
      case 0x08:
        return 'Path';
      case 0x0B:
        return 'Control';
      default:
        return 'Tipo 0x${type.toRadixString(16).padLeft(2, '0')}';
    }
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.portable_wifi_off,
            size: 58,
            color: theme.colorScheme.onSurface.withAlpha(70),
          ),
          const SizedBox(height: 12),
          Text(
            context.l10n.rxLogEmptyTitle,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            context.l10n.rxLogEmptyHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
