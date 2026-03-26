import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    // Mark channel as read when this screen is opened.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(unreadCountsProvider.notifier)
          .markChannelRead(widget.channelIndex);
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

    service.sendChannelMessage(widget.channelIndex, text);

    // Add outgoing message to local state
    ref
        .read(messagesProvider.notifier)
        .addOutgoing(
          ChatMessage(
            text: text,
            timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            isOutgoing: true,
            channelIndex: widget.channelIndex,
          ),
        );

    _textController.clear();
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

  @override
  Widget build(BuildContext context) {
    // While this screen is visible, clear unread badge for this channel
    // whenever new messages arrive.
    ref.listen<List<ChatMessage>>(messagesProvider, (_, __) {
      ref
          .read(unreadCountsProvider.notifier)
          .markChannelRead(widget.channelIndex);
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
                      return _MessageBubble(message: msg);
                    },
                  ),
        ),

        // Input bar
        _ChatInputBar(
          controller: _textController,
          onSend: _sendMessage,
          hintText: 'Mensagem para o canal...',
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
            onTap: () => context.go('/channels/${channel.index}'),
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
  const _MessageBubble({required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMe = message.isOutgoing;
    final time = DateTime.fromMillisecondsSinceEpoch(message.timestamp * 1000);
    final timeStr =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

    return Align(
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
            Text(
              timeStr,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface.withAlpha(100),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatInputBar extends StatelessWidget {
  const _ChatInputBar({
    required this.controller,
    required this.onSend,
    this.hintText = 'Escreva uma mensagem...',
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final String hintText;

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
        child: Row(
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
            IconButton.filled(onPressed: onSend, icon: const Icon(Icons.send)),
          ],
        ),
      ),
    );
  }
}
