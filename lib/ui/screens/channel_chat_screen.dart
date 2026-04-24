import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import 'package:url_launcher/url_launcher.dart';

import '../../l10n/l10n.dart';
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

  /// Key attached to the unread divider widget so we can ensureVisible on it.
  final _unreadDividerKey = GlobalKey();
  ChatMessage? _replyingTo;
  bool _atBottom = true;

  /// Unread count captured before marking channel read on open.
  /// Used to scroll to the first unread message and show the divider.
  int _unreadOnOpen = 0;

  /// Index (in the message list) of the first unread message when the screen
  /// was opened. -1 means the divider should not be shown.
  int _firstUnreadIndex = -1;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      // Capture unread count BEFORE clearing it.
      _unreadOnOpen = ref
          .read(unreadCountsProvider)
          .forChannel(widget.channelIndex);
      ref
          .read(unreadCountsProvider.notifier)
          .markChannelRead(widget.channelIndex);
      // Load persisted messages, then scroll to first unread (or bottom).
      await ref
          .read(messagesProvider.notifier)
          .ensureLoadedForChannel(widget.channelIndex);
      if (mounted) {
        if (_unreadOnOpen > 0) {
          // Compute the divider index after messages are loaded.
          final msgs =
              ref
                  .read(messagesProvider)
                  .where((m) => m.channelIndex == widget.channelIndex)
                  .toList();
          final idx = (msgs.length - _unreadOnOpen).clamp(0, msgs.length - 1);
          if (idx >= 0 && idx < msgs.length) {
            setState(() => _firstUnreadIndex = idx);
          }
          _scrollToFirstUnread();
        } else {
          _scrollToBottom(animate: false, attempts: 4);
        }
      }
    });
  }

  @override
  void didUpdateWidget(covariant ChannelChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channelIndex == widget.channelIndex) return;

    _replyingTo = null;
    _textController.clear();
    _atBottom = true;
    _firstUnreadIndex = -1;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      _unreadOnOpen = ref
          .read(unreadCountsProvider)
          .forChannel(widget.channelIndex);
      ref
          .read(unreadCountsProvider.notifier)
          .markChannelRead(widget.channelIndex);
      await ref
          .read(messagesProvider.notifier)
          .ensureLoadedForChannel(widget.channelIndex);
      if (mounted) {
        if (_unreadOnOpen > 0) {
          final msgs =
              ref
                  .read(messagesProvider)
                  .where((m) => m.channelIndex == widget.channelIndex)
                  .toList();
          final idx = (msgs.length - _unreadOnOpen).clamp(0, msgs.length - 1);
          if (idx >= 0 && idx < msgs.length) {
            setState(() => _firstUnreadIndex = idx);
          }
          _scrollToFirstUnread();
        } else {
          _scrollToBottom(animate: false, attempts: 4);
        }
      }
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final atBottom =
        _scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 80;
    if (atBottom != _atBottom) setState(() => _atBottom = atBottom);
    // Once the user has scrolled to the bottom, dismiss the unread divider.
    if (atBottom && _firstUnreadIndex != -1) {
      setState(() => _firstUnreadIndex = -1);
    }
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

  /// Scroll so the unread divider is at the top of the viewport.
  /// Delegates to [_tryScrollToDivider] which retries each frame until the
  /// divider widget is actually built by the lazy ListView.
  void _scrollToFirstUnread() {
    if (_firstUnreadIndex < 0) {
      _scrollToBottom(animate: false, attempts: 4);
      return;
    }
    _tryScrollToDivider(attempts: 6);
  }

  /// Each attempt:
  ///  - If the divider GlobalKey has a live context → ensureVisible (done).
  ///  - Otherwise do a rough fractional jump to force the lazy list to build
  ///    items near the divider, then schedule the next attempt.
  void _tryScrollToDivider({int attempts = 6}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _firstUnreadIndex < 0) return;

      // Try precise scroll first.
      final ctx = _unreadDividerKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx, alignment: 0.0, duration: Duration.zero);
        return;
      }

      // Divider not built yet — do a rough jump to bring it into the build
      // window of the lazy list, then retry next frame.
      if (_scrollController.hasClients) {
        final max = _scrollController.position.maxScrollExtent;
        if (max > 0) {
          final msgs =
              ref
                  .read(messagesProvider)
                  .where((m) => m.channelIndex == widget.channelIndex)
                  .toList();
          if (msgs.isNotEmpty) {
            final fraction = _firstUnreadIndex / (msgs.length + 1);
            _scrollController.jumpTo((fraction * max).clamp(0.0, max));
          }
        }
      }

      if (attempts > 1) _tryScrollToDivider(attempts: attempts - 1);
    });
  }

  void _scrollToBottom({bool animate = true, int attempts = 1}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (animate) {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(target);
      }

      if (attempts > 1) {
        final retryDelay = animate ? 240 : 80;
        Future<void>.delayed(Duration(milliseconds: retryDelay), () {
          if (mounted) {
            _scrollToBottom(animate: false, attempts: attempts - 1);
          }
        });
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
    final isMuted = ref.watch(
      mutedChannelsProvider.select((s) => s.contains(widget.channelIndex)),
    );

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
              if (isMuted)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Icon(
                    Icons.notifications_off_outlined,
                    size: 16,
                    color: theme.colorScheme.onSurface.withAlpha(140),
                  ),
                ),
              const Spacer(),
              Text(
                '${channelMessages.length} mensagens',
                style: theme.textTheme.bodySmall,
              ),
              if (channelMessages.isNotEmpty)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 20),
                  tooltip: context.l10n.chatMenuOptions,
                  onSelected: (value) async {
                    if (value == 'mute') {
                      await ref
                          .read(mutedChannelsProvider.notifier)
                          .toggle(widget.channelIndex);
                    } else if (value == 'clear') {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder:
                            (ctx) => AlertDialog(
                              title: Text(context.l10n.commonClearHistory),
                              content: const Text(
                                'Apagar todas as mensagens deste canal? Esta ação não pode ser revertida.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: Text(context.l10n.commonCancel),
                                ),
                                FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: theme.colorScheme.error,
                                    foregroundColor: theme.colorScheme.onError,
                                  ),
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: Text(context.l10n.commonDelete),
                                ),
                              ],
                            ),
                      );
                      if (confirm == true && context.mounted) {
                        await ref
                            .read(messagesProvider.notifier)
                            .deleteChannelHistory(widget.channelIndex);
                      }
                    }
                  },
                  itemBuilder:
                      (_) => [
                        PopupMenuItem(
                          value: 'mute',
                          child: ListTile(
                            leading: Icon(
                              isMuted
                                  ? Icons.notifications_outlined
                                  : Icons.notifications_off_outlined,
                              color:
                                  isMuted
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.onSurface.withAlpha(
                                        160,
                                      ),
                            ),
                            title: Text(
                              isMuted
                                  ? context.l10n.chatUnmuteChannel
                                  : context.l10n.chatMuteChannel,
                            ),
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                          ),
                        ),
                        PopupMenuItem(
                          value: 'clear',
                          child: ListTile(
                            leading: Icon(
                              Icons.delete_sweep,
                              color: theme.colorScheme.error,
                            ),
                            title: Text(
                              context.l10n.commonClearHistory,
                              style: TextStyle(color: theme.colorScheme.error),
                            ),
                            contentPadding: EdgeInsets.zero,
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
                          context.l10n.chatNoMessages,
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
                    // Extra item slot for the unread divider when active.
                    itemCount:
                        channelMessages.length +
                        (_firstUnreadIndex >= 0 ? 1 : 0),
                    itemBuilder: (context, index) {
                      // If the divider is active and we hit its slot, render it.
                      if (_firstUnreadIndex >= 0 &&
                          index == _firstUnreadIndex) {
                        return _UnreadDivider(
                          key: _unreadDividerKey,
                          onDismiss:
                              () => setState(() => _firstUnreadIndex = -1),
                        );
                      }
                      // Shift real message index down by 1 after the divider.
                      final msgIndex =
                          (_firstUnreadIndex >= 0 && index > _firstUnreadIndex)
                              ? index - 1
                              : index;
                      final msg = channelMessages[msgIndex];
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
                    onPressed:
                        () => _scrollToBottom(animate: true, attempts: 5),
                    child: const Icon(Icons.keyboard_double_arrow_down),
                  ),
                ),
            ],
          ),
        ),

        // Input bar
        if (channelName?.toLowerCase() == '#ping')
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  final service = ref.read(radioServiceProvider);
                  if (service == null) return;
                  final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
                  ref
                      .read(messagesProvider.notifier)
                      .addOutgoing(
                        ChatMessage(
                          text: '!ping',
                          timestamp: ts,
                          isOutgoing: true,
                          channelIndex: widget.channelIndex,
                        ),
                      );
                  service.sendChannelMessage(
                    widget.channelIndex,
                    '!ping',
                    timestamp: ts,
                  );
                  _scrollToBottom();
                },
                icon: const Icon(Icons.wifi_tethering),
                label: Text(context.l10n.chatPingButton),
              ),
            ),
          )
        else
          _ChatInputBar(
            controller: _textController,
            onSend: _sendMessage,
            hintText: context.l10n.chatInputHint,
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
/// - count == 0, within 10 s of first render: amber pill "A propagar..."
/// - count == 0, 10 s elapsed with no repeater heard: blue pill "Enviada"
/// - count  > 0: green pill with a broadcast icon + count
class _HeardBadge extends StatefulWidget {
  const _HeardBadge({
    required this.count,
    required this.theme,
    required this.confirmed,
  });

  final int count;
  final ThemeData theme;
  final bool confirmed; // kept for potential future use

  @override
  State<_HeardBadge> createState() => _HeardBadgeState();
}

class _HeardBadgeState extends State<_HeardBadge> {
  Timer? _timer;
  bool _timedOut = false;

  @override
  void initState() {
    super.initState();
    // Start the timer immediately — if no repeater is heard within 10 s,
    // we show "Enviada". The radio does not always send SendConfirmedPush
    // for channel messages so we cannot gate this on widget.confirmed.
    if (widget.count == 0) {
      _timer = Timer(const Duration(seconds: 10), () {
        if (mounted) setState(() => _timedOut = true);
      });
    }
  }

  @override
  void didUpdateWidget(_HeardBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A repeater was heard — timer no longer needed.
    if (widget.count > 0) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final heard = widget.count > 0;
    final showSent = !heard && _timedOut;
    final bgColor =
        heard
            ? Colors.green.shade700.withAlpha(200)
            : showSent
            ? Colors.blue.shade700.withAlpha(200)
            : Colors.amber.shade800.withAlpha(180);
    const fgColor = Colors.white;
    final icon =
        heard
            ? Icons.cell_tower
            : showSent
            ? Icons.check_circle_outline
            : Icons.hourglass_empty;
    final label =
        heard
            ? '${widget.count} Repetidor${widget.count > 1 ? 'es' : ''}'
            : showSent
            ? context.l10n.commonSent
            : context.l10n.commonPropagating;

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
                style: (widget.theme.textTheme.labelSmall ?? const TextStyle())
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

/// Renders text with `@[name]` mentions and `#hashtag` channel links as pill chips.
///
/// - `@[name]` pills: tinted by [selfMentionColor]/[otherMentionColor].
/// - `#hashtag` pills: tinted by the theme secondary color; tappable when
///   [onHashtagTap] is provided.
Future<void> _launchUrl(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  if (!context.mounted) return;
  final confirmed = await showDialog<bool>(
    context: context,
    builder:
        (ctx) => AlertDialog(
          title: Text(ctx.l10n.urlOpenTitle),
          content: Text(
            url,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ctx.l10n.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(ctx.l10n.urlOpenConfirm),
            ),
          ],
        ),
  );
  if (confirmed == true) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

Widget _buildMentionText(
  BuildContext context,
  String text,
  ThemeData theme,
  TextStyle? style, {
  String? selfName,
  Color? selfMentionColor,
  Color? otherMentionColor,
  void Function(String channelName)? onHashtagTap,
  bool showMeshcoreResultButton = false,
}) {
  text = _sanitizeUtf16(text);

  // Extract a meshcore.pt/p/ URL before building inline spans so it can be
  // rendered as a full-width button below the text instead of inline.
  String? meshcoreResultUrl;
  if (showMeshcoreResultButton) {
    final meshcorePattern = RegExp(r'https?://[^\s]*meshcore\.pt/p/[^\s]*');
    final m = meshcorePattern.firstMatch(text);
    if (m != null) {
      meshcoreResultUrl = m.group(0)!;
      // Remove the URL (and any trailing/leading whitespace around it) from text.
      text = text.replaceFirst(meshcorePattern, '').trim();
      // Also strip the leading @[selfName] reply pill since the button makes
      // it clear who the message is addressed to.
      text = text.replaceFirst(RegExp(r'^@\[[^\]]+\]\s*'), '').trim();
    }
  }

  // Combined: @[mention] OR #hashtag OR https?:// URL.
  final pattern = RegExp(
    r'@\[([^\]]+)\]|#([A-Za-z][A-Za-z0-9_]*)|((https?://)[^\s]+)',
  );
  final matches = pattern.allMatches(text).toList();

  Widget textWidget =
      matches.isEmpty
          ? Text(text, style: style)
          : () {
            final spans = <InlineSpan>[];
            var cursor = 0;

            for (final match in matches) {
              if (match.start > cursor) {
                spans.add(
                  TextSpan(
                    text: text.substring(cursor, match.start),
                    style: style,
                  ),
                );
              }

              if (match.group(1) != null) {
                // ── @[mention] pill ────────────────────────────────────────────
                final name = match.group(1)!;
                final isSelf =
                    selfName != null &&
                    name.trim().toLowerCase() == selfName.trim().toLowerCase();
                final pillColor =
                    isSelf
                        ? (selfMentionColor ?? theme.colorScheme.tertiary)
                        : (otherMentionColor ?? theme.colorScheme.primary);
                final textColor = _pillTextColor(pillColor);
                spans.add(
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: pillColor,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '@$name',
                        style: (theme.textTheme.labelSmall ?? const TextStyle())
                            .copyWith(
                              color: textColor,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ),
                  ),
                );
              } else if (match.group(2) != null) {
                // ── #hashtag pill ──────────────────────────────────────────────
                final tag = match.group(2)!;
                final pillColor = theme.colorScheme.secondary;
                final textColor = _pillTextColor(pillColor);
                spans.add(
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: GestureDetector(
                      onTap:
                          onHashtagTap != null ? () => onHashtagTap(tag) : null,
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: pillColor,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '#$tag',
                          style: (theme.textTheme.labelSmall ??
                                  const TextStyle())
                              .copyWith(
                                color: textColor,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ),
                    ),
                  ),
                );
              } else if (match.group(3) != null) {
                // ── https:// URL ───────────────────────────────────────────────
                final url = match.group(3)!;
                spans.add(
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: GestureDetector(
                      onTap: () => _launchUrl(context, url),
                      child: Text(
                        url,
                        style: (style ?? const TextStyle()).copyWith(
                          color: Colors.lightBlue,
                          decoration: TextDecoration.underline,
                          decorationColor: Colors.lightBlue,
                        ),
                      ),
                    ),
                  ),
                );
              }
              cursor = match.end;
            }

            if (cursor < text.length) {
              spans.add(TextSpan(text: text.substring(cursor), style: style));
            }
            return Text.rich(TextSpan(children: spans));
          }();

  if (meshcoreResultUrl == null) return textWidget;

  final resultUrl = meshcoreResultUrl;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      if (text.isNotEmpty) textWidget,
      const SizedBox(height: 6),
      ElevatedButton.icon(
        onPressed: () => _launchUrl(context, resultUrl),
        icon: const Icon(Icons.open_in_browser, size: 14),
        label: Text(context.l10n.chatViewResultOnline),
        style: ElevatedButton.styleFrom(
          textStyle: const TextStyle(fontSize: 12),
        ),
      ),
    ],
  );
}

/// Horizontal divider shown between the last-read message and the first unread.
/// Dismissed automatically when the user scrolls to the bottom, or tapped.
class _UnreadDivider extends StatelessWidget {
  const _UnreadDivider({super.key, required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(child: Divider(color: color.withAlpha(160), thickness: 1)),
          GestureDetector(
            onTap: onDismiss,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: color.withAlpha(30),
                border: Border.all(color: color.withAlpha(120)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.mark_chat_unread_outlined, size: 14, color: color),
                  const SizedBox(width: 4),
                  Text(
                    context.l10n.chatNewMessages,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.close, size: 12, color: color.withAlpha(160)),
                ],
              ),
            ),
          ),
          Expanded(child: Divider(color: color.withAlpha(160), thickness: 1)),
        ],
      ),
    );
  }
}

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
// Message paths sheet
// ---------------------------------------------------------------------------

/// Bottom sheet showing per-path reception details for an outgoing channel
/// message.  Requires [packetHeardProvider] data to be present (in-session
/// 0x88 frames only — data is not persisted across restarts).
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
