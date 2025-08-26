import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/flashcard.dart';

enum FocusFilter { all, zero, one, twoPlus }

class LernmodusController {
  LernmodusController({
    required List<Flashcard> allCards,
    required this.deckTitle,
    String? progressKeyOverride,
  })  : _allCards = allCards,
        _progressKeyBase = progressKeyOverride ?? deckTitle;

  // ----------------- public read-only state -----------------
  List<Flashcard> get allCards => _allCards;
  FocusFilter get filter => _filter;
  bool get onlyFavorites => _onlyFavorites;
  bool get randomOrder => _randomOrder;
  bool get revealed => _revealed;
  int get favoritesCount => _favoritesById.length;
  int get notesCount =>
      _notesById.values.where((t) => t.trim().isNotEmpty).length;

  ({int zero, int one, int twoPlus}) get buckets {
    int zero = 0, one = 0, twoPlus = 0;
    for (final c in _allCards) {
      final k = correctOf(c);
      if (k == 0) zero++;
      else if (k == 1) one++;
      else twoPlus++;
    }
    return (zero: zero, one: one, twoPlus: twoPlus);
  }

  Flashcard? get currentCard {
    final list = _ordered;
    if (list.isEmpty) return null;
    return list[_currentIndex.clamp(0, list.length - 1)];
  }

  int correctOf(Flashcard c) => _correctById[c.id] ?? 0;
  bool isFavorite(Flashcard c) => _favoritesById.contains(c.id);
  String noteOf(Flashcard c) => _notesById[c.id] ?? '';

  // ----------------- internals -----------------
  final List<Flashcard> _allCards;
  final String deckTitle;
  final String _progressKeyBase;

  final Map<String, int> _correctById = {};
  final Set<String> _favoritesById = {};
  final Map<String, String> _notesById = {};

  FocusFilter _filter = FocusFilter.all;
  bool _onlyFavorites = false;
  bool _randomOrder = false;
  int _shuffleSeed = 0;
  final List<String> _orderIds = [];
  int _currentIndex = 0;
  bool _revealed = false;

  SharedPreferences? _prefs;

  // keys
  String get _progressKey => 'lernprogress_$_progressKeyBase';
  String get _orderKey => 'lernorder_$_progressKeyBase';
  String get _seedKey => 'lernseed_$_progressKeyBase';
  String get _favoritesKey => 'lernfavorites_$_progressKeyBase';
  String get _notesKey => 'lernnotes_$_progressKeyBase';

  // ------------- persistence -------------
  Future<void> loadFromPrefs(SharedPreferences prefs) async {
    _prefs = prefs;

    // progress
    final raw = prefs.getString(_progressKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        decoded.forEach((k, v) {
          final n = (v is int) ? v : int.tryParse(v.toString()) ?? 0;
          _correctById[k] = n;
        });
      } catch (_) {}
    } else {
      // seed from model if provided
      for (final c in _allCards) {
        if (c.correctCount != 0) {
          _correctById[c.id] = c.correctCount;
        }
      }
    }

    // order
    _randomOrder = prefs.getBool(_orderKey) ?? false;
    _shuffleSeed =
        prefs.getInt(_seedKey) ?? DateTime.now().millisecondsSinceEpoch;

    // favorites
    final favRaw = prefs.getString(_favoritesKey);
    if (favRaw != null && favRaw.isNotEmpty) {
      try {
        final List<dynamic> arr = jsonDecode(favRaw);
        _favoritesById
          ..clear()
          ..addAll(arr.map((e) => e.toString()));
      } catch (_) {}
    }

    // notes
    final notesRaw = prefs.getString(_notesKey);
    if (notesRaw != null && notesRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(notesRaw) as Map<String, dynamic>;
        _notesById
          ..clear()
          ..addAll(decoded.map((k, v) => MapEntry(k, v.toString())));
      } catch (_) {}
    }

    _recomputeOrder(resetIndex: true);
  }

  Future<void> saveProgress() async {
    await _prefs?.setString(_progressKey, jsonEncode(_correctById));
  }

  Future<void> saveOrderPrefs() async {
    await _prefs?.setBool(_orderKey, _randomOrder);
    await _prefs?.setInt(_seedKey, _shuffleSeed);
  }

  Future<void> saveFavorites() async {
    await _prefs?.setString(_favoritesKey, jsonEncode(_favoritesById.toList()));
  }

  Future<void> saveNotes() async {
    await _prefs?.setString(_notesKey, jsonEncode(_notesById));
  }

  // ------------- ordering / filtering -------------
  List<Flashcard> get _filtered {
    Iterable<Flashcard> base;
    switch (_filter) {
      case FocusFilter.zero:
        base = _allCards.where((c) => correctOf(c) == 0);
        break;
      case FocusFilter.one:
        base = _allCards.where((c) => correctOf(c) == 1);
        break;
      case FocusFilter.twoPlus:
        base = _allCards.where((c) => correctOf(c) >= 2);
        break;
      case FocusFilter.all:
      default:
        base = _allCards;
    }
    if (_onlyFavorites) {
      base = base.where((c) => isFavorite(c));
    }
    return base.toList();
  }

  List<Flashcard> get _ordered {
    final byId = {for (final c in _filtered) c.id: c};
    if (_orderIds.length != byId.length || !_orderIds.every(byId.containsKey)) {
      _recomputeOrder();
    }
    return _orderIds.map((id) => byId[id]!).toList();
  }

  void _recomputeOrder({bool resetIndex = false}) {
    final ids = _filtered.map((c) => c.id).toList();
    _orderIds
      ..clear()
      ..addAll(ids);

    if (_randomOrder) {
      final r = Random(_shuffleSeed);
      for (int i = _orderIds.length - 1; i > 0; i--) {
        final j = r.nextInt(i + 1);
        final tmp = _orderIds[i];
        _orderIds[i] = _orderIds[j];
        _orderIds[j] = tmp;
      }
    }
    if (_orderIds.isEmpty) {
      _currentIndex = 0;
    } else {
      _currentIndex = resetIndex ? 0 : _currentIndex.clamp(0, _orderIds.length - 1);
    }
  }

  Future<void> persistOrderIfNeeded() async {
    // nothing else to persist besides random flag/seed which is already stored
    await saveOrderPrefs();
  }

  // ------------- UI actions (called from screen) -------------
  void setFilter(FocusFilter f) {
    _filter = f;
    _revealed = false;
    _recomputeOrder(resetIndex: true);
  }

  void toggleFavoritesOnly(bool value) {
    _onlyFavorites = value;
    _revealed = false;
    _recomputeOrder(resetIndex: true);
  }

  void toggleRandomOrder(bool value) {
    _randomOrder = value;
    if (_randomOrder) {
      _shuffleSeed = DateTime.now().millisecondsSinceEpoch;
    }
    _revealed = false;
    _recomputeOrder(resetIndex: true);
  }

  void toggleReveal() {
    _revealed = !_revealed;
  }

  bool markRight() {
    if (!_revealed) return false;
    final list = _ordered;
    if (list.isEmpty) return false;
    final card = list[_currentIndex];
    _correctById[card.id] = (_correctById[card.id] ?? 0) + 1;

    final prevLen = _ordered.length;
    _recomputeOrder(); // may move card into another bucket → filtered set changes

    if (_ordered.isEmpty) {
      _currentIndex = 0;
      _revealed = false;
    } else {
      _currentIndex = _currentIndex.clamp(0, _ordered.length - 1);
      if (_ordered.length == prevLen) {
        _advanceToNext();
      } else {
        _revealed = false;
      }
    }
    return true;
  }

  void markWrong() {
    if (!_revealed) return;
    _advanceToNext();
  }

  void _advanceToNext() {
    final list = _ordered;
    if (list.isEmpty) {
      _currentIndex = 0;
      _revealed = false;
      return;
    }
    _currentIndex = (_currentIndex + 1) % list.length;
    _revealed = false;
  }

  void toggleFavorite(Flashcard c) {
    final id = c.id;
    if (_favoritesById.contains(id)) {
      _favoritesById.remove(id);
    } else {
      _favoritesById.add(id);
    }

    final wasOnlyFav = _onlyFavorites;
    final prevLen = _ordered.length;
    _recomputeOrder();

    if (wasOnlyFav) {
      if (_ordered.isEmpty) {
        _currentIndex = 0;
        _revealed = false;
      } else {
        _currentIndex = _currentIndex.clamp(0, _ordered.length - 1);
        if (_ordered.length != prevLen) {
          _revealed = false;
        }
      }
    }
  }

  void setNote(Flashcard c, String text) {
    if (text.trim().isEmpty) {
      _notesById.remove(c.id);
    } else {
      _notesById[c.id] = text.trim();
    }
    HapticFeedback.selectionClick();
  }
}
