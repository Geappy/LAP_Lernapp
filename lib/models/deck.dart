// lib/models/deck.dart
import 'flashcard.dart';
import 'unmatched.dart';

class Deck {
  final String id;
  final String title;
  final String? sourceName;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<Flashcard> cards;
  final List<Unmatched> unmatched; // "Notizen" / nicht zugeordnet

  const Deck({
    required this.id,
    required this.title,
    required this.cards,
    required this.createdAt,
    required this.updatedAt,
    this.sourceName,
    this.unmatched = const [],
  });

  Deck copyWith({
    String? id,
    String? title,
    String? sourceName,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<Flashcard>? cards,
    List<Unmatched>? unmatched,
  }) {
    return Deck(
      id: id ?? this.id,
      title: title ?? this.title,
      sourceName: sourceName ?? this.sourceName,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      cards: cards ?? this.cards,
      unmatched: unmatched ?? this.unmatched,
    );
  }

  int get cardCount => cards.length;

  // Verteilung für Lernmodus/Deck-Übersicht
  int get zeroCorrect => cards.where((c) => c.correctCount == 0).length;
  int get oneCorrect  => cards.where((c) => c.correctCount == 1).length;
  int get twoPlus     => cards.where((c) => c.correctCount >= 2).length;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'sourceName': sourceName,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'cards': cards.map((c) => c.toJson()).toList(),
        'unmatched': unmatched.map((u) => u.toJson()).toList(),
      };

  factory Deck.fromJson(Map<String, dynamic> json) => Deck(
        id: (json['id'] ?? '').toString(),
        title: (json['title'] ?? '').toString(),
        sourceName: json['sourceName'] == null ? null : json['sourceName'].toString(),
        createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()) ?? DateTime.now(),
        updatedAt: DateTime.tryParse((json['updatedAt'] ?? '').toString()) ?? DateTime.now(),
        cards: (json['cards'] as List<dynamic>? ?? const [])
            .map((e) => Flashcard.fromJson(e as Map<String, dynamic>))
            .toList(),
        unmatched: (json['unmatched'] as List<dynamic>? ?? const [])
            .map((e) => Unmatched.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

// Für Deck-Übersicht (ListView)
class DeckMeta {
  final String id;
  final String title;
  final int cardCount;
  final int? unmatchedCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  const DeckMeta({
    required this.id,
    required this.title,
    required this.cardCount,
    required this.createdAt,
    required this.updatedAt,
    this.unmatchedCount,
  });
}
