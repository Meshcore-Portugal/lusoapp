import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../protocol/protocol.dart';
import '../../providers/radio_providers.dart';

/// Private (1:1) chat screen with a specific contact.
class PrivateChatScreen extends ConsumerStatefulWidget {
  const PrivateChatScreen({super.key, required this.contactKeyHex});
  final String contactKeyHex;

  @override
  ConsumerState<PrivateChatScreen> createState() => _PrivateChatScreenState();
}

class _PrivateChatScreenState extends ConsumerState<PrivateChatScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  bool _waitingForTrace = false;
  ChatMessage? _replyingTo;
  bool _atBottom = true;

  Uint8List get _contactKey {
    final hex = widget.contactKeyHex;
    final bytes = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return Uint8List.fromList(bytes);
  }

  Contact? _findContact(List<Contact> contacts) {
    final key = _contactKey;
    for (final c in contacts) {
      if (c.publicKey.length >= key.length) {
        var match = true;
        for (var i = 0; i < key.length && i < c.publicKey.length; i++) {
          if (key[i] != c.publicKey[i]) {
            match = false;
            break;
          }
        }
        if (match) return c;
      }
    }
    return null;
  }

  void _sendMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    final service = ref.read(radioServiceProvider);
    if (service == null) return;

    // Send using first 6 bytes of the public key as prefix
    final keyPrefix =
        _contactKey.length >= 6 ? _contactKey.sublist(0, 6) : _contactKey;
    final replyContact =
        _replyingTo != null ? _findContact(ref.read(contactsProvider)) : null;
    final replyPrefix =
        _replyingTo != null
            ? '@[${replyContact?.displayName ?? 'Contacto'}] '
            : '';
    final fullText = '$replyPrefix$text';

    // Add outgoing message to state BEFORE sending the BLE command.
    // The firmware response (SentResponse with routeFlag) can arrive before
    // the next microtask, so the message must already be in state for
    // markLastOutgoingRoute() to find it.
    ref
        .read(messagesProvider.notifier)
        .addOutgoing(
          ChatMessage(
            text: fullText,
            timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            isOutgoing: true,
            senderKey: _contactKey,
          ),
        );

    service.sendPrivateMessage(keyPrefix, fullText);

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

  // First 12 hex chars = first 6 bytes of the key — matches incoming senderKey.
  String get _prefix6Hex {
    final hex = widget.contactKeyHex;
    return hex.length >= 12 ? hex.substring(0, 12) : hex;
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final atBottom =
        _scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 80;
    if (atBottom != _atBottom) setState(() => _atBottom = atBottom);
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      ref.read(unreadCountsProvider.notifier).markContactRead(_prefix6Hex);
      // Load persisted messages, then scroll to bottom once they are in state.
      await ref
          .read(messagesProvider.notifier)
          .ensureLoadedForContact(_prefix6Hex);
      if (mounted) _scrollToBottom();
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // While this screen is visible, clear unread badge for this contact
    // whenever new messages arrive, and tail-scroll to the latest message.
    ref.listen<List<ChatMessage>>(messagesProvider, (prev, next) {
      ref.read(unreadCountsProvider.notifier).markContactRead(_prefix6Hex);
      if (prev != null && next.length > prev.length && _atBottom) {
        _scrollToBottom();
      }
    });

    // Show trace result sheet when a new trace arrives
    ref.listen<TraceResult?>(traceResultProvider, (prev, next) {
      if (!_waitingForTrace || next == null || !mounted) return;
      if (prev?.tag == next.tag && prev?.timestamp == next.timestamp) return;
      _waitingForTrace = false;
      _showTraceSheet(next);
    });

    final selfName = ref.watch(selfInfoProvider)?.name;
    final contacts = ref.watch(contactsProvider);
    final allMessages = ref.watch(messagesProvider);
    final contact = _findContact(contacts);
    final theme = Theme.of(context);

    // Filter messages for this contact
    final contactMessages =
        allMessages.where((m) {
          if (m.isChannel) return false;
          if (m.isOutgoing) {
            // Outgoing messages: match by senderKey we stored
            if (m.senderKey == null) return false;
            return _prefixMatch(m.senderKey!, _contactKey);
          }
          // Incoming: match senderKey prefix
          if (m.senderKey == null) return false;
          return _prefixMatch(m.senderKey!, _contactKey);
        }).toList();

    return Column(
      children: [
        // Contact header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Icon(
                  _contactIcon(contact?.type ?? 0),
                  color: theme.colorScheme.onPrimaryContainer,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      contact?.displayName ?? 'Contacto',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (contact != null)
                      Text(
                        '${_contactTypeName(contact.type)} - ${contact.shortId}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withAlpha(120),
                        ),
                      ),
                  ],
                ),
              ),
              // Actions
              PopupMenuButton<String>(
                onSelected: (value) {
                  final service = ref.read(radioServiceProvider);
                  if (service == null || contact == null) return;
                  switch (value) {
                    case 'trace':
                      setState(() => _waitingForTrace = true);
                      service.tracePath(Random().nextInt(0x7FFFFFFF));
                    case 'reset_path':
                      service.resetPath(contact.publicKey);
                  }
                },
                itemBuilder:
                    (_) => [
                      const PopupMenuItem(
                        value: 'trace',
                        child: ListTile(
                          leading: Icon(Icons.route),
                          title: Text('Tracar rota'),
                          dense: true,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'reset_path',
                        child: ListTile(
                          leading: Icon(Icons.refresh),
                          title: Text('Limpar caminho'),
                          dense: true,
                        ),
                      ),
                    ],
              ),
            ],
          ),
        ),

        // Messages
        Expanded(
          child: Stack(
            children: [
              contactMessages.isEmpty
                  ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 64,
                          color: theme.colorScheme.onSurface.withAlpha(60),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Sem mensagens',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.onSurface.withAlpha(120),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Envie a primeira mensagem!',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  )
                  : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(8),
                    itemCount: contactMessages.length,
                    itemBuilder: (context, index) {
                      final msg = contactMessages[index];
                      return _PrivateMessageBubble(
                        message: msg,
                        selfName: selfName,
                        contactDisplayName:
                            msg.isOutgoing ? null : contact?.displayName,
                        contactPathLen: contact?.pathLen,
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
                    heroTag: 'scroll_bottom_priv${widget.contactKeyHex}',
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
          hintText: 'Mensagem para ${contact?.name ?? "contacto"}...',
          replyTo: _replyingTo,
          onCancelReply:
              _replyingTo != null
                  ? () => setState(() => _replyingTo = null)
                  : null,
        ),
      ],
    );
  }

  bool _prefixMatch(Uint8List a, Uint8List b) {
    final len = a.length < b.length ? a.length : b.length;
    if (len < 4) return false;
    for (var i = 0; i < len && i < 6; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  IconData _contactIcon(int type) {
    switch (type) {
      case 1:
        return Icons.person;
      case 2:
        return Icons.repeat;
      case 3:
        return Icons.meeting_room;
      case 4:
        return Icons.sensors;
      default:
        return Icons.device_unknown;
    }
  }

  String _contactTypeName(int type) {
    switch (type) {
      case 1:
        return 'Chat';
      case 2:
        return 'Repetidor';
      case 3:
        return 'Sala';
      case 4:
        return 'Sensor';
      default:
        return 'Desconhecido';
    }
  }

  void _showTraceSheet(TraceResult result) {
    final theme = Theme.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _TraceResultSheet(result: result, theme: theme),
    );
  }
}

/// Renders text that may start with an `@[name]` mention.
/// The mention is shown as an accent-coloured rounded pill; the rest is normal text.
/// Renders text with all `@[name]` mentions as pill chips anywhere in the message.
/// Mentions matching [selfName] use the tertiary colour for emphasis;
/// all other mentions use the primary colour.
Widget _buildMentionText(
  String text,
  ThemeData theme,
  TextStyle? style, {
  String? selfName,
}) {
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
    final pillColor =
        isSelf ? theme.colorScheme.tertiary : theme.colorScheme.primary;
    final textColor =
        isSelf ? theme.colorScheme.onTertiary : Colors.white;
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

class _PrivateMessageBubble extends StatelessWidget {
  const _PrivateMessageBubble({
    required this.message,
    this.onReply,
    this.contactDisplayName,
    this.contactPathLen,
    this.selfName,
  });
  final ChatMessage message;
  final VoidCallback? onReply;
  final String? contactDisplayName;
  final int? contactPathLen;
  final String? selfName;

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

  static String _metaSuffix(ChatMessage msg, {int? contactPathLen}) {
    final parts = <String>[];
    if (msg.snr != null) parts.add('SNR ${msg.snr!.toStringAsFixed(1)} dB');
    if (msg.pathLen != null) {
      final hops = msg.pathLen! & 0x3F;
      if (hops == 0) {
        parts.add('Directo');
      } else {
        parts.add('Ouvido $hops Repetidor${hops > 1 ? 'es' : ''}');
      }
    }
    if (msg.isOutgoing && msg.sentRouteFlag != null && msg.pathLen == null) {
      if (msg.sentRouteFlag == 0) {
        // Direct routing — use contact's known path length for hop count.
        final cHops =
            (contactPathLen != null && contactPathLen != 0xFF)
                ? contactPathLen & 0x3F
                : 0;
        if (cHops > 0) {
          parts.add('Ouvido $cHops Repetidor${cHops > 1 ? 'es' : ''}');
        } else {
          parts.add('Directo');
        }
      } else {
        parts.add('Ouvido 1 Repetidor');
      }
    }
    return parts.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMe = message.isOutgoing;
    final time = DateTime.fromMillisecondsSinceEpoch(message.timestamp * 1000);
    final timeStr =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    final meta = _metaSuffix(message, contactPathLen: contactPathLen);
    final metaLine = meta.isNotEmpty ? '$timeStr • $meta' : timeStr;

    if (isMe) {
      return Padding(
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
              const SizedBox(height: 2),
            ],
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
                    message.text,
                    theme,
                    theme.textTheme.bodyMedium,
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

    if (onReply != null) {
      return _SwipeToReplyWrapper(onReply: onReply!, child: row);
    }
    return row;
  }
}

class _ChatInputBar extends StatelessWidget {
  const _ChatInputBar({
    required this.controller,
    required this.onSend,
    this.hintText = 'Escreva uma mensagem...',
    this.replyTo,
    this.onCancelReply,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final String hintText;
  final ChatMessage? replyTo;
  final VoidCallback? onCancelReply;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(8),
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
            if (replyTo != null && onCancelReply != null)
              _ReplyStrip(
                message: replyTo!,
                onCancel: onCancelReply!,
                theme: theme,
              ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    decoration: InputDecoration(
                      hintText: hintText,
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
                  onPressed: onSend,
                  icon: const Icon(Icons.send),
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
                  message.text,
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
// Trace result bottom sheet
// ---------------------------------------------------------------------------

class _TraceResultSheet extends StatelessWidget {
  const _TraceResultSheet({required this.result, required this.theme});

  final TraceResult result;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final ts =
        '${result.timestamp.hour.toString().padLeft(2, '0')}:'
        '${result.timestamp.minute.toString().padLeft(2, '0')}:'
        '${result.timestamp.second.toString().padLeft(2, '0')}';

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
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
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(Icons.route, color: theme.colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Rota encontrada — $ts',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  '${result.hopCount} hop${result.hopCount != 1 ? 's' : ''}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 16),
          if (result.hops.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Rota directa (sem repetidores)',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            for (int i = 0; i < result.hops.length; i++)
              _TraceHopTile(index: i + 1, hop: result.hops[i], theme: theme),
          ListTile(
            leading: Icon(
              Icons.arrow_downward,
              color: Colors.green.shade600,
              size: 20,
            ),
            title: const Text('Recebido no rádio'),
            trailing: Text(
              '${result.finalSnrDb.toStringAsFixed(1)} dB',
              style: theme.textTheme.labelLarge?.copyWith(
                color: Colors.green.shade600,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }
}

class _TraceHopTile extends StatelessWidget {
  const _TraceHopTile({
    required this.index,
    required this.hop,
    required this.theme,
  });

  final int index;
  final TraceHop hop;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final snrColor =
        hop.snrDb > 5
            ? Colors.green.shade600
            : hop.snrDb > 0
            ? Colors.orange.shade700
            : Colors.red.shade600;

    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 14,
        backgroundColor: theme.colorScheme.primaryContainer,
        child: Text(
          '$index',
          style: TextStyle(
            color: theme.colorScheme.onPrimaryContainer,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      title: Text(
        hop.name ?? hop.hashHex,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontFamily: hop.name == null ? 'monospace' : null,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle:
          hop.hasGps
              ? Text(
                '${hop.latitude!.toStringAsFixed(5)}, ${hop.longitude!.toStringAsFixed(5)}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
              : Text(
                'Sem GPS',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outlineVariant,
                ),
              ),
      trailing: Text(
        '${hop.snrDb.toStringAsFixed(1)} dB',
        style: theme.textTheme.labelLarge?.copyWith(
          color: snrColor,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
