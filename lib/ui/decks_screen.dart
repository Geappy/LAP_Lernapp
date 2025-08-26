import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../models/deck.dart';
import '../../models/progress_update.dart';
import '../../models/unmatched.dart';
import '../../services/pdf_parser.dart';
import '../../services/storage_service.dart';
import './widgets/progress_dialog.dart';
import './lernmodus_screen.dart';
import '../../services/builtin_h1.dart';

import 'widgets/deck_card.dart';
import 'widgets/empty_state.dart';
import 'widgets/snack.dart';

class DecksScreen extends StatefulWidget {
  const DecksScreen({super.key});

  @override
  State<DecksScreen> createState() => _DecksScreenState();
}

class _DecksScreenState extends State<DecksScreen> {
  final _busy = ValueNotifier<bool>(false);
  late Future<List<DeckMeta>> _futureDecks;

  @override
  void initState() {
    super.initState();
    _futureDecks = StorageService.listDecks();
  }

  Future<void> _reload() async {
    setState(() {
      _futureDecks = StorageService.listDecks();
    });
  }

  Future<void> _importPdf() async {
    if (_busy.value) return;
    _busy.value = true;

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        withData: false,
        allowMultiple: false,
      );
      if (!mounted) return;
      if (result == null) return; // cancelled

      final file = result.files.single;
      final title = (file.name).replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '').trim();
      final stopwatch = Stopwatch()..start();

      final writer = await StreamingDeckWriter.begin(
        title: title.isEmpty ? 'Karteikarten' : title,
        sourceName: file.name,
      );

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StreamBuilder<ProgressUpdate>(
            stream: PdfParser.parseWithProgress(file, debug: false),
            builder: (ctx, snapshot) {
              final d = snapshot.data;

              if (snapshot.hasError) {
                // show an error and allow the user to close
                return AlertDialog(
                  title: const Text('Fehler beim Analysieren'),
                  content: Text('${snapshot.error}'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('OK'),
                    ),
                  ],
                );
              }

              if (d != null) {
                if (d.cards != null && d.cards!.isNotEmpty) {
                  writer.appendCards(d.cards!);
                }
                if (d.unmatched != null && d.unmatched!.isNotEmpty) {
                  writer.appendNotes(d.unmatched!);
                }
                if (d.done) {
                  // Defer closing the dialog until after the current frame
                  WidgetsBinding.instance.addPostFrameCallback((_) async {
                    if (!mounted) return;
                    if (Navigator.of(dialogContext).canPop()) {
                      Navigator.of(dialogContext).pop();
                    }
                    try {
                      await writer.finish();
                      await _reload();
                      if (!mounted) return;
                      showSnack(context, 'Deck gespeichert (${writer.cardCount} Karten, ${writer.unmatchedCount} Notizen).');
                    } catch (e) {
                      if (!mounted) return;
                      showSnack(context, 'Speichern fehlgeschlagen: $e');
                    }
                  });
                }
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
    } catch (e) {
      if (!mounted) return;
      showSnack(context, 'Fehler beim Import: $e');
    } finally {
      _busy.value = false;
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
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }

    if (deck == null || deck.cards.isEmpty) {
      showSnack(context, 'Deck konnte nicht geladen werden.');
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LernmodusScreen(
          cards: deck.cards,
          title: deck.title,
          progressKey: deck.id,
        ),
      ),
    );
  }

  Future<void> _showDetails(DeckMeta d) async {
    final deck = await StorageService.loadDeck(d.id);
    if (!mounted) return;
    final list = deck?.unmatched ?? const <Unmatched>[];

    // Draggable and scrollable bottom sheet for long lists
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: list.isEmpty ? 0.3 : 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        builder: (ctx, scrollController) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: list.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Keine Notizen – alles erkannt 🎉'),
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Nicht zugeordnete Fragenteile (${list.length})',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Expanded(
                          child: ListView.separated(
                            controller: scrollController,
                            itemCount: list.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final u = list[i];
                              return ListTile(
                                dense: true,
                                leading: Badge(
                                  label: Text('${u.page}'),
                                  child: const Icon(Icons.description_outlined),
                                ),
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
      ),
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
        showSnack(context, 'Titel aktualisiert.');
      } catch (e) {
        if (!mounted) return;
        showSnack(context, 'Umbenennen fehlgeschlagen: $e');
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
      showSnack(context, 'Deck gelöscht.');
    }
  }

  String _formatDate(DateTime dt) {
    final d = dt.toLocal();
    String two(int n) => n < 10 ? '0$n' : '$n';
    return '${two(d.day)}.${two(d.month)}.${d.year}, ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          'Decks',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
        ),
        actions: [
          ValueListenableBuilder<bool>(
            valueListenable: _busy,
            builder: (_, busy, __) => IconButton(
              tooltip: 'H1-Deck hinzufügen (eingebaut)',
              icon: const Icon(Icons.flash_on),
              onPressed: busy
                  ? null
                  : () async {
                      _busy.value = true;
                      try {
                        final (cards, notes) = await installH1FullDeck();
                        await _reload();
                        if (!mounted) return;
                        showSnack(context, 'Deck gespeichert ($cards Karten, $notes Notizen).');
                      } catch (e) {
                        if (!mounted) return;
                        showSnack(context, 'Installieren fehlgeschlagen: $e');
                      } finally {
                        _busy.value = false;
                      }
                    },
            ),
          ),
        ],
      ),

      body: FutureBuilder<List<DeckMeta>>(
        future: _futureDecks,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final decks = snap.data ?? const <DeckMeta>[];
          if (decks.isEmpty) {
            return const EmptyState();
          }
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
              itemCount: decks.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final d = decks[i];
                return DeckCard(
                  meta: d,
                  formatDate: _formatDate,
                  onOpen: () => _openDeck(d),
                  onDetails: () => _showDetails(d),
                  onRename: () => _renameDeck(d),
                  onDelete: () => _deleteDeck(d),
                );
              },
            ),
          );
        },
      ),

      floatingActionButton: ValueListenableBuilder<bool>(
        valueListenable: _busy,
        builder: (_, busy, __) => FloatingActionButton.extended(
          onPressed: busy ? null : _importPdf,
          icon: const Icon(Icons.upload_file),
          label: const Text('PDF importieren'),
        ),
      ),
    );
  }
}
