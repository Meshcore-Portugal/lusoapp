import 'package:flutter/material.dart';

/// A labelled text-input row with optional Refresh and Apply icons.
///
/// Used in the Repeater Settings tab to expose a single CLI config field.
class RepeaterConfigRow extends StatelessWidget {
  const RepeaterConfigRow({
    super.key,
    required this.label,
    required this.controller,
    required this.enabled,
    required this.onApply,
    this.sublabel,
    this.hint,
    this.suffix,
    this.keyboardType,
    this.loading = false,
    this.showRefresh = false,
    this.onRefresh,
  });

  final String label;
  final String? sublabel;
  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onApply;
  final String? hint;
  final String? suffix;
  final TextInputType? keyboardType;
  final bool loading;
  final bool showRefresh;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (showRefresh)
              IconButton(
                tooltip: 'Refresh',
                icon:
                    loading
                        ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Icon(Icons.refresh, size: 20),
                onPressed: enabled && !loading ? onRefresh : null,
              ),
            IconButton(
              tooltip: 'Apply',
              icon: const Icon(Icons.check, size: 20),
              onPressed: enabled && !loading ? onApply : null,
            ),
          ],
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          enabled: enabled && !loading,
          onSubmitted: enabled && !loading ? (_) => onApply() : null,
          decoration: InputDecoration(
            labelText: sublabel ?? hint,
            hintText: hint,
            suffixText: suffix,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ],
    );
  }
}
