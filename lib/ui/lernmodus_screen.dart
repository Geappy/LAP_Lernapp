// lib/screens/lernmodus_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/flashcard.dart';

enum FocusFilter { all, zero, one, twoPlus }

class LernmodusScreen extends StatefulWidget {
  const LernmodusScreen({
    super.key,
    required this.cards,
    required this.title,
    this.progressKey, // optional: pass a stable deck ID if available
  });

  final List<Flashcard> cards;
  final String title;
  final String? progressKey;

  @override
  State<LernmodusScreen> createState() => _LernmodusScreenState();
}

class _LernmodusScreenState extends State<LernmodusScreen> {
  // Persistent progress: how often each card was answered "right".
  final Map<String, int> _correctById = {};

  // Local UI state
  FocusFilter _filter = FocusFilter.all;
  bool _showFilterPanel = false;
  int _currentIndex = 0;
  bool _revealed = false;

  // Persistence helpers
  late SharedPreferences _prefs;
  bool _prefsReady = false;

  // Use a stable key per deck/screen. Prefer deckId; fall back to title.
  String get _progressKey =>
      'lernprogress_${widget.progressKey ?? widget.title}';

  // Accessors
  List<Flashcard> get _allCards => widget.cards;
  String _keyOf(Flashcard c) => c.id;
  int _correctOf(Flashcard c) => _correctById[_keyOf(c)] ?? 0;

  // Filtered view
  List<Flashcard> get _filtered {
    switch (_filter) {
      case FocusFilter.zero:
        return _allCards.where((c) => _correctOf(c) == 0).toList();
      case FocusFilter.one:
        return _allCards.where((c) => _correctOf(c) == 1).toList();
      case FocusFilter.twoPlus:
        return _allCards.where((c) => _correctOf(c) >= 2).toList();
      case FocusFilter.all:
      default:
        return _allCards;
    }
  }

  // Buckets for the progress bar
  ({int zero, int one, int twoPlus}) get _buckets {
    int zero = 0, one = 0, twoPlus = 0;
    for (final c in _allCards) {
      final k = _correctOf(c);
      if (k == 0) {
        zero++;
      } else if (k == 1) {
        one++;
      } else {
        twoPlus++;
      }
    }
    return (zero: zero, one: one, twoPlus: twoPlus);
  }

  // Lifecycle
  @override
  void initState() {
    super.initState();
    _initPrefsAndLoad();
  }

  Future<void> _initPrefsAndLoad() async {
    _prefs = await SharedPreferences.getInstance();

    // Load saved map if present
    final raw = _prefs.getString(_progressKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        decoded.forEach((k, v) {
          final n = (v is int) ? v : int.tryParse(v.toString()) ?? 0;
          _correctById[k] = n;
        });
      } catch (_) {
        // Ignore corrupt data; will rebuild from defaults below
      }
    }

    // If nothing saved yet, seed from Flashcard.correctCount (your model).
    if (_correctById.isEmpty) {
      for (final c in _allCards) {
        if (c.correctCount != 0) {
          _correctById[_keyOf(c)] = c.correctCount;
        }
      }
    }

    setState(() => _prefsReady = true);
  }

  Future<void> _saveProgress() async {
    // Persist the whole map as JSON
    await _prefs.setString(_progressKey, jsonEncode(_correctById));
  }

  // UI actions
  void _setFilter(FocusFilter f) {
    setState(() {
      _filter = f;
      _showFilterPanel = false;
      _currentIndex = 0;
      _revealed = false;
    });
  }

  void _advanceToNext() {
    final list = _filtered;
    if (list.isEmpty) {
      setState(() {
        _currentIndex = 0;
        _revealed = false;
      });
      return;
    }
    setState(() {
      _currentIndex = (_currentIndex + 1) % list.length;
      _revealed = false;
    });
  }

  void _markRight() {
    if (!_revealed) return;
    final list = _filtered;
    if (list.isEmpty) return;
    final card = list[_currentIndex];
    final key = _keyOf(card);

    setState(() {
      _correctById[key] = (_correctById[key] ?? 0) + 1;

      // Because filter buckets can change after increment, recalc and move.
      final after = _filtered;
      if (after.isEmpty) {
        _currentIndex = 0;
        _revealed = false;
      } else {
        _currentIndex = _currentIndex.clamp(0, after.length - 1);
        _advanceToNext();
      }
    });

    _saveProgress(); // persist after change
  }

  void _markWrong() {
    if (!_revealed) return;
    // Wrong answers are not counted; just move on
    _advanceToNext();
  }

  void _toggleReveal() {
    setState(() => _revealed = !_revealed);
  }

  Color _bucketColor(int correct) {
    if (correct >= 2) return Colors.green;
    if (correct == 1) return Colors.orange;
    return Colors.red;
  }

  // Widgets
  Widget _buildCard(Flashcard c) {
    final correct = _correctOf(c);
    final borderColor = _bucketColor(correct);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: _toggleReveal,
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: borderColor, width: 4),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if ((c.number ?? '').isNotEmpty)
                    Text(
                      c.number!,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  if ((c.number ?? '').isNotEmpty) const SizedBox(height: 6),
                  Text(
                    c.question,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  AnimatedCrossFade(
                    duration: const Duration(milliseconds: 180),
                    crossFadeState: _revealed
                        ? CrossFadeState.showFirst
                        : CrossFadeState.showSecond,
                    firstChild: Text(
                      c.answer,
                      style: const TextStyle(fontSize: 18, height: 1.35),
                    ),
                    secondChild: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          vertical: 18, horizontal: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .outline
                              .withOpacity(0.4),
                          style: BorderStyle.solid,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.touch_app,
                              size: 18,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(0.6)),
                          const SizedBox(width: 8),
                          Text(
                            'Tippe, um die Antwort anzuzeigen',
                            style: TextStyle(
                              fontSize: 14,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(0.6),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgressBar() {
    final total = _allCards.length;
    final b = _buckets;

    double f(int n) => total == 0 ? 0 : n / total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _showFilterPanel = !_showFilterPanel),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                SizedBox(
                  height: 22,
                  child: Row(
                    children: [
                      _SegmentBarPortion(
                        fraction: f(b.zero),
                        color: Colors.red,
                        label: '${b.zero}',
                      ),
                      _SegmentBarPortion(
                        fraction: f(b.one),
                        color: Colors.orange,
                        label: '${b.one}',
                      ),
                      _SegmentBarPortion(
                        fraction: f(b.twoPlus),
                        color: Colors.green,
                        label: '${b.twoPlus}',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Gesamt: $total',
                      style: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.7),
                      ),
                    ),
                    Icon(
                      _showFilterPanel ? Icons.expand_less : Icons.expand_more,
                      size: 20,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 200),
          crossFadeState: _showFilterPanel
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          firstChild: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 8,
              children: [
                _filterChip('Alle ($total)', FocusFilter.all,
                    selected: _filter == FocusFilter.all, color: Colors.blue),
                _filterChip('0× (${b.zero})', FocusFilter.zero,
                    selected: _filter == FocusFilter.zero, color: Colors.red),
                _filterChip('1× (${b.one})', FocusFilter.one,
                    selected: _filter == FocusFilter.one, color: Colors.orange),
                _filterChip('2+× (${b.twoPlus})', FocusFilter.twoPlus,
                    selected: _filter == FocusFilter.twoPlus, color: Colors.green),
              ],
            ),
          ),
          secondChild: const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _filterChip(String label, FocusFilter f,
      {required bool selected, required Color color}) {
    return FilterChip(
      selected: selected,
      label: Text(label),
      onSelected: (_) => _setFilter(f),
      selectedColor: color.withOpacity(0.15),
      checkmarkColor: color,
      side: BorderSide(color: color.withOpacity(0.5)),
      showCheckmark: selected,
      labelStyle: TextStyle(
        color: selected ? color : null,
        fontWeight: selected ? FontWeight.w600 : null,
      ),
    );
  }

  Widget _buildBigButtons() {
    final enabled = _revealed; // only usable after reveal

    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: enabled ? _markWrong : null,
            icon: const Icon(Icons.close_rounded, size: 28),
            label: const Text('Falsch'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(64),
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              textStyle: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
              backgroundColor: enabled
                  ? Colors.red.withOpacity(0.12)
                  : Colors.red.withOpacity(0.06),
              foregroundColor: Colors.red,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: enabled ? _markRight : null,
            icon: const Icon(Icons.check_rounded, size: 28),
            label: const Text('Richtig'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(64),
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              textStyle: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
              backgroundColor: enabled
                  ? Colors.green.withOpacity(0.12)
                  : Colors.green.withOpacity(0.06),
              foregroundColor: Colors.green,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyHint() {
    final b = _buckets;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.inbox, size: 48),
        const SizedBox(height: 12),
        const Text(
          'Keine Karten im aktuellen Filter.',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          '0×: ${b.zero}   1×: ${b.one}   2+×: ${b.twoPlus}',
          style: const TextStyle(fontSize: 14),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => _setFilter(FocusFilter.all),
          icon: const Icon(Icons.layers),
          label: const Text('Alle Karten anzeigen'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_prefsReady) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final list = _filtered;
    final current =
        list.isNotEmpty ? list[_currentIndex.clamp(0, list.length - 1)] : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildProgressBar(),
            const SizedBox(height: 16),
            Expanded(
                child: current == null ? _buildEmptyHint() : _buildCard(current)),
            const SizedBox(height: 12),
            _buildBigButtons(),
          ],
        ),
      ),
    );
  }
}

class _SegmentBarPortion extends StatelessWidget {
  const _SegmentBarPortion({
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
