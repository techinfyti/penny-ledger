import 'package:flutter/material.dart';

class StatCard extends StatelessWidget {
  final String label;
  final double value;
  final String currencySymbol;
  final Color accentColor;
  final IconData icon;

  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.currencySymbol,
    required this.accentColor,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: accentColor, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(label, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$currencySymbol${value.toStringAsFixed(2)}',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: accentColor),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
