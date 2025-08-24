// lib/models/flashcard.dart
class Flashcard {
  final String id;          // stabil über Speichern/Laden
  final String question;
  final String answer;
  final String? number;

  final int correctCount;
  final int wrongCount;

  const Flashcard({
    required this.id,
    required this.question,
    required this.answer,
    this.number,
    this.correctCount = 0,
    this.wrongCount = 0,
  });

  Flashcard copyWith({
    String? id,
    String? question,
    String? answer,
    String? number,
    int? correctCount,
    int? wrongCount,
  }) {
    return Flashcard(
      id: id ?? this.id,
      question: question ?? this.question,
      answer: answer ?? this.answer,
      number: number ?? this.number,
      correctCount: correctCount ?? this.correctCount,
      wrongCount: wrongCount ?? this.wrongCount,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'question': question,
        'answer': answer,
        'number': number,
        'correctCount': correctCount,
        'wrongCount': wrongCount,
      };

  factory Flashcard.fromJson(Map<String, dynamic> json) => Flashcard(
        id: (json['id'] ?? '').toString(),
        question: (json['question'] ?? '').toString(),
        answer: (json['answer'] ?? '').toString(),
        number: json['number'] == null ? null : json['number'].toString(),
        correctCount: (json['correctCount'] ?? 0) as int,
        wrongCount: (json['wrongCount'] ?? 0) as int,
      );
}
