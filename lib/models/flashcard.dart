class Flashcard {
  final String question;
  final String answer;
  final String? number;
  int correctCount;
  int wrongCount;

  Flashcard({
    required this.question,
    required this.answer,
    this.number,
    this.correctCount = 0,
    this.wrongCount = 0,
  });

  Map<String, dynamic> toJson() => {
    'question': question,
    'answer': answer,
    'number': number,
    'correctCount': correctCount,
    'wrongCount': wrongCount,
  };

  factory Flashcard.fromJson(Map<String, dynamic> j) => Flashcard(
    question: j['question'] ?? '',
    answer: j['answer'] ?? '',
    number: j['number'],
    correctCount: (j['correctCount'] ?? 0) as int,
    wrongCount: (j['wrongCount'] ?? 0) as int,
  );
}
