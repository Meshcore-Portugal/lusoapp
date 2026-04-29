part of '../channels_list_screen.dart';

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
          _chip(_Filter.todos, context.l10n.commonAll, Icons.forum, totalCount),
          _chip(
            _Filter.naoLidos,
            context.l10n.commonUnread,
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
            context.l10n.channelsEmpty,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface.withAlpha(120),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.channelsEmptyHint,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh),
            label: Text(context.l10n.channelsRefresh),
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
            context.l10n.channelsAllRead,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface.withAlpha(120),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.channelsAllReadHint,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          TextButton.icon(
            onPressed: onClearFilter,
            icon: const Icon(Icons.list),
            label: Text(context.l10n.channelsSeeAll),
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
  const _ChannelTile({required this.channel, required this.onEdit});
  final ChannelInfo channel;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final unreadCount = ref.watch(
      unreadCountsProvider.select((u) => u.forChannel(channel.index)),
    );
    final isMuted = ref.watch(
      mutedChannelsProvider.select((s) => s.contains(channel.index)),
    );

    // Watch only this channel's version so the card rebuilds only when
    // messages arrive on this specific channel (#2 perf fix).
    ref.watch(
      messageVersionsProvider.select((vs) => vs['ch_${channel.index}'] ?? 0),
    );
    final channelMessages = ref
        .read(messagesProvider.notifier)
        .forChannel(channel.index);
    final lastMessage =
        channelMessages.isNotEmpty ? channelMessages.last : null;
    final hasUnread = unreadCount > 0;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/channels/${channel.index}'),
        onLongPress: onEdit,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              // Leading: index badge with unread indicator (greyed when muted)
              Badge(
                isLabelVisible: hasUnread && !isMuted,
                label: Text(unreadCount > 99 ? '99+' : '$unreadCount'),
                child: CircleAvatar(
                  backgroundColor:
                      hasUnread && !isMuted
                          ? theme.colorScheme.primaryContainer
                          : theme.colorScheme.surfaceContainerHighest,
                  child:
                      isMuted
                          ? Icon(
                            Icons.notifications_off_outlined,
                            size: 18,
                            color: theme.colorScheme.onSurface.withAlpha(120),
                          )
                          : Text(
                            '${channel.index}',
                            style: TextStyle(
                              color:
                                  hasUnread
                                      ? theme.colorScheme.onPrimaryContainer
                                      : theme.colorScheme.onSurface.withAlpha(
                                        180,
                                      ),
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
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            channel.name,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight:
                                  hasUnread && !isMuted
                                      ? FontWeight.bold
                                      : FontWeight.w500,
                              color:
                                  isMuted
                                      ? theme.colorScheme.onSurface.withAlpha(
                                        120,
                                      )
                                      : null,
                            ),
                          ),
                        ),
                        if (isMuted)
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Text(
                              context.l10n.channelsMuteLabel,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurface.withAlpha(
                                  100,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _previewText(context, lastMessage),
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

              // Options button
              IconButton(
                icon: const Icon(Icons.more_vert, size: 18),
                tooltip: context.l10n.channelsOptionsFabTooltip,
                onPressed: onEdit,
                visualDensity: VisualDensity.compact,
              ),

              // Trailing: timestamp + total count
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (lastMessage != null)
                    Text(
                      _formatTimestamp(context, lastMessage.timestamp),
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

  String _previewText(BuildContext context, ChatMessage? msg) {
    if (msg == null) return context.l10n.commonNoMessages;
    final l10n = context.l10n;
    if (msg.isOutgoing) return '${l10n.commonSentByMe}: ${msg.text}';
    if (msg.senderName != null && msg.senderName!.isNotEmpty) {
      return '${msg.senderName}: ${msg.text}';
    }
    return msg.text;
  }

  String _formatTimestamp(BuildContext context, int ts) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return context.l10n.telemetryNow;
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${dt.day}/${dt.month}';
  }
}

// ---------------------------------------------------------------------------
