part of '../channel_chat_screen.dart';

class _MessagePathsSheet extends ConsumerWidget {
  const _MessagePathsSheet({required this.msg});
  final ChatMessage msg;

  static const Distance _distance = Distance();

  static bool _hasValidGps(double? lat, double? lon) =>
      lat != null && lon != null && !(lat == 0.0 && lon == 0.0);

  static LatLng? _gpsPoint(double? lat, double? lon) =>
      _hasValidGps(lat, lon) ? LatLng(lat!, lon!) : null;

  static String _formatDistance(double meters) {
    if (meters >= 1000) return '${(meters / 1000).toStringAsFixed(1)} km';
    return '${meters.round()} m';
  }

  /// Extract the sender name from a channel message (same logic as the bubble).
  static String _senderName(ChatMessage msg) {
    if (msg.senderName != null && msg.senderName!.isNotEmpty) {
      return msg.senderName!;
    }
    final colonIdx = msg.text.indexOf(': ');
    if (colonIdx > 0) return msg.text.substring(0, colonIdx).trim();
    return 'Desconhecido';
  }

  /// Returns the best-matching relay [Contact] for [hopHash], or null.
  ///
  /// Only repeaters (type=2) and rooms (type=3) are considered — these are
  /// the only MeshCore node types that forward packets.  Clients (type=1)
  /// and sensors (type=4) never relay and are explicitly excluded.
  ///
  /// With PATH_HASH_SIZE=1 (firmware default) two relay contacts can share
  /// the same first byte.  We return the best match.  False-positives from
  /// client nodes are prevented by the type filter; name collisions between
  /// two relay contacts are an accepted limitation of 1-byte hashes.
  static Contact? _findMatchingContact(
    Uint8List hopHash,
    List<Contact> contacts,
  ) {
    final candidates = <Contact>[];
    for (final c in contacts) {
      // Only relay-capable types: repeater (2) and room (3).
      if (!c.isRepeater && !c.isRoom) continue;
      if (c.publicKey.length < hopHash.length) continue;
      var match = true;
      for (var i = 0; i < hopHash.length; i++) {
        if (c.publicKey[i] != hopHash[i]) {
          match = false;
          break;
        }
      }
      if (match) candidates.add(c);
    }
    if (candidates.isEmpty) return null;
    // Tiebreak: most recently modified → most recently advertised → alphabetical.
    candidates.sort((a, b) {
      final lmA = a.lastModified ?? 0;
      final lmB = b.lastModified ?? 0;
      if (lmA != lmB) return lmB.compareTo(lmA);
      if (a.lastAdvertTimestamp != b.lastAdvertTimestamp) {
        return b.lastAdvertTimestamp.compareTo(a.lastAdvertTimestamp);
      }
      return a.displayName.compareTo(b.displayName);
    });
    return candidates.first;
  }

  static String? _matchContact(Uint8List hopHash, List<Contact> contacts) =>
      _findMatchingContact(hopHash, contacts)?.displayName;

  /// Converts a [MessagePath] into a [TraceResult] for map overlay.
  /// Each hop hash is resolved to a contact to obtain GPS coordinates and name.
  static TraceResult _buildTraceResult(
    MessagePath path,
    List<Contact> contacts,
  ) {
    final hops = <TraceHop>[];
    for (var h = 0; h < path.pathHashCount; h++) {
      final offset = h * path.pathHashSize;
      if (offset + path.pathHashSize > path.pathBytes.length) break;
      final hopHash = path.pathBytes.sublist(
        offset,
        offset + path.pathHashSize,
      );
      final contact = _findMatchingContact(hopHash, contacts);
      final hexId =
          hopHash.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      hops.add(
        TraceHop(
          hashHex: hexId,
          snrDb: path.snr,
          name: contact?.displayName,
          latitude: contact?.latitude,
          longitude: contact?.longitude,
        ),
      );
    }
    return TraceResult(
      tag: 0,
      hops: hops,
      finalSnrDb: path.snr,
      timestamp: DateTime.now(),
    );
  }

  static const _avatarPalette = [
    Color(0xFF7B61FF),
    Color(0xFF00897B),
    Color(0xFFE91E63),
    Color(0xFF1976D2),
    Color(0xFFFF6D00),
    Color(0xFF6D4C41),
    Color(0xFF558B2F),
    Color(0xFF6A1B9A),
  ];

  static Color _avatarColor(String name) {
    if (name.isEmpty) return _avatarPalette[0];
    var hash = 0;
    for (final c in name.codeUnits) {
      hash = (hash * 31 + c) & 0x7FFFFFFF;
    }
    return _avatarPalette[hash % _avatarPalette.length];
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return '?';
    if (parts.length >= 2 && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    final s = parts[0];
    return (s.length >= 2 ? s.substring(0, 2) : s).toUpperCase();
  }

  /// Renders a single node row (sender / relay hop / receiver) in the path chain.
  static Widget _buildChainRow({
    required ThemeData theme,
    required Widget leading,
    required String title,
    required String subtitle,
    Color? subtitleColor,
    Widget? trailing,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        leading,
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                subtitle,
                style: TextStyle(fontSize: 12, color: subtitleColor),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing],
      ],
    );
  }

  /// Vertical connector line drawn between chain nodes.
  static Widget _buildConnector(ThemeData theme) {
    return Padding(
      // left=19 centres the 2px line under a 40px diameter CircleAvatar.
      padding: const EdgeInsets.only(left: 19),
      child: Container(
        width: 2,
        height: 20,
        decoration: BoxDecoration(
          color: theme.colorScheme.outlineVariant,
          borderRadius: BorderRadius.circular(1),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final allPaths = ref.watch(packetHeardProvider);
    final paths =
        msg.packetHashHex != null
            ? (allPaths[msg.packetHashHex] ?? <MessagePath>[])
            : <MessagePath>[];
    final contacts = ref.watch(contactsProvider);
    final senderName = _senderName(msg);
    final selfInfo = ref.watch(selfInfoProvider);
    final selfPoint = _gpsPoint(selfInfo?.latitude, selfInfo?.longitude);

    final heardTimes = paths.length;

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder:
          (ctx, scrollController) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    Icon(Icons.call_merge, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Ouvido $heardTimes ${heardTimes == 1 ? 'vez' : 'vezes'}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  msg.isOutgoing
                      ? 'Cada caminho representa uma vez que o teu rádio ouviu a mensagem de volta.'
                      : 'Toca num caminho para ver a rota completa.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (paths.isEmpty)
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Os dados de caminho não estão disponíveis.\nReconecta o rádio para registar novos caminhos.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.only(top: 4, bottom: 16),
                    itemCount: paths.length,
                    itemBuilder: (ctx, i) {
                      final path = paths[i];
                      final isDirect = path.pathHashCount == 0;
                      final hops = path.pathHashCount;

                      // ── Last hop summary (shown in collapsed header) ───────
                      final lastOff =
                          hops > 0 ? (hops - 1) * path.pathHashSize : -1;
                      final String? lastHopName =
                          lastOff >= 0 &&
                                  lastOff + path.pathHashSize <=
                                      path.pathBytes.length
                              ? _matchContact(
                                path.pathBytes.sublist(
                                  lastOff,
                                  lastOff + path.pathHashSize,
                                ),
                                contacts,
                              )
                              : null;
                      final String lastHopHex =
                          lastOff >= 0 && lastOff < path.pathBytes.length
                              ? path.pathBytes[lastOff]
                                  .toRadixString(16)
                                  .padLeft(2, '0')
                                  .toUpperCase()
                              : '';
                      final String summaryTitle =
                          isDirect ? 'Direto' : (lastHopName ?? lastHopHex);
                      final String snrStr = path.snr.toStringAsFixed(1);
                      final String subtitleStr =
                          isDirect
                              ? 'SNR $snrStr dB · direto'
                              : 'SNR $snrStr dB · $hops salto${hops == 1 ? '' : 's'}';

                      // ── Sender node ──────────────────────────────────────
                      final Widget senderLeading;
                      final String senderTitle;
                      if (msg.isOutgoing) {
                        senderLeading = CircleAvatar(
                          backgroundColor: theme.colorScheme.primary,
                          child: Icon(
                            Icons.radio,
                            color: theme.colorScheme.onPrimary,
                            size: 20,
                          ),
                        );
                        senderTitle = 'O teu rádio';
                      } else {
                        senderLeading = CircleAvatar(
                          backgroundColor: _avatarColor(senderName),
                          child: Text(
                            _initials(senderName),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        );
                        senderTitle = senderName;
                      }

                      // ── Intermediate relay hops ───────────────────────────
                      final hopWidgets = <Widget>[];
                      LatLng? previousPoint = msg.isOutgoing ? selfPoint : null;
                      for (var h = 0; h < hops; h++) {
                        final offset = h * path.pathHashSize;
                        final hexId =
                            offset < path.pathBytes.length
                                ? path.pathBytes[offset]
                                    .toRadixString(16)
                                    .padLeft(2, '0')
                                : '?';
                        final Contact? hopContact;
                        if (offset + path.pathHashSize <=
                            path.pathBytes.length) {
                          hopContact = _findMatchingContact(
                            path.pathBytes.sublist(
                              offset,
                              offset + path.pathHashSize,
                            ),
                            contacts,
                          );
                        } else {
                          hopContact = null;
                        }
                        final hopName = hopContact?.displayName;
                        final hopPoint = _gpsPoint(
                          hopContact?.latitude,
                          hopContact?.longitude,
                        );
                        final distanceLabel =
                            (previousPoint != null && hopPoint != null)
                                ? _formatDistance(
                                  _distance.as(
                                    LengthUnit.Meter,
                                    previousPoint,
                                    hopPoint,
                                  ),
                                )
                                : null;
                        if (hopPoint != null) previousPoint = hopPoint;

                        final hopSubtitle =
                            distanceLabel != null
                                ? 'Salto ${h + 1} · $distanceLabel · Repetiu'
                                : 'Salto ${h + 1} · Repetiu';

                        hopWidgets.add(_buildConnector(theme));
                        hopWidgets.add(
                          _buildChainRow(
                            theme: theme,
                            leading: CircleAvatar(
                              backgroundColor:
                                  theme.colorScheme.secondaryContainer,
                              child: Text(
                                hexId,
                                style: TextStyle(
                                  color: theme.colorScheme.onSecondaryContainer,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            title: hopName ?? 'Nó desconhecido',
                            subtitle: hopSubtitle,
                            subtitleColor:
                                hopName != null
                                    ? Colors.orange.shade700
                                    : theme.colorScheme.onSurfaceVariant,
                          ),
                        );
                      }

                      final receiverDistanceLabel =
                          (!isDirect &&
                                  previousPoint != null &&
                                  selfPoint != null)
                              ? _formatDistance(
                                _distance.as(
                                  LengthUnit.Meter,
                                  previousPoint,
                                  selfPoint,
                                ),
                              )
                              : null;

                      final receiverSubtitle =
                          isDirect
                              ? 'Ouvido diretamente'
                              : receiverDistanceLabel != null
                              ? 'Recebeu a mensagem · $receiverDistanceLabel'
                              : 'Recebeu a mensagem';

                      // ── Full chain (shown when expanded) ──────────────────
                      final fullChain = Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildChainRow(
                              theme: theme,
                              leading: senderLeading,
                              title: senderTitle,
                              subtitle:
                                  msg.isOutgoing
                                      ? 'Enviaste a mensagem'
                                      : 'Enviou a mensagem',
                              subtitleColor: theme.colorScheme.onSurfaceVariant,
                            ),
                            ...hopWidgets,
                            _buildConnector(theme),
                            _buildChainRow(
                              theme: theme,
                              leading: CircleAvatar(
                                backgroundColor: theme.colorScheme.primary,
                                child: Icon(
                                  Icons.phone_android,
                                  color: theme.colorScheme.onPrimary,
                                  size: 20,
                                ),
                              ),
                              title: 'O teu rádio',
                              subtitle: receiverSubtitle,
                              subtitleColor:
                                  isDirect
                                      ? Colors.green.shade600
                                      : theme.colorScheme.onSurfaceVariant,
                              trailing: _SnrBar(snr: path.snr, theme: theme),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.map_outlined, size: 18),
                                label: Text(context.l10n.chatViewOnMap),
                                onPressed: () {
                                  ref.read(traceResultProvider.notifier).state =
                                      _buildTraceResult(path, contacts);
                                  Navigator.of(context).pop();
                                  context.go('/map');
                                },
                              ),
                            ),
                          ],
                        ),
                      );

                      return ExpansionTile(
                        tilePadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 2,
                        ),
                        leading:
                            isDirect
                                ? CircleAvatar(
                                  backgroundColor: Colors.green.shade700,
                                  child: const Icon(
                                    Icons.sensors,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                )
                                : CircleAvatar(
                                  backgroundColor: _avatarColor(summaryTitle),
                                  child: Text(
                                    _initials(summaryTitle),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                        title: Text(
                          summaryTitle,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          subtitleStr,
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                isDirect
                                    ? Colors.green.shade600
                                    : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        children: [fullChain],
                      );
                    },
                  ),
                ),
            ],
          ),
    );
  }
}

/// Signal-strength bar widget matching the visual style in the paths sheet.
class _SnrBar extends StatelessWidget {
  const _SnrBar({required this.snr, required this.theme});
  final double snr;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    // Map SNR → 1–4 bars: <0 → 1, 0–5 → 2, 5–10 → 3, >10 → 4
    final bars =
        snr < 0
            ? 1
            : snr < 5
            ? 2
            : snr < 10
            ? 3
            : 4;
    const maxBars = 4;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var b = 1; b <= maxBars; b++)
              Container(
                width: 5,
                height: (5 + b * 4).toDouble(),
                margin: const EdgeInsets.only(left: 2),
                decoration: BoxDecoration(
                  color:
                      b <= bars ? Colors.green.shade600 : Colors.grey.shade600,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          '${snr.toStringAsFixed(1)}dB',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Detail row helper
// ---------------------------------------------------------------------------

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.theme,
  });
  final IconData icon;
  final String label;
  final String value;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
