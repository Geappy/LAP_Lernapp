// lib/ui/import_screen.dart
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/flashcard.dart';
import '../models/progress_update.dart';
import '../services/pdf_parser.dart';
import '../services/storage_service.dart';
import './widgets/progress_dialog.dart';

/// --- helper: de-dupe by flashcard.id ---
List<Flashcard> _dedupeById(List<Flashcard> list) {
  final seen = <String>{};
  final out = <Flashcard>[];
  for (final c in list) {
    if (seen.add(c.id)) out.add(c);
  }
  return out;
}

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  bool _isLoading = false;
  String? _sourceName;

  String _basenameNoExt(String name) {
    final slash = name.replaceAll('\\', '/');
    final base = slash.split('/').last;
    final dot = base.lastIndexOf('.');
    return dot > 0 ? base.substring(0, dot) : base;
  }

  Future<void> _handleParsingDone({
    required BuildContext rootContext,
    required List<Flashcard> cards,
    required String sourceName,
  }) async {
    Navigator.of(rootContext, rootNavigator: true).pop();
    if (mounted) setState(() => _isLoading = false);

    if (cards.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(rootContext).showSnackBar(
          const SnackBar(content: Text('Keine Karten erkannt.')),
        );
      }
      return;
    }

    final title = _basenameNoExt(sourceName);

    try {
      // ignore: avoid_print
      print('💾 Speichere Deck "$title" (${cards.length} Karten) …');
      await StorageService.saveDeck(
        title: title,
        cards: cards,
        sourceName: sourceName,
      );
      // ignore: avoid_print
      print('✅ Deck gespeichert');

      if (!mounted) return;

      ScaffoldMessenger.of(rootContext).showSnackBar(
        SnackBar(content: Text('Gespeichert: "$title" (${cards.length} Karten)')),
      );

      Navigator.of(rootContext).pop(true); // zurück zur Übersicht + Refresh
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(rootContext).showSnackBar(
        SnackBar(content: Text('Speichern fehlgeschlagen: $e')),
      );
    }
  }

  Future<void> _pickAndParsePdf() async {
    try {
      setState(() => _isLoading = true);

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        withData: false,
      );

      if (!mounted) return;

      if (result == null) {
        setState(() => _isLoading = false);
        return;
      }

      final file = result.files.single;
      _sourceName = file.name;

      final rootContext = context;
      final stopwatch = Stopwatch()..start();

      // NEW: stream to disk
      final writer = await StreamingDeckWriter.begin(
        title: _basenameNoExt(_sourceName!),
        sourceName: _sourceName!,
      );

      await showDialog<void>(
        context: rootContext,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StreamBuilder<ProgressUpdate>(
            stream: PdfParser.parseWithProgress(file, debug: false),
            builder: (ctx, snapshot) {
              final d = snapshot.data;

              if (d?.cards != null && d!.cards!.isNotEmpty) {
                // write to disk immediately to keep RAM low
                writer.appendCards(d.cards!);
              }
              if (d?.unmatched != null && d!.unmatched!.isNotEmpty) {
                writer.appendNotes(d.unmatched!);
              }
              if (d?.done == true) {
                WidgetsBinding.instance.addPostFrameCallback((_) async {
                  if (!mounted) return;
                  Navigator.of(dialogContext).pop();
                  try {
                    await writer.finish();
                    if (!mounted) return;
                    ScaffoldMessenger.of(rootContext).showSnackBar(
                      SnackBar(content: Text('Gespeichert: "${_basenameNoExt(_sourceName!)}" (${writer.cardCount} Karten)')),
                    );
                    Navigator.of(rootContext).pop(true);
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(rootContext).showSnackBar(
                      SnackBar(content: Text('Speichern fehlgeschlagen: $e')),
                    );
                  }
                });
              }

              return ProgressDialog(
                current: d?.current ?? 0,
                total: d?.total ?? 1,
                elapsed: stopwatch.elapsed,
                snippet: d?.snippet,
                debugMessage: d?.debugMessage,
              );
            },
          );
        },
      );

      if (!mounted) return;
      setState(() => _isLoading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler beim Einlesen: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PDF → Karteikarten')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.picture_as_pdf,
                  size: 72, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 16),
              const Text(
                'Wähle ein PDF mit Fragen & Antworten aus.\n'
                'Die App erzeugt daraus Karteikarten, speichert ein Deck\n'
                'und kehrt zur Übersicht zurück.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _isLoading ? null : _pickAndParsePdf,
                icon: const Icon(Icons.upload_file),
                label: const Text('PDF auswählen'),
              ),
              if (_isLoading) ...[
                const SizedBox(height: 24),
                const CircularProgressIndicator(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
