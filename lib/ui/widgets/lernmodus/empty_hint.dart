import 'package:flutter/material.dart';

class EmptyHint extends StatelessWidget {
  const EmptyHint({
    super.key,
    required this.buckets,
    required this.onShowAll,
  });

  final ({int zero, int one, int twoPlus}) buckets;
  final VoidCallback onShowAll;

  @override
  Widget build(BuildContext context) {
    final b = buckets;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.inbox, size: 48),
        const SizedBox(height: 12),
        const Text('Keine Karten im aktuellen Filter.',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text('0×: ${b.zero}   1×: ${b.one}   2+×: ${b.twoPlus}', style: const TextStyle(fontSize: 14)),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: onShowAll,
          icon: const Icon(Icons.layers),
          label: const Text('Alle Karten anzeigen'),
        ),
      ],
    );
  }
}
