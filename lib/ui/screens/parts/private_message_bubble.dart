part of '../private_chat_screen.dart';

class _PrivateMessageBubble extends StatelessWidget {
  const _PrivateMessageBubble({
    required this.message,
    this.onReply,
    this.onRetry,
    this.contactDisplayName,
    this.contactPathLen,
    this.selfName,
    this.selfMentionColor,
    this.otherMentionColor,
  });
  final ChatMessage message;
  final VoidCallback? onReply;
  final VoidCallback? onRetry;
  final String? contactDisplayName;
  final int? contactPathLen;
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

  static String _metaSuffix(ChatMessage msg) {
    if (msg.snr != null) return 'SNR ${msg.snr!.toStringAsFixed(1)} dB';
    return '';
  }

  /// Returns the route (label, icon, colour) for a message bubble.
  ///
  /// For **incoming** messages we use [msg.pathLen] — the actual hop count
  /// reported by the radio when the frame arrived.
  ///
  /// For **outgoing** messages we rely solely on [msg.sentRouteFlag]:
  ///   0 → sent via the stored direct path ("Direto")
  ///   1 → sent via flood ("Flood")
  ///
  /// We deliberately do NOT derive hop count from the contact's current
  /// [contactPathLen] for outgoing messages. That value changes whenever the
  /// path is reset or rediscovered, which would cause historical message
  /// labels to silently flip — that's the confusing behaviour we're avoiding.
  static (String label, IconData icon, Color? color)? _msgRouteInfo(
    ChatMessage msg,
    ThemeData theme,
  ) {
    // Incoming: use the path length the radio reported for this frame.
    // Firmware convention: 0xFF = arrived via direct (stored) route;
    //                      N    = arrived via flood with (N & 0x3F) hops.
    if (msg.pathLen != null) {
      final pathLen = msg.pathLen!;
      if (pathLen == 0xFF) {
        return ('Direto', Icons.arrow_forward, Colors.green.shade600);
      }
      final hops = pathLen & 0x3F;
      if (hops == 0) {
        return ('Flood', Icons.waves, theme.colorScheme.onSurfaceVariant);
      }
      return (
        '$hops salto${hops > 1 ? 's' : ''}',
        Icons.route,
        theme.colorScheme.secondary,
      );
    }

    // Outgoing: use only the routing mode chosen at send time.
    if (msg.isOutgoing && msg.sentRouteFlag != null) {
      if (msg.sentRouteFlag == 0) {
        return ('Direto', Icons.arrow_forward, Colors.green.shade600);
      } else {
        return ('Flood', Icons.waves, theme.colorScheme.onSurfaceVariant);
      }
    }

    return null;
  }

  void _showMsgContextMenu(BuildContext context, ChatMessage msg) {
    final theme = Theme.of(context);
    showModalBottomSheet<void>(
      context: context,
      builder:
          (_) => SafeArea(
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
                if (msg.isOutgoing && (msg.failed || msg.sentRouteFlag == null))
                  ListTile(
                    leading: Icon(
                      Icons.refresh,
                      color:
                          msg.failed
                              ? Theme.of(context).colorScheme.error
                              : null,
                    ),
                    title: Text(context.l10n.chatRetry),
                    onTap: () {
                      Navigator.pop(context);
                      onRetry?.call();
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
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text(context.l10n.chatMsgDetails),
                  onTap: () {
                    Navigator.pop(context);
                    _showMsgDetails(context, msg, theme);
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
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
    } else if (msg.isOutgoing && msg.sentRouteFlag != null) {
      // Outgoing direct route — use contact's known path length
      if (msg.sentRouteFlag == 0 &&
          contactPathLen != null &&
          contactPathLen != 0xFF) {
        hops = contactPathLen! & 0x3F;
      } else if (msg.sentRouteFlag != 0) {
        hops = 1;
      }
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
                              ? 'Direto'
                              : '$hops salto${hops > 1 ? 's' : ''}',
                      theme: theme,
                    ),
                  if (msg.snr != null)
                    _DetailRow(
                      icon: Icons.signal_cellular_alt,
                      label: 'SNR',
                      value: '${msg.snr!.toStringAsFixed(1)} dB',
                      theme: theme,
                    ),
                  if (msg.isOutgoing && msg.sentRouteFlag != null)
                    _DetailRow(
                      icon: Icons.send,
                      label: 'Enviado via',
                      value: msg.sentRouteFlag == 0 ? 'Direto' : 'Flood',
                      theme: theme,
                    ),
                  if (msg.isOutgoing)
                    _DetailRow(
                      icon:
                          msg.failed
                              ? Icons.error_outline
                              : msg.confirmed
                              ? Icons.done_all
                              : Icons.done,
                      label: 'Estado',
                      value:
                          msg.failed
                              ? context.l10n.chatFailed
                              : msg.confirmed
                              ? 'Confirmado'
                              : 'Pendente',
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMe = message.isOutgoing;
    final time = DateTime.fromMillisecondsSinceEpoch(message.timestamp * 1000);
    final timeStr =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    final meta = _metaSuffix(message);
    final metaLine = meta.isNotEmpty ? '$timeStr • $meta' : timeStr;
    final routeInfo = _msgRouteInfo(message, theme);

    if (isMe) {
      return GestureDetector(
        onLongPress: () => _showMsgContextMenu(context, message),
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
                  child: _buildMentionText(
                    context,
                    message.text,
                    theme,
                    theme.textTheme.bodyMedium,
                    selfName: selfName,
                    selfMentionColor: selfMentionColor,
                    otherMentionColor: otherMentionColor,
                  ),
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
                      if (routeInfo != null) ...[
                        Text(
                          ' • ',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurface.withAlpha(100),
                          ),
                        ),
                        Icon(routeInfo.$2, size: 11, color: routeInfo.$3),
                        const SizedBox(width: 2),
                        Text(
                          routeInfo.$1,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: routeInfo.$3,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(width: 4),
                      if (message.failed)
                        GestureDetector(
                          onTap: onRetry,
                          child: Icon(
                            Icons.error_outline,
                            size: 14,
                            color: Theme.of(context).colorScheme.error,
                          ),
                        )
                      else
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

    // Received
    final senderName =
        contactDisplayName ??
        (message.senderName != null && message.senderName!.isNotEmpty
            ? message.senderName!
            : null);
    final avatarLabel = senderName ?? '?';
    final color = _avatarColor(avatarLabel);

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
                if (senderName != null)
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
                  child: _buildMentionText(
                    context,
                    message.text,
                    theme,
                    theme.textTheme.bodyMedium,
                    selfName: selfName,
                    selfMentionColor: selfMentionColor,
                    otherMentionColor: otherMentionColor,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 3, left: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        metaLine,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurface.withAlpha(100),
                        ),
                      ),
                      if (routeInfo != null) ...[
                        Text(
                          ' • ',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurface.withAlpha(100),
                          ),
                        ),
                        Icon(routeInfo.$2, size: 11, color: routeInfo.$3),
                        const SizedBox(width: 2),
                        Text(
                          routeInfo.$1,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: routeInfo.$3,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
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
      onLongPress: () => _showMsgContextMenu(context, message),
      child: row,
    );
    if (onReply != null) {
      return _SwipeToReplyWrapper(onReply: onReply!, child: rowWithPress);
    }
    return rowWithPress;
  }
}
