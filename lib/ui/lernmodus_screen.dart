import 'package:flutter/material.dart';
import '../models/flashcard.dart';

class LernmodusScreen extends StatefulWidget {
  final String title;
  final List<Flashcard> cards;

  const LernmodusScreen({
    super.key,
    required this.title,
    required this.cards,
  });

  @override
  State<LernmodusScreen> createState() => _LernmodusScreenState();
}

class _LernmodusScreenState extends State<LernmodusScreen> {
  int _index = 0;
  bool _showAnswer = false;

  void _next() {
    if (_index < widget.cards.length - 1) {
      setState(() {
        _index++;
        _showAnswer = false;
      });
    }
  }

  void _prev() {
    if (_index > 0) {
      setState(() {
        _index--;
        _showAnswer = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.cards.length;
    final card = widget.cards[_index];

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.title} (${_index + 1}/$total)'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            LinearProgressIndicator(
              value: (_index + 1) / total,
              minHeight: 6,
            ),
            const SizedBox(height: 16),
            if ((card.number ?? '').isNotEmpty)
              Text(card.number!, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _showAnswer = !_showAnswer),
                child: Card(
                  elevation: 1.5,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: SingleChildScrollView(
                      child: AnimatedCrossFade(
                        firstChild: Text(
                          card.question.isEmpty ? '(keine Frage)' : card.question,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        secondChild: Text(
                          card.answer.isEmpty ? '(keine Antwort)' : card.answer,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        crossFadeState: _showAnswer
                            ? CrossFadeState.showSecond
                            : CrossFadeState.showFirst,
                        duration: const Duration(milliseconds: 180),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _index > 0 ? _prev : null,
                    icon: const Icon(Icons.chevron_left),
                    label: const Text('Zurück'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _index < total - 1 ? _next : null,
                    icon: const Icon(Icons.chevron_right),
                    label: const Text('Weiter'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => setState(() => _showAnswer = !_showAnswer),
              child: Text(_showAnswer ? 'Frage anzeigen' : 'Antwort anzeigen'),
            ),
          ],
        ),
      ),
    );
  }
}
