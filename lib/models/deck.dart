import 'flashcard.dart';

class DeckMeta {
  final String id;
  final String title;
  final DateTime createdAt;
  final int cardCount;
  final String? sourceName;

  DeckMeta({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.cardCount,
    this.sourceName,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'cardCount': cardCount,
        'sourceName': sourceName,
      };

  factory DeckMeta.fromJson(Map<String, dynamic> json) => DeckMeta(
        id: json['id'] as String,
        title: json['title'] as String? ?? 'Unbenannt',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        cardCount: json['cardCount'] as int? ?? 0,
        sourceName: json['sourceName'] as String?,
      );
}

class Deck {
  final String id;
  final String title;
  final DateTime createdAt;
  final List<Flashcard> cards;
  final String? sourceName;

  Deck({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.cards,
    this.sourceName,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'cards': cards.map((c) => c.toJson()).toList(),
        'sourceName': sourceName,
      };

  factory Deck.fromJson(Map<String, dynamic> json) => Deck(
        id: json['id'] as String,
        title: json['title'] as String? ?? 'Unbenannt',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        cards: (json['cards'] as List? ?? [])
            .map((e) => Flashcard.fromJson(
                Map<String, dynamic>.from(e as Map)))
            .toList(),
        sourceName: json['sourceName'] as String?,
      );
}
