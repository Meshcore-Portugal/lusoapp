import 'package:flutter/material.dart';

/// Bold section title used between cards in the Repeater screen.
class RepeaterSectionHeader extends StatelessWidget {
  const RepeaterSectionHeader({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
    );
  }
}

/// Compact outlined refresh button (e.g. "Refresh stats" on the Status tab).
class RepeaterRefreshButton extends StatelessWidget {
  const RepeaterRefreshButton({
    super.key,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: enabled ? onTap : null,
      icon: const Icon(Icons.refresh, size: 16),
      label: Text(label),
    );
  }
}
