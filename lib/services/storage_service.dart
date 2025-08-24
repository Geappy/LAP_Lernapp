import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/deck.dart';
import '../models/flashcard.dart';

class StorageService {
  static const _kMetaKey = 'decks:index'; // JSON array of DeckMeta
  static String _deckKey(String id) => 'deck:$id';

  /// List index of decks
  static Future<List<DeckMeta>> listDecks() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_kMetaKey);
    if (s == null || s.isEmpty) return [];
    try {
      return Deck.decodeMetaList(s);
    } catch (_) {
      return [];
    }
  }

  /// Save a new deck and add to index
  static Future<Deck> saveDeck({
    required String title,
    required List<Flashcard> cards,
    String? sourceName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final id = DateTime.now().millisecondsSinceEpoch.toString();

    final deck = Deck(id: id, title: title, sourceName: sourceName, cards: cards);

    // write deck
    await prefs.setString(_deckKey(deck.id), jsonEncode(deck.toJson()));

    // update index
    final existing = await listDecks();
    final updated = [deck.toMeta(), ...existing];
    await prefs.setString(_kMetaKey, Deck.encodeMetaList(updated));

    return deck;
    }

  /// Load full deck by id
  static Future<Deck?> loadDeck(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_deckKey(id));
    if (s == null) return null;
    return Deck.fromJson(jsonDecode(s) as Map<String, dynamic>);
  }

  /// Persist modified deck
  static Future<void> updateDeck(Deck deck) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_deckKey(deck.id), jsonEncode(deck.toJson()));

    // also keep meta in sync (title/count might change)
    final list = await listDecks();
    final idx = list.indexWhere((m) => m.id == deck.id);
    if (idx != -1) {
      list[idx] = deck.toMeta();
      await prefs.setString(_kMetaKey, Deck.encodeMetaList(list));
    }
  }

  static Future<void> renameDeck(String id, String newTitle) async {
    final deck = await loadDeck(id);
    if (deck == null) return;
    deck.title = newTitle;
    await updateDeck(deck);
  }

  static Future<void> deleteDeck(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_deckKey(id));

    final list = await listDecks();
    list.removeWhere((m) => m.id == id);
    await prefs.setString(_kMetaKey, Deck.encodeMetaList(list));
  }
}
