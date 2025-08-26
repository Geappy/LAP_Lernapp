import 'package:flutter/material.dart';

class SegmentBarPortion extends StatelessWidget {
  const SegmentBarPortion({
    super.key,
    required this.fraction,
    required this.color,
    required this.label,
  });

  final double fraction; // 0..1
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final w = (fraction.isNaN || fraction <= 0) ? 0.0 : fraction;
    return Expanded(
      flex: (w * 1000).round().clamp(0, 1000),
      child: Container(
        decoration: BoxDecoration(
          color: color.withOpacity(0.25),
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ),
    );
  }
}
