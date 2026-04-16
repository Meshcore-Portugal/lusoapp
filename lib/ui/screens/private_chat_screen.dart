import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../protocol/protocol.dart';
import '../../providers/radio_providers.dart';
import '../widgets/path_sheet.dart';

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
  Timer? _traceTimeout;
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
    _traceTimeout?.cancel();
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
      _traceTimeout?.cancel();
      _traceTimeout = null;
      setState(() => _waitingForTrace = false);
      _showTraceSheet(next);
    });

    final selfName = ref.watch(selfInfoProvider)?.name;
    final selfMentionColor = ref.watch(selfMentionColorProvider);
    final otherMentionColor = ref.watch(otherMentionColorProvider);
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
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
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
                            GestureDetector(
                              onTap:
                                  () => showModalBottomSheet<void>(
                                    context: context,
                                    isScrollControlled: true,
                                    builder:
                                        (_) =>
                                            ContactPathSheet(contact: contact),
                                  ),
                              child: _ContactPathSubtitle(
                                contact: contact,
                                theme: theme,
                              ),
                            ),
                        ],
                      ),
                    ),
                    // Actions
                    PopupMenuButton<String>(
                      onSelected: (value) {
                        if (contact == null) return;
                        switch (value) {
                          case 'trace':
                            _doTrace(contact);
                          case 'path':
                            showModalBottomSheet<void>(
                              context: context,
                              isScrollControlled: true,
                              builder:
                                  (_) => ContactPathSheet(contact: contact),
                            );
                        }
                      },
                      itemBuilder:
                          (_) => [
                            PopupMenuItem(
                              value: 'trace',
                              child: ListTile(
                                leading: const Icon(Icons.route),
                                title: Text(context.l10n.privateTraceRoute),
                                dense: true,
                              ),
                            ),
                            PopupMenuItem(
                              value: 'path',
                              child: ListTile(
                                leading: const Icon(Icons.alt_route),
                                title: Text(context.l10n.privateManagePath),
                                dense: true,
                              ),
                            ),
                          ],
                    ),
                  ],
                ),
              ),
              // Trace-in-progress banner — visible in the header itself
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                child:
                    _waitingForTrace
                        ? _TracingBanner(
                          contactName: contact?.displayName ?? 'contacto',
                          onCancel: () {
                            _traceTimeout?.cancel();
                            setState(() => _waitingForTrace = false);
                          },
                          theme: theme,
                        )
                        : const SizedBox.shrink(),
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
                          context.l10n.privateNoMessages,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.onSurface.withAlpha(120),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          context.l10n.privateSendFirstMessage,
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
                        selfMentionColor: selfMentionColor,
                        otherMentionColor: otherMentionColor,
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
          hintText: context.l10n.privateMessageTo(
            contact?.name ?? context.l10n.commonContact,
          ),
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

  bool _prefixMatch6(Uint8List a, Uint8List b) {
    if (a.length < 6 || b.length < 6) return false;
    for (var i = 0; i < 6; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Convert a `List<int>` of uint32-LE values (as decoded from PathDiscoveryPush)
  /// back into the raw byte sequence the firmware expects as path bytes.
  Uint8List _outPathToBytes(List<int> outPath) {
    final bytes = Uint8List(outPath.length * 4);
    var i = 0;
    for (final val in outPath) {
      bytes[i++] = val & 0xFF;
      bytes[i++] = (val >> 8) & 0xFF;
      bytes[i++] = (val >> 16) & 0xFF;
      bytes[i++] = (val >> 24) & 0xFF;
    }
    return bytes;
  }

  /// Full trace flow:
  ///  1. Check path cache — if hit, send trace immediately.
  ///  2. Cache miss — run path discovery (CMD_SEND_PATH_DISCOVERY_REQ 0x34),
  ///     wait for PathDiscoveryPush (0x8D), then send trace with discovered path.
  ///  3. On any timeout or missing path → snackbar + cancel spinner.
  Future<void> _doTrace(Contact contact) async {
    final service = ref.read(radioServiceProvider);
    if (service == null) return;

    _traceTimeout?.cancel();
    setState(() => _waitingForTrace = true);

    Uint8List? pathBytes;

    final cached = ref.read(pathCacheProvider)[_prefix6Hex];
    if (cached != null && cached.isNotEmpty) {
      pathBytes = _outPathToBytes(cached);
    } else {
      // Discover the path first — firmware needs hop-hash bytes, not the public key.
      final pubKeyPrefix = contact.publicKey.sublist(0, 6);
      final completer = Completer<List<int>?>();
      late StreamSubscription<CompanionResponse> sub;
      sub = service.responses.listen((r) {
        if (completer.isCompleted) return;
        if (r is PathDiscoveryPush &&
            _prefixMatch6(r.pubKeyPrefix, pubKeyPrefix)) {
          completer.complete(r.outPath);
        }
      });

      await service.sendPathDiscovery(contact.publicKey);

      final outPath = await completer.future
          .timeout(const Duration(seconds: 15), onTimeout: () => null)
          .whenComplete(sub.cancel);

      if (outPath != null && outPath.isNotEmpty) {
        pathBytes = _outPathToBytes(outPath);
      }
    }

    if (!mounted || !_waitingForTrace) return;

    if (pathBytes == null) {
      setState(() => _waitingForTrace = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.privateRouteFailed),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    // Send trace with correct hop-hash path bytes.
    await service.tracePath(Random().nextInt(0x7FFFFFFF), path: pathBytes);

    // Arm timeout for the trace-data response (PUSH_CODE_TRACE_DATA 0x89).
    _traceTimeout = Timer(const Duration(seconds: 15), () {
      if (mounted && _waitingForTrace) {
        setState(() => _waitingForTrace = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.privateRouteNoResponse),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    });
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
    this.selfMentionColor,
    this.otherMentionColor,
  });
  final ChatMessage message;
  final VoidCallback? onReply;
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
                      icon: msg.confirmed ? Icons.done_all : Icons.done,
                      label: 'Estado',
                      value: msg.confirmed ? 'Confirmado' : 'Pendente',
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
// Tracing banner — shown inside the header while waiting for a trace reply
// ---------------------------------------------------------------------------

class _TracingBanner extends StatelessWidget {
  const _TracingBanner({
    required this.contactName,
    required this.onCancel,
    required this.theme,
  });

  final String contactName;
  final VoidCallback onCancel;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withAlpha(180),
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.primary.withAlpha(60),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'A traçar rota para $contactName...',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          TextButton(
            onPressed: onCancel,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'Cancelar',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Contact path subtitle — shown under the name in the chat header
// ---------------------------------------------------------------------------

/// Compact one-line subtitle combining contact type, shortId, and route info.
/// Route uses `pathLen`: 0 = Direct, 0xFF = Flood, N = N hops.
class _ContactPathSubtitle extends StatelessWidget {
  const _ContactPathSubtitle({required this.contact, required this.theme});

  final Contact contact;
  final ThemeData theme;

  static String _typeName(int type) {
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

  static (String label, IconData icon, Color? color) _routeInfo(
    int pathLen,
    ThemeData theme,
  ) {
    if (pathLen == 0xFF) {
      return ('Flood', Icons.waves, theme.colorScheme.onSurfaceVariant);
    }
    if (pathLen == 0) {
      return ('Direto', Icons.arrow_forward, Colors.green.shade600);
    }
    final hops = pathLen & 0x3F;
    return (
      '$hops salto${hops > 1 ? 's' : ''}',
      Icons.route,
      theme.colorScheme.secondary,
    );
  }

  @override
  Widget build(BuildContext context) {
    final (routeLabel, routeIcon, routeColor) = _routeInfo(
      contact.pathLen,
      theme,
    );
    final dimColor = theme.colorScheme.onSurface.withAlpha(120);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${_typeName(contact.type)} · ${contact.shortId}',
          style: theme.textTheme.bodySmall?.copyWith(color: dimColor),
        ),
        const SizedBox(width: 6),
        Container(width: 1, height: 10, color: dimColor.withAlpha(80)),
        const SizedBox(width: 6),
        Icon(routeIcon, size: 11, color: routeColor),
        const SizedBox(width: 3),
        Text(
          routeLabel,
          style: theme.textTheme.bodySmall?.copyWith(
            color: routeColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
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
            title: Text(context.l10n.privateReceivedOnRadio),
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
