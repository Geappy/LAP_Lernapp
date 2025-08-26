// lib/services/storage_service.dart
import 'dart:async';   // <-- needed for Completer & Future
import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/deck.dart';
import '../models/flashcard.dart';
import '../models/unmatched.dart';

class StorageService {
  // ------- Keys -------
  static const _kIndex = 'decks_index'; // List<String> ids
  static String _deckKey(String id) => 'deck_$id'; // String (JSON)
  static String _deckMetaKey(String id) => 'deck_${id}_meta'; // String (JSON)

  static final Future<SharedPreferences> _prefs = SharedPreferences.getInstance();
  static final _mutex = _Mutex();

  // ------- Helpers -------
  static Future<List<String>> _getIndex(SharedPreferences prefs) async {
    return prefs.getStringList(_kIndex) ?? <String>[];
  }

  static Future<void> _setIndex(SharedPreferences prefs, List<String> ids) async {
    await prefs.setStringList(_kIndex, ids);
  }

  static Future<void> _writeDeckAndMeta(SharedPreferences prefs, Deck deck) async {
    final deckJson = jsonEncode(deck.toJson());
    final metaJson = jsonEncode({
      'id': deck.id,
      'title': deck.title,
      'cardCount': deck.cardCount,
      'createdAt': deck.createdAt.toIso8601String(),
      'updatedAt': deck.updatedAt.toIso8601String(),
      'unmatchedCount': deck.unmatched.length,
    });

    final ok1 = await prefs.setString(_deckKey(deck.id), deckJson);
    final ok2 = await prefs.setString(_deckMetaKey(deck.id), metaJson);
    if (!ok1 || !ok2) throw Exception('Deck konnte nicht gespeichert werden');
  }

  // ------- Public API -------

  static Future<List<DeckMeta>> listDecks() async {
    final prefs = await _prefs;
    final ids = await _getIndex(prefs);
    final metas = <DeckMeta>[];

    for (final id in ids) {
      final metaStr = prefs.getString(_deckMetaKey(id));
      if (metaStr == null) continue;
      try {
        final m = jsonDecode(metaStr) as Map<String, dynamic>;
        metas.add(DeckMeta(
          id: m['id'] as String,
          title: m['title'] as String,
          cardCount: (m['cardCount'] as num).toInt(),
          createdAt: DateTime.parse(m['createdAt'] as String),
          updatedAt: DateTime.parse(m['updatedAt'] as String),
          unmatchedCount: (m['unmatchedCount'] as num?)?.toInt() ?? 0,
        ));
      } catch (_) {}
    }
    metas.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return metas;
  }

  static Future<Deck?> loadDeck(String id) async {
    final prefs = await _prefs;
    final jsonStr = prefs.getString(_deckKey(id));
    if (jsonStr == null) return null;
    try {
      return Deck.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<String> saveDeck({
    String? id,
    required String title,
    required List<Flashcard> cards,
    String? sourceName,
    List<Unmatched>? unmatched,
  }) {
    return _mutex.run(() async {
      final prefs = await _prefs;
      final now = DateTime.now();
      final deckId = id ?? _uuidV4();

      final deck = Deck(
        id: deckId,
        title: title,
        sourceName: sourceName,
        createdAt: now,
        updatedAt: now,
        cards: cards,
        unmatched: unmatched ?? const [],
      );

      await _writeDeckAndMeta(prefs, deck);

      final ids = await _getIndex(prefs);
      if (!ids.contains(deckId)) {
        ids.add(deckId);
        await _setIndex(prefs, ids);
      }
      return deckId;
    });
  }

  static Future<void> updateDeck(Deck deck) {
    return _mutex.run(() async {
      final prefs = await _prefs;
      final updated = deck.copyWith(updatedAt: DateTime.now());
      await _writeDeckAndMeta(prefs, updated);
    });
  }

  static Future<bool> renameDeck(String id, String newTitle) async {
    final deck = await loadDeck(id);
    if (deck == null) return false;
    await updateDeck(deck.copyWith(title: newTitle));
    return true;
  }

  static Future<void> deleteDeck(String id) {
    return _mutex.run(() async {
      final prefs = await _prefs;
      await prefs.remove(_deckKey(id));
      await prefs.remove(_deckMetaKey(id));
      final ids = await _getIndex(prefs);
      ids.removeWhere((e) => e == id);
      await _setIndex(prefs, ids);
    });
  }

  static Future<bool> upsertCard({
    required String deckId,
    required Flashcard card,
  }) async {
    final deck = await loadDeck(deckId);
    if (deck == null) return false;

    final idx = deck.cards.indexWhere((c) => c.id == card.id);
    final newCards = [...deck.cards];
    final inserted = idx < 0;

    if (inserted) {
      newCards.add(card);
    } else {
      newCards[idx] = card;
    }
    await updateDeck(deck.copyWith(cards: newCards));
    return inserted;
  }

  // ---------- Utilities ----------
  static String _uuidV4() {
    final rand = Random();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    bytes[6] = (bytes[6] & 0x0F) | 0x40; // version
    bytes[8] = (bytes[8] & 0x3F) | 0x80; // variant

    String b(int i) => bytes[i].toRadixString(16).padLeft(2, '0');
    return '${b(0)}${b(1)}${b(2)}${b(3)}-'
        '${b(4)}${b(5)}-'
        '${b(6)}${b(7)}-'
        '${b(8)}${b(9)}-'
        '${b(10)}${b(11)}${b(12)}${b(13)}${b(14)}${b(15)}';
  }
}

/// Web-sicherer Streaming-Writer: sammelt Karten/Notizen im Speicher
/// und speichert alles am Ende in SharedPreferences.
class StreamingDeckWriter {
  final String title;
  final String? sourceName;

  final List<Flashcard> _cards = [];
  final List<Unmatched> _notes = [];

  bool _finished = false;
  int _count = 0;
  int _notesCount = 0;

  StreamingDeckWriter._(this.title, this.sourceName);

  static Future<StreamingDeckWriter> begin({
    required String title,
    String? sourceName,
  }) async {
    return StreamingDeckWriter._(title, sourceName);
  }

  void appendCards(List<Flashcard> cards) {
    if (_finished || cards.isEmpty) return;
    _cards.addAll(cards);
    _count += cards.length;
  }

  void appendNotes(List<Unmatched> notes) {
    if (_finished || notes.isEmpty) return;
    _notes.addAll(notes);
    _notesCount += notes.length;
  }

  Future<String> finish() async {
    if (_finished) throw StateError('finish() wurde bereits aufgerufen.');
    _finished = true;

    return StorageService.saveDeck(
      title: title,
      cards: _cards,
      sourceName: sourceName,
      unmatched: _notes,
    );
  }

  int get cardCount => _count;
  int get unmatchedCount => _notesCount;
}

/// Very small in-process mutex.
class _Mutex {
  Future<void> _tail = Future.value();

  Future<T> run<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await action());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }
}
