import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/radio_providers.dart';
import '../../transport/radio_transport.dart';

/// App settings screen.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selfInfo = ref.watch(selfInfoProvider);
    final connectionState = ref.watch(connectionProvider);
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Identity
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.badge, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Identidade',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    title: const Text('Nome do No'),
                    subtitle: Text(selfInfo?.name ?? 'Nao conectado'),
                    trailing: const Icon(Icons.edit),
                    onTap: () => _editName(context, ref),
                  ),
                  if (selfInfo != null)
                    ListTile(
                      title: const Text('Chave Publica'),
                      subtitle: Text(
                        selfInfo.publicKey
                            .map((b) => b.toRadixString(16).padLeft(2, '0'))
                            .join(),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Connection
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.link, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Ligacao',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    title: const Text('Estado'),
                    subtitle: Text(_connectionStateText(connectionState)),
                    leading: Icon(
                      connectionState == TransportState.connected
                          ? Icons.check_circle
                          : Icons.cancel,
                      color: connectionState == TransportState.connected
                          ? Colors.green
                          : Colors.red,
                    ),
                  ),
                  if (connectionState == TransportState.connected)
                    ListTile(
                      title: const Text('Desligar'),
                      subtitle: const Text('Terminar ligacao ao radio'),
                      leading: const Icon(Icons.link_off),
                      onTap: () async {
                        await ref.read(connectionProvider.notifier).disconnect();
                        if (context.mounted) {
                          context.go('/connect');
                        }
                      },
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // About
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Sobre',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const ListTile(
                    title: Text('MeshCore PT'),
                    subtitle: Text('v0.1.0 - Comunidade Portuguesa MeshCore'),
                  ),
                  const ListTile(
                    title: Text('Protocolo'),
                    subtitle: Text('Companion Radio Protocol v3'),
                  ),
                  const ListTile(
                    title: Text('Licenca'),
                    subtitle: Text('MIT'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _connectionStateText(TransportState state) {
    switch (state) {
      case TransportState.connected:
        return 'Ligado';
      case TransportState.connecting:
        return 'A ligar...';
      case TransportState.scanning:
        return 'A procurar...';
      case TransportState.error:
        return 'Erro de ligacao';
      case TransportState.disconnected:
        return 'Desligado';
    }
  }

  void _editName(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController(
      text: ref.read(selfInfoProvider)?.name ?? '',
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Alterar Nome'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Nome do no',
            hintText: 'Ex: CT1XXX-MC',
          ),
          maxLength: 32,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                ref.read(radioServiceProvider)?.setAdvertName(name);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }
}
