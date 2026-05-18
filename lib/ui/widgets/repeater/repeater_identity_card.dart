import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';
import '../../../protocol/models.dart';
import '../../theme.dart';
import '../path_sheet.dart' show contactPathLabel;

/// Header card showing the repeater's display name, short ID, path, and an
/// admin badge once the user has authenticated.
class RepeaterIdentityCard extends StatelessWidget {
  const RepeaterIdentityCard({
    super.key,
    required this.name,
    required this.contact,
    required this.loggedIn,
  });

  final String name;
  final Contact? contact;
  final bool loggedIn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.primary.withAlpha(30),
              ),
              child: const Icon(
                Icons.cell_tower,
                color: AppTheme.primary,
                size: 26,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (contact != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'ID: ${contact!.shortId}  ·  '
                      '${contactPathLabel(contact!.pathLen)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (loggedIn)
              Tooltip(
                message: l10n.repeaterAuthenticated,
                child: const Icon(
                  Icons.admin_panel_settings,
                  color: Colors.green,
                  size: 20,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
