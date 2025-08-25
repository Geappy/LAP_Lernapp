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

import '../services/builtin_h1.dart';

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
        withData: false, // IMPORTANT: don't hold entire file in memory
        allowMultiple: false,
      );
      if (!mounted) return;
      if (result == null) {
        setState(() => _busy = false);
        return;
      }

      final file = result.files.single;
      final title = (file.name).replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '').trim();
      final stopwatch = Stopwatch()..start();

      // Stream to disk, don’t collect in memory
      final writer = await StreamingDeckWriter.begin(
        title: title.isEmpty ? 'Karteikarten' : title,
        sourceName: file.name,
      );

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StreamBuilder<ProgressUpdate>(
            stream: PdfParser.parseWithProgress(file, debug: false), // keep debug off to save RAM
            builder: (ctx, snapshot) {
              final d = snapshot.data;

              if (d != null) {
                if (d.cards != null && d.cards!.isNotEmpty) {
                  writer.appendCards(d.cards!); // stream to disk
                }
                if (d.unmatched != null && d.unmatched!.isNotEmpty) {
                  writer.appendNotes(d.unmatched!);
                }
                if (d.done) {
                  WidgetsBinding.instance.addPostFrameCallback((_) async {
                    if (!mounted) return;
                    Navigator.of(dialogContext).pop();
                    try {
                      await writer.finish();
                      await _reload();
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Deck gespeichert (${writer.cardCount} Karten, ${writer.unmatchedCount} Notizen).',
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
          progressKey: deck.id, // stabiler Fortschritts-Schlüssel pro Deck
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
      showDragHandle: true,
      builder: (_) {
        final list = deck?.unmatched ?? const <Unmatched>[];
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: list.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Keine Notizen – alles erkannt 🎉'),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
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
          IconButton(
            tooltip: 'H1-Deck hinzufügen',
            icon: const Icon(Icons.flash_on),
            onPressed: _busy ? null : () async {
              setState(() => _busy = true);
              try {
                final (cards, notes) = await installH1FullDeck();
                await _reload();
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Deck gespeichert ($cards Karten, $notes Notizen).')),
                );
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Installieren fehlgeschlagen: $e')),
                );
              } finally {
                if (mounted) setState(() => _busy = false);
              }
            },
          ),
        ],
      ),

      body: _decks.isEmpty
          ? const _EmptyState()
          : RefreshIndicator(
              onRefresh: _reload,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                itemCount: _decks.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final d = _decks[i];
                  return _DeckCard(
                    meta: d,
                    formatDate: _formatDate,
                    onOpen: () => _openDeck(d),
                    onDetails: () => _showDetails(d),
                    onRename: () => _renameDeck(d),
                    onDelete: () => _deleteDeck(d),
                  );
                },
              ),
            ),

      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _importPdf,
        icon: const Icon(Icons.upload_file),
        label: const Text('PDF importieren'),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.style, size: 64, color: cs.primary.withOpacity(0.8)),
            const SizedBox(height: 12),
            const Text(
              'Noch keine Decks',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Importiere oben rechts über den Button.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeckCard extends StatelessWidget {
  const _DeckCard({
    required this.meta,
    required this.formatDate,
    required this.onOpen,
    required this.onDetails,
    required this.onRename,
    required this.onDelete,
  });

  final DeckMeta meta;
  final String Function(DateTime) formatDate;
  final VoidCallback onOpen;
  final VoidCallback onDetails;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final unmatched = meta.unmatchedCount ?? 0;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onOpen,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [cs.surface, cs.surfaceContainerHighest],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outline.withOpacity(0.25)),
          boxShadow: [
            BoxShadow(
              color: cs.shadow.withOpacity(0.04),
              blurRadius: 14,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [cs.primary, cs.primaryContainer],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const Center(
                  child: Icon(Icons.style, color: Colors.white),
                ),
              ),
              const SizedBox(width: 14),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      meta.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _chip(context,
                            icon: Icons.collections_bookmark_outlined,
                            label: '${meta.cardCount} Karten'),
                        _chip(context,
                            icon: Icons.schedule,
                            label: formatDate(meta.createdAt),
                            tone: ChipTone.neutral),
                        if (unmatched > 0)
                          _chip(context,
                              icon: Icons.warning_amber_rounded,
                              label: '$unmatched Notizen',
                              tone: ChipTone.warning),
                      ],
                    ),
                  ],
                ),
              ),

              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'details') onDetails();
                  if (v == 'rename') onRename();
                  if (v == 'delete') onDelete();
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'details',
                    child: Row(
                      children: [
                        Icon(Icons.notes_outlined),
                        SizedBox(width: 10),
                        Text('Details / Notizen'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'rename',
                    child: Row(
                      children: [
                        Icon(Icons.drive_file_rename_outline),
                        SizedBox(width: 10),
                        Text('Umbenennen'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline),
                        SizedBox(width: 10),
                        Text('Löschen'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(BuildContext context,
      {required IconData icon,
      required String label,
      ChipTone tone = ChipTone.primary}) {
    final cs = Theme.of(context).colorScheme;
    Color bg;
    Color fg;
    switch (tone) {
      case ChipTone.warning:
        bg = Colors.amber.withOpacity(0.18);
        fg = Colors.amber.shade800;
        break;
      case ChipTone.neutral:
        bg = cs.surfaceContainerHighest;
        fg = cs.onSurface.withOpacity(0.75);
        break;
      case ChipTone.primary:
      default:
        bg = cs.primary.withOpacity(0.12);
        fg = cs.primary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

enum ChipTone { primary, warning, neutral }
