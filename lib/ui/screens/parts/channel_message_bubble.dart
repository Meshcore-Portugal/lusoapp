part of '../channel_chat_screen.dart';

class _MessageBubble extends ConsumerWidget {
  const _MessageBubble({
    required this.message,
    this.onReply,
    this.selfName,
    this.selfMentionColor,
    this.otherMentionColor,
  });
  final ChatMessage message;
  final VoidCallback? onReply;
  final String? selfName;
  final Color? selfMentionColor;
  final Color? otherMentionColor;

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

  /// Try to match hop hash bytes against repeater/room contacts.
  /// Returns the contact's displayName, or null if no match.
  static String? _resolveHopName(Uint8List hopHash, List<Contact> contacts) {
    final candidates = <Contact>[];
    for (final c in contacts) {
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
    candidates.sort((a, b) {
      final lmA = a.lastModified ?? 0;
      final lmB = b.lastModified ?? 0;
      if (lmA != lmB) return lmB.compareTo(lmA);
      return b.lastAdvertTimestamp.compareTo(a.lastAdvertTimestamp);
    });
    return candidates.first.displayName;
  }

  /// Extract the name of the last relay hop (closest to our radio) in [path],
  /// or null if this path is direct (no hops).
  static String? _lastHopName(MessagePath path, List<Contact> contacts) {
    final n = path.pathHashCount;
    if (n == 0) return null;
    final lastOff = (n - 1) * path.pathHashSize;
    if (lastOff + path.pathHashSize > path.pathBytes.length) {
      // Fallback: hex of first byte at offset
      return lastOff < path.pathBytes.length
          ? path.pathBytes[lastOff]
              .toRadixString(16)
              .padLeft(2, '0')
              .toUpperCase()
          : '?';
    }
    final name = _resolveHopName(
      path.pathBytes.sublist(lastOff, lastOff + path.pathHashSize),
      contacts,
    );
    if (name != null) return name;
    // Fallback: hex prefix
    return path.pathBytes[lastOff]
        .toRadixString(16)
        .padLeft(2, '0')
        .toUpperCase();
  }

  /// Pick the most informative path to represent in the bubble chip:
  /// prefer paths that have at least one relay hop.
  static MessagePath? _primaryPath(List<MessagePath> paths) {
    if (paths.isEmpty) return null;
    for (final p in paths) {
      if (p.pathHashCount > 0) return p;
    }
    return paths.first; // all direct
  }

  /// Compact path chip shown inside each message bubble.
  ///
  /// Shows the last relay hop (closest to receiver) as a tappable pill.
  /// A "+N" badge indicates additional paths. Tapping opens the full sheet.
  ///
  /// Outgoing:   ⟲2  [via RelayName +1]
  /// Incoming:        [via RelayName +1]
  /// Fallback (no 0x88 data): plain "N saltos" text, not tappable.
  static Widget _buildPathLine({
    required BuildContext context,
    required ThemeData theme,
    required Color subtleColor,
    required bool isOutgoing,
    required int heardCount,
    required int? pathLen,
    required List<MessagePath> paths,
    required List<Contact> contacts,
    VoidCallback? onTap,
  }) {
    // ── OUTGOING: no paths, just heard count ────────────────────────────────
    if (isOutgoing && paths.isEmpty) {
      if (heardCount == 0) return const SizedBox.shrink();
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.repeat, size: 12, color: subtleColor),
          const SizedBox(width: 3),
          Text(
            '$heardCount',
            style: TextStyle(fontSize: 11, color: subtleColor),
          ),
        ],
      );
    }

    // ── INCOMING: no 0x88 data yet — plain hop count fallback ───────────────
    if (!isOutgoing && paths.isEmpty) {
      if (pathLen == null || pathLen == 0xFF) return const SizedBox.shrink();
      final hops = pathLen & 0x3F;
      if (hops == 0) return const SizedBox.shrink();
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.subdirectory_arrow_right, size: 12, color: subtleColor),
          const SizedBox(width: 3),
          Text(
            '$hops salto${hops == 1 ? '' : 's'}',
            style: TextStyle(fontSize: 11, color: subtleColor),
          ),
        ],
      );
    }

    // ── Build relay chip from recorded paths ─────────────────────────────────
    final primary = _primaryPath(paths)!;
    final lastName = _lastHopName(primary, contacts);
    final extraPaths = paths.length - 1; // additional paths beyond the primary

    // If primary is direct and all others too, nothing to show (for incoming)
    // For outgoing keep showing the heard count even when direct
    if (lastName == null && !isOutgoing) return const SizedBox.shrink();

    final chipColor = subtleColor.withAlpha(22);
    final borderColor = subtleColor.withAlpha(55);
    final labelStyle = TextStyle(fontSize: 11, color: subtleColor);
    final badgeStyle = TextStyle(
      fontSize: 10,
      color: subtleColor,
      fontWeight: FontWeight.bold,
    );

    Widget chip = GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 220),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: chipColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.router, size: 11, color: subtleColor),
            const SizedBox(width: 4),
            if (lastName != null)
              Flexible(
                child: Text(
                  lastName,
                  style: labelStyle,
                  overflow: TextOverflow.ellipsis,
                ),
              )
            else
              Text(context.l10n.commonDirect, style: labelStyle),
            if (extraPaths > 0) ...[
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: subtleColor.withAlpha(45),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('+$extraPaths', style: badgeStyle),
              ),
            ],
          ],
        ),
      ),
    );

    // For outgoing, prefix with repeat count
    if (isOutgoing && heardCount > 0) {
      chip = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.repeat, size: 12, color: subtleColor),
          const SizedBox(width: 3),
          Text('$heardCount', style: labelStyle),
          const SizedBox(width: 6),
          Flexible(child: chip),
        ],
      );
    }

    return chip;
  }

  /// Handles a tap on a `#hashtag` channel link inside a message bubble.
  ///
  /// If [tag] matches an existing channel (case-insensitive), navigates to it.
  /// Otherwise opens a bottom sheet to create-and-join the hashtag channel.
  void _handleHashtagTap(BuildContext context, WidgetRef ref, String tag) {
    final channelName = tag.startsWith('#') ? tag : '#$tag';
    final channels = ref.read(channelsProvider);
    final existing =
        channels
            .where((c) => c.name.toLowerCase() == channelName.toLowerCase())
            .firstOrNull;
    if (existing != null) {
      context.push('/channels/${existing.index}');
    } else {
      _showHashtagCreateSheet(context, ref, channelName);
    }
  }

  void _showHashtagCreateSheet(
    BuildContext context,
    WidgetRef ref,
    String channelName, // already normalised with leading '#'
  ) {
    final theme = Theme.of(context);
    final keyBytes = hashtagChannelKey(channelName);
    final keyHex =
        keyBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder:
          (sheetCtx) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.tag, color: theme.colorScheme.secondary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          channelName,
                          style: theme.textTheme.titleLarge,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Canal Hashtag — qualquer pessoa com o nome pode entrar.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withAlpha(160),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Chave: $keyHex',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontFamily: 'monospace',
                      color: theme.colorScheme.onSurface.withAlpha(120),
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    icon: const Icon(Icons.add_circle_outline),
                    label: Text(context.l10n.chatCreateJoinChannel),
                    onPressed: () async {
                      final service = ref.read(radioServiceProvider);
                      if (service == null) return;

                      final channels = ref.read(channelsProvider);

                      // Re-check: may have been created while sheet was open.
                      final alreadyExists = channels.any(
                        (c) =>
                            c.name.toLowerCase() == channelName.toLowerCase(),
                      );
                      if (alreadyExists) {
                        final ch = channels.firstWhere(
                          (c) =>
                              c.name.toLowerCase() == channelName.toLowerCase(),
                        );
                        if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                        if (context.mounted) {
                          unawaited(context.push('/channels/${ch.index}'));
                        }
                        return;
                      }

                      final maxChannels =
                          ref.read(deviceInfoProvider)?.maxChannels ?? 8;
                      // Only non-empty slots are truly "used" — the firmware
                      // reports all slots back (including empty ones with a
                      // blank name), so filtering is required to find a free slot.
                      final usedIndices =
                          channels
                              .where((c) => !c.isEmpty)
                              .map((c) => c.index)
                              .toSet();
                      final freeSlot =
                          List.generate(
                            maxChannels,
                            (i) => i,
                          ).where((i) => !usedIndices.contains(i)).firstOrNull;

                      if (freeSlot == null) {
                        if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Sem espaço disponível para novos canais.',
                              ),
                            ),
                          );
                        }
                        return;
                      }

                      final secret = hashtagChannelKey(channelName);
                      await service.setChannel(freeSlot, channelName, secret);
                      await Future.delayed(const Duration(milliseconds: 200));
                      await service.requestChannel(freeSlot);

                      if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                      if (context.mounted) {
                        unawaited(context.push('/channels/$freeSlot'));
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () => Navigator.pop(sheetCtx),
                    child: Text(context.l10n.commonCancel),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  static String _metaSuffix(ChatMessage msg) {
    final parts = <String>[];
    if (msg.snr != null) parts.add('SNR ${msg.snr!.toStringAsFixed(1)} dB');
    if (msg.pathLen != null) {
      final hops = msg.pathLen == 0xFF ? -1 : msg.pathLen! & 0x3F;
      if (hops <= 0) {
        parts.add('Directo');
      } else {
        parts.add('$hops hop${hops > 1 ? 's' : ''}');
      }
    }
    return parts.join(' • ');
  }

  void _showMsgContextMenu(
    BuildContext context,
    ChatMessage msg,
    WidgetRef ref,
  ) {
    final theme = Theme.of(context);
    showModalBottomSheet<void>(
      context: context,
      builder:
          (_) => SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (!msg.isOutgoing && onReply != null)
                    ListTile(
                      leading: const Icon(Icons.reply),
                      title: Text(context.l10n.commonReply),
                      onTap: () {
                        Navigator.pop(context);
                        onReply!();
                      },
                    ),
                  if (msg.isOutgoing && msg.channelIndex != null)
                    ListTile(
                      leading: const Icon(Icons.refresh),
                      title: Text(context.l10n.chatRetry),
                      onTap: () {
                        Navigator.pop(context);
                        // Reset hash so the new transmission can claim a
                        // fresh loopback echo and relay count.
                        ref
                            .read(messagesProvider.notifier)
                            .resetChannelResend(msg);
                        final service = ref.read(radioServiceProvider);
                        service?.sendChannelMessage(
                          msg.channelIndex!,
                          msg.text,
                          timestamp: msg.timestamp,
                        );
                      },
                    ),
                  ListTile(
                    leading: const Icon(Icons.copy),
                    title: Text(context.l10n.commonCopyText),
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: msg.text));
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(context.l10n.commonMessageCopied),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    },
                  ),
                  if (msg.packetHashHex != null)
                    ListTile(
                      leading: const Icon(Icons.call_merge),
                      title: Text(context.l10n.chatPathLabel),
                      subtitle: Text(
                        msg.isOutgoing
                            ? 'Ouvida ${msg.heardCount} ${msg.heardCount == 1 ? 'vez' : 'vezes'} por repetidores'
                            : 'Recebida via repetidores',
                        style: theme.textTheme.bodySmall,
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        _showMessagePaths(context, msg);
                      },
                    ),
                  if (msg.pathLen != null || msg.snr != null)
                    ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: Text(context.l10n.chatMsgDetails),
                      onTap: () {
                        Navigator.pop(context);
                        _showMsgDetails(context, msg, theme);
                      },
                    ),
                  const Divider(height: 8),
                  ListTile(
                    leading: Icon(
                      Icons.delete_outline,
                      color: theme.colorScheme.error,
                    ),
                    title: Text(
                      'Apagar mensagem',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      ref.read(messagesProvider.notifier).deleteMessage(msg);
                    },
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
    );
  }

  void _showMessagePaths(BuildContext context, ChatMessage msg) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _MessagePathsSheet(msg: msg),
    );
  }

  void _showMsgDetails(BuildContext context, ChatMessage msg, ThemeData theme) {
    final time = DateTime.fromMillisecondsSinceEpoch(msg.timestamp * 1000);
    final timeStr =
        '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} '
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
    int? hops;
    if (msg.pathLen != null) {
      hops = msg.pathLen == 0xFF ? 0 : msg.pathLen! & 0x3F;
    }
    showModalBottomSheet<void>(
      context: context,
      builder:
          (_) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Detalhes da mensagem',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                  _DetailRow(
                    icon: Icons.access_time,
                    label: 'Hora',
                    value: timeStr,
                    theme: theme,
                  ),
                  if (hops != null)
                    _DetailRow(
                      icon: Icons.route,
                      label: 'Caminho',
                      value:
                          hops == 0
                              ? 'Directo'
                              : '$hops hop${hops > 1 ? 's' : ''}',
                      theme: theme,
                    ),
                  if (msg.snr != null)
                    _DetailRow(
                      icon: Icons.signal_cellular_alt,
                      label: 'SNR',
                      value: '${msg.snr!.toStringAsFixed(1)} dB',
                      theme: theme,
                    ),
                  if (msg.isChannel && msg.heardCount > 0)
                    _DetailRow(
                      icon: Icons.cell_tower,
                      label: 'Repetidores',
                      value: '${msg.heardCount}',
                      theme: theme,
                    ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
    );
  }

  @override
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isMe = message.isOutgoing;
    final allPaths = ref.watch(packetHeardProvider);
    final paths =
        message.packetHashHex != null
            ? (allPaths[message.packetHashHex] ?? <MessagePath>[])
            : <MessagePath>[];
    final contacts = ref.watch(contactsProvider);
    final time = DateTime.fromMillisecondsSinceEpoch(message.timestamp * 1000);
    final timeStr =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    final meta = _metaSuffix(message);
    final metaLine = meta.isNotEmpty ? '$timeStr • $meta' : timeStr;

    if (isMe) {
      return GestureDetector(
        onLongPress: () => _showMsgContextMenu(context, message, ref),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Align(
            alignment: Alignment.centerRight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.72,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(4),
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildMentionText(
                        context,
                        message.text,
                        theme,
                        theme.textTheme.bodyMedium,
                        selfName: selfName,
                        selfMentionColor: selfMentionColor,
                        otherMentionColor: otherMentionColor,
                        onHashtagTap:
                            (tag) => _handleHashtagTap(context, ref, tag),
                      ),
                      Builder(
                        builder: (_) {
                          final line = _buildPathLine(
                            context: context,
                            theme: theme,
                            subtleColor: theme.colorScheme.onPrimaryContainer
                                .withAlpha(160),
                            isOutgoing: true,
                            heardCount: message.heardCount,
                            pathLen: message.pathLen,
                            paths: paths,
                            contacts: contacts,
                            onTap:
                                message.packetHashHex != null
                                    ? () => _showMessagePaths(context, message)
                                    : null,
                          );
                          if (line is SizedBox) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: line,
                          );
                        },
                      ),
                    ],
                  ),
                ),
                _HeardBadge(
                  count: message.heardCount,
                  theme: theme,
                  confirmed: message.confirmed,
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 3, right: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        metaLine,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurface.withAlpha(100),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        message.confirmed ? Icons.done_all : Icons.done,
                        size: 13,
                        color:
                            message.confirmed
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurface.withAlpha(130),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
              ],
            ),
          ),
        ),
      );
    }

    // Received — channel messages embed sender as "Name: body" when senderName is null
    String? senderName =
        message.senderName?.isNotEmpty == true ? message.senderName : null;
    String displayText = message.text;
    if (senderName == null) {
      final colonIdx = message.text.indexOf(': ');
      if (colonIdx > 0) {
        senderName = message.text.substring(0, colonIdx).trim();
        displayText = message.text.substring(colonIdx + 2);
      }
    }
    final avatarLabel = senderName ?? '';
    final color = _avatarColor(
      avatarLabel.isNotEmpty ? avatarLabel : 'Unknown',
    );

    final row = Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: color,
            child: Text(
              _initials(avatarLabel),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (senderName != null && senderName.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3, left: 2),
                    child: Text(
                      senderName,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.68,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildMentionText(
                        context,
                        displayText,
                        theme,
                        theme.textTheme.bodyMedium,
                        selfName: selfName,
                        selfMentionColor: selfMentionColor,
                        otherMentionColor: otherMentionColor,
                        onHashtagTap:
                            (tag) => _handleHashtagTap(context, ref, tag),
                        showMeshcoreResultButton: () {
                          final sn = selfName;
                          if (sn == null) return false;
                          return RegExp(
                            '@\\[${RegExp.escape(sn)}\\]',
                            caseSensitive: false,
                          ).hasMatch(displayText);
                        }(),
                      ),
                      Builder(
                        builder: (_) {
                          final line = _buildPathLine(
                            context: context,
                            theme: theme,
                            subtleColor: theme.colorScheme.onSurface.withAlpha(
                              110,
                            ),
                            isOutgoing: false,
                            heardCount: 0,
                            pathLen: message.pathLen,
                            paths: paths,
                            contacts: contacts,
                            onTap:
                                message.packetHashHex != null
                                    ? () => _showMessagePaths(context, message)
                                    : null,
                          );
                          if (line is SizedBox) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: line,
                          );
                        },
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 3, left: 2),
                  child: Text(
                    metaLine,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurface.withAlpha(100),
                    ),
                  ),
                ),
                const SizedBox(height: 2),
              ],
            ),
          ),
        ],
      ),
    );

    final rowWithPress = GestureDetector(
      onLongPress: () => _showMsgContextMenu(context, message, ref),
      child: row,
    );
    if (onReply != null) {
      return _SwipeToReplyWrapper(onReply: onReply!, child: rowWithPress);
    }
    return rowWithPress;
  }
}
