// lib/services/storage_service.dart
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
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

/// Streaming writer that keeps file sinks open during import to avoid
/// memory spikes. At finish(), it loads the NDJSON files and writes
/// the final deck into SharedPreferences (so your UI finds it as before).
class StreamingDeckWriter {
  final String title;
  final String? sourceName;
  final String deckId;

  late final Directory _tmpDir;
  late final File _cardsNdjson;
  late final File _notesNdjson;

  IOSink? _cardsSink;
  IOSink? _notesSink;

  bool _finished = false;
  int _count = 0;
  int _notes = 0;

  StreamingDeckWriter._(this.title, this.sourceName, this.deckId);

  static Future<StreamingDeckWriter> begin({
    required String title,
    String? sourceName,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final deckId = 'deck_$ts';

    final w = StreamingDeckWriter._(title, sourceName, deckId);
    w._tmpDir = Directory('${dir.path}/stream_$deckId')..createSync(recursive: true);
    w._cardsNdjson = File('${w._tmpDir.path}/cards.ndjson')..createSync(recursive: true);
    w._notesNdjson = File('${w._tmpDir.path}/notes.ndjson')..createSync(recursive: true);

    // open once & keep open
    w._cardsSink = w._cardsNdjson.openWrite(mode: FileMode.writeOnlyAppend);
    w._notesSink = w._notesNdjson.openWrite(mode: FileMode.writeOnlyAppend);
    return w;
  }

  void appendCards(List<Flashcard> cards) {
    if (_finished || cards.isEmpty) return;
    final s = _cardsSink;
    if (s == null) return;
    for (final c in cards) {
      s.writeln(jsonEncode({
        'id': c.id,
        'question': c.question,
        'answer': c.answer,
        'number': c.number,
      }));
      _count++;
    }
  }

  void appendNotes(List<Unmatched> notes) {
    if (_finished || notes.isEmpty) return;
    final s = _notesSink;
    if (s == null) return;
    for (final n in notes) {
      s.writeln(jsonEncode({
        'page': n.page,
        'reason': n.reason,
        'text': n.text,
      }));
      _notes++;
    }
  }

  /// Finalize:
  /// - close sinks
  /// - stream-read NDJSON → build lists
  /// - save via StorageService.saveDeck (SharedPreferences)
  /// - cleanup temp files
  Future<String> finish() async {
    if (_finished) return deckId;
    _finished = true;

    await _cardsSink?.flush();
    await _notesSink?.flush();
    await _cardsSink?.close();
    await _notesSink?.close();
    _cardsSink = null;
    _notesSink = null;

    // stream-read into objects (deck needs full list for SharedPrefs)
    final cards = <Flashcard>[];
    final notes = <Unmatched>[];

    if (_cardsNdjson.existsSync()) {
      final stream = _cardsNdjson.openRead().transform(utf8.decoder).transform(const LineSplitter());
      await for (final line in stream) {
        final ln = line.trim();
        if (ln.isEmpty) continue;
        final m = jsonDecode(ln) as Map<String, dynamic>;
        cards.add(Flashcard(
          id: m['id'] as String,
          question: m['question'] as String,
          answer: m['answer'] as String,
          number: m['number'] as String?,
        ));
      }
    }

    if (_notesNdjson.existsSync()) {
      final stream = _notesNdjson.openRead().transform(utf8.decoder).transform(const LineSplitter());
      await for (final line in stream) {
        final ln = line.trim();
        if (ln.isEmpty) continue;
        final m = jsonDecode(ln) as Map<String, dynamic>;
        notes.add(Unmatched(
          page: (m['page'] as num?)?.toInt() ?? 0,
          reason: m['reason'] as String? ?? '',
          text: m['text'] as String? ?? '',
        ));
      }
    }

    // Save to SharedPreferences so the rest of the app sees it
    final savedId = await StorageService.saveDeck(
      title: title,
      cards: cards,
      sourceName: sourceName,
      unmatched: notes,
    );

    // cleanup temp
    try {
      _cardsNdjson.deleteSync();
      _notesNdjson.deleteSync();
      _tmpDir.deleteSync(recursive: true);
    } catch (_) {}

    return savedId;
  }

  int get cardCount => _count;
  int get unmatchedCount => _notes;
}
