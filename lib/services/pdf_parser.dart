// lib/services/pdf_parser.dart
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../models/flashcard.dart';
import '../models/progress_update.dart';
import '../models/unmatched.dart';

/// Robuster Parser:
/// - verarbeitet Seiten in Batches (RAM-schonend)
/// - erkennt "Frage"/"Antwort" mit/ohne Doppelpunkt, auch in derselben Zeile
/// - trägt "carry" über Seite X -> X+1, wenn Frage/Antwort überläuft
/// - sammelt "Unmatched" (Frage ohne Antwort, Antwort ohne Frage)
class PdfParser {
  static Stream<ProgressUpdate> parseWithProgress(dynamic platformFile) async* {
    final Uint8List? bytes = platformFile.bytes as Uint8List?;
    if (bytes == null) {
      throw Exception(
        'Keine Bytes im FilePicker-Result. Aktiviere withData:true beim FilePicker.',
      );
    }

    // Seiten zählen (Mini-Open)
    int totalPages = 0;
    try {
      final probe = PdfDocument(inputBytes: bytes);
      totalPages = probe.pages.count;
      probe.dispose();
    } catch (_) {
      totalPages = 0;
    }

    if (totalPages == 0) {
      yield ProgressUpdate(
        current: 0,
        total: 0,
        done: true,
        debugMessage: 'Keine Seiten gefunden.',
      );
      return;
    }

    yield ProgressUpdate(
      current: 0,
      total: totalPages,
      done: false,
      debugMessage: '🔍 PDF geladen: $totalPages Seiten',
    );

    const int batchSize = 8;
    int emittedCards = 0;

    // "carry" – offener Block über Seitenumbruch (z. B. Frage ohne Antwort)
    String carryText = '';
    String? carryLabel; // "Frage" oder "Antwort" (praktisch nur "Frage")

    // Für spätere Speicherung (wird am Ende komplett mitgegeben)
    final List<Unmatched> allUnmatched = [];

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
          final pageNo = i + 1;

          String pageText;
          try {
            pageText = extractor.extractText(
              startPageIndex: i,
              endPageIndex: i,
            );
          } catch (e) {
            // Seite überspringen
            allUnmatched.add(Unmatched(
              page: pageNo,
              reason: 'Seite übersprungen (Fehler beim Extrahieren)',
              text: '$e',
            ));
            yield ProgressUpdate(
              current: pageNo,
              total: totalPages,
              done: false,
              unmatched: [allUnmatched.last],
              debugMessage: '⚠️ Seite $pageNo übersprungen: $e',
            );
            await Future.delayed(Duration.zero);
            continue;
          }

          final combined = _normalize(
            [
              if (carryLabel != null) '${carryLabel}\n$carryText',
              pageText,
            ].where((s) => s.isNotEmpty).join('\n'),
          );

          final result = _parseCombined(combined, pageNo: pageNo);

          // Karten sofort streamen
          if (result.cards.isNotEmpty) {
            emittedCards += result.cards.length;
            yield ProgressUpdate(
              current: pageNo,
              total: totalPages,
              done: false,
              cards: result.cards,
              snippet: _previewSnippet(result.cards.first),
              debugMessage:
                  '✅ Seite $pageNo/$totalPages → +${result.cards.length} Karten (gesamt $emittedCards)',
            );
          } else {
            yield ProgressUpdate(
              current: pageNo,
              total: totalPages,
              done: false,
              debugMessage: '➡️  Seite $pageNo/$totalPages → keine neue Karte, weiter …',
            );
          }

          // Unmatched aus dieser Seite sammeln (ohne Carry – das ist ja offen)
          if (result.unmatched.isNotEmpty) {
            allUnmatched.addAll(result.unmatched);
            yield ProgressUpdate(
              current: pageNo,
              total: totalPages,
              done: false,
              unmatched: result.unmatched,
              debugMessage:
                  'ℹ️  Seite $pageNo → ${result.unmatched.length} nicht zugeordnete Blöcke protokolliert',
            );
          }

          // neuen Carry setzen (falls nötig)
          carryLabel = result.carryLabel;
          carryText = result.carryText;

          await Future.delayed(Duration.zero);
        }
      } finally {
        doc.dispose();
      }
    }

    // Abschluss: offener Carry wird als Unmatched protokolliert
    if (carryLabel != null && carryText.trim().isNotEmpty) {
      final u = Unmatched(
        page: totalPages,
        reason: '$carryLabel ohne Partner (Dokumentende)',
        text: _shorten(carryText),
      );
      allUnmatched.add(u);
      yield ProgressUpdate(
        current: totalPages,
        total: totalPages,
        done: false,
        unmatched: [u],
        debugMessage: '🧩 Abschluss: offener $carryLabel → als Unmatched gespeichert',
      );
    }

    // Fertig – gesamtes Unmatched mitschicken, damit der Aufrufer es speichern kann
    yield ProgressUpdate(
      current: totalPages,
      total: totalPages,
      done: true,
      unmatched: allUnmatched,
      debugMessage:
          'Fertig. Insgesamt $emittedCards Karten, ${allUnmatched.length} Notizen.',
    );
  }

  // ---------- Parsing in Segmente (Frage/Antwort) ----------

  // Wir zerteilen in Blöcke "Label + Inhalt". Label ist "Frage" oder "Antwort"
  // (mit/ohne Doppelpunkt; Inhalt kann in derselben Zeile starten).
  static final RegExp _labelBlock = RegExp(
    r'(?:(?:^|\n)\s*)(?:Nr\.\s*\d+[^\n]*\n\s*)?' // optionale "Nr. 12" vor dem Label
    r'(Frage|Antwort)\s*:?\s*'                   // Label, optionaler Doppelpunkt
    r'(.*?)(?=(?:\n\s*(?:Nr\.\s*\d+\s*)?(?:Frage|Antwort)\s*:?\s*)|$)', // bis zum nächsten Label/Ende
    caseSensitive: false,
    dotAll: true,
    multiLine: true,
  );

  static _ParseResult _parseCombined(String combined, {required int pageNo}) {
    final cards = <Flashcard>[];
    final unmatched = <Unmatched>[];

    // Silbentrennungen entschärfen (z. B. "Schaden-\nersatz" → "Schadenersatz")
    final text = combined.replaceAll(RegExp(r'(\w)-\n(\w)'), r'$1$2');

    final blocks = _labelBlock.allMatches(text).map((m) {
      final label = (m.group(1) ?? '').trim().toLowerCase(); // frage/antwort
      final body = (m.group(2) ?? '').trim();
      // Prüfe "Nr." in einem Fenster vor dem Match
      String? number;
      final prefixStart = max(0, m.start - 100);
      final prefix = text.substring(prefixStart, m.start);
      final n = RegExp(r'Nr\.\s*([0-9]{1,5})').firstMatch(prefix);
      if (n != null) number = 'Nr. ${n.group(1)}';
      return _Block(label: label, body: body, number: number);
    }).toList();

    // Sequenziell: "frage" → "antwort" → Karte
    int i = 0;
    while (i < blocks.length) {
      final b = blocks[i];
      if (b.label == 'frage') {
        if (i + 1 < blocks.length && blocks[i + 1].label == 'antwort') {
          final q = _cleanQA(blocks[i].body);
          final a = _cleanQA(blocks[i + 1].body);
          if (q.isNotEmpty || a.isNotEmpty) {
            final id = _makeCardId(blocks[i].number, q, a);
            cards.add(Flashcard(
              id: id,
              question: q,
              answer: a,
              number: blocks[i].number ?? blocks[i + 1].number,
            ));
          }
          i += 2;
          continue;
        } else {
          // Frage ohne Antwort → als Carry zurückgeben (nicht unmatched!)
          final carryLabel = 'Frage';
          final carryText = blocks[i].body;
          return _ParseResult(
            cards: cards,
            unmatched: unmatched,
            carryLabel: carryLabel,
            carryText: carryText,
          );
        }
      } else if (b.label == 'antwort') {
        // Antwort ohne vorausgehende Frage → unmatched protokollieren
        unmatched.add(Unmatched(
          page: pageNo,
          reason: 'Antwort ohne Frage',
          text: _shorten(b.body),
        ));
        i += 1;
        continue;
      } else {
        // unbekanntes Label (sollte nicht vorkommen)
        unmatched.add(Unmatched(
          page: pageNo,
          reason: 'Unbekanntes Label',
          text: _shorten(b.body),
        ));
        i += 1;
      }
    }

    // kein offener Carry
    return _ParseResult(
      cards: cards,
      unmatched: unmatched,
    );
  }

  // ---------- Normalisierung / Utilities ----------

  static String _normalize(String s) {
    // Zeilenenden vereinheitlichen
    s = s.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    // offensichtliche Header/Footer ("Seite X / Y", Seitenzahl allein, etc.)
    s = s.replaceAll(
      RegExp(r'^\s*Seite\s+\d+\s*/\s*\d+\s*$', multiLine: true),
      '',
    );
    s = s.replaceAll(RegExp(r'^\s*\d+\s*$',
        multiLine: true), ''); // nackte Seitenzahlen am Zeilenanfang

    // Mehrfachleerräume eindampfen
    s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    return s.trim();
  }

  static String _cleanQA(String s) {
    // Aufzählungsreste, doppelte Leerzeilen, unnötige Whitespaces
    s = s.replaceAll(RegExp(r'\s+\n'), '\n');
    s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return s.trim();
  }

  static String _previewSnippet(Flashcard c) {
    final s = c.question.isNotEmpty ? c.question : c.answer;
    return s.length <= 80 ? s : '${s.substring(0, 77)}…';
  }

  static String _shorten(String s) {
    s = s.trim();
    if (s.length <= 160) return s;
    return '${s.substring(0, 157)}…';
  }

  /// Stabile, deterministische ID aus (Nr., Frage, Antwort) — Web-sicher (BigInt).
  static String _makeCardId(String? number, String q, String a) {
    final input = '${number ?? ''}\n$q\n$a';
    return _fnv64Hex(input);
  }

  /// 64-bit FNV-1a als Hex-String, implementiert mit BigInt (kompatibel mit Flutter Web).
  static String _fnv64Hex(String s) {
    final BigInt mask64 = BigInt.parse('0xFFFFFFFFFFFFFFFF');
    BigInt hash = BigInt.parse('0xcbf29ce484222325'); // offset basis
    final BigInt prime = BigInt.parse('0x100000001b3'); // FNV prime

    for (final b in utf8.encode(s)) {
      hash = (hash ^ BigInt.from(b)) & mask64;
      hash = (hash * prime) & mask64;
    }
    // 16-stellige Hex-Darstellung
    final hex = hash.toRadixString(16);
    return hex.padLeft(16, '0');
  }
}

class _Block {
  final String label; // "frage" | "antwort"
  final String body;
  final String? number;

  _Block({required this.label, required this.body, this.number});
}

class _ParseResult {
  final List<Flashcard> cards;
  final List<Unmatched> unmatched;
  final String? carryLabel; // "Frage" oder null
  final String carryText;

  _ParseResult({
    required this.cards,
    required this.unmatched,
    this.carryLabel,
    this.carryText = '',
  });
}
