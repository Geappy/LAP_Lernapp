// lib/services/pdf_parser.dart
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io' show File;

import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../models/flashcard.dart';
import '../models/progress_update.dart';
import '../models/unmatched.dart';

// -------------- small helpers --------------

String _fnv64Hex(String s) {
  final BigInt mask64 = BigInt.parse('0xFFFFFFFFFFFFFFFF');
  BigInt hash = BigInt.parse('0xcbf29ce484222325');
  final BigInt prime = BigInt.parse('0x100000001b3');
  for (final b in utf8.encode(s)) {
    hash = (hash ^ BigInt.from(b)) & mask64;
    hash = (hash * prime) & mask64;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}

String _makeCardId(String? number, String q, String a) {
  return _fnv64Hex('${number ?? ''}\n$q\n$a');
}

String _abbr(String s) => s.length <= 60 ? s : '${s.substring(0, 57)}…';

String _cleanQA(String s) {
  s = s.replaceAll(RegExp(r'\s+\n'), '\n');
  s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return s.trim();
}

String _fixHyphensAndNormalize(String s) {
  s = s.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  s = s.replaceAll('\u00AD', '');
  s = s.replaceAll(RegExp(r'(\w)-\n(\w)'), r'$1$2');
  s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return s;
}

String? _extractNrFromLine(String line) {
  final m = RegExp(r'^\s*(Nr\.\s*\d{1,5})\b').firstMatch(line);
  if (m == null) return null;
  final m2 = RegExp(r'Nr\.\s*(\d{1,5})').firstMatch(m.group(1)!);
  if (m2 == null) return null;
  return 'Nr. ${m2.group(1)}';
}

final _labelRe = RegExp(r'^\s*(frage|antwort)\s*[:\.]?\s*(.*)$', caseSensitive: false);

class _SegmentParse {
  final Flashcard? card;
  final Unmatched? note;
  _SegmentParse({this.card, this.note});
}

_SegmentParse _parseSegmentBody(String number, String body) {
  final lines = body.split('\n');

  int frageIdx = -1, antwortIdx = -1;
  String frageTail = '', antwortTail = '';

  for (int i = 0; i < lines.length; i++) {
    final m = _labelRe.firstMatch(lines[i]);
    if (m == null) continue;
    final label = (m.group(1) ?? '').toLowerCase();
    final tail = (m.group(2) ?? '').trim();
    if (label == 'frage' && frageIdx == -1) {
      frageIdx = i;
      frageTail = tail;
    } else if (label == 'antwort' && antwortIdx == -1) {
      antwortIdx = i;
      antwortTail = tail;
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
  } else {
    final fallbackQ = lines.map((l) => l.trim()).where((l) => l.isNotEmpty).take(4).join(' ');
    question = _cleanQA(fallbackQ);
  }

  if (antwortIdx >= 0) {
    final aStart = antwortIdx + 1;
    final aLines = <String>[
      if (antwortTail.isNotEmpty) antwortTail,
      ...lines.sublist(aStart),
    ];
    answer = _cleanQA(aLines.join('\n'));
  } else if (frageIdx >= 0) {
    final trailing = _cleanQA(lines.sublist(frageIdx + 1).join('\n'));
    if (trailing.isNotEmpty) answer = trailing;
  }

  if (question.isNotEmpty) {
    final safeAnswer = answer.isNotEmpty ? answer : '[keine Antwort im Text gefunden]';
    return _SegmentParse(
      card: Flashcard(
        id: _makeCardId(number, question, safeAnswer),
        question: question,
        answer: safeAnswer,
        number: number,
      ),
      note: answer.isEmpty
          ? Unmatched(page: 0, reason: 'Antwort fehlt', text: question.length > 140 ? '${question.substring(0, 137)}…' : question)
          : null,
    );
  } else {
    return _SegmentParse(
      card: null,
      note: Unmatched(page: 0, reason: 'Frage nicht gefunden (Segment ohne Frage)', text: body.length > 140 ? '${body.substring(0, 137)}…' : body),
    );
  }
}

// -------------- MAIN: ultra-low-memory streaming --------------

class PdfParser {
  static const int _kMaxSegmentChars = 200000; // ~200 KB per "Nr."
  static const int _kThrottleMask = 0x1FF;     // yield every ~512 lines

  /// Streams one card at a time; only the current segment is held in RAM.
  static Stream<ProgressUpdate> parseWithProgress(
    dynamic platformFile, {
    bool debug = false,
  }) async* {
    // Prefer reading from file path (since withData:false leaves bytes null)
    Uint8List? bytes;
    try {
      final String? path = platformFile.path as String?;
      if (path != null && path.isNotEmpty) {
        bytes = await File(path).readAsBytes();
      } else {
        bytes = platformFile.bytes as Uint8List?;
      }
    } catch (e) {
      yield ProgressUpdate(current: 0, total: 0, done: true, debugMessage: 'Datei konnte nicht gelesen werden: $e');
      return;
    }

    if (bytes == null) {
      yield ProgressUpdate(current: 0, total: 0, done: true, debugMessage: 'Keine Bytes und kein Pfad – prüfe FilePicker (withData:false & path).');
      return;
    }

    late PdfDocument doc;
    int totalPages = 0;

    try {
      // Open once
      doc = PdfDocument(inputBytes: bytes);
      totalPages = doc.pages.count;
    } catch (e) {
      yield ProgressUpdate(current: 0, total: 0, done: true, debugMessage: 'PDF open error: $e');
      return;
    } finally {
      // Drop raw buffer so GC can reclaim memory
      bytes = null;
    }

    if (totalPages == 0) {
      yield ProgressUpdate(current: 0, total: 0, done: true, debugMessage: 'Keine Seiten gefunden.');
      return;
    }

    yield ProgressUpdate(
      current: 0,
      total: totalPages,
      done: false,
      debugMessage: '🔍 PDF geladen: $totalPages Seiten (State-Machine Parser)',
    );

    try {
      final extractor = PdfTextExtractor(doc);

      String? currentNr;
      final StringBuffer currentBody = StringBuffer();
      int produced = 0;
      int throttle = 0;
      bool segmentCapped = false;

      List<ProgressUpdate> _flush(int pageNo) {
        if (currentNr == null) return const [];
        final parsed = _parseSegmentBody(currentNr!, currentBody.toString());
        currentNr = null;
        currentBody.clear();
        segmentCapped = false;

        final ups = <ProgressUpdate>[];
        if (parsed.card != null) {
          final c = parsed.card!;
          produced++;
          if (debug) {
            // ignore: avoid_print
            print('➡️  Nr=${c.number}\n   Frage (${c.question.length}): ${_abbr(c.question)}\n   Antwort (${c.answer.length}): ${_abbr(c.answer)}');
          }
          ups.add(ProgressUpdate(
            current: pageNo,
            total: totalPages,
            done: false,
            cards: [c],
            snippet: null,
            debugMessage: '✅ Karte $produced (bis Seite $pageNo)',
          ));
        }
        if (parsed.note != null) {
          ups.add(ProgressUpdate(
            current: pageNo,
            total: totalPages,
            done: false,
            unmatched: [parsed.note!],
            snippet: null,
            debugMessage: 'ℹ️ Hinweis ${parsed.note!.reason}',
          ));
        }
        return ups;
      }

      for (int i = 0; i < totalPages; i++) {
        final pageNo = i + 1;
        try {
          String raw = extractor.extractText(startPageIndex: i, endPageIndex: i);
          raw = _fixHyphensAndNormalize(raw);

          final lines = raw.split('\n');
          for (final line in lines) {
            final trimmed = line.trim();
            if (trimmed.isEmpty) {
              if (currentNr != null && !segmentCapped) currentBody.writeln();
              continue;
            }
            if (RegExp(r'^Seite\s+\d+\s*/\s*\d+\s*$', caseSensitive: false).hasMatch(trimmed)) continue;
            if (RegExp(r'^Stand:\s*\d{2}\.\d{2}\.\d{4}').hasMatch(trimmed)) continue;
            if (RegExp(r'^(Fachkunde|Metalltechnik)\b', caseSensitive: false).hasMatch(trimmed)) continue;
            if (RegExp(r'^Thema:\s*', caseSensitive: false).hasMatch(trimmed)) continue;

            final maybeNr = _extractNrFromLine(trimmed);
            if (maybeNr != null) {
              if (currentNr != null) {
                for (final u in _flush(pageNo)) {
                  yield u;
                }
              }
              currentNr = maybeNr;
              segmentCapped = false;
            } else {
              if (currentNr != null) {
                if (!segmentCapped) {
                  if (currentBody.length + trimmed.length + 1 <= _kMaxSegmentChars) {
                    currentBody.writeln(trimmed);
                  } else {
                    segmentCapped = true;
                    // Record a note once about capping this segment
                    yield ProgressUpdate(
                      current: pageNo,
                      total: totalPages,
                      done: false,
                      unmatched: [
                        Unmatched(
                          page: pageNo,
                          reason: 'Segment sehr lang – Text gekürzt',
                          text: 'Der Abschnitt "$currentNr" wurde auf ~${_kMaxSegmentChars ~/ 1000} KB Text begrenzt.',
                        ),
                      ],
                      snippet: null,
                      debugMessage: '⚠️ Segmentlänge begrenzt (Speicherschutz)',
                    );
                  }
                }
              }
            }

            if ((++throttle & _kThrottleMask) == 0) {
              await Future<void>.delayed(const Duration(milliseconds: 1));
            }
          }

          if (debug) {
            yield ProgressUpdate(
              current: pageNo,
              total: totalPages,
              done: false,
              debugMessage: '📄 Seite $pageNo verarbeitet',
            );
          }
        } catch (e) {
          yield ProgressUpdate(
            current: pageNo,
            total: totalPages,
            done: false,
            unmatched: [Unmatched(page: pageNo, reason: 'Seite übersprungen (Fehler beim Extrahieren)', text: '$e')],
            debugMessage: '⚠️ Seite $pageNo übersprungen: $e',
          );
        }

        await Future<void>.delayed(Duration.zero);
      }

      for (final u in _flush(totalPages)) {
        yield u;
      }

      yield ProgressUpdate(
        current: totalPages,
        total: totalPages,
        done: true,
        debugMessage: 'Fertig. Karten erzeugt: $produced (State-Machine Parser)',
      );
    } finally {
      doc.dispose();
    }
  }

  /// Collect all cards (still streamed). Use only for small PDFs.
  static Future<List<Flashcard>> parseAll(dynamic platformFile, {bool debug = false}) async {
    final out = <Flashcard>[];
    final seen = <String>{};
    await for (final u in parseWithProgress(platformFile, debug: debug)) {
      final cs = u.cards;
      if (cs != null && cs.isNotEmpty) {
        for (final c in cs) {
          if (seen.add(c.id)) out.add(c);
        }
      }
    }
    return out;
  }
}
