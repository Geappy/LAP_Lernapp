import 'dart:math';
import 'dart:typed_data';

import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../models/flashcard.dart';
import '../models/progress_update.dart';

class PdfParser {
  /// Streamt Fortschritt + Karten in kleinen Häppchen.
  static Stream<ProgressUpdate> parseWithProgress(dynamic platformFile) async* {
    final Uint8List? bytes = platformFile.bytes as Uint8List?;
    if (bytes == null) {
      throw Exception(
        'Keine Bytes im FilePicker-Result. Aktiviere withData:true beim FilePicker.',
      );
    }

    int totalPages = 0;
    try {
      final probe = PdfDocument(inputBytes: bytes);
      totalPages = probe.pages.count;
      probe.dispose();
    } catch (_) {}

    if (totalPages <= 0) {
      yield ProgressUpdate(current: 0, total: 0, done: true,
          debugMessage: 'Keine Seiten gefunden.');
      return;
    }

    yield ProgressUpdate(
      current: 0,
      total: totalPages,
      done: false,
      debugMessage: '🔍 PDF geladen: $totalPages Seiten',
    );

    const int batchSize = 8;
    String carry = '';
    int emitted = 0;

    for (int start = 0; start < totalPages; start += batchSize) {
      final end = min(start + batchSize, totalPages);

      late PdfDocument doc;
      try {
        doc = PdfDocument(inputBytes: bytes);
      } catch (e) {
        yield ProgressUpdate(
          current: start,
          total: totalPages,
          done: true,
          debugMessage: 'PDF konnte im Batch nicht geöffnet werden: $e',
        );
        return;
      }

      try {
        final extractor = PdfTextExtractor(doc);
        for (int i = start; i < end; i++) {
          String pageText = '';
          try {
            pageText = extractor.extractText(
              startPageIndex: i,
              endPageIndex: i,
            );
          } catch (e) {
            yield ProgressUpdate(
              current: i + 1,
              total: totalPages,
              done: false,
              debugMessage: '⚠️ Seite ${i + 1} übersprungen: $e',
            );
            await Future.delayed(Duration.zero);
            continue;
          }

          final combined =
              _normalize(carry.isEmpty ? pageText : ('$carry\n$pageText'));

          final parsed = _parsePage(combined);
          carry = parsed.carry;

          if (parsed.cards.isNotEmpty) {
            emitted += parsed.cards.length;
            yield ProgressUpdate(
              current: i + 1,
              total: totalPages,
              done: false,
              cards: parsed.cards,
              snippet: _previewSnippet(parsed.cards.first),
              debugMessage:
                  '✅ Seite ${i + 1}/$totalPages → +${parsed.cards.length} Karten (gesamt $emitted)',
            );
          } else {
            yield ProgressUpdate(
              current: i + 1,
              total: totalPages,
              done: false,
              debugMessage:
                  '➡️  Seite ${i + 1}/$totalPages → keine neue Karte, weiter …',
            );
          }

          await Future.delayed(Duration.zero);
        }
      } finally {
        doc.dispose();
      }
    }

    if (carry.trim().isNotEmpty) {
      final last = _parsePage(carry);
      if (last.cards.isNotEmpty) {
        emitted += last.cards.length;
        yield ProgressUpdate(
          current: totalPages,
          total: totalPages,
          done: false,
          cards: last.cards,
          snippet: _previewSnippet(last.cards.first),
          debugMessage:
              '🧩 Abschluss-Extraktion → +${last.cards.length} Karten (gesamt $emitted)',
        );
      }
    }

    yield ProgressUpdate(
      current: totalPages,
      total: totalPages,
      done: true,
      debugMessage: 'Fertig. Insgesamt $emitted Karten.',
    );
  }

  static String _normalize(String s) {
    s = s.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    s = s.replaceAll(
      RegExp(r'^\s*Seite\s+\d+\s*/\s*\d+\s*$', multiLine: true),
      '',
    );
    return s;
    }

  static _PageParseResult _parsePage(String text) {
    final cards = <Flashcard>[];
    String carryOut = '';

    final qa = RegExp(
      r'(?:^|\n)\s*(?:Nr\.\s*[0-9]{1,4}[^\n]*\n+)?\s*Frage\s*\n+(.+?)\n+Antwort\s*\n+(.+?)(?=\n\s*(?:Nr\.|Frage\s*\n)|$)',
      caseSensitive: false,
      multiLine: true,
      dotAll: true,
    );

    for (final m in qa.allMatches(text)) {
      final q = (m.group(1) ?? '').trim();
      final a = (m.group(2) ?? '').trim();

      String? number;
      final prefixStart = max(0, m.start - 80);
      final prefix = text.substring(prefixStart, m.start);
      final n = RegExp(r'Nr\.\s*([0-9]{1,4})').firstMatch(prefix);
      if (n != null) number = 'Nr. ${n.group(1)}';

      if (q.isNotEmpty || a.isNotEmpty) {
        cards.add(Flashcard(question: q, answer: a, number: number));
      }
    }

    final lastFrage =
        RegExp(r'(Frage\s*\n+.+)$', caseSensitive: false, dotAll: true);
    final lastMatch = lastFrage.firstMatch(text);
    if (lastMatch != null) {
      final tail = lastMatch.group(1) ?? '';
      if (!RegExp(r'\n\s*Antwort\s*\n', caseSensitive: false).hasMatch(tail)) {
        carryOut = tail;
      }
    }

    final seen = <String>{};
    final unique = <Flashcard>[];
    for (final c in cards) {
      final k = '${c.question}\u0000${c.answer}';
      if (seen.add(k)) unique.add(c);
    }

    return _PageParseResult(unique, carryOut);
  }

  static String _previewSnippet(Flashcard c) {
    final s = c.question.isNotEmpty ? c.question : c.answer;
    return s.length <= 80 ? s : '${s.substring(0, 77)}…';
  }
}

class _PageParseResult {
  final List<Flashcard> cards;
  final String carry;
  _PageParseResult(this.cards, this.carry);
}
