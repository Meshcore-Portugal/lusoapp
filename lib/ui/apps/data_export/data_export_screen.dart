import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../l10n/l10n.dart';
import '../../../protocol/models.dart';
import '../../../providers/radio_providers.dart';

/// Data Export app — exports contacts (CSV) and map data (KML) via share sheet.
class DataExportScreen extends ConsumerStatefulWidget {
  const DataExportScreen({super.key});

  @override
  ConsumerState<DataExportScreen> createState() => _DataExportScreenState();
}

class _DataExportScreenState extends ConsumerState<DataExportScreen> {
  bool _exportingContacts = false;
  bool _exportingMessages = false;
  bool _exportingKml = false;

  // ---------------------------------------------------------------------------
  // CSV — contacts
  // ---------------------------------------------------------------------------
  String _buildContactsCsv(List<Contact> contacts) {
    final buf = StringBuffer();
    buf.writeln(
      'name,display_name,type,short_id,public_key_hex,'
      'latitude,longitude,last_heard,favourite',
    );
    for (final c in contacts) {
      final pkHex =
          c.publicKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      final type = switch (c.type) {
        0x01 => 'chat',
        0x02 => 'repeater',
        0x03 => 'room',
        0x04 => 'sensor',
        _ => c.type.toString(),
      };
      final lastHeard =
          c.lastAdvertTimestamp == 0
              ? ''
              : DateTime.fromMillisecondsSinceEpoch(
                c.lastAdvertTimestamp * 1000,
              ).toIso8601String();
      buf.writeln(
        [
          _csvEsc(c.name),
          _csvEsc(c.displayName),
          type,
          c.shortId,
          pkHex,
          c.latitude?.toStringAsFixed(6) ?? '',
          c.longitude?.toStringAsFixed(6) ?? '',
          lastHeard,
          c.isFavorite ? '1' : '0',
        ].join(','),
      );
    }
    return buf.toString();
  }

  // ---------------------------------------------------------------------------
  // CSV — messages (all stored conversations)
  // ---------------------------------------------------------------------------
  Future<String> _buildMessagesCsv(List<Contact> contacts) async {
    // Ensure all contact histories are loaded.
    final notifier = ref.read(messagesProvider.notifier);
    for (final c in contacts) {
      await notifier.ensureLoadedForContact(c.shortId);
    }
    final channels = ref.read(channelsProvider).where((c) => !c.isEmpty);
    for (final ch in channels) {
      await notifier.ensureLoadedForChannel(ch.index);
    }

    final buf = StringBuffer();
    buf.writeln(
      'timestamp_iso,direction,conversation_type,conversation_name,'
      'sender_name,text,snr_db,hop_count,confirmed',
    );

    final msgs = List<ChatMessage>.from(ref.read(messagesProvider))
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    for (final m in msgs) {
      if (m.isCliResponse) continue; // skip CLI noise
      final ts =
          DateTime.fromMillisecondsSinceEpoch(
            m.timestamp * 1000,
          ).toIso8601String();
      final direction = m.isOutgoing ? 'out' : 'in';
      String convType;
      String convName;
      if (m.channelIndex != null) {
        convType = 'channel';
        final ch = channels.where((c) => c.index == m.channelIndex).firstOrNull;
        convName = ch?.name ?? 'ch${m.channelIndex}';
      } else {
        convType = 'private';
        final senderHex =
            m.senderKey != null
                ? m.senderKey!
                    .sublist(0, 4)
                    .map((b) => b.toRadixString(16).padLeft(2, '0'))
                    .join()
                : '';
        final contact =
            contacts.where((c) => c.shortId == senderHex).firstOrNull;
        convName = contact?.displayName ?? m.senderName ?? senderHex;
      }
      buf.writeln(
        [
          ts,
          direction,
          convType,
          _csvEsc(convName),
          _csvEsc(m.senderName ?? ''),
          _csvEsc(m.text),
          m.snr?.toStringAsFixed(1) ?? '',
          m.pathLen?.toString() ?? '',
          m.confirmed ? '1' : '0',
        ].join(','),
      );
    }
    return buf.toString();
  }

  // ---------------------------------------------------------------------------
  // KML — contacts with GPS
  // ---------------------------------------------------------------------------
  String _buildKml(List<Contact> contacts, SelfInfo? self) {
    final buf = StringBuffer();
    buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buf.writeln(
      '<kml xmlns="http://www.opengis.net/kml/2.2">'
      '<Document>',
    );
    buf.writeln('<name>MeshCore Contacts</name>');
    buf.writeln(
      '<description>Exported from lusoapp — MeshCore Portugal</description>',
    );

    // Style map: one icon per node type.
    final styles = {
      'chat': (
        'http://maps.google.com/mapfiles/kml/paddle/blu-circle.png',
        '0xFF4488FF',
      ),
      'repeater': (
        'http://maps.google.com/mapfiles/kml/paddle/orange-circle.png',
        '0xFFFF8800',
      ),
      'room': (
        'http://maps.google.com/mapfiles/kml/paddle/purple-circle.png',
        '0xFFAA44CC',
      ),
      'sensor': (
        'http://maps.google.com/mapfiles/kml/paddle/grn-circle.png',
        '0xFF22AA88',
      ),
      'self': (
        'http://maps.google.com/mapfiles/kml/paddle/red-circle.png',
        '0xFFFF2222',
      ),
    };
    for (final entry in styles.entries) {
      buf.writeln(
        '<Style id="${entry.key}">'
        '<IconStyle><color>${entry.value.$2}</color>'
        '<Icon><href>${entry.value.$1}</href></Icon>'
        '</IconStyle></Style>',
      );
    }

    // Own position.
    if (self != null && self.latitude != null && self.longitude != null) {
      buf.writeln(
        '<Placemark>'
        '<name>${_xmlEsc(self.name)} (you)</name>'
        '<styleUrl>#self</styleUrl>'
        '<Point><coordinates>'
        '${self.longitude!.toStringAsFixed(6)},${self.latitude!.toStringAsFixed(6)},0'
        '</coordinates></Point>'
        '</Placemark>',
      );
    }

    // Contacts with GPS.
    for (final c in contacts) {
      if (c.latitude == null || c.longitude == null) continue;
      final styleId = switch (c.type) {
        0x02 => 'repeater',
        0x03 => 'room',
        0x04 => 'sensor',
        _ => 'chat',
      };
      final lastHeard =
          c.lastAdvertTimestamp == 0
              ? ''
              : DateTime.fromMillisecondsSinceEpoch(
                c.lastAdvertTimestamp * 1000,
              ).toIso8601String();
      buf.writeln(
        '<Placemark>'
        '<name>${_xmlEsc(c.displayName)}</name>'
        '<description>'
        'Type: $styleId&#10;'
        'ID: ${c.shortId}&#10;'
        'Last heard: $lastHeard&#10;'
        'Favourite: ${c.isFavorite}'
        '</description>'
        '<styleUrl>#$styleId</styleUrl>'
        '<Point><coordinates>'
        '${c.longitude!.toStringAsFixed(6)},${c.latitude!.toStringAsFixed(6)},0'
        '</coordinates></Point>'
        '</Placemark>',
      );
    }

    buf.writeln('</Document></kml>');
    return buf.toString();
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------
  static String _csvEsc(String s) {
    if (s.contains(',') || s.contains('"') || s.contains('\n')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  static String _xmlEsc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static String _timestamp() =>
      DateTime.now().toIso8601String().replaceAll(':', '-').substring(0, 19);

  Future<void> _share(
    Uint8List bytes,
    String filename,
    String mime,
    String subject,
  ) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, name: filename, mimeType: mime)],
        subject: subject,
      ),
    );
  }

  Future<void> _exportContacts() async {
    setState(() => _exportingContacts = true);
    try {
      final contacts = ref.read(contactsProvider);
      if (contacts.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.dataExportNoContacts)),
          );
        }
        return;
      }
      final csv = _buildContactsCsv(contacts);
      final bytes = Uint8List.fromList(utf8.encode(csv));
      await _share(
        bytes,
        'meshcore_contacts_${_timestamp()}.csv',
        'text/csv',
        'MeshCore Contacts',
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.dataExportFailed)));
      }
    } finally {
      if (mounted) setState(() => _exportingContacts = false);
    }
  }

  Future<void> _exportMessages() async {
    setState(() => _exportingMessages = true);
    try {
      final contacts = ref.read(contactsProvider);
      final csv = await _buildMessagesCsv(contacts);
      final lines = csv.split('\n').length - 1; // -1 for header
      if (lines <= 1) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.dataExportNoMessages)),
          );
        }
        return;
      }
      final bytes = Uint8List.fromList(utf8.encode(csv));
      await _share(
        bytes,
        'meshcore_messages_${_timestamp()}.csv',
        'text/csv',
        'MeshCore Messages',
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.dataExportFailed)));
      }
    } finally {
      if (mounted) setState(() => _exportingMessages = false);
    }
  }

  Future<void> _exportKml() async {
    setState(() => _exportingKml = true);
    try {
      final contacts = ref.read(contactsProvider);
      final self = ref.read(selfInfoProvider);
      final withGps = contacts.where(
        (c) => c.latitude != null && c.longitude != null,
      );
      final selfHasGps = self?.latitude != null && self?.longitude != null;
      if (withGps.isEmpty && !selfHasGps) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(context.l10n.dataExportNoGps)));
        }
        return;
      }
      final kml = _buildKml(contacts, self);
      final bytes = Uint8List.fromList(utf8.encode(kml));
      await _share(
        bytes,
        'meshcore_map_${_timestamp()}.kml',
        'application/vnd.google-earth.kml+xml',
        'MeshCore Map',
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.dataExportFailed)));
      }
    } finally {
      if (mounted) setState(() => _exportingKml = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final contacts = ref.watch(contactsProvider);
    final theme = Theme.of(context);
    final gpsCount =
        contacts.where((c) => c.latitude != null && c.longitude != null).length;

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.dataExportTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ExportCard(
            icon: Icons.contacts_outlined,
            color: const Color(0xFF4F46E5),
            title: context.l10n.dataExportContactsTitle,
            description: context.l10n.dataExportContactsDesc(contacts.length),
            format: 'CSV',
            loading: _exportingContacts,
            onExport: contacts.isEmpty ? null : _exportContacts,
          ),
          const SizedBox(height: 12),
          _ExportCard(
            icon: Icons.chat_bubble_outline,
            color: const Color(0xFF0EA5E9),
            title: context.l10n.dataExportMessagesTitle,
            description: context.l10n.dataExportMessagesDesc,
            format: 'CSV',
            loading: _exportingMessages,
            onExport: _exportMessages,
          ),
          const SizedBox(height: 12),
          _ExportCard(
            icon: Icons.map_outlined,
            color: const Color(0xFF22C55E),
            title: context.l10n.dataExportKmlTitle,
            description: context.l10n.dataExportKmlDesc(gpsCount),
            format: 'KML',
            loading: _exportingKml,
            onExport: gpsCount == 0 ? null : _exportKml,
          ),
          const SizedBox(height: 24),
          Text(
            context.l10n.dataExportNote,
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

// ---------------------------------------------------------------------------
// Export card widget
// ---------------------------------------------------------------------------
class _ExportCard extends StatelessWidget {
  const _ExportCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
    required this.format,
    required this.loading,
    required this.onExport,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String description;
  final String format;
  final bool loading;
  final VoidCallback? onExport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withAlpha(30),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color.withAlpha(80), width: 1.2),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: color.withAlpha(25),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: color.withAlpha(80),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          format,
                          style: TextStyle(
                            color: color,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 40,
              height: 40,
              child:
                  loading
                      ? Padding(
                        padding: const EdgeInsets.all(8),
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: color,
                        ),
                      )
                      : IconButton(
                        icon: Icon(
                          Icons.ios_share_outlined,
                          color:
                              onExport == null
                                  ? theme.colorScheme.onSurface.withAlpha(60)
                                  : color,
                        ),
                        onPressed: onExport,
                        tooltip: 'Export $format',
                        padding: EdgeInsets.zero,
                      ),
            ),
          ],
        ),
      ),
    );
  }
}
