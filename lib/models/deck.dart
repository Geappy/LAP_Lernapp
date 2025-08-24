import 'dart:convert';
import 'flashcard.dart';

class DeckMeta {
  final String id;
  final String title;
  final int cardCount;
  final DateTime createdAt;

  const DeckMeta({
    required this.id,
    required this.title,
    required this.cardCount,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'count': cardCount,
        'createdAt': createdAt.toIso8601String(),
      };

  factory DeckMeta.fromJson(Map<String, dynamic> j) => DeckMeta(
        id: j['id'] as String,
        title: j['title'] as String? ?? 'Karteikarten',
        cardCount: j['count'] as int? ?? 0,
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
      );
}

class Deck {
  final String id;
  String title;
  final String? sourceName;
  final DateTime createdAt;
  final List<Flashcard> cards;

  Deck({
    required this.id,
    required this.title,
    required this.cards,
    this.sourceName,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'source': sourceName,
        'createdAt': createdAt.toIso8601String(),
        'cards': cards.map((c) => c.toJson()).toList(),
      };

  factory Deck.fromJson(Map<String, dynamic> j) => Deck(
        id: j['id'] as String,
        title: j['title'] as String? ?? 'Karteikarten',
        sourceName: j['source'] as String?,
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
        cards: (j['cards'] as List<dynamic>? ?? const [])
            .map((e) => Flashcard.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  DeckMeta toMeta() => DeckMeta(
        id: id,
        title: title,
        cardCount: cards.length,
        createdAt: createdAt,
      );

  static String encodeMetaList(List<DeckMeta> list) =>
      jsonEncode(list.map((e) => e.toJson()).toList());

  static List<DeckMeta> decodeMetaList(String s) {
    final raw = jsonDecode(s) as List<dynamic>;
    return raw.map((e) => DeckMeta.fromJson(e as Map<String, dynamic>)).toList();
  }
}
