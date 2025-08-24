import 'flashcard.dart';

class ProgressUpdate {
  final int current; // verarbeitete Seiten
  final int total;   // Gesamtseiten
  final bool done;
  final List<Flashcard>? cards; // inkrementelle Karten
  final String? snippet;        // kurze Vorschau
  final String? debugMessage;   // Logtext

  ProgressUpdate({
    required this.current,
    required this.total,
    required this.done,
    this.cards,
    this.snippet,
    this.debugMessage,
  });
}
