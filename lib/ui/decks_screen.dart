// lib/ui/decks_screen.dart
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/deck.dart';
import '../models/flashcard.dart';
import '../models/progress_update.dart';
import '../models/unmatched.dart';
import '../services/pdf_parser.dart';
import '../services/storage_service.dart';
import './widgets/progress_dialog.dart';
import 'lernmodus_screen.dart';

/// --- helper: de-dupe by flashcard.id ---
List<Flashcard> _dedupeById(List<Flashcard> list) {
  final seen = <String>{};
  final out = <Flashcard>[];
  for (final c in list) {
    if (seen.add(c.id)) out.add(c);
  }
  return out;
}

class DecksScreen extends StatefulWidget {
  const DecksScreen({super.key});

  @override
  State<DecksScreen> createState() => _DecksScreenState();
}

class _DecksScreenState extends State<DecksScreen> {
  List<DeckMeta> _decks = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final decks = await StorageService.listDecks();
    if (!mounted) return;
    setState(() => _decks = decks);
  }

  Future<void> _importPdf() async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        withData: true,
      );
      if (!mounted) return;
      if (result == null) {
        setState(() => _busy = false);
        return;
      }

      final file = result.files.single;
      final title = (file.name)
          .replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '')
          .trim();

      final stopwatch = Stopwatch()..start();
      final collected = <Flashcard>[];
      final unmatched = <Unmatched>[];

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StreamBuilder<ProgressUpdate>(
            stream: PdfParser.parseWithProgress(file),
            builder: (_, snap) {
              final data = snap.data;

              if (data != null) {
                // maintain a local 'seen' for this dialog lifetime
                final seen = collected.map((c) => c.id).toSet();

                // Prefer the final full batch when present (prevents double-counting)
                if (data.done && data.cards != null && data.cards!.isNotEmpty) {
                  collected
                    ..clear()
                    ..addAll(_dedupeById(data.cards!));
                } else if (data.cards != null && data.cards!.isNotEmpty) {
                  for (final c in data.cards!) {
                    if (seen.add(c.id)) collected.add(c);
                  }
                }

                if (data.unmatched != null && data.unmatched!.isNotEmpty) {
                  unmatched.addAll(data.unmatched!);
                }

                if (data.done) {
                  WidgetsBinding.instance.addPostFrameCallback((_) async {
                    if (!mounted) return;
                    Navigator.of(dialogContext).pop();
                    stopwatch.stop();

                    try {
                      await StorageService.saveDeck(
                        title: title.isEmpty ? 'Karteikarten' : title,
                        cards: _dedupeById(collected), // safety
                        sourceName: file.name,
                        unmatched: unmatched,
                      );
                      await _reload();
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Deck gespeichert (${_dedupeById(collected).length} Karten, ${unmatched.length} Notizen).',
                          ),
                        ),
                      );
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Speichern fehlgeschlagen: $e')),
                      );
                    }
                  });
                }
              }

              return ProgressDialog(
                current: data?.current ?? 0,
                total: data?.total ?? 1,
                elapsed: stopwatch.elapsed,
                snippet: data?.snippet,
                debugMessage: data?.debugMessage,
              );
            },
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler beim Import: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openDeck(DeckMeta meta) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    final deck = await StorageService.loadDeck(meta.id);
    if (!mounted) return;
    Navigator.of(context).pop();

    if (deck == null || deck.cards.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Deck konnte nicht geladen werden.')),
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LernmodusScreen(
          cards: deck.cards,
          title: deck.title,
        ),
      ),
    );
  }

  Future<void> _showDetails(DeckMeta d) async {
    final deck = await StorageService.loadDeck(d.id);
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) {
        final list = deck?.unmatched ?? const <Unmatched>[];
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: list.isEmpty
                ? const Text('Keine Notizen – alles erkannt 🎉')
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Nicht zugeordnete Fragenteile (${list.length})',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: list.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final u = list[i];
                            return ListTile(
                              dense: true,
                              leading: Text('#${u.page}'),
                              title: Text(u.reason),
                              subtitle: Text(u.text),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }

  Future<void> _renameDeck(DeckMeta d) async {
    final controller = TextEditingController(text: d.title);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Deck umbenennen'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Neuer Titel'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Speichern')),
        ],
      ),
    );
    if (ok == true) {
      final newTitle = controller.text.trim();
      if (newTitle.isEmpty || newTitle == d.title) return;
      try {
        await StorageService.renameDeck(d.id, newTitle);
        await _reload();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Titel aktualisiert.')));
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Umbenennen fehlgeschlagen: $e')));
      }
    }
  }

  Future<void> _deleteDeck(DeckMeta d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Deck löschen?'),
        content: Text('„${d.title}“ dauerhaft entfernen?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Löschen')),
        ],
      ),
    );
    if (ok == true) {
      await StorageService.deleteDeck(d.id);
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deck gelöscht.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Meine Decks')),
      body: _decks.isEmpty
          ? const Center(child: Text('Noch keine Decks. Importiere ein PDF über den Button.'))
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: _decks.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final d = _decks[i];
                return Card(
                  elevation: 0.5,
                  child: ListTile(
                    onTap: () => _openDeck(d),
                    leading: const Icon(Icons.style),
                    title: Text(d.title),
                    subtitle: Text(
                      [
                        '${d.cardCount} Karten',
                        if (d.unmatchedCount != null) '⚠️ ${d.unmatchedCount} nicht zugeordnet',
                        d.createdAt.toLocal().toString().replaceFirst(RegExp(r':\d{2}\.\d+$'), ''),
                      ].join(' • '),
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'details') _showDetails(d);
                        if (v == 'rename') _renameDeck(d);
                        if (v == 'delete') _deleteDeck(d);
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(value: 'details', child: Text('Details / Notizen')),
                        PopupMenuItem(value: 'rename', child: Text('Umbenennen')),
                        PopupMenuItem(value: 'delete', child: Text('Löschen')),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _importPdf,
        icon: const Icon(Icons.upload_file),
        label: const Text('PDF importieren'),
      ),
    );
  }
}
