import 'package:flutter/material.dart';

/// A short "what is this / what it's for" banner shown under a tool's header.
class ToolDescription extends StatelessWidget {
  final IconData icon;
  final String text;
  const ToolDescription({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
