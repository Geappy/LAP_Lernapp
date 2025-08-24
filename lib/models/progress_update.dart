// lib/models/progress_update.dart
import 'package:meta/meta.dart';
import 'flashcard.dart';
import 'unmatched.dart';

@immutable
class ProgressUpdate {
  final int current; // aktuelle Seite (1-basiert), bei Start 0
  final int total;   // Gesamtseiten
  final bool done;

  final List<Flashcard>? cards;       // inkrementell gefundene Karten
  final List<Unmatched>? unmatched;   // inkrementell gefundene "Notizen"
  final String? snippet;              // kurzer Vorschau-Text
  final String? debugMessage;         // für UI/Console

  const ProgressUpdate({
    required this.current,
    required this.total,
    required this.done,
    this.cards,
    this.unmatched,
    this.snippet,
    this.debugMessage,
  });
}
