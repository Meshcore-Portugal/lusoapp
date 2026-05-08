import 'package:flutter/material.dart';

/// A `ListTile` styled for the Repeater "Remote actions" section.
class RepeaterActionTile extends StatelessWidget {
  const RepeaterActionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(
        icon,
        size: 22,
        color:
            enabled
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurface.withAlpha(60),
      ),
      title: Text(
        title,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w500,
          color: enabled ? null : theme.colorScheme.onSurface.withAlpha(80),
        ),
      ),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      onTap: enabled ? onTap : null,
    );
  }
}
