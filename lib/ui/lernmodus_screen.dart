// lib/screens/lernmodus_screen.dart
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/flashcard.dart';
import 'package:flutter/services.dart';

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

  // Persistent favorites: cards saved for later.
  final Set<String> _favoritesById = {};

  // Persistent notes: free-form text per card.
  final Map<String, String> _notesById = {};

  // Local UI state
  FocusFilter _filter = FocusFilter.all;
  bool _showFilterPanel = false;
  int _currentIndex = 0;
  bool _revealed = false;

  // Favorites-only view toggle
  bool _onlyFavorites = false;

  // Order state (sorted vs random) + persistence
  bool _randomOrder = false;
  int _shuffleSeed = 0; // keep a stable seed during a session
  final List<String> _orderIds = []; // current ordered ids for the visible list

  // Persistence helpers
  late SharedPreferences _prefs;
  bool _prefsReady = false;

  // Use a stable key per deck/screen. Prefer deckId; fall back to title.
  String get _progressKey =>
      'lernprogress_${widget.progressKey ?? widget.title}';
  String get _orderKey =>
      'lernorder_${widget.progressKey ?? widget.title}';
  String get _seedKey =>
      'lernseed_${widget.progressKey ?? widget.title}';
  String get _favoritesKey =>
      'lernfavorites_${widget.progressKey ?? widget.title}';
  String get _notesKey =>
      'lernnotes_${widget.progressKey ?? widget.title}';

  // Accessors
  List<Flashcard> get _allCards => widget.cards;
  String _keyOf(Flashcard c) => c.id;
  int _correctOf(Flashcard c) => _correctById[_keyOf(c)] ?? 0;
  bool _isFav(Flashcard c) => _favoritesById.contains(_keyOf(c));
  String _noteOf(Flashcard c) => _notesById[_keyOf(c)] ?? '';

  // Base filtered view (without ordering)
  List<Flashcard> get _filtered {
    Iterable<Flashcard> base;
    switch (_filter) {
      case FocusFilter.zero:
        base = _allCards.where((c) => _correctOf(c) == 0);
        break;
      case FocusFilter.one:
        base = _allCards.where((c) => _correctOf(c) == 1);
        break;
      case FocusFilter.twoPlus:
        base = _allCards.where((c) => _correctOf(c) >= 2);
        break;
      case FocusFilter.all:
      default:
        base = _allCards;
        break;
    }
    if (_onlyFavorites) {
      base = base.where((c) => _isFav(c));
    }
    return base.toList();
  }

  // Ordered filtered list according to _orderIds cache
  List<Flashcard> get _ordered {
    final byId = {for (final c in _filtered) _keyOf(c): c};

    // If _orderIds is out of sync (length/contents differ), rebuild.
    if (_orderIds.length != byId.length ||
        !_orderIds.every(byId.containsKey)) {
      _recomputeOrder();
    }

    return _orderIds.map((id) => byId[id]!).toList();
  }

  // Buckets for the progress bar (over entire deck, not filtered)
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

    // Load order prefs
    _randomOrder = _prefs.getBool(_orderKey) ?? false;
    _shuffleSeed = _prefs.getInt(_seedKey) ??
        DateTime.now().millisecondsSinceEpoch;

    // Load favorites
    final favRaw = _prefs.getString(_favoritesKey);
    if (favRaw != null && favRaw.isNotEmpty) {
      try {
        final List<dynamic> arr = jsonDecode(favRaw);
        _favoritesById
          ..clear()
          ..addAll(arr.map((e) => e.toString()));
      } catch (_) {
        // ignore malformed
      }
    }

    // Load notes
    final notesRaw = _prefs.getString(_notesKey);
    if (notesRaw != null && notesRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(notesRaw) as Map<String, dynamic>;
        _notesById
          ..clear()
          ..addAll(decoded.map((k, v) => MapEntry(k, v.toString())));
      } catch (_) {
        // ignore malformed
      }
    }

    setState(() {
      _prefsReady = true;
      _recomputeOrder();
      _currentIndex = 0;
      _revealed = false;
    });
  }

  Future<void> _saveProgress() async {
    await _prefs.setString(_progressKey, jsonEncode(_correctById));
  }

  Future<void> _saveOrderPrefs() async {
    await _prefs.setBool(_orderKey, _randomOrder);
    await _prefs.setInt(_seedKey, _shuffleSeed);
  }

  Future<void> _saveFavorites() async {
    await _prefs.setString(_favoritesKey, jsonEncode(_favoritesById.toList()));
  }

  Future<void> _saveNotes() async {
    await _prefs.setString(_notesKey, jsonEncode(_notesById));
  }

  // Build/refresh the _orderIds cache based on _filtered and _randomOrder
  void _recomputeOrder() {
    final list = _filtered;
    final ids = list.map(_keyOf).toList();

    _orderIds
      ..clear()
      ..addAll(ids);

    if (_randomOrder) {
      // Deterministic shuffle for a stable study order.
      final r = Random(_shuffleSeed);
      for (int i = _orderIds.length - 1; i > 0; i--) {
        final j = r.nextInt(i + 1);
        final tmp = _orderIds[i];
        _orderIds[i] = _orderIds[j];
        _orderIds[j] = tmp;
      }
    }
    // Clamp index after reordering
    if (_orderIds.isEmpty) {
      _currentIndex = 0;
    } else {
      _currentIndex = _currentIndex.clamp(0, _orderIds.length - 1);
    }
  }

  // UI actions
  void _setFilter(FocusFilter f) {
    setState(() {
      _filter = f;
      _showFilterPanel = false;
      _currentIndex = 0;
      _revealed = false;
      _recomputeOrder();
    });
  }

  void _toggleFavoritesOnly(bool value) {
    setState(() {
      _onlyFavorites = value;
      _currentIndex = 0;
      _revealed = false;
      _recomputeOrder();
    });
  }

  void _advanceToNext() {
    final list = _ordered;
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
    final list = _ordered;
    if (list.isEmpty) return;
    final card = list[_currentIndex];
    final key = _keyOf(card);

    setState(() {
      _correctById[key] = (_correctById[key] ?? 0) + 1;
      // Re-evaluate filters & order because the bucket may have changed.
      final prevLength = _ordered.length;
      _recomputeOrder();

      if (_ordered.isEmpty) {
        _currentIndex = 0;
        _revealed = false;
      } else {
        // If list shrank, clamp; otherwise advance to next item.
        _currentIndex = _currentIndex.clamp(0, _ordered.length - 1);
        if (_ordered.length == prevLength) {
          _advanceToNext();
        } else {
          _revealed = false;
        }
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

  void _toggleRandomOrder(bool value) {
    setState(() {
      _randomOrder = value;
      // New seed when enabling random to reshuffle;
      // keep the existing seed when disabling (for later re-enable).
      if (_randomOrder) {
        _shuffleSeed = DateTime.now().millisecondsSinceEpoch;
      }
      _currentIndex = 0;
      _revealed = false;
      _recomputeOrder();
    });
    _saveOrderPrefs();
  }

  void _toggleFavorite(Flashcard c) {
    final id = _keyOf(c);
    setState(() {
      if (_favoritesById.contains(id)) {
        _favoritesById.remove(id);
      } else {
        _favoritesById.add(id);
      }
      // If we are in favorites-only mode and we un-favorite current,
      // we need to recompute and clamp/advance.
      final wasOnlyFav = _onlyFavorites;
      final prevLen = _ordered.length;
      _recomputeOrder();
      if (wasOnlyFav) {
        if (_ordered.isEmpty) {
          _currentIndex = 0;
          _revealed = false;
        } else {
          _currentIndex = _currentIndex.clamp(0, _ordered.length - 1);
          if (_ordered.length == prevLen) {
            // keep current index
          } else {
            _revealed = false;
          }
        }
      }
    });
    _saveFavorites();
  }

  Future<void> _editNote(Flashcard c) async {
    final id = _keyOf(c);
    final controller = TextEditingController(text: _notesById[id] ?? '');
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: bottomInset + 16,
            top: 8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.edit_note_rounded),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Notiz zur Karte',
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      controller.clear();
                    },
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Leeren'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                maxLines: null,
                minLines: 4,
                autofocus: true,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: 'Schreibe deine Gedanken, Eselsbrücken oder Links…',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(ctx).pop(null),
                      icon: const Icon(Icons.close),
                      label: const Text('Abbrechen'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () =>
                          Navigator.of(ctx).pop(controller.text.trim()),
                      icon: const Icon(Icons.save_rounded),
                      label: const Text('Speichern'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );

    if (result != null) {
      setState(() {
        if (result.isEmpty) {
          _notesById.remove(id);
        } else {
          _notesById[id] = result;
        }
      });
      await _saveNotes();
      HapticFeedback.selectionClick();
    }
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
    final fav = _isFav(c);
    final note = _noteOf(c);

    final list = _ordered;
    final key = ValueKey(
        'card_${_keyOf(c)}_${_currentIndex}_${_revealed ? 1 : 0}_${_randomOrder ? 1 : 0}_${fav ? 1 : 0}_${note.isNotEmpty ? 1 : 0}');

    return Dismissible(
      key: key,
      direction: _revealed
          ? DismissDirection.horizontal
          : DismissDirection.none,
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.12),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.check_rounded, size: 32),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.12),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.close_rounded, size: 32),
      ),
      confirmDismiss: (dir) async {
        if (!_revealed || list.isEmpty) return false;
        if (dir == DismissDirection.startToEnd) {
          HapticFeedback.lightImpact();
          _markRight();
        } else if (dir == DismissDirection.endToStart) {
          HapticFeedback.lightImpact();
          _markWrong();
        }
        return false; // don’t remove, we handled it
      },
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: _toggleReveal,
        onLongPress: () => _editNote(c), // quick access to notes
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Theme.of(context).colorScheme.surface,
                Theme.of(context).colorScheme.surfaceContainerHighest,
              ],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderColor.withOpacity(0.6), width: 2.5),
            boxShadow: [
              BoxShadow(
                color: borderColor.withOpacity(0.12),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Stack(
              children: [
                // Main content column
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if ((c.number ?? '').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6, right: 64),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.confirmation_number, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              c.number!,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withOpacity(0.7),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Text(
                      c.question,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Divider(
                      height: 1,
                      color: Theme.of(context)
                          .colorScheme
                          .outline
                          .withOpacity(0.25),
                    ),
                    const SizedBox(height: 10),
                    AnimatedCrossFade(
                      duration: const Duration(milliseconds: 200),
                      crossFadeState: _revealed
                          ? CrossFadeState.showFirst
                          : CrossFadeState.showSecond,
                      firstChild: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.answer,
                            style: const TextStyle(fontSize: 18, height: 1.35),
                          ),
                          if (note.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            _NotePreview(
                              text: note,
                              onTap: () => _editNote(c),
                            ),
                          ],
                        ],
                      ),
                      secondChild: Column(
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                vertical: 16, horizontal: 12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Theme.of(context)
                                    .colorScheme
                                    .outline
                                    .withOpacity(0.35),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.touch_app, size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  'Tippe, um die Antwort anzuzeigen',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontStyle: FontStyle.italic,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withOpacity(0.65),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (note.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            _NotePreview(
                              text: note,
                              onTap: () => _editNote(c),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                // Top-right action buttons: favorite + note
                Positioned(
                  right: 0,
                  top: 0,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        splashRadius: 24,
                        tooltip: 'Notiz bearbeiten',
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          _editNote(c);
                        },
                        icon: Icon(
                          _noteOf(c).isNotEmpty
                              ? Icons.edit_note_rounded
                              : Icons.note_add_outlined,
                          size: 26,
                          color: _noteOf(c).isNotEmpty
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(0.6),
                        ),
                      ),
                      IconButton(
                        splashRadius: 24,
                        tooltip:
                            fav ? 'Aus Favoriten entfernen' : 'Zu Favoriten',
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          _toggleFavorite(c);
                        },
                        icon: Icon(
                          fav
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          size: 26,
                          color: fav
                              ? Colors.amber
                              : Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProgressBar() {
    final total = _allCards.length;
    final b = _buckets;
    final favCount = _favoritesById.length;
    final notesCount = _notesById.values.where((t) => t.trim().isNotEmpty).length;

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
                      'Gesamt: $total  •  Favoriten: $favCount  •  Notizen: $notesCount',
                      style: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.7),
                      ),
                    ),
                    Row(
                      children: [
                        const Icon(Icons.shuffle, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          _randomOrder ? 'Zufällig' : 'Sortiert',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.8),
                          ),
                        ),
                      ],
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
            child: Column(
              children: [
                Wrap(
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
                const SizedBox(height: 8),
                // The order switch
                SwitchListTile.adaptive(
                  value: _randomOrder,
                  onChanged: _toggleRandomOrder,
                  secondary: const Icon(Icons.shuffle),
                  title: const Text(
                    'Zufällige Reihenfolge',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    _randomOrder
                        ? 'Karten werden in zufälliger, stabiler Reihenfolge angezeigt.'
                        : 'Karten folgen der sortierten Reihenfolge.',
                    style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.8),
                    ),
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
                // Favorites-only switch
                SwitchListTile.adaptive(
                  value: _onlyFavorites,
                  onChanged: _toggleFavoritesOnly,
                  secondary: const Icon(Icons.star_rounded),
                  title: const Text(
                    'Nur Favoriten anzeigen',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    'Zeigt nur Karten, die du gespeichert hast.',
                    style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.8),
                    ),
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
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

    final list = _ordered;
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

class _NotePreview extends StatelessWidget {
  const _NotePreview({
    required this.text,
    required this.onTap,
  });

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final preview = text.split('\n').first.trim();
    return Material(
      color: Theme.of(context).colorScheme.secondaryContainer.withOpacity(0.4),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
          child: Row(
            children: [
              const Icon(Icons.sticky_note_2_outlined, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  preview.isEmpty ? '(Notiz bearbeiten …)' : preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.edit_outlined, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}
