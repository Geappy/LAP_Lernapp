// lib/services/storage_service.dart
import 'dart:convert';
// Wichtig: KEIN dart:io und KEIN path_provider hier – das bricht auf Web!
// import 'dart:io';
// import 'package:path_provider/path_provider.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/deck.dart';
import '../models/flashcard.dart';
import '../models/unmatched.dart';

class StorageService {
  // Keys for SharedPreferences
  static const _kIndex = 'decks_index'; // List<String> ids
  static String _deckKey(String id) => 'deck_$id'; // String (JSON)

  static Future<List<String>> _getIndex(SharedPreferences prefs) async {
    final list = prefs.getStringList(_kIndex);
    return list ?? <String>[];
  }

  static Future<void> _setIndex(SharedPreferences prefs, List<String> ids) async {
    await prefs.setStringList(_kIndex, ids);
  }

  // -------- Public API --------

  static Future<List<DeckMeta>> listDecks() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = await _getIndex(prefs);

    final metas = <DeckMeta>[];
    for (final id in ids) {
      final jsonStr = prefs.getString(_deckKey(id));
      if (jsonStr == null) continue;
      try {
        final deck = Deck.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
        metas.add(DeckMeta(
          id: deck.id,
          title: deck.title,
          cardCount: deck.cardCount,
          createdAt: deck.createdAt,
          updatedAt: deck.updatedAt,
          unmatchedCount: deck.unmatched.isEmpty ? 0 : deck.unmatched.length,
        ));
      } catch (_) {
        // skip broken deck entry
      }
    }
    metas.sort((a, b) => b.updatedAt.compareTo(a.updatedAt)); // newest first
    return metas;
  }

  static Future<Deck?> loadDeck(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_deckKey(id));
    if (jsonStr == null) return null;
    try {
      return Deck.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Saves a whole deck (used by non-streaming imports or after edits)
  static Future<String> saveDeck({
    required String title,
    required List<Flashcard> cards,
    String? sourceName,
    List<Unmatched>? unmatched,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final id = now.millisecondsSinceEpoch.toString();

    final deck = Deck(
      id: id,
      title: title,
      sourceName: sourceName,
      createdAt: now,
      updatedAt: now,
      cards: cards,
      unmatched: unmatched ?? const [],
    );

    final ok = await prefs.setString(_deckKey(id), jsonEncode(deck.toJson()));
    if (!ok) {
      throw Exception('Deck konnte nicht gespeichert werden');
    }

    final ids = await _getIndex(prefs);
    ids.add(id);
    await _setIndex(prefs, ids);
    return id;
  }

  static Future<void> updateDeck(Deck deck) async {
    final prefs = await SharedPreferences.getInstance();
    final updated = deck.copyWith(updatedAt: DateTime.now());
    final ok = await prefs.setString(_deckKey(updated.id), jsonEncode(updated.toJson()));
    if (!ok) {
      throw Exception('Deck-Update fehlgeschlagen');
    }
  }

  static Future<void> renameDeck(String id, String newTitle) async {
    final deck = await loadDeck(id);
    if (deck == null) return;
    await updateDeck(deck.copyWith(title: newTitle, updatedAt: DateTime.now()));
  }

  static Future<void> deleteDeck(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_deckKey(id));
    final ids = await _getIndex(prefs);
    ids.remove(id);
    await _setIndex(prefs, ids);
  }

  static Future<void> upsertCard({
    required String deckId,
    required Flashcard card,
  }) async {
    final deck = await loadDeck(deckId);
    if (deck == null) return;
    final idx = deck.cards.indexWhere((c) => c.id == card.id);
    final newCards = [...deck.cards];
    if (idx >= 0) {
      newCards[idx] = card;
    } else {
      newCards.add(card);
    }
    await updateDeck(deck.copyWith(cards: newCards));
  }
}

///
/// Web-sichere Streaming-Variante ohne Dateien:
/// - sammelt Karten/Notizen im Speicher
/// - schreibt am Ende das komplette Deck in SharedPreferences
///
/// API kompatibel zu deiner bisherigen Nutzung.
///
class StreamingDeckWriter {
  final String title;
  final String? sourceName;
  final String deckId;

  final List<Flashcard> _cards = [];
  final List<Unmatched> _notes = [];

  bool _finished = false;
  int _count = 0;
  int _notesCount = 0;

  StreamingDeckWriter._(this.title, this.sourceName, this.deckId);

  static Future<StreamingDeckWriter> begin({
    required String title,
    String? sourceName,
  }) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final deckId = 'deck_$ts';
    return StreamingDeckWriter._(title, sourceName, deckId);
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

  /// Finalize:
  /// - save via StorageService.saveDeck (SharedPreferences)
  Future<String> finish() async {
    if (_finished) return deckId;
    _finished = true;

    final savedId = await StorageService.saveDeck(
      title: title,
      cards: _cards,
      sourceName: sourceName,
      unmatched: _notes,
    );

    return savedId;
  }

  int get cardCount => _count;
  int get unmatchedCount => _notesCount;
}
