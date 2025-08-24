// lib/services/pdf_parser.dart
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../models/flashcard.dart';
import '../models/progress_update.dart';
import '../models/unmatched.dart';

/// ---------- Top-level Helper Classes ----------
class _NumberSegment {
  final String number; // canonical "Nr. 00xx"
  final String body;   // text after the Nr. line until next Nr.
  _NumberSegment(this.number, this.body);
}

class _SegmentParse {
  final Flashcard? card;
  final Unmatched? unmatched;
  _SegmentParse({this.card, this.unmatched});
}

/// ---------- Top-level Helper Functions ----------
String? _extractNr(String line) {
  // extract exactly "Nr. 0001" etc. anywhere within the line
  final m = RegExp(r'(Nr\.\s*\d{1,5})').firstMatch(line);
  if (m != null) return m.group(1)!.trim();
  // fallback: "Nr. 0001 8068.29050" -> still "Nr. 0001"
  final m2 = RegExp(r'Nr\.\s*(\d{1,5})').firstMatch(line);
  if (m2 != null) return 'Nr. ${m2.group(1)}';
  return null;
}

String _fixHyphens(String s) {
  // remove soft hyphen U+00AD which can appear mid-word
  s = s.replaceAll('\u00AD', '');
  // join hard-hyphen line breaks like "Schaden-\nersatz"
  s = s.replaceAll(RegExp(r'(\w)-\n(\w)'), r'$1$2');
  return s;
}

String _normalize(String s) {
  s = s.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

  // remove headers/footers and common artifacts (a bit broader)
  s = s.replaceAll(RegExp(r'^\s*Stand:\s*\d{2}\.\d{2}\.\d{4}.*$', multiLine: true), '');
  s = s.replaceAll(RegExp(r'^\s*Seite\s+\d+\s*/\s*\d+\s*$', multiLine: true), '');
  s = s.replaceAll(RegExp(r'^\s*\d+\s*$', multiLine: true), ''); // lone page numbers
  s = s.replaceAll(RegExp(r'^\s*Fachkunde[^\n]*$', multiLine: true, caseSensitive: false), '');
  s = s.replaceAll(RegExp(r'^\s*Metalltechnik[^\n]*$', multiLine: true, caseSensitive: false), '');
  s = s.replaceAll(RegExp(r'^\s*Thema:\s*[^\n]*$', multiLine: true, caseSensitive: false), '');
  s = s.replaceAll('<!--Break-->', '');

  // collapse excess blank lines
  s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');

  return s.trim();
}

String _cleanQA(String s) {
  s = s.replaceAll(RegExp(r'\s+\n'), '\n');
  s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return s.trim();
}

Map<String, int> _countDuplicates(List<String> numbers) {
  final map = <String, int>{};
  for (final n in numbers) {
    if (n.isEmpty) continue;
    map[n] = (map[n] ?? 0) + 1;
  }
  map.removeWhere((k, v) => v <= 1);
  return map;
}

String _abbr(String s) => s.length <= 60 ? s : '${s.substring(0, 57)}…';

String _shortList(List<String> items, {int maxItems = 10}) {
  if (items.length <= maxItems) return items.join(', ');
  return items.sublist(0, maxItems).join(', ') + ' … (+${items.length - maxItems})';
}

String _shorten(String s) {
  s = s.trim();
  if (s.length <= 140) return s;
  return '${s.substring(0, 137)}…';
}

String _makeCardId(String? number, String q, String a) {
  final input = '${number ?? ''}\n$q\n$a';
  return _fnv64Hex(input);
}

String _fnv64Hex(String s) {
  final BigInt mask64 = BigInt.parse('0xFFFFFFFFFFFFFFFF');
  BigInt hash = BigInt.parse('0xcbf29ce484222325'); // offset basis
  final BigInt prime = BigInt.parse('0x100000001b3'); // FNV prime
  for (final b in utf8.encode(s)) {
    hash = (hash ^ BigInt.from(b)) & mask64;
    hash = (hash * prime) & mask64;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}

List<String> _findAllNumbersOrdered(String text) {
  // get "Nr. ####" occurrences in doc order
  final pattern = RegExp(r'(?<=\n|^)\s*(Nr\.\s*\d{1,5})\b', multiLine: true);
  return pattern.allMatches(text).map((m) => m.group(1)!.trim()).toList();
}

/// Splits text into segments (one per number line). Uses the CAPTURED line as the number.
/// Body starts **after** the matched line (skip the immediate newline if present).
List<_NumberSegment> _splitByNumberSegments(String text, {bool debug = false}) {
  // match each line that starts with a number (capture the whole line)
  final linePattern = RegExp(r'^\s*(Nr\.\s*\d{1,5}.*)$', multiLine: true);
  final matches = linePattern.allMatches(text).toList();
  final segments = <_NumberSegment>[];

  if (matches.isEmpty) return segments;

  for (int i = 0; i < matches.length; i++) {
    final m = matches[i];
    final capturedLine = m.group(1) ?? '';
    String canonNumber = _extractNr(capturedLine) ?? 'Nr._UNBEKANNT';

    // Body: from end of this matched line to next match.start
    int bodyStart = m.end;
    // skip exactly one newline if present
    if (bodyStart < text.length && text.codeUnitAt(bodyStart) == 0x0A) {
      bodyStart += 1;
    }
    final int bodyEnd = (i + 1 < matches.length) ? matches[i + 1].start : text.length;
    final body = text.substring(bodyStart, max(bodyStart, bodyEnd));

    if (debug) {
      final peek = body.split('\n').take(2).join(' | ');
      // ignore: avoid_print
      print('🔧 Split → $canonNumber | FirstLine="${capturedLine.trim()}" | BodyPeek="${_abbr(peek)}"');
    }

    segments.add(_NumberSegment(canonNumber, body));
  }

  return segments;
}

/// ---------- Label handling (robust & inline-tail aware) ----------
final _labelRe = RegExp(r'^\s*(frage|antwort)\s*[:\.]?\s*(.*)$', caseSensitive: false);

_SegmentParse _parseSegment(String number, String body) {
  // If number somehow came empty, try to re-derive from first line of the body.
  if (number.isEmpty || number == 'Nr._UNBEKANNT') {
    final firstLine = body.split('\n').firstWhere((_) => true, orElse: () => '');
    final n2 = _extractNr(firstLine);
    if (n2 != null && n2.isNotEmpty) number = n2;
  }

  // Parse Frage / Antwort
  final lines = body.split('\n');

  int frageIdx = -1;
  int antwortIdx = -1;
  String frageTail = '';
  String antwortTail = '';

  for (int i = 0; i < lines.length; i++) {
    final m = _labelRe.firstMatch(lines[i]);
    if (m == null) continue;
    final label = (m.group(1) ?? '').toLowerCase();
    final tail = (m.group(2) ?? '').trim();

    if (label == 'frage' && frageIdx == -1) {
      frageIdx = i;
      frageTail = tail; // content on same line as label, if any
    } else if (label == 'antwort' && antwortIdx == -1) {
      antwortIdx = i;
      antwortTail = tail; // content on same line as label, if any
    }
  }

  String question = '';
  String answer = '';

  if (frageIdx >= 0) {
    final qStart = frageIdx + 1;
    final qEnd = (antwortIdx > frageIdx && antwortIdx >= 0) ? antwortIdx : lines.length;
    final qLines = <String>[
      if (frageTail.isNotEmpty) frageTail,
      ...lines.sublist(qStart, qEnd),
    ];
    question = _cleanQA(qLines.join('\n'));
  }

  if (antwortIdx >= 0) {
    final aStart = antwortIdx + 1;
    final aLines = <String>[
      if (antwortTail.isNotEmpty) antwortTail,
      ...lines.sublist(aStart),
    ];
    answer = _cleanQA(aLines.join('\n'));
  }

  // If Frage exists but no Antwort label, use trailing text after Frage as answer (if any).
  if (frageIdx >= 0 && antwortIdx == -1) {
    final afterFrage = lines.sublist(frageIdx + 1);
    final trailing = _cleanQA(afterFrage.join('\n'));
    if (trailing.isNotEmpty) {
      answer = trailing;
    }
  }

  // If we still have no Frage, fallback: first non-empty lines as question
  if (frageIdx == -1) {
    final fallbackQ = lines.map((l) => l.trim()).where((l) => l.isNotEmpty).take(4).join(' ');
    question = _cleanQA(fallbackQ);
  }

  if (question.isNotEmpty) {
    final safeAnswer = answer.isNotEmpty ? answer : '[keine Antwort im Text gefunden]';
    final card = Flashcard(
      id: _makeCardId(number, question, safeAnswer),
      question: question,
      answer: safeAnswer,
      number: number,
    );
    Unmatched? note;
    if (answer.isEmpty) {
      note = Unmatched(page: 0, reason: 'Antwort fehlt', text: _shorten(question));
    }
    return _SegmentParse(card: card, unmatched: note);
  } else {
    final note = Unmatched(page: 0, reason: 'Frage nicht gefunden (Segment ohne Frage)', text: _shorten(body));
    return _SegmentParse(card: null, unmatched: note);
  }
}

/// ---------- Main Parser ----------
class PdfParser {
  /// Deterministic parser:
  /// * Collects whole document text once
  /// * Splits by "Nr. ####" → one stable segment = one card
  /// * Robust Frage/Antwort extraction inside each segment
  static Stream<ProgressUpdate> parseWithProgress(
    dynamic platformFile, {
    bool debug = true,
  }) async* {
    final Uint8List? bytes = platformFile.bytes as Uint8List?;
    if (bytes == null) {
      throw Exception('Keine Bytes im FilePicker-Result. Aktiviere withData:true beim FilePicker.');
    }

    // 1) Count pages
    int totalPages = 0;
    try {
      final probe = PdfDocument(inputBytes: bytes);
      totalPages = probe.pages.count;
      probe.dispose();
    } catch (_) {
      totalPages = 0;
    }

    if (totalPages == 0) {
      yield ProgressUpdate(current: 0, total: 0, done: true, debugMessage: 'Keine Seiten gefunden.');
      return;
    }

    yield ProgressUpdate(
      current: 0,
      total: totalPages,
      done: false,
      debugMessage: '🔍 PDF geladen: $totalPages Seiten',
    );

    // 2) Extract ALL pages' raw text (once), with progress
    final List<String> pageTexts = List.filled(totalPages, '');
    {
      late PdfDocument doc;
      try {
        doc = PdfDocument(inputBytes: bytes);
      } catch (e) {
        yield ProgressUpdate(current: 0, total: totalPages, done: true, debugMessage: 'PDF open error: $e');
        return;
      }

      try {
        final extractor = PdfTextExtractor(doc);
        for (int i = 0; i < totalPages; i++) {
          final pageNo = i + 1;
          try {
            final raw = extractor.extractText(startPageIndex: i, endPageIndex: i);
            pageTexts[i] = raw;
            yield ProgressUpdate(
              current: pageNo,
              total: totalPages,
              done: false,
              debugMessage: '📄 Seite $pageNo extrahiert',
            );
          } catch (e) {
            pageTexts[i] = '';
            yield ProgressUpdate(
              current: pageNo,
              total: totalPages,
              done: false,
              unmatched: [
                Unmatched(page: pageNo, reason: 'Seite übersprungen (Fehler beim Extrahieren)', text: '$e')
              ],
              debugMessage: '⚠️ Seite $pageNo übersprungen: $e',
            );
          }
          await Future.delayed(Duration.zero);
        }
      } finally {
        doc.dispose();
      }
    }

    // 3) Combine & normalize whole doc
    final combinedRaw = pageTexts.join('\n\n');
    final combined = _normalize(_fixHyphens(combinedRaw));

    // 4) Pre-scan: collect all Nr. present (audit)
    final List<String> allNumbersOrdered = _findAllNumbersOrdered(combined);
    if (debug) {
      // ignore: avoid_print
      print('📋 Pre-Scan Nrn (${allNumbersOrdered.length}): ${_shortList(allNumbersOrdered)}');
    }

    // 5) Split into segments by Nr. (robust)
    final segments = _splitByNumberSegments(combined, debug: debug);
    if (debug) {
      // ignore: avoid_print
      print('🧩 Segmente erkannt: ${segments.length}');
    }

    // 6) Parse each segment deterministically + emit per card
    int emittedCards = 0;
    final List<Unmatched> notes = [];
    final List<Flashcard> allCards = []; // <-- accumulate full batch

    for (int i = 0; i < segments.length; i++) {
      final seg = segments[i];
      final parsed = _parseSegment(seg.number, seg.body);

      if (parsed.card != null) {
        final c = parsed.card!;
        emittedCards++;
        allCards.add(c);

        if (debug) {
          final q = c.question;
          final a = c.answer;
          // ignore: avoid_print
          print('➡️  Nr=${c.number}'
              '\n   Frage (${q.length}): ${_abbr(q)}'
              '\n   Antwort (${a.length}): ${_abbr(a)}');
        }

        // emit THIS card to keep UI behavior identical to old per-page appends
        yield ProgressUpdate(
          current: min(i + 1, segments.length),
          total: segments.length,
          done: false,
          cards: [c],
          snippet: _abbr(c.question.isNotEmpty ? c.question : c.answer),
          debugMessage: '✅ Karte $emittedCards/${segments.length} (Nr. ${c.number})',
        );
      }

      if (parsed.unmatched != null) {
        notes.add(parsed.unmatched!);
        yield ProgressUpdate(
          current: min(i + 1, segments.length),
          total: segments.length,
          done: false,
          unmatched: [parsed.unmatched!],
          debugMessage: 'ℹ️ Hinweis für Nr. ${seg.number}: ${parsed.unmatched!.reason}',
        );
      }

      await Future.delayed(Duration.zero);
    }

    // 7) Audit expected vs produced
    final producedNumbers = <String>{};
    for (final n in segments.map((s) => s.number)) {
      producedNumbers.add(n);
    }
    final missing = allNumbersOrdered.where((n) => !producedNumbers.contains(n)).toList();
    final dupCount = _countDuplicates(segments.map((s) => s.number).toList());

    if (debug) {
      // ignore: avoid_print
      print('📊 Audit: Erwartet: ${allNumbersOrdered.length}, Erzeugt (Segmente): ${segments.length}');
      if (missing.isEmpty) {
        // ignore: avoid_print
        print('✅ Keine fehlenden Nrn.');
      } else {
        // ignore: avoid_print
        print('❗ Fehlende Nrn (${missing.length}): ${_shortList(missing)}');
      }
      if (dupCount.isNotEmpty) {
        // ignore: avoid_print
        print('❕ Doppelte Nrn: $dupCount');
      }
    }

    // 8) Final progress (emit FULL BATCH so UI can replace list at the end if desired)
    yield ProgressUpdate(
      current: segments.length,
      total: segments.length,
      done: true,
      cards: allCards, // <--- entire list here
      unmatched: notes,
      debugMessage: 'Fertig. Karten: ${allCards.length} • Notizen: ${notes.length}',
    );
  }

  /// Convenience: parse and return one full list (no UI streaming).
  static Future<List<Flashcard>> parseAll(dynamic platformFile, {bool debug = false}) async {
    final acc = <Flashcard>[];
    await for (final u in parseWithProgress(platformFile, debug: debug)) {
      if (u.cards != null && u.cards!.isNotEmpty) acc.addAll(u.cards!);
    }
    // De-dupe by id (defensive)
    final seen = <String>{};
    return acc.where((c) => seen.add(c.id)).toList();
  }
}
