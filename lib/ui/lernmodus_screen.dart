import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/flashcard.dart';
import './widgets/lernmodus/progress_panel.dart';
import './widgets/lernmodus/flashcard_card.dart';
import './widgets/lernmodus/empty_hint.dart';
import './state/lernmodus_controller.dart';

class LernmodusScreen extends StatefulWidget {
  const LernmodusScreen({
    super.key,
    required this.cards,
    required this.title,
    this.progressKey,
  });

  final List<Flashcard> cards;
  final String title;
  final String? progressKey;

  @override
  State<LernmodusScreen> createState() => _LernmodusScreenState();
}

class _LernmodusScreenState extends State<LernmodusScreen> {
  late LernmodusController _vm;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _vm = LernmodusController(
      allCards: widget.cards,
      deckTitle: widget.title,
      progressKeyOverride: widget.progressKey,
    );
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    await _vm.loadFromPrefs(prefs);
    if (!mounted) return;
    setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final current = _vm.currentCard;

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ProgressPanel(
              buckets: _vm.buckets,
              total: _vm.allCards.length,
              favoritesCount: _vm.favoritesCount,
              notesCount: _vm.notesCount,
              randomOrder: _vm.randomOrder,
              filter: _vm.filter,
              onlyFavorites: _vm.onlyFavorites,
              onChangeFilter: _vm.setFilter,
              onToggleRandom: (v) async {
                _vm.toggleRandomOrder(v);
                await _vm.saveOrderPrefs();
                setState(() {});
              },
              onToggleOnlyFavorites: (v) {
                _vm.toggleFavoritesOnly(v);
                setState(() {});
              },
            ),
            const SizedBox(height: 16),
            Expanded(
              child: current == null
                  ? EmptyHint(
                      buckets: _vm.buckets,
                      onShowAll: () {
                        _vm.setFilter(FocusFilter.all);
                        setState(() {});
                      },
                    )
                  : FlashcardCard(
                      card: current,
                      revealed: _vm.revealed,
                      isFavorite: _vm.isFavorite(current),
                      note: _vm.noteOf(current),
                      correctCount: _vm.correctOf(current),
                      onToggleReveal: () {
                        _vm.toggleReveal();
                        setState(() {});
                      },
                      onSwipeRight: () async {
                        final changed = _vm.markRight();
                        await _vm.saveProgress();
                        if (changed) await _vm.persistOrderIfNeeded();
                        setState(() {});
                      },
                      onSwipeLeft: () {
                        _vm.markWrong();
                        setState(() {});
                      },
                      onToggleFavorite: () async {
                        _vm.toggleFavorite(current);
                        await _vm.saveFavorites();
                        setState(() {});
                      },
                      onEditNote: (newText) async {
                        _vm.setNote(current, newText);
                        await _vm.saveNotes();
                        setState(() {});
                      },
                    ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _vm.revealed ? () { _vm.markWrong(); setState(() {}); } : null,
                    icon: const Icon(Icons.close_rounded, size: 28),
                    label: const Text('Falsch'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(64),
                      elevation: 1,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                      backgroundColor: (_vm.revealed ? Colors.red : Colors.red.withOpacity(0.5)).withOpacity(0.12),
                      foregroundColor: Colors.red,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _vm.revealed ? () async {
                      final changed = _vm.markRight();
                      await _vm.saveProgress();
                      if (changed) await _vm.persistOrderIfNeeded();
                      setState(() {});
                    } : null,
                    icon: const Icon(Icons.check_rounded, size: 28),
                    label: const Text('Richtig'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(64),
                      elevation: 1,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                      backgroundColor: (_vm.revealed ? Colors.green : Colors.green.withOpacity(0.5)).withOpacity(0.12),
                      foregroundColor: Colors.green,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
