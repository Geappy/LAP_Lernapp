import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/deck.dart';
import '../models/flashcard.dart';

class StorageService {
  static const _kIndexKey = 'decks_index';
  static String _deckKey(String id) => 'deck:$id';

  // ---------- ID/Random ----------
  static final _rng = Random();
  static const _alphabet = 'abcdefghjkmnpqrstuvwxyz23456789';
  static String _rand(int len) {
    final b = StringBuffer();
    for (int i = 0; i < len; i++) {
      b.write(_alphabet[_rng.nextInt(_alphabet.length)]);
    }
    return b.toString();
  }

  static String _makeId() {
    final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    return '$ts-${_rand(8)}';
  }

  // ---------- Large String (Chunking) ----------
  static const int _chunkSize = 512 * 1024; // 512 KB

  static Future<bool> _setLargeString(
      SharedPreferences prefs, String key, String value) async {
    await _removeLargeString(prefs, key);

    if (value.length <= _chunkSize) {
      return prefs.setString(key, value);
    }

    final chunks = (value.length / _chunkSize).ceil();
    if (!await prefs.setInt('$key:chunks', chunks)) return false;

    for (int i = 0; i < chunks; i++) {
      final start = i * _chunkSize;
      final end = (start + _chunkSize < value.length)
          ? start + _chunkSize
          : value.length;
      final ok = await prefs.setString('$key:$i', value.substring(start, end));
      if (!ok) {
        await _removeLargeString(prefs, key);
        return false;
      }
    }
    return true;
  }

  static Future<String?> _getLargeString(
      SharedPreferences prefs, String key) async {
    final chunks = prefs.getInt('$key:chunks');
    if (chunks == null) return prefs.getString(key);

    final buf = StringBuffer();
    for (int i = 0; i < chunks; i++) {
      final part = prefs.getString('$key:$i');
      if (part == null) return null;
      buf.write(part);
    }
    return buf.toString();
  }

  static Future<void> _removeLargeString(
      SharedPreferences prefs, String key) async {
    final chunks = prefs.getInt('$key:chunks');
    if (chunks != null) {
      for (int i = 0; i < chunks; i++) {
        await prefs.remove('$key:$i');
      }
      await prefs.remove('$key:chunks');
    }
    await prefs.remove(key);
  }

  // ---------- Self-Heal (falls Index fehlt/korrupt ist) ----------
  static Future<void> _selfHealIndex(SharedPreferences prefs) async {
    final keys = prefs.getKeys();
    final ids = <String>{};

    // Decks erkennen: entweder kleiner Single-Key ("deck:<id>")
    // oder Chunked ("deck:<id>:chunks")
    for (final k in keys) {
      if (k.startsWith('deck:')) {
        if (k.endsWith(':chunks')) {
          final id = k.substring(5, k.length - ':chunks'.length);
          ids.add(id);
        } else if (!k.contains(':')) {
          ids.add(k.substring(5));
        }
      }
    }

    final metas = <Map<String, dynamic>>[];
    for (final id in ids) {
      final raw = await _getLargeString(prefs, _deckKey(id));
      if (raw == null) continue;
      try {
        final deck = Deck.fromJson(jsonDecode(raw));
        metas.add({
          'id': deck.id,
          'title': deck.title,
          'createdAt': deck.createdAt.toIso8601String(),
          'cardCount': deck.cards.length,
          'sourceName': deck.sourceName,
        });
      } catch (e) {
        // ignore: avoid_print
        print('Self-heal: Konnte Deck $id nicht lesen: $e');
      }
    }

    await _setLargeString(prefs, _kIndexKey, jsonEncode(metas));
  }

  // ---------- Public API ----------
  static Future<String> saveDeck({
    required String title,
    required List<Flashcard> cards,
    String? sourceName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (cards.isEmpty) throw Exception('Keine Karten – nichts zu speichern.');

    final id = _makeId();
    final deck = Deck(
      id: id,
      title: title.isEmpty ? 'Karteikarten' : title,
      createdAt: DateTime.now(),
      cards: cards,
      sourceName: sourceName,
    );

    final okDeck = await _setLargeString(prefs, _deckKey(id), jsonEncode(deck.toJson()));
    if (!okDeck) {
      throw Exception('Deck-Daten konnten nicht gespeichert werden (Quota?).');
    }

    final indexRaw = await _getLargeString(prefs, _kIndexKey);
    final List list = (indexRaw == null || indexRaw.isEmpty)
        ? <dynamic>[]
        : (jsonDecode(indexRaw) as List);

    list.insert(0, {
      'id': id,
      'title': deck.title,
      'createdAt': deck.createdAt.toIso8601String(),
      'cardCount': cards.length,
      'sourceName': sourceName,
    });

    final okIndex = await _setLargeString(prefs, _kIndexKey, jsonEncode(list));
    if (!okIndex) {
      await _removeLargeString(prefs, _deckKey(id)); // rollback
      throw Exception('Index konnte nicht aktualisiert werden (Quota?).');
    }

    // Sanity-Check
    final exists = (await listDecks()).any((m) => m.id == id);
    if (!exists) throw Exception('Deck gespeichert, aber nicht im Index gefunden.');
    return id;
  }

  static Future<List<DeckMeta>> listDecks() async {
    final prefs = await SharedPreferences.getInstance();
    String? indexRaw = await _getLargeString(prefs, _kIndexKey);

    if (indexRaw == null || indexRaw.isEmpty) {
      // Versuch Index zu reparieren
      await _selfHealIndex(prefs);
      indexRaw = await _getLargeString(prefs, _kIndexKey);
      if (indexRaw == null || indexRaw.isEmpty) return [];
    }

    try {
      final List data = jsonDecode(indexRaw);
      return data.map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        return DeckMeta(
          id: m['id'] as String,
          title: m['title'] as String,
          createdAt: DateTime.parse(m['createdAt'] as String),
          cardCount: (m['cardCount'] as num).toInt(),
          sourceName: m['sourceName'] as String?,
        );
      }).toList();
    } catch (e) {
      // ignore: avoid_print
      print('Index-Parsefehler: $e');
      return [];
    }
  }

  static Future<Deck?> loadDeck(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = await _getLargeString(prefs, _deckKey(id));
    if (raw == null) return null;
    try {
      return Deck.fromJson(jsonDecode(raw));
    } catch (e) {
      // ignore: avoid_print
      print('Deck-Parsefehler ($id): $e');
      return null;
    }
  }

  static Future<void> renameDeck(String id, String newTitle) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = await _getLargeString(prefs, _deckKey(id));
    if (raw == null) throw Exception('Deck nicht gefunden.');

    final old = Deck.fromJson(jsonDecode(raw));
    final updated = Deck(
      id: old.id,
      title: newTitle,
      createdAt: old.createdAt,
      cards: old.cards,
      sourceName: old.sourceName,
    );

    final okDeck = await _setLargeString(prefs, _deckKey(id), jsonEncode(updated.toJson()));
    if (!okDeck) throw Exception('Titel konnte nicht gespeichert werden.');

    final indexRaw = await _getLargeString(prefs, _kIndexKey);
    if (indexRaw == null || indexRaw.isEmpty) {
      await _selfHealIndex(prefs);
    } else {
      final List data = jsonDecode(indexRaw);
      for (final e in data) {
        if (e is Map && e['id'] == id) {
          e['title'] = newTitle;
          break;
        }
      }
      await _setLargeString(prefs, _kIndexKey, jsonEncode(data));
    }
  }

  static Future<void> deleteDeck(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await _removeLargeString(prefs, _deckKey(id));

    final indexRaw = await _getLargeString(prefs, _kIndexKey);
    if (indexRaw == null || indexRaw.isEmpty) return;
    final List data = jsonDecode(indexRaw);
    data.removeWhere((e) => e is Map && e['id'] == id);
    await _setLargeString(prefs, _kIndexKey, jsonEncode(data));
  }

  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    final metas = await listDecks();
    for (final m in metas) {
      await _removeLargeString(prefs, _deckKey(m.id));
    }
    await _removeLargeString(prefs, _kIndexKey);
  }
}
