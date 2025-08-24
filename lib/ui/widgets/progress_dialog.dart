import 'package:flutter/material.dart';

class ProgressDialog extends StatelessWidget {
  final int current;
  final int total;
  final Duration elapsed;
  final String? snippet;
  final String? debugMessage;

  const ProgressDialog({
    super.key,
    required this.current,
    required this.total,
    required this.elapsed,
    this.snippet,
    this.debugMessage,
  });

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${m}m ${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : current / total;
    final percent = (progress * 100).clamp(0, 100).toStringAsFixed(0);

    return AlertDialog(
      title: const Text('PDF wird verarbeitet …'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(value: total > 0 ? progress : null),
          const SizedBox(height: 12),
          Text('Seite $current von $total  •  $percent%  •  ${_fmt(elapsed)}'),
          if (snippet != null && snippet!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Beispiel:\n$snippet',
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (debugMessage != null && debugMessage!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              debugMessage!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}
