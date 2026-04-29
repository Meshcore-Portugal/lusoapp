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
import '../widgets/canned_message_picker.dart';

part 'parts/channel_message_bubble.dart';
part 'parts/channel_paths_sheet.dart';

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
          final msgs = ref
              .read(messagesProvider.notifier)
              .forChannel(widget.channelIndex);
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
          final msgs = ref
              .read(messagesProvider.notifier)
              .forChannel(widget.channelIndex);
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
          final msgs = ref
              .read(messagesProvider.notifier)
              .forChannel(widget.channelIndex);
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
    // Watch ONLY this channel's message version — rebuild only when a message
    // arrives for this specific channel, not on every message app-wide.
    ref.watch(
      messageVersionsProvider.select(
        (vs) => vs['ch_${widget.channelIndex}'] ?? 0,
      ),
    );
    // When the version ticks up, mark read and tail-scroll.
    ref.listen<int>(
      messageVersionsProvider.select(
        (vs) => vs['ch_${widget.channelIndex}'] ?? 0,
      ),
      (prev, next) {
        if (prev != null && next > prev) {
          ref
              .read(unreadCountsProvider.notifier)
              .markChannelRead(widget.channelIndex);
          if (_atBottom) _scrollToBottom();
        }
      },
    );

    final selfName = ref.watch(selfInfoProvider)?.name;
    final selfMentionColor = ref.watch(selfMentionColorProvider);
    final otherMentionColor = ref.watch(otherMentionColorProvider);
    final channels = ref.watch(channelsProvider);
    // O(1) partition lookup — no filter scan over all messages (#7 perf fix).
    final channelMessages = ref
        .read(messagesProvider.notifier)
        .forChannel(widget.channelIndex);
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
                      CannedMessagePicker(
                        onPick: (text) {
                          widget.controller.text = text;
                          widget
                              .controller
                              .selection = TextSelection.fromPosition(
                            TextPosition(offset: text.length),
                          );
                        },
                      ),
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
