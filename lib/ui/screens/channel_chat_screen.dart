import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../protocol/protocol.dart';
import '../../providers/radio_providers.dart';

/// Channel list and chat screen.
class ChannelChatScreen extends ConsumerStatefulWidget {
  const ChannelChatScreen({super.key, required this.channelIndex});
  final int channelIndex;

  @override
  ConsumerState<ChannelChatScreen> createState() => _ChannelChatScreenState();
}

class _ChannelChatScreenState extends ConsumerState<ChannelChatScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  ChatMessage? _replyingTo;
  bool _atBottom = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      ref
          .read(unreadCountsProvider.notifier)
          .markChannelRead(widget.channelIndex);
      // Load persisted messages, then scroll to bottom once they are in state.
      await ref
          .read(messagesProvider.notifier)
          .ensureLoadedForChannel(widget.channelIndex);
      if (mounted) _scrollToBottom();
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final atBottom =
        _scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 80;
    if (atBottom != _atBottom) setState(() => _atBottom = atBottom);
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    final service = ref.read(radioServiceProvider);
    if (service == null) return;

    final replyPrefix =
        _replyingTo != null ? '@[${_senderFromMessage(_replyingTo!)}] ' : '';
    final fullText = '$replyPrefix$text';

    // Compute timestamp once so encoder and stored message share the same value.
    // The loopback echo carries this timestamp, allowing exact matching.
    final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    // Add outgoing message to state before sending so any immediate firmware
    // response can find it (same pattern as private chat).
    ref
        .read(messagesProvider.notifier)
        .addOutgoing(
          ChatMessage(
            text: fullText,
            timestamp: ts,
            isOutgoing: true,
            channelIndex: widget.channelIndex,
          ),
        );

    service.sendChannelMessage(widget.channelIndex, fullText, timestamp: ts);

    _textController.clear();
    if (_replyingTo != null) setState(() => _replyingTo = null);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Extracts the sender name from a received channel message.
  /// Channel messages arrive as "SenderName: message text" with no separate
  /// senderName field, so we parse the part before the first ': '.
  String _senderFromMessage(ChatMessage msg) {
    if (msg.senderName != null) return msg.senderName!;
    final idx = msg.text.indexOf(': ');
    if (idx > 0) return msg.text.substring(0, idx);
    return 'Canal';
  }

  @override
  Widget build(BuildContext context) {
    // While this screen is visible, clear unread badge for this channel
    // whenever new messages arrive, and tail-scroll to the latest message.
    ref.listen<List<ChatMessage>>(messagesProvider, (prev, next) {
      ref
          .read(unreadCountsProvider.notifier)
          .markChannelRead(widget.channelIndex);
      if (prev != null && next.length > prev.length && _atBottom) {
        _scrollToBottom();
      }
    });

    final selfName = ref.watch(selfInfoProvider)?.name;
    final selfMentionColor = ref.watch(selfMentionColorProvider);
    final otherMentionColor = ref.watch(otherMentionColorProvider);
    final channels = ref.watch(channelsProvider);
    final allMessages = ref.watch(messagesProvider);
    final channelMessages =
        allMessages
            .where((m) => m.channelIndex == widget.channelIndex)
            .toList();
    final theme = Theme.of(context);

    final channelName =
        channels
            .where((c) => c.index == widget.channelIndex)
            .map((c) => c.name)
            .firstOrNull;

    return Column(
      children: [
        // Channel header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
          ),
          child: Row(
            children: [
              Icon(Icons.tag, color: theme.colorScheme.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                channelName ?? 'Canal ${widget.channelIndex}',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(
                '${channelMessages.length} mensagens',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),

        // Messages
        Expanded(
          child: Stack(
            children: [
              channelMessages.isEmpty
                  ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.forum_outlined,
                          size: 64,
                          color: theme.colorScheme.onSurface.withAlpha(60),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Sem mensagens neste canal',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.onSurface.withAlpha(120),
                          ),
                        ),
                      ],
                    ),
                  )
                  : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(8),
                    itemCount: channelMessages.length,
                    itemBuilder: (context, index) {
                      final msg = channelMessages[index];
                      return _MessageBubble(
                        message: msg,
                        selfName: selfName,
                        selfMentionColor: selfMentionColor,
                        otherMentionColor: otherMentionColor,
                        onReply:
                            msg.isOutgoing
                                ? null
                                : () => setState(() => _replyingTo = msg),
                      );
                    },
                  ),
              if (!_atBottom)
                Positioned(
                  bottom: 8,
                  right: 12,
                  child: FloatingActionButton.small(
                    heroTag: 'scroll_bottom_ch${widget.channelIndex}',
                    onPressed: _scrollToBottom,
                    child: const Icon(Icons.keyboard_double_arrow_down),
                  ),
                ),
            ],
          ),
        ),

        // Input bar
        _ChatInputBar(
          controller: _textController,
          onSend: _sendMessage,
          hintText: 'Mensagem para o canal...',
          replyTo: _replyingTo,
          onCancelReply:
              _replyingTo != null
                  ? () => setState(() => _replyingTo = null)
                  : null,
          participants: {
            for (final m in channelMessages.where((m) => !m.isOutgoing))
              _senderFromMessage(m),
          }..remove('Canal'),
        ),
      ],
    );
  }
}

/// Contacts screen showing all known contacts.
/// Also accessed from the bottom nav as the "Canais" tab shows channel list.
class ChannelsTabScreen extends ConsumerWidget {
  const ChannelsTabScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channels = ref.watch(channelsProvider);
    final theme = Theme.of(context);

    if (channels.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.forum_outlined,
              size: 64,
              color: theme.colorScheme.onSurface.withAlpha(60),
            ),
            const SizedBox(height: 16),
            Text(
              'Sem canais configurados',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurface.withAlpha(120),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Ligue-se a um radio MeshCore primeiro',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: channels.length,
      itemBuilder: (context, index) {
        final channel = channels[index];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Text(
                '${channel.index}',
                style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
              ),
            ),
            title: Text(
              channel.name.isNotEmpty ? channel.name : 'Canal ${channel.index}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.pushReplacement('/channels/${channel.index}'),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Heard-by-repeaters badge
// ---------------------------------------------------------------------------

/// Small pill badge shown below outgoing channel message bubbles indicating
/// how many repeaters have echoed the message back to the radio.
///
/// - count == 0: amber pill "A propagar..." (not yet picked up by a repeater)
/// - count  > 0: green pill with a broadcast icon + count
class _HeardBadge extends StatelessWidget {
  const _HeardBadge({required this.count, required this.theme});

  final int count;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final heard = count > 0;
    final bgColor =
        heard
            ? Colors.green.shade700.withAlpha(200)
            : Colors.amber.shade800.withAlpha(180);
    const fgColor = Colors.white;
    final icon = heard ? Icons.cell_tower : Icons.hourglass_empty;
    final label =
        heard ? '$count Repetidor${count > 1 ? 'es' : ''}' : 'A propagar...';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 11, color: fgColor),
              const SizedBox(width: 4),
              Text(
                label,
                style: (theme.textTheme.labelSmall ?? const TextStyle())
                    .copyWith(color: fgColor, fontSize: 10),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared widgets
// ---------------------------------------------------------------------------

/// Returns black or white for readable text on [bg].
Color _pillTextColor(Color bg) =>
    bg.computeLuminance() > 0.45 ? Colors.black : Colors.white;

/// Replaces lone UTF-16 surrogate code units with U+FFFD so that the Flutter
/// text engine never receives a malformed UTF-16 string.  Lone surrogates can
/// arrive when radio firmware sends raw binary inside a text field.
String _sanitizeUtf16(String s) {
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c >= 0xD800 && c <= 0xDBFF) {
      // High surrogate — valid only if immediately followed by a low surrogate.
      if (i + 1 < s.length) {
        final next = s.codeUnitAt(i + 1);
        if (next >= 0xDC00 && next <= 0xDFFF) {
          buf.writeCharCode(c);
          buf.writeCharCode(next);
          i++;
          continue;
        }
      }
      buf.writeCharCode(0xFFFD); // unpaired high surrogate
    } else if (c >= 0xDC00 && c <= 0xDFFF) {
      buf.writeCharCode(0xFFFD); // unpaired low surrogate
    } else {
      buf.writeCharCode(c);
    }
  }
  return buf.toString();
}

/// Renders text with all `@[name]` mentions as pill chips anywhere in the message.
/// Mentions matching [selfName] use [selfMentionColor] (or the theme tertiary);
/// all other mentions use [otherMentionColor] (or the theme primary).
Widget _buildMentionText(
  String text,
  ThemeData theme,
  TextStyle? style, {
  String? selfName,
  Color? selfMentionColor,
  Color? otherMentionColor,
}) {
  text = _sanitizeUtf16(text);
  final pattern = RegExp(r'@\[([^\]]+)\]');
  final matches = pattern.allMatches(text).toList();
  if (matches.isEmpty) return Text(text, style: style);

  final spans = <InlineSpan>[];
  var cursor = 0;

  for (final match in matches) {
    if (match.start > cursor) {
      spans.add(
        TextSpan(text: text.substring(cursor, match.start), style: style),
      );
    }
    final name = match.group(1)!;
    final isSelf =
        selfName != null &&
        name.trim().toLowerCase() == selfName.trim().toLowerCase();
    final pillColor = isSelf
        ? (selfMentionColor ?? theme.colorScheme.tertiary)
        : (otherMentionColor ?? theme.colorScheme.primary);
    final textColor = _pillTextColor(pillColor);
    spans.add(
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 1),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: pillColor,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '@$name',
            style: (theme.textTheme.labelSmall ?? const TextStyle()).copyWith(
              color: textColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
    cursor = match.end;
  }

  if (cursor < text.length) {
    spans.add(TextSpan(text: text.substring(cursor), style: style));
  }

  return Text.rich(TextSpan(children: spans));
}

class _MessageBubble extends StatelessWidget {
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

  void _showMsgContextMenu(BuildContext context, ChatMessage msg) {
    final theme = Theme.of(context);
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
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
                title: const Text('Responder'),
                onTap: () { Navigator.pop(context); onReply!(); },
              ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copiar texto'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: msg.text));
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Texto copiado'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
            ),
            if (msg.pathLen != null || msg.snr != null)
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Detalhes'),
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
    }
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.info_outline, color: theme.colorScheme.primary),
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
                  value: hops == 0 ? 'Directo' : '$hops hop${hops > 1 ? 's' : ''}',
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMe = message.isOutgoing;
    final time = DateTime.fromMillisecondsSinceEpoch(message.timestamp * 1000);
    final timeStr =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    final meta = _metaSuffix(message);
    final metaLine = meta.isNotEmpty ? '$timeStr • $meta' : timeStr;

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
                // Heard-by-repeaters badge — only for channel messages
                if (message.isChannel)
                  Padding(
                    padding: const EdgeInsets.only(top: 1, right: 4, bottom: 2),
                    child: _HeardBadge(count: message.heardCount, theme: theme),
                  )
                else
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
                  child: _buildMentionText(
                    displayText,
                    theme,
                    theme.textTheme.bodyMedium,
                    selfName: selfName,
                    selfMentionColor: selfMentionColor,
                    otherMentionColor: otherMentionColor,
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
      onLongPress: () => _showMsgContextMenu(context, message),
      child: row,
    );
    if (onReply != null) {
      return _SwipeToReplyWrapper(onReply: onReply!, child: rowWithPress);
    }
    return rowWithPress;
  }
}

class _ChatInputBar extends StatefulWidget {
  const _ChatInputBar({
    required this.controller,
    required this.onSend,
    this.hintText = 'Escreva uma mensagem...',
    this.replyTo,
    this.onCancelReply,
    this.participants = const {},
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final String hintText;
  final ChatMessage? replyTo;
  final VoidCallback? onCancelReply;
  final Set<String> participants;

  @override
  State<_ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<_ChatInputBar> {
  List<String> _suggestions = [];

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  /// Returns the active `@query` fragment at the cursor, or null if none.
  String? _mentionQuery() {
    final text = widget.controller.text;
    final cursor = widget.controller.selection.baseOffset;
    if (cursor < 0 || cursor > text.length) return null;
    final before = text.substring(0, cursor);
    // Find the last '@' that hasn't been closed with ']'
    final atIdx = before.lastIndexOf('@');
    if (atIdx < 0) return null;
    final fragment = before.substring(atIdx + 1);
    // If there's a space or newline in the fragment it's not a mention
    if (fragment.contains(' ') || fragment.contains('\n')) return null;
    return fragment.toLowerCase();
  }

  void _onTextChanged() {
    final query = _mentionQuery();
    if (query == null) {
      if (_suggestions.isNotEmpty) setState(() => _suggestions = []);
      return;
    }
    final filtered =
        widget.participants
            .where((p) => p.toLowerCase().contains(query))
            .toList()
          ..sort();
    if (filtered.toString() != _suggestions.toString()) {
      setState(() => _suggestions = filtered);
    }
  }

  void _insertMention(String name) {
    final text = widget.controller.text;
    final cursor = widget.controller.selection.baseOffset;
    final before = text.substring(0, cursor);
    final atIdx = before.lastIndexOf('@');
    final after = text.substring(cursor);
    final inserted = '${text.substring(0, atIdx)}@[$name] $after';
    widget.controller.value = TextEditingValue(
      text: inserted,
      selection: TextSelection.collapsed(offset: atIdx + name.length + 4),
    );
    setState(() => _suggestions = []);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant, width: 0.5),
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Mention suggestion strip
            if (_suggestions.isNotEmpty)
              Container(
                height: 40,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  border: Border(
                    bottom: BorderSide(
                      color: theme.colorScheme.outlineVariant,
                      width: 0.5,
                    ),
                  ),
                ),
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: _suggestions.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (context, i) {
                    final name = _suggestions[i];
                    return Center(
                      child: ActionChip(
                        label: Text('@$name'),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _insertMention(name),
                      ),
                    );
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.replyTo != null && widget.onCancelReply != null)
                    _ReplyStrip(
                      message: widget.replyTo!,
                      onCancel: widget.onCancelReply!,
                      theme: theme,
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: widget.controller,
                          decoration: InputDecoration(
                            hintText: widget.hintText,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                          ),
                          keyboardType: TextInputType.multiline,
                          textInputAction: TextInputAction.newline,
                          minLines: 1,
                          maxLines: 5,
                          maxLength: 140,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: widget.onSend,
                        icon: const Icon(Icons.send),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Swipe-to-reply + reply strip widgets
// ---------------------------------------------------------------------------

class _SwipeToReplyWrapper extends StatefulWidget {
  const _SwipeToReplyWrapper({required this.child, required this.onReply});
  final Widget child;
  final VoidCallback onReply;

  @override
  State<_SwipeToReplyWrapper> createState() => _SwipeToReplyWrapperState();
}

class _SwipeToReplyWrapperState extends State<_SwipeToReplyWrapper> {
  double _offset = 0;
  bool _fired = false;
  static const _kThreshold = 64.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = (_offset / _kThreshold).clamp(0.0, 1.0);
    return GestureDetector(
      onHorizontalDragUpdate: (d) {
        if (d.delta.dx > 0) {
          setState(() {
            _offset = (_offset + d.delta.dx).clamp(0.0, _kThreshold * 1.3);
            if (_offset >= _kThreshold && !_fired) {
              _fired = true;
              HapticFeedback.lightImpact();
              widget.onReply();
            }
          });
        }
      },
      onHorizontalDragEnd:
          (_) => setState(() {
            _offset = 0;
            _fired = false;
          }),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 4,
            top: 0,
            bottom: 0,
            child: Center(
              child: Opacity(
                opacity: progress,
                child: Transform.scale(
                  scale: 0.6 + 0.4 * progress,
                  child: Icon(
                    Icons.reply,
                    color: theme.colorScheme.primary,
                    size: 24,
                  ),
                ),
              ),
            ),
          ),
          Transform.translate(offset: Offset(_offset, 0), child: widget.child),
        ],
      ),
    );
  }
}

class _ReplyStrip extends StatelessWidget {
  const _ReplyStrip({
    required this.message,
    required this.onCancel,
    required this.theme,
  });
  final ChatMessage message;
  final VoidCallback onCancel;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final senderLabel =
        message.isOutgoing
            ? '@[Você]'
            : '@[${message.senderName ?? 'Contacto'}]';
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(color: theme.colorScheme.primary, width: 3),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.reply, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  senderLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  _sanitizeUtf16(message.text),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            onPressed: onCancel,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          ),
        ],
      ),
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
