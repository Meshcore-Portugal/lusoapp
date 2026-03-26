import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
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
    final prefix =
        _contactKey.length >= 6 ? _contactKey.sublist(0, 6) : _contactKey;
    service.sendPrivateMessage(prefix, text);

    // Add outgoing message to local state
    ref
        .read(messagesProvider.notifier)
        .addOutgoing(
          ChatMessage(
            text: text,
            timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            isOutgoing: true,
            senderKey: _contactKey,
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

  // First 12 hex chars = first 6 bytes of the key — matches incoming senderKey.
  String get _prefix6Hex {
    final hex = widget.contactKeyHex;
    return hex.length >= 12 ? hex.substring(0, 12) : hex;
  }

  @override
  void initState() {
    super.initState();
    // Mark contact as read when this screen is opened.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(unreadCountsProvider.notifier).markContactRead(_prefix6Hex);
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
    // whenever new messages arrive.
    ref.listen<List<ChatMessage>>(messagesProvider, (_, __) {
      ref.read(unreadCountsProvider.notifier).markContactRead(_prefix6Hex);
    });

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
                      contact?.name ?? 'Contacto',
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
                      service.tracePath(contact.publicKey);
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
          child:
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
                      return _PrivateMessageBubble(message: msg);
                    },
                  ),
        ),

        // Input bar
        _ChatInputBar(
          controller: _textController,
          onSend: _sendMessage,
          hintText: 'Mensagem para ${contact?.name ?? "contacto"}...',
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
}

class _PrivateMessageBubble extends StatelessWidget {
  const _PrivateMessageBubble({required this.message});
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
                if (isMe && message.confirmed) ...[
                  const SizedBox(width: 4),
                  Icon(
                    Icons.done_all,
                    size: 14,
                    color: theme.colorScheme.primary,
                  ),
                ],
              ],
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
