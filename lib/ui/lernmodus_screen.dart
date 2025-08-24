import 'package:flutter/material.dart';

import '../models/deck.dart';
import '../models/flashcard.dart';

enum FocusMode { all, zero, one, twoPlus }

class LernmodusScreen extends StatefulWidget {
  const LernmodusScreen({
    super.key,
    required this.deck,
    this.onSave,
  });

  final Deck deck;
  final Future<void> Function(Deck deck)? onSave;

  @override
  State<LernmodusScreen> createState() => _LernmodusScreenState();
}

class _LernmodusScreenState extends State<LernmodusScreen> {
  /// zählt pro Karte, wie oft korrekt beantwortet
  final Map<String, int> _correct = {};

  /// aktueller Filter
  FocusMode _focus = FocusMode.all;

  /// Index im aktuell gefilterten Satz
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // Alle Karten mit 0 initialisieren (einmalig)
    for (final c in widget.deck.cards) {
      _correct.putIfAbsent(_key(c), () => 0);
    }
  }

  String _key(Flashcard c) =>
      '${c.number ?? ''}∷${c.question.trim()}∷${c.answer.trim()}';

  int _countFor(Flashcard c) => _correct[_key(c)] ?? 0;

  List<Flashcard> get _all => widget.deck.cards;

  List<Flashcard> get _visible {
    switch (_focus) {
      case FocusMode.all:
        return _all;
      case FocusMode.zero:
        return _all.where((c) => _countFor(c) == 0).toList(growable: false);
      case FocusMode.one:
        return _all.where((c) => _countFor(c) == 1).toList(growable: false);
      case FocusMode.twoPlus:
        return _all.where((c) => _countFor(c) >= 2).toList(growable: false);
    }
  }

  void _setFocus(FocusMode f) {
    setState(() {
      _focus = f;
      // Falls der aktuelle Index fürs neue Set zu groß ist → clampen
      final v = _visible;
      if (v.isEmpty) {
        _index = 0;
      } else if (_index >= v.length) {
        _index = 0;
      }
    });
  }

  /// Geht deterministisch zur nächsten Karte im aktuellen Filterset.
  void _advance() {
    final v = _visible;
    if (v.isEmpty) {
      setState(() => _index = 0);
      return;
    }
    setState(() => _index = (_index + 1) % v.length);
  }

  void _markRight() {
    final v = _visible;
    if (v.isEmpty) return;

    final current = v[_index];
    final k = _key(current);

    setState(() {
      _correct[k] = (_correct[k] ?? 0) + 1;
    });

    // Karte könnte jetzt aus dem Filter (z.B. zero/one) herausfallen.
    final v2 = _visible;
    if (v2.isEmpty) {
      // Nach dem Hochstufen gibt es hier nichts mehr zu lernen
      setState(() => _index = 0);
      return;
    }
    // Wenn die gleiche Position nun außerhalb liegt, auf gleiche Position (oder 0) clampen.
    if (_index >= v2.length) {
      setState(() => _index = 0);
    } else {
      // Im Normalfall einfach zur nächsten Karte
      _advance();
    }
  }

  void _markWrong() {
    // Falsch ändert nichts am Zähler → einfach nächste Karte
    final v = _visible;
    if (v.isEmpty) return;
    _advance();
  }

  Color _borderColorFor(Flashcard c) {
    final n = _countFor(c);
    if (n == 0) return Colors.red;
    if (n == 1) return Colors.orange;
    return Colors.green;
  }

  @override
  Widget build(BuildContext context) {
    // Zähler für Segment/Chips
    final total = _all.length;
    final zero = _all.where((c) => _countFor(c) == 0).length;
    final one = _all.where((c) => _countFor(c) == 1).length;
    final twoPlus = total - zero - one;

    final v = _visible;
    final hasCards = v.isNotEmpty;
    final Flashcard? card = hasCards ? v[_index] : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.deck.title),
        actions: [
          PopupMenuButton<FocusMode>(
            initialValue: _focus,
            onSelected: _setFocus,
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: FocusMode.all,
                child: Text('Alle Karten'),
              ),
              PopupMenuItem(
                value: FocusMode.zero,
                child: Row(
                  children: [
                    const Icon(Icons.circle, size: 10, color: Colors.red),
                    const SizedBox(width: 8),
                    Text('0× richtig ($zero)'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: FocusMode.one,
                child: Row(
                  children: [
                    const Icon(Icons.circle, size: 10, color: Colors.orange),
                    const SizedBox(width: 8),
                    Text('1× richtig ($one)'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: FocusMode.twoPlus,
                child: Row(
                  children: [
                    const Icon(Icons.circle, size: 10, color: Colors.green),
                    const SizedBox(width: 8),
                    Text('≥2× richtig ($twoPlus)'),
                  ],
                ),
              ),
            ],
            icon: const Icon(Icons.filter_alt),
            tooltip: 'Filter wählen',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _StackedSegmentBar(
              zero: zero,
              one: one,
              twoPlus: twoPlus,
              total: total,
              selected: _focus,
              onTap: _setFocus,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                _chip(
                  label: 'Alle ($total)',
                  selected: _focus == FocusMode.all,
                  color: Theme.of(context).colorScheme.primary,
                  onTap: () => _setFocus(FocusMode.all),
                ),
                _chip(
                  label: '0× ($zero)',
                  selected: _focus == FocusMode.zero,
                  color: Colors.red,
                  onTap: () => _setFocus(FocusMode.zero),
                ),
                _chip(
                  label: '1× ($one)',
                  selected: _focus == FocusMode.one,
                  color: Colors.orange,
                  onTap: () => _setFocus(FocusMode.one),
                ),
                _chip(
                  label: '≥2× ($twoPlus)',
                  selected: _focus == FocusMode.twoPlus,
                  color: Colors.green,
                  onTap: () => _setFocus(FocusMode.twoPlus),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: hasCards
                  ? _FlashcardView(
                      card: card!,
                      borderColor: _borderColorFor(card),
                      count: _countFor(card),
                    )
                  : _EmptyHint(focus: _focus),
            ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: hasCards ? _markWrong : null,
                    icon: const Icon(Icons.close),
                    label: const Text('Falsch'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: hasCards ? _markRight : null,
                    icon: const Icon(Icons.check),
                    label: const Text('Richtig'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required Color color,
    required VoidCallback onTap,
  }) {
    final labelColor =
        selected ? Color.alphaBlend(Colors.black.withOpacity(0.2), color) : null;
    final borderColor = selected ? color.withOpacity(0.7) : null;

    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: color.withOpacity(0.18),
      labelStyle: TextStyle(
        color: labelColor,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
      side: selected && borderColor != null ? BorderSide(color: borderColor) : null,
    );
  }
}

// ---------- Karte ----------

class _FlashcardView extends StatefulWidget {
  const _FlashcardView({
    required this.card,
    required this.borderColor,
    required this.count,
  });

  final Flashcard card;
  final Color borderColor;
  final int count;

  @override
  State<_FlashcardView> createState() => _FlashcardViewState();
}

class _FlashcardViewState extends State<_FlashcardView> {
  bool _showAnswer = false;

  @override
  void didUpdateWidget(covariant _FlashcardView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.card != widget.card) {
      _showAnswer = false; // bei neuer Karte wieder Frage zeigen
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () => setState(() => _showAnswer = !_showAnswer),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: widget.borderColor, width: 3),
          borderRadius: BorderRadius.circular(16),
          color: cs.surface,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if ((widget.card.number ?? '').trim().isNotEmpty)
                Text(
                  widget.card.number!,
                  style: TextStyle(
                    color: widget.borderColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              const SizedBox(height: 6),
              Text(
                widget.card.question.isEmpty
                    ? '— (keine Frage erkannt) —'
                    : widget.card.question,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              AnimatedCrossFade(
                crossFadeState: _showAnswer
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 150),
                firstChild: Text(
                  'Antwort antippen, um sie zu zeigen',
                  style: TextStyle(color: cs.outline),
                ),
                secondChild: Text(
                  widget.card.answer.isEmpty
                      ? '— (keine Antwort erkannt) —'
                      : widget.card.answer,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: widget.borderColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(999),
                    border:
                        Border.all(color: widget.borderColor.withOpacity(0.5)),
                  ),
                  child: Text(
                    widget.count == 0
                        ? '0× richtig'
                        : widget.count == 1
                            ? '1× richtig'
                            : '${widget.count}× richtig',
                    style: TextStyle(
                      color: widget.borderColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------- Segmentbar: 3 gestapelte Segmente (rot/orange/grün) ----------

class _StackedSegmentBar extends StatelessWidget {
  const _StackedSegmentBar({
    required this.zero,
    required this.one,
    required this.twoPlus,
    required this.total,
    required this.selected,
    required this.onTap,
  });

  final int zero;
  final int one;
  final int twoPlus;
  final int total;
  final FocusMode selected;
  final void Function(FocusMode) onTap;

  @override
  Widget build(BuildContext context) {
    if (total == 0) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        double part(int n) => total == 0 ? 0 : (n / total) * w;

        Widget seg(Color c, int n, FocusMode f) {
          final sel = selected == f;
          final width = part(n).clamp(0.0, w);
          if (width <= 0) return const SizedBox.shrink();
          return InkWell(
            onTap: () => onTap(f),
            child: Container(
              width: width,
              height: sel ? 14 : 10,
              decoration: BoxDecoration(
                color: c.withOpacity(sel ? 0.85 : 0.55),
                border: sel ? Border.all(color: c, width: 2) : null,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(f == FocusMode.zero ? 999 : 0),
                  bottomLeft: Radius.circular(f == FocusMode.zero ? 999 : 0),
                  topRight: Radius.circular(f == FocusMode.twoPlus ? 999 : 0),
                  bottomRight: Radius.circular(f == FocusMode.twoPlus ? 999 : 0),
                ),
              ),
            ),
          );
        }

        return Row(
          children: [
            seg(Colors.red, zero, FocusMode.zero),
            seg(Colors.orange, one, FocusMode.one),
            seg(Colors.green, twoPlus, FocusMode.twoPlus),
          ],
        );
      },
    );
  }
}

// ---------- Leerer Zustand ----------

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.focus});
  final FocusMode focus;

  @override
  Widget build(BuildContext context) {
    final text = switch (focus) {
      FocusMode.all => 'Keine Karten vorhanden.',
      FocusMode.zero => 'Keine Karten mit 0× richtig.',
      FocusMode.one => 'Keine Karten mit 1× richtig.',
      FocusMode.twoPlus => 'Keine Karten mit ≥2× richtig.',
    };
    return Center(
      child: Text(
        text,
        style: TextStyle(
          color: Theme.of(context).colorScheme.outline,
        ),
      ),
    );
  }
}
