import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../protocol/protocol.dart';
import '../../providers/radio_providers.dart';
import '../theme.dart';

/// Human-readable path label for a contact's out_path_len value.
/// The byte uses the same 2-bit/6-bit encoding as packet path_len:
///   upper 2 bits = hash-size encoding, lower 6 bits = actual hop count.
/// 0xFF = no known path (flood routing), hops==0 = direct, else N hops.
String contactPathLabel(int pathLen) {
  if (pathLen == 0xFF) return 'Flood';
  final hops = pathLen & 0x3F; // lower 6 bits = hop count
  if (hops == 0) return 'Direto';
  return '$hops salto${hops == 1 ? '' : 's'}';
}

/// Full path-management bottom sheet.
/// Shared between the contacts tab (long-press → Gerir caminho) and the
/// private chat header (⋮ → Gerir caminho).
class ContactPathSheet extends ConsumerStatefulWidget {
  const ContactPathSheet({super.key, required this.contact});

  final Contact contact;

  @override
  ConsumerState<ContactPathSheet> createState() => _ContactPathSheetState();
}

class _ContactPathSheetState extends ConsumerState<ContactPathSheet> {
  bool _resetting = false;
  bool _discovering = false;
  String? _statusMessage;
  bool _statusIsError = false;

  Future<void> _resetPath() async {
    final service = ref.read(radioServiceProvider);
    if (service == null) return;

    setState(() {
      _resetting = true;
      _statusMessage = null;
    });

    final completer = Completer<String?>(); // null = success
    late StreamSubscription<CompanionResponse> sub;
    sub = service.responses.listen((r) {
      if (completer.isCompleted) return;
      if (r is OkResponse) {
        completer.complete(null);
      } else if (r is ErrorResponse) {
        final msg =
            r.errorCode == 2
                ? 'Contacto não encontrado no rádio'
                : 'Erro do rádio (código ${r.errorCode})';
        completer.complete(msg);
      }
    });

    await service.resetPath(widget.contact.publicKey);

    final error = await completer.future
        .timeout(
          const Duration(seconds: 8),
          onTimeout: () => 'Sem resposta do rádio (timeout)',
        )
        .whenComplete(sub.cancel);

    if (!mounted) return;
    if (error == null) {
      await service.requestContacts();
      setState(() {
        _resetting = false;
        _statusMessage =
            'Caminho reiniciado — rádio usará flood na próxima mensagem';
        _statusIsError = false;
      });
    } else {
      setState(() {
        _resetting = false;
        _statusMessage = error;
        _statusIsError = true;
      });
    }
  }

  Future<void> _discoverPath() async {
    final service = ref.read(radioServiceProvider);
    if (service == null) return;

    setState(() {
      _discovering = true;
      _statusMessage = null;
    });

    final pubKeyPrefix = widget.contact.publicKey.sublist(0, 6);

    final completer = Completer<String?>();
    late StreamSubscription<CompanionResponse> sub;
    sub = service.responses.listen((r) {
      if (completer.isCompleted) return;
      if (r is PathDiscoveryPush) {
        if (r.pubKeyPrefix.length >= 6 &&
            pubKeyPrefix.length >= 6 &&
            List.generate(
              6,
              (i) => r.pubKeyPrefix[i] == pubKeyPrefix[i],
            ).every((e) => e)) {
          final out = r.outPath.length;
          final inn = r.inPath.length;
          completer.complete(
            'Caminho descoberto: $out salto${out == 1 ? '' : 's'} (saída)  /  '
            '$inn salto${inn == 1 ? '' : 's'} (entrada)',
          );
        }
      } else if (r is ErrorResponse) {
        final msg =
            r.errorCode == 2
                ? 'Contacto não encontrado no rádio'
                : 'Erro do rádio (código ${r.errorCode})';
        completer.complete('__error__$msg');
      }
    });

    await service.sendPathDiscovery(widget.contact.publicKey);

    final result = await completer.future
        .timeout(
          const Duration(seconds: 30),
          onTimeout: () => '__error__Sem resposta (timeout de 30 s)',
        )
        .whenComplete(sub.cancel);

    if (!mounted) return;

    final isError = result?.startsWith('__error__') ?? false;
    final message =
        isError ? result!.substring('__error__'.length) : result ?? '';

    if (!isError) {
      await service.requestContacts();
    }

    setState(() {
      _discovering = false;
      _statusMessage = message;
      _statusIsError = isError;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final contact = widget.contact;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final pathLabelStr = contactPathLabel(contact.pathLen);

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withAlpha(40),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.route, color: AppTheme.primary, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Caminho: ${contact.displayName}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'ID: ${contact.shortId}  |  Caminho atual: $pathLabelStr',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const Divider(height: 20),

          // Reset path
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.refresh),
            title: const Text('Reiniciar caminho'),
            subtitle: const Text(
              'Apaga o caminho guardado — o rádio voltará a usar flood na próxima transmissão.',
            ),
            trailing:
                _resetting
                    ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : null,
          ),
          FilledButton.tonalIcon(
            onPressed: (_resetting || _discovering) ? null : _resetPath,
            icon: const Icon(Icons.restart_alt),
            label: const Text('Reiniciar caminho'),
          ),
          const SizedBox(height: 12),

          // Discover path
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.search),
            title: const Text('Descobrir caminho'),
            subtitle: const Text(
              'Envia uma sondagem flood para encontrar o melhor caminho até este nó (pode demorar até 30 s).',
            ),
            trailing:
                _discovering
                    ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : null,
          ),
          FilledButton.icon(
            onPressed: (_resetting || _discovering) ? null : _discoverPath,
            icon: const Icon(Icons.route),
            label: const Text('Descobrir caminho'),
          ),
          const SizedBox(height: 12),

          // Status message
          if (_statusMessage != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color:
                    _statusIsError
                        ? theme.colorScheme.errorContainer
                        : theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _statusMessage!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color:
                      _statusIsError
                          ? theme.colorScheme.onErrorContainer
                          : theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
