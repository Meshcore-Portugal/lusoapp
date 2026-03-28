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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(unreadCountsProvider.notifier)
          .markChannelRead(widget.channelIndex);
      // Load persisted messages for this channel on first open.
      ref
          .read(messagesProvider.notifier)
          .ensureLoadedForChannel(widget.channelIndex);
    });
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
        _replyingTo != null ? '@${_senderFromMessage(_replyingTo!)}: ' : '';
    final fullText = '$replyPrefix$text';

    service.sendChannelMessage(widget.channelIndex, fullText);

    // Add outgoing message to local state
    ref
        .read(messagesProvider.notifier)
        .addOutgoing(
          ChatMessage(
            text: fullText,
            timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            isOutgoing: true,
            channelIndex: widget.channelIndex,
          ),
        );

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
      if (prev != null && next.length > prev.length) _scrollToBottom();
    });

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
          child:
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
                        onReply:
                            msg.isOutgoing
                                ? null
                                : () => setState(() => _replyingTo = msg),
                      );
                    },
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
// Shared widgets
// ---------------------------------------------------------------------------

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, this.onReply});
  final ChatMessage message;
  final VoidCallback? onReply;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMe = message.isOutgoing;
    final time = DateTime.fromMillisecondsSinceEpoch(message.timestamp * 1000);
    final timeStr =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

    final bubble = Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color:
              isMe
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMe && message.senderName != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  message.senderName!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            Text(message.text),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  timeStr,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withAlpha(100),
                  ),
                ),
                if (!isMe && message.snr != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    'SNR ${message.snr!.toStringAsFixed(1)} dB',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurface.withAlpha(90),
                    ),
                  ),
                ],
                if (isMe) ...[
                  const SizedBox(width: 6),
                  Icon(
                    message.confirmed ? Icons.done_all : Icons.done,
                    size: 18,
                    color:
                        message.confirmed
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface.withAlpha(140),
                    shadows:
                        message.confirmed
                            ? [
                              Shadow(
                                color: theme.colorScheme.primary.withAlpha(80),
                                blurRadius: 4,
                              ),
                            ]
                            : null,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );

    if (!isMe && onReply != null) {
      return _SwipeToReplyWrapper(onReply: onReply!, child: bubble);
    }
    return bubble;
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
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => onSend(),
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
        message.isOutgoing ? 'Você' : (message.senderName ?? 'Contacto');
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
