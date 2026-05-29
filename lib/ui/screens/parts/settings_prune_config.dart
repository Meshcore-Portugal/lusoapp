part of '../settings_screen.dart';

/// Card that shows contact pruning configuration controls.
class _PruneConfigCard extends ConsumerStatefulWidget {
  const _PruneConfigCard();

  @override
  ConsumerState<_PruneConfigCard> createState() => _PruneConfigCardState();
}

class _PruneConfigCardState extends ConsumerState<_PruneConfigCard> {
  late TextEditingController _daysController;

  @override
  void initState() {
    super.initState();
    _daysController = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final config = ref.watch(pruneConfigProvider);
    _daysController.text = config.daysThreshold.toString();
  }

  @override
  void dispose() {
    _daysController.dispose();
    super.dispose();
  }

  void _updateDaysThreshold(String value) {
    final days = int.tryParse(value);
    if (days != null && days > 0) {
      ref.read(pruneConfigProvider.notifier).setDaysThreshold(days);
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(pruneConfigProvider);
    final notifier = ref.read(pruneConfigProvider.notifier);
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.delete_sweep, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Limpeza de Contactos',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Remove contactos inativos da memória da rádio',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 16),

            // Days threshold input
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Dias de Inatividade',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Contactos sem contacto > X dias serão removidos',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 80,
                    child: TextField(
                      controller: _daysController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 12,
                        ),
                        suffixText: 'dias',
                      ),
                      onChanged: _updateDaysThreshold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Contact type toggles
            Text(
              'Tipos de Contacto a Remover',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),

            // Chat toggle
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Chats / Pessoais'),
              subtitle: Text(
                'Remover contactos de chat (0x01)',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              value: config.pruneChats,
              onChanged: (v) => notifier.setPruneChats(v),
            ),

            // Repeater toggle
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Repetidores'),
              subtitle: Text(
                'Remover contactos de repetidor (0x02)',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              value: config.pruneRepeaters,
              onChanged: (v) => notifier.setPruneRepeaters(v),
            ),

            // Room toggle
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Salas'),
              subtitle: Text(
                'Remover contactos de sala (0x03)',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              value: config.pruneRooms,
              onChanged: (v) => notifier.setPruneRooms(v),
            ),

            // Sensor toggle
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Sensores'),
              subtitle: Text(
                'Remover contactos de sensor (0x04)',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              value: config.pruneSensors,
              onChanged: (v) => notifier.setPruneSensors(v),
            ),

            const SizedBox(height: 12),

            // Reset button
            Align(
              child: TextButton.icon(
                icon: const Icon(Icons.restart_alt),
                label: const Text('Restaurar Padrão'),
                onPressed: () => notifier.reset(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
