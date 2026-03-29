import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../protocol/protocol.dart';
import '../../providers/radio_providers.dart';
import '../theme.dart';

// ---------------------------------------------------------------------------
// Room screen — login gate + chat
// ---------------------------------------------------------------------------

/// Entry point for a MeshCore room server.  Shows a join form first;
/// after a successful [LoginSuccessPush] switches to the chat view.
class RoomScreen extends ConsumerStatefulWidget {
  const RoomScreen({super.key, required this.contactKeyHex});

  /// Full 64-hex-char public key of the room contact.
  final String contactKeyHex;

  @override
  ConsumerState<RoomScreen> createState() => _RoomScreenState();
}

enum _JoinState { idle, joining, joined, failed }

class _RoomScreenState extends ConsumerState<RoomScreen> {
  final _passCtrl = TextEditingController();
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  _JoinState _joinState = _JoinState.idle;
  bool _obscurePass = true;
  ChatMessage? _replyingTo;

  // ---------------------------------------------------------------------------
  // Key helpers
  // ---------------------------------------------------------------------------

  Uint8List get _contactKey {
    final hex = widget.contactKeyHex;
    final bytes = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return Uint8List.fromList(bytes);
  }

  /// First 12 hex chars = first 6 bytes — matches [ChatMessage.senderKey].
  String get _prefix6Hex {
    final hex = widget.contactKeyHex;
    return hex.length >= 12 ? hex.substring(0, 12) : hex;
  }

  Uint8List get _keyPrefix6 {
    final key = _contactKey;
    return key.sublist(0, 6.clamp(0, key.length));
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

  bool _prefixMatch(Uint8List a, Uint8List b) {
    final len = a.length < b.length ? a.length : b.length;
    if (len < 4) return false;
    for (var i = 0; i < len && i < 6; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Clear any stale login result from a previous attempt.
      ref.read(loginResultProvider.notifier).state = null;
      // Pre-load persisted messages so they appear immediately after joining.
      ref.read(messagesProvider.notifier).ensureLoadedForContact(_prefix6Hex);
    });
  }

  @override
  void dispose() {
    _passCtrl.dispose();
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _joinRoom() async {
    final service = ref.read(radioServiceProvider);
    if (service == null) return;
    ref.read(loginResultProvider.notifier).state = null;
    setState(() => _joinState = _JoinState.joining);
    await service.login(_contactKey, _passCtrl.text);
  }

  void _sendMessage() {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    final service = ref.read(radioServiceProvider);
    if (service == null) return;

    final replyContact =
        _replyingTo != null ? _findContact(ref.read(contactsProvider)) : null;
    final replyPrefix =
        _replyingTo != null ? '[@${replyContact?.displayName ?? 'Sala'}] ' : '';
    final fullText = '$replyPrefix$text';

    service.sendPrivateMessage(_keyPrefix6, fullText);
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
    _textCtrl.clear();
    if (_replyingTo != null) setState(() => _replyingTo = null);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // React to login result pushes from the radio.
    ref.listen<bool?>(loginResultProvider, (_, result) {
      if (result == null || !mounted) return;
      setState(
        () => _joinState = result ? _JoinState.joined : _JoinState.failed,
      );
      if (result) {
        ref.read(unreadCountsProvider.notifier).markContactRead(_prefix6Hex);
      }
    });

    // While in chat, clear unread and scroll to bottom on new messages.
    ref.listen<List<ChatMessage>>(messagesProvider, (prev, next) {
      if (_joinState == _JoinState.joined) {
        ref.read(unreadCountsProvider.notifier).markContactRead(_prefix6Hex);
        if (prev != null && next.length > prev.length) _scrollToBottom();
      }
    });

    final contacts = ref.watch(contactsProvider);
    final contact = _findContact(contacts);
    final theme = Theme.of(context);
    final allMessages = ref.watch(messagesProvider);

    final roomMessages =
        allMessages.where((m) {
          if (m.isChannel) return false;
          if (m.senderKey == null) return false;
          return _prefixMatch(m.senderKey!, _contactKey);
        }).toList();

    return Column(
      children: [
        // Room header
        _RoomHeader(contact: contact, theme: theme),

        // Body: join form or chat
        Expanded(
          child:
              _joinState == _JoinState.joined
                  ? _ChatBody(
                    messages: roomMessages,
                    scrollController: _scrollCtrl,
                    contact: contact,
                    onSetReply: (msg) => setState(() => _replyingTo = msg),
                  )
                  : _JoinBody(
                    contact: contact,
                    joinState: _joinState,
                    passCtrl: _passCtrl,
                    obscurePass: _obscurePass,
                    onToggleObscure:
                        () => setState(() => _obscurePass = !_obscurePass),
                    onJoin: _joinRoom,
                    theme: theme,
                  ),
        ),

        // Input bar — only shown when joined
        if (_joinState == _JoinState.joined)
          _ChatInputBar(
            controller: _textCtrl,
            onSend: _sendMessage,
            hintText: 'Mensagem para ${contact?.displayName ?? 'sala'}...',
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

// ---------------------------------------------------------------------------
// Room header
// ---------------------------------------------------------------------------

class _RoomHeader extends StatelessWidget {
  const _RoomHeader({required this.contact, required this.theme});

  final Contact? contact;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.purple.withAlpha(40),
            child: const Icon(
              Icons.meeting_room,
              color: Colors.purple,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  contact?.displayName ?? 'Sala',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (contact != null)
                  Text(
                    'Sala  •  ID: ${contact!.shortId}  •  Saltos: ${contact!.pathLen}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withAlpha(120),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Join body
// ---------------------------------------------------------------------------

class _JoinBody extends StatelessWidget {
  const _JoinBody({
    required this.contact,
    required this.joinState,
    required this.passCtrl,
    required this.obscurePass,
    required this.onToggleObscure,
    required this.onJoin,
    required this.theme,
  });

  final Contact? contact;
  final _JoinState joinState;
  final TextEditingController passCtrl;
  final bool obscurePass;
  final VoidCallback onToggleObscure;
  final VoidCallback onJoin;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final joining = joinState == _JoinState.joining;
    final failed = joinState == _JoinState.failed;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 24),
          Icon(
            Icons.meeting_room_outlined,
            size: 72,
            color: AppTheme.primary.withAlpha(180),
          ),
          const SizedBox(height: 20),
          Text(
            contact != null
                ? 'Entrar em "${contact!.displayName}"'
                : 'Entrar na sala',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Esta sala pode requerer uma palavra-passe. '
            'Deixe em branco se for pública.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withAlpha(160),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          TextField(
            controller: passCtrl,
            obscureText: obscurePass,
            decoration: InputDecoration(
              labelText: 'Palavra-passe (opcional)',
              hintText: 'Deixar em branco se sem palavra-passe',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.lock_outline),
              errorText: failed ? 'Falhou — verifique a palavra-passe' : null,
              suffixIcon: IconButton(
                icon: Icon(
                  obscurePass ? Icons.visibility : Icons.visibility_off,
                ),
                onPressed: onToggleObscure,
              ),
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => joining ? null : onJoin(),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: joining ? null : onJoin,
            icon:
                joining
                    ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Icon(Icons.login),
            label: Text(joining ? 'A ligar...' : 'Entrar na sala'),
          ),
          if (failed) ...[
            const SizedBox(height: 12),
            Text(
              'Não foi possível entrar na sala. '
              'Verifique a palavra-passe e tente novamente.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Chat body (shown after successful join)
// ---------------------------------------------------------------------------

class _ChatBody extends StatelessWidget {
  const _ChatBody({
    required this.messages,
    required this.scrollController,
    required this.contact,
    required this.onSetReply,
  });

  final List<ChatMessage> messages;
  final ScrollController scrollController;
  final Contact? contact;
  final ValueChanged<ChatMessage> onSetReply;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (messages.isEmpty) {
      return Center(
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
      );
    }

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.all(8),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final msg = messages[index];
        return _RoomMessageBubble(
          message: msg,
          onReply: msg.isOutgoing ? null : () => onSetReply(msg),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Message bubble
// ---------------------------------------------------------------------------

class _RoomMessageBubble extends StatelessWidget {
  const _RoomMessageBubble({required this.message, this.onReply});

  final ChatMessage message;
  final VoidCallback? onReply;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMe = message.isOutgoing;
    final time = DateTime.fromMillisecondsSinceEpoch(message.timestamp * 1000);
    final timeStr =
        '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';

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
            if (!isMe)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  '[${message.senderName ?? 'Sala'}]',
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
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );

    if (!isMe && onReply != null) {
      return _SwipeToReply(onReply: onReply!, child: bubble);
    }
    return bubble;
  }
}

// ---------------------------------------------------------------------------
// Swipe-to-reply wrapper (inline, avoids cross-file dependency)
// ---------------------------------------------------------------------------

class _SwipeToReply extends StatefulWidget {
  const _SwipeToReply({required this.child, required this.onReply});
  final Widget child;
  final VoidCallback onReply;

  @override
  State<_SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<_SwipeToReply> {
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

// ---------------------------------------------------------------------------
// Input bar
// ---------------------------------------------------------------------------

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
// Reply strip
// ---------------------------------------------------------------------------

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
        message.isOutgoing ? '[@Você]' : '[@${message.senderName ?? 'Sala'}]';
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
