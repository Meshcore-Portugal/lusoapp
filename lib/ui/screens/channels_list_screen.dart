import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../protocol/protocol.dart';
import '../../providers/radio_providers.dart';

// Filter options
enum _Filter { todos, naoLidos }

/// Channels list screen with filter chips and last-message preview.
class ChannelsListScreen extends ConsumerStatefulWidget {
  const ChannelsListScreen({super.key});

  @override
  ConsumerState<ChannelsListScreen> createState() => _ChannelsListScreenState();
}

class _ChannelsListScreenState extends ConsumerState<ChannelsListScreen> {
  _Filter _filter = _Filter.todos;

  @override
  Widget build(BuildContext context) {
    final channels = ref.watch(channelsProvider);
    final unread = ref.watch(unreadCountsProvider);

    // Only show slots that have a name configured.
    final configured = channels.where((c) => c.name.isNotEmpty).toList();

    // Count channels with unread messages.
    final unreadChannelCount =
        configured.where((c) => unread.forChannel(c.index) > 0).length;

    // Apply filter.
    final filtered =
        _filter == _Filter.naoLidos
            ? configured.where((c) => unread.forChannel(c.index) > 0).toList()
            : List<ChannelInfo>.from(configured);

    // Sort: unread-first, then by index.
    filtered.sort((a, b) {
      final ua = unread.forChannel(a.index);
      final ub = unread.forChannel(b.index);
      if (ua != ub) return ub.compareTo(ua);
      return a.index.compareTo(b.index);
    });

    return Column(
      children: [
        // Filter chips bar
        _FilterBar(
          filter: _filter,
          totalCount: configured.length,
          unreadCount: unreadChannelCount,
          onChanged: (f) => setState(() => _filter = f),
        ),

        // Content
        Expanded(
          child:
              configured.isEmpty
                  ? _EmptyState(
                    onRefresh: () {
                      final service = ref.read(radioServiceProvider);
                      if (service == null) return;
                      for (var i = 0; i < 8; i++) {
                        service.requestChannel(i);
                      }
                    },
                  )
                  : filtered.isEmpty
                  ? _NoUnreadState(
                    onClearFilter:
                        () => setState(() => _filter = _Filter.todos),
                  )
                  : RefreshIndicator(
                    onRefresh: () async {
                      final service = ref.read(radioServiceProvider);
                      if (service == null) return;
                      for (var i = 0; i < 8; i++) {
                        await service.requestChannel(i);
                        await Future.delayed(const Duration(milliseconds: 100));
                      }
                    },
                    child: ListView.builder(
                      padding: const EdgeInsets.only(top: 4, bottom: 8),
                      itemCount: filtered.length,
                      itemBuilder:
                          (context, index) =>
                              _ChannelTile(channel: filtered[index]),
                    ),
                  ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Filter bar
// ---------------------------------------------------------------------------

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.filter,
    required this.totalCount,
    required this.unreadCount,
    required this.onChanged,
  });

  final _Filter filter;
  final int totalCount;
  final int unreadCount;
  final ValueChanged<_Filter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        spacing: 8,
        children: [
          _chip(_Filter.todos, 'Todos', Icons.forum, totalCount),
          _chip(
            _Filter.naoLidos,
            'Não lidos',
            Icons.mark_chat_unread,
            unreadCount,
          ),
        ],
      ),
    );
  }

  Widget _chip(_Filter f, String label, IconData icon, int count) {
    final selected = filter == f;
    return FilterChip(
      selected: selected,
      avatar: Icon(icon, size: 16),
      label: Text(count > 0 ? '$label ($count)' : label),
      onSelected: (_) => onChanged(f),
      showCheckmark: false,
    );
  }
}

// ---------------------------------------------------------------------------
// Empty states
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onRefresh});
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
            'Sem canais',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface.withAlpha(120),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Os canais configurados no rádio aparecem aqui',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Actualizar Canais'),
          ),
        ],
      ),
    );
  }
}

class _NoUnreadState extends StatelessWidget {
  const _NoUnreadState({required this.onClearFilter});
  final VoidCallback onClearFilter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.mark_chat_read_outlined,
            size: 64,
            color: theme.colorScheme.onSurface.withAlpha(60),
          ),
          const SizedBox(height: 16),
          Text(
            'Tudo lido',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface.withAlpha(120),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Sem mensagens não lidas nos canais',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          TextButton.icon(
            onPressed: onClearFilter,
            icon: const Icon(Icons.list),
            label: const Text('Ver todos os canais'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Channel tile
// ---------------------------------------------------------------------------

class _ChannelTile extends ConsumerWidget {
  const _ChannelTile({required this.channel});
  final ChannelInfo channel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final unreadCount = ref.watch(
      unreadCountsProvider.select((u) => u.forChannel(channel.index)),
    );

    final allMessages = ref.watch(messagesProvider);
    final channelMessages =
        allMessages.where((m) => m.channelIndex == channel.index).toList();

    final lastMessage =
        channelMessages.isNotEmpty ? channelMessages.last : null;

    final hasUnread = unreadCount > 0;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.go('/channels/${channel.index}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              // Leading: index badge with unread count
              Badge(
                isLabelVisible: hasUnread,
                label: Text(unreadCount > 99 ? '99+' : '$unreadCount'),
                child: CircleAvatar(
                  backgroundColor:
                      hasUnread
                          ? theme.colorScheme.primaryContainer
                          : theme.colorScheme.surfaceContainerHighest,
                  child: Text(
                    '${channel.index}',
                    style: TextStyle(
                      color:
                          hasUnread
                              ? theme.colorScheme.onPrimaryContainer
                              : theme.colorScheme.onSurface.withAlpha(180),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 12),

              // Channel name + last message preview
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      channel.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight:
                            hasUnread ? FontWeight.bold : FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _previewText(lastMessage),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            hasUnread
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurface.withAlpha(140),
                        fontWeight: hasUnread ? FontWeight.w600 : null,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // Trailing: timestamp + total count
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (lastMessage != null)
                    Text(
                      _formatTimestamp(lastMessage.timestamp),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color:
                            hasUnread
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurface.withAlpha(120),
                        fontWeight: hasUnread ? FontWeight.bold : null,
                      ),
                    ),
                  if (channelMessages.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${channelMessages.length} msg',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurface.withAlpha(100),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _previewText(ChatMessage? msg) {
    if (msg == null) return 'Sem mensagens';
    if (msg.isOutgoing) return 'Eu: ${msg.text}';
    if (msg.senderName != null && msg.senderName!.isNotEmpty) {
      return '${msg.senderName}: ${msg.text}';
    }
    return msg.text;
  }

  String _formatTimestamp(int ts) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Agora';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${dt.day}/${dt.month}';
  }
}
