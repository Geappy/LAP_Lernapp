class Flashcard {
  final String question;
  final String answer;
  final String? number;

  Flashcard({required this.question, required this.answer, this.number});

  Map<String, dynamic> toJson() => {
        'q': question,
        'a': answer,
        'n': number,
      };

  factory Flashcard.fromJson(Map<String, dynamic> json) => Flashcard(
        question: json['q'] as String? ?? '',
        answer: json['a'] as String? ?? '',
        number: json['n'] as String?,
      );
}
