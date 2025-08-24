// lib/services/storage_service.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/deck.dart';
import '../models/flashcard.dart';
import '../models/unmatched.dart';

class StorageService {
  // Keys:
  static const _kIndex = 'decks_index';             // List<String> ids
  static String _deckKey(String id) => 'deck_$id';  // JSON

  // --- Index laden/speichern ---

  static Future<List<String>> _getIndex(SharedPreferences prefs) async {
    final list = prefs.getStringList(_kIndex);
    return list ?? <String>[];
  }

  static Future<void> _setIndex(SharedPreferences prefs, List<String> ids) async {
    await prefs.setStringList(_kIndex, ids);
  }

  // --- Öffentliche API ---

  static Future<List<DeckMeta>> listDecks() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = await _getIndex(prefs);

    final metas = <DeckMeta>[];
    for (final id in ids) {
      final jsonStr = prefs.getString(_deckKey(id));
      if (jsonStr == null) continue;
      try {
        final map = jsonDecode(jsonStr) as Map<String, dynamic>;
        final deck = Deck.fromJson(map);
        metas.add(DeckMeta(
          id: deck.id,
          title: deck.title,
          cardCount: deck.cardCount,
          createdAt: deck.createdAt,
          updatedAt: deck.updatedAt,
          unmatchedCount: deck.unmatched.isEmpty ? 0 : deck.unmatched.length,
        ));
      } catch (_) {
        // defektes Deck überspringen
      }
    }
    // Neuestes oben
    metas.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
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

  /// Neues Deck anlegen (z. B. nach PDF-Import)
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

  /// Ganzes Deck überschreiben (z. B. nach Lernfortschritt)
  static Future<void> updateDeck(Deck deck) async {
    final prefs = await SharedPreferences.getInstance();
    final updated = deck.copyWith(updatedAt: DateTime.now());
    final ok = await prefs.setString(_deckKey(deck.id), jsonEncode(updated.toJson()));
    if (!ok) {
      throw Exception('Deck-Update fehlgeschlagen');
    }
    // Index beibehalten
  }

  static Future<void> renameDeck(String id, String newTitle) async {
    final deck = await loadDeck(id);
    if (deck == null) return;
    final updated = deck.copyWith(title: newTitle, updatedAt: DateTime.now());
    await updateDeck(updated);
  }

  static Future<void> deleteDeck(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_deckKey(id));
    final ids = await _getIndex(prefs);
    ids.remove(id);
    await _setIndex(prefs, ids);
  }

  // Hilfsfunktion: einzelne Karte ersetzen (optional)
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
