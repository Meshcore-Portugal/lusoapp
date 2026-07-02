import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  bool _importingContacts = false;
  bool _importingMessages = false;

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
      'channel_index,private_key_hex,sender_name,text,snr_db,hop_count,confirmed',
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
      final hopCount =
          m.pathLen == null
              ? ''
              : m.pathLen == 0xFF
              ? 'flood'
              : '${m.pathLen! & 0x3F}';
      String convType;
      String convName;
      String channelIndex = '';
      String privateKeyHex = '';
      if (m.channelIndex != null) {
        convType = 'channel';
        channelIndex = '${m.channelIndex}';
        final ch = channels.where((c) => c.index == m.channelIndex).firstOrNull;
        convName = ch?.name ?? 'ch${m.channelIndex}';
      } else {
        convType = 'private';
        privateKeyHex =
            m.senderKey != null
                ? m.senderKey!
                    .map((b) => b.toRadixString(16).padLeft(2, '0'))
                    .join()
                : '';
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
          channelIndex,
          privateKeyHex,
          _csvEsc(m.senderName ?? ''),
          _csvEsc(m.text),
          m.snr?.toStringAsFixed(1) ?? '',
          hopCount,
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

  static List<List<String>> _parseCsvRows(String input) {
    final rows = <List<String>>[];
    final row = <String>[];
    final field = StringBuffer();
    var inQuotes = false;

    void endField() {
      row.add(field.toString());
      field.clear();
    }

    void endRow() {
      endField();
      if (row.isNotEmpty && !(row.length == 1 && row.first.isEmpty)) {
        rows.add(List<String>.from(row));
      }
      row.clear();
    }

    for (var i = 0; i < input.length; i++) {
      final ch = input[i];
      if (inQuotes) {
        if (ch == '"') {
          if (i + 1 < input.length && input[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          field.write(ch);
        }
        continue;
      }

      if (ch == '"') {
        inQuotes = true;
      } else if (ch == ',') {
        endField();
      } else if (ch == '\n') {
        endRow();
      } else if (ch == '\r') {
        if (i + 1 < input.length && input[i + 1] == '\n') i++;
        endRow();
      } else {
        field.write(ch);
      }
    }

    if (field.isNotEmpty || row.isNotEmpty) endRow();
    return rows;
  }

  static Uint8List? _hexToBytes(String hex) {
    final clean = hex.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    if (clean.isEmpty || clean.length.isOdd) return null;
    final out = Uint8List(clean.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      final byteHex = clean.substring(i * 2, i * 2 + 2);
      final v = int.tryParse(byteHex, radix: 16);
      if (v == null) return null;
      out[i] = v;
    }
    return out;
  }

  static int _contactTypeFromCsv(String raw) {
    final v = raw.trim().toLowerCase();
    return switch (v) {
      'chat' => 0x01,
      'repeater' => 0x02,
      'room' => 0x03,
      'sensor' => 0x04,
      _ => int.tryParse(v) ?? 0x01,
    };
  }

  static int? _parseTimestampSec(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    final parsedIso = DateTime.tryParse(s);
    if (parsedIso != null) return parsedIso.millisecondsSinceEpoch ~/ 1000;
    final numeric = int.tryParse(s);
    if (numeric == null) return null;
    if (numeric > 1000000000000) return numeric ~/ 1000; // ms
    return numeric; // sec
  }

  Future<Uint8List?> _pickCsvBytes() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return null;

      final picked = result.files.single;
      final name = picked.name.toLowerCase();
      if (!name.endsWith('.csv')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please select a CSV (.csv) file')),
          );
        }
        return null;
      }

      if (picked.bytes == null || picked.bytes!.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not read selected file')),
          );
        }
        return null;
      }
      return picked.bytes;
    } on MissingPluginException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'File picker is unavailable in this build. Please fully restart the app.',
            ),
          ),
        );
      }
      return null;
    } on PlatformException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open file picker')),
        );
      }
      return null;
    }
  }

  Future<void> _importContacts() async {
    setState(() => _importingContacts = true);
    try {
      final bytes = await _pickCsvBytes();
      if (bytes == null) return;
      final rows = _parseCsvRows(utf8.decode(bytes, allowMalformed: true));
      if (rows.length < 2) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Invalid contacts CSV')));
        }
        return;
      }

      final header = rows.first;
      final index = <String, int>{
        for (var i = 0; i < header.length; i++)
          header[i].trim().toLowerCase(): i,
      };
      final pkIdx = index['public_key_hex'];
      if (pkIdx == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Missing public_key_hex column')),
          );
        }
        return;
      }

      String col(List<String> row, String key) {
        final i = index[key];
        return (i == null || i >= row.length) ? '' : row[i].trim();
      }

      final imported = <Contact>[];
      for (final row in rows.skip(1)) {
        final pk = _hexToBytes(col(row, 'public_key_hex'));
        if (pk == null || pk.isEmpty) continue;
        final name = col(row, 'name');
        final displayName = col(row, 'display_name');
        final customName =
            displayName.isNotEmpty && displayName != name ? displayName : null;
        final lastHeard = _parseTimestampSec(col(row, 'last_heard')) ?? 0;
        final latitude = double.tryParse(col(row, 'latitude'));
        final longitude = double.tryParse(col(row, 'longitude'));
        final favouriteRaw = col(row, 'favourite').toLowerCase();
        final isFav =
            favouriteRaw == '1' ||
            favouriteRaw == 'true' ||
            favouriteRaw == 'yes';

        imported.add(
          Contact(
            publicKey: pk,
            type: _contactTypeFromCsv(col(row, 'type')),
            flags: isFav ? 0x01 : 0x00,
            pathLen: 0xFF,
            name: name,
            lastAdvertTimestamp: lastHeard,
            latitude: latitude,
            longitude: longitude,
            lastModified: lastHeard > 0 ? lastHeard : null,
            customName: customName,
          ),
        );
      }

      if (imported.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('No contacts imported')));
        }
        return;
      }

      final existing = ref.read(contactsProvider);
      final merged = <String, Contact>{
        for (final c in existing)
          c.publicKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join(): c,
      };
      for (final c in imported) {
        merged[c.publicKey
                .map((b) => b.toRadixString(16).padLeft(2, '0'))
                .join()] =
            c;
      }

      ref.read(contactsProvider.notifier).refresh(merged.values.toList());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Imported ${imported.length} contacts')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.dataExportFailed)));
      }
    } finally {
      if (mounted) setState(() => _importingContacts = false);
    }
  }

  Future<void> _importMessages() async {
    setState(() => _importingMessages = true);
    try {
      final bytes = await _pickCsvBytes();
      if (bytes == null) return;
      final rows = _parseCsvRows(utf8.decode(bytes, allowMalformed: true));
      if (rows.length < 2) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Invalid messages CSV')));
        }
        return;
      }

      final header = rows.first;
      final index = <String, int>{
        for (var i = 0; i < header.length; i++)
          header[i].trim().toLowerCase(): i,
      };

      String col(List<String> row, String key) {
        final i = index[key];
        return (i == null || i >= row.length) ? '' : row[i].trim();
      }

      final parsed = <ChatMessage>[];
      final privateHexes = <String>{};
      final channelIndices = <int>{};
      var skipped = 0;

      for (final row in rows.skip(1)) {
        final timestamp = _parseTimestampSec(col(row, 'timestamp_iso'));
        if (timestamp == null) {
          skipped++;
          continue;
        }

        final direction = col(row, 'direction').toLowerCase();
        final isOutgoing = direction == 'out';
        final conversationType = col(row, 'conversation_type').toLowerCase();
        final conversationName = col(row, 'conversation_name');

        int? channelIndex = int.tryParse(col(row, 'channel_index'));
        if (channelIndex == null && conversationType == 'channel') {
          final m = RegExp(r'^ch(\d+)$').firstMatch(conversationName);
          if (m != null) channelIndex = int.tryParse(m.group(1)!);
        }

        final privateKeyHex = col(row, 'private_key_hex');
        final privateKey = _hexToBytes(privateKeyHex);

        if (conversationType == 'channel' && channelIndex == null) {
          skipped++;
          continue;
        }
        if (conversationType == 'private' &&
            (privateKey == null || privateKey.isEmpty)) {
          skipped++;
          continue;
        }
        if (conversationType != 'channel' && conversationType != 'private') {
          skipped++;
          continue;
        }

        final hopRaw = col(row, 'hop_count').toLowerCase();
        int? pathLen;
        if (hopRaw.isNotEmpty) {
          if (hopRaw == 'flood') {
            pathLen = 0xFF;
          } else {
            final hops = int.tryParse(hopRaw);
            if (hops != null) pathLen = hops & 0x3F;
          }
        }

        final confirmedRaw = col(row, 'confirmed').toLowerCase();
        final confirmed =
            confirmedRaw == '1' ||
            confirmedRaw == 'true' ||
            confirmedRaw == 'yes';

        final msg = ChatMessage(
          text: col(row, 'text'),
          timestamp: timestamp,
          isOutgoing: isOutgoing,
          senderKey: conversationType == 'private' ? privateKey : null,
          channelIndex: conversationType == 'channel' ? channelIndex : null,
          senderName:
              col(row, 'sender_name').isEmpty ? null : col(row, 'sender_name'),
          confirmed: confirmed,
          snr: double.tryParse(col(row, 'snr_db')),
          pathLen: pathLen,
        );
        parsed.add(msg);

        if (msg.channelIndex != null) {
          channelIndices.add(msg.channelIndex!);
        } else if (msg.senderKey != null && msg.senderKey!.isNotEmpty) {
          final hex6 =
              msg.senderKey!
                  .sublist(
                    0,
                    msg.senderKey!.length < 6 ? msg.senderKey!.length : 6,
                  )
                  .map((b) => b.toRadixString(16).padLeft(2, '0'))
                  .join();
          privateHexes.add(hex6);
        }
      }

      if (parsed.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'No importable messages found. Export with the latest app first.',
              ),
            ),
          );
        }
        return;
      }

      final notifier = ref.read(messagesProvider.notifier);
      for (final hex6 in privateHexes) {
        await notifier.ensureLoadedForContact(hex6);
      }
      for (final idx in channelIndices) {
        await notifier.ensureLoadedForChannel(idx);
      }

      for (final msg in parsed) {
        notifier.addMessage(msg);
      }

      if (mounted) {
        final skippedPart = skipped > 0 ? ' ($skipped skipped)' : '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Imported ${parsed.length} messages$skippedPart'),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.dataExportFailed)));
      }
    } finally {
      if (mounted) setState(() => _importingMessages = false);
    }
  }

  static String _fileStamp() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    return '$y$m${d}_$hh$mm';
  }

  static String _exportFileName(String type, String ext) =>
      'MeshCore_${type}_${_fileStamp()}.$ext';

  Future<void> _share(
    Uint8List bytes,
    String filename,
    String mime,
    String subject,
  ) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, name: filename, mimeType: mime)],
        fileNameOverrides: [filename],
        subject: subject,
      ),
    );
  }

  Future<void> _saveLocal(Uint8List bytes, String filename) async {
    final Directory baseDir;
    if (Platform.isAndroid) {
      baseDir =
          await getDownloadsDirectory() ??
          await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
    } else {
      baseDir =
          await getDownloadsDirectory() ??
          await getApplicationDocumentsDirectory();
    }

    final dir = Directory('${baseDir.path}/MeshCore');
    await dir.create(recursive: true);

    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved to ${file.path}'),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<_ExportAction?> _showExportSheet(String label) {
    final theme = Theme.of(context);
    return showModalBottomSheet<_ExportAction>(
      context: context,
      builder:
          (ctx) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Text(
                      'Export $label',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Divider(height: 16),
                  ListTile(
                    leading: const Icon(Icons.ios_share_outlined),
                    title: const Text('Share'),
                    subtitle: const Text('Send via apps, email, cloud…'),
                    onTap: () => Navigator.pop(ctx, _ExportAction.share),
                  ),
                  ListTile(
                    leading: const Icon(Icons.save_alt_outlined),
                    title: const Text('Save to device'),
                    subtitle: const Text('Write file to device storage'),
                    onTap: () => Navigator.pop(ctx, _ExportAction.saveLocal),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
    );
  }

  Future<void> _exportContacts() async {
    final action = await _showExportSheet('Contacts CSV');
    if (action == null) return;
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
      final filename = _exportFileName('Contacts', 'csv');
      if (action == _ExportAction.share) {
        await _share(bytes, filename, 'text/csv', 'MeshCore Contacts');
      } else {
        await _saveLocal(bytes, filename);
      }
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
    final action = await _showExportSheet('Messages CSV');
    if (action == null) return;
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
      final filename = _exportFileName('Messages', 'csv');
      if (action == _ExportAction.share) {
        await _share(bytes, filename, 'text/csv', 'MeshCore Messages');
      } else {
        await _saveLocal(bytes, filename);
      }
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
    final action = await _showExportSheet('Map KML');
    if (action == null) return;
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
      final filename = _exportFileName('MapData', 'kml');
      if (action == _ExportAction.share) {
        await _share(
          bytes,
          filename,
          'application/vnd.google-earth.kml+xml',
          'MeshCore Map',
        );
      } else {
        await _saveLocal(bytes, filename);
      }
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
            importLoading: _importingContacts,
            onExport: contacts.isEmpty ? null : _exportContacts,
            onImport: _importContacts,
          ),
          const SizedBox(height: 12),
          _ExportCard(
            icon: Icons.chat_bubble_outline,
            color: const Color(0xFF0EA5E9),
            title: context.l10n.dataExportMessagesTitle,
            description: context.l10n.dataExportMessagesDesc,
            format: 'CSV',
            loading: _exportingMessages,
            importLoading: _importingMessages,
            onExport: _exportMessages,
            onImport: _importMessages,
          ),
          const SizedBox(height: 12),
          _ExportCard(
            icon: Icons.map_outlined,
            color: const Color(0xFF22C55E),
            title: context.l10n.dataExportKmlTitle,
            description: context.l10n.dataExportKmlDesc(gpsCount),
            format: 'KML',
            loading: _exportingKml,
            importLoading: false,
            onExport: gpsCount == 0 ? null : _exportKml,
            onImport: null,
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
    required this.importLoading,
    required this.onExport,
    required this.onImport,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String description;
  final String format;
  final bool loading;
  final bool importLoading;
  final VoidCallback? onExport;
  final VoidCallback? onImport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row: icon + title + badge ──────────────────────────
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withAlpha(30),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color.withAlpha(80), width: 1.2),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 12),
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
              ],
            ),
            // ── Action buttons ────────────────────────────────────────────
            const SizedBox(height: 12),
            Row(
              children: [
                if (onImport != null) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: color,
                        side: BorderSide(color: color.withAlpha(120)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      icon:
                          importLoading
                              ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: color,
                                ),
                              )
                              : const Icon(
                                Icons.file_upload_outlined,
                                size: 18,
                              ),
                      label: const Text('Import'),
                      onPressed: importLoading ? null : onImport,
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    icon:
                        loading
                            ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                            : const Icon(Icons.ios_share_outlined, size: 18),
                    label: const Text('Export'),
                    onPressed: (loading || onExport == null) ? null : onExport,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Export action enum
// ---------------------------------------------------------------------------
enum _ExportAction { share, saveLocal }
