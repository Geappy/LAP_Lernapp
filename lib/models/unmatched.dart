// lib/models/unmatched.dart
class Unmatched {
  final int page;        // 1-basierte Seitennummer
  final String reason;   // z.B. "Frage ohne Antwort"
  final String text;     // kurzer Ausschnitt

  Unmatched({
    required this.page,
    required this.reason,
    required this.text,
  });

  Map<String, dynamic> toJson() => {
        'page': page,
        'reason': reason,
        'text': text,
      };

  factory Unmatched.fromJson(Map<String, dynamic> json) => Unmatched(
        page: (json['page'] ?? 0) as int,
        reason: (json['reason'] ?? '') as String,
        text: (json['text'] ?? '') as String,
      );
}
