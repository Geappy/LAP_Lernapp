// lib/screens/import_screen.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';

import '../models/flashcard.dart';
import 'lernmodus_screen.dart';

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  String? _rawJson;
  List<Flashcard> _parsed = [];
  String _status = 'Keine Datei ausgewählt.';
  String _deckTitle = 'Neues Deck';

  bool get _hasData => _parsed.isNotEmpty;

  Future<void> _pickJsonFile() async {
    try {
      final typeGroup = XTypeGroup(
        label: 'JSON',
        extensions: const ['json'],
        mimeTypes: const ['application/json', 'text/json'],
      );
      final XFile? file = await openFile(acceptedTypeGroups: [typeGroup]);
      if (file == null) return;

      final bytes = await file.readAsBytes();
      final text = utf8.decode(bytes);

      await _loadFromRawJson(text, suggestedTitle: _fileNameWithoutExt(file.name));
    } catch (e) {
      setState(() {
        _status = 'Fehler beim Öffnen: $e';
        _parsed = [];
      });
    }
  }

  Future<void> _pasteJsonManually() async {
    final controller = TextEditingController(text: _rawJson ?? '');
    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('JSON einfügen'),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: controller,
            maxLines: 12,
            decoration: const InputDecoration(
              hintText: '{ "title": "Mein Deck", "cards": [ ... ] } oder [ ... ]',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Abbrechen'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, controller.text),
            icon: const Icon(Icons.save),
            label: const Text('Übernehmen'),
          ),
        ],
      ),
    );

    if (result == null) return;

    await _loadFromRawJson(result);
  }

  Future<void> _loadFromRawJson(String text, {String? suggestedTitle}) async {
    setState(() {
      _status = 'Lese JSON…';
      _rawJson = text;
    });
    try {
      final decoded = jsonDecode(text);

      String? titleFromJson;
      List<dynamic> rawCards;

      if (decoded is Map<String, dynamic>) {
        titleFromJson = (decoded['title'] ?? decoded['name'] ?? '').toString().trim();
        final cardsAny = decoded['cards'] ?? decoded['flashcards'] ?? decoded['items'];
        if (cardsAny is! List) throw const FormatException('Erwarte Feld "cards" als Liste.');
        rawCards = cardsAny;
      } else if (decoded is List) {
        rawCards = decoded;
      } else {
        throw const FormatException('Unerwartetes JSON-Format.');
      }

      final cards = <Flashcard>[];
      for (final item in rawCards) {
        if (item is! Map) continue;
        cards.add(Flashcard.fromJson(Map<String, dynamic>.from(item)));
      }
      if (cards.isEmpty) throw const FormatException('Keine Karten gefunden.');

      setState(() {
        _parsed = cards;
        _deckTitle = (titleFromJson?.isNotEmpty == true)
            ? titleFromJson!
            : (suggestedTitle ?? 'Neues Deck');
        _status = 'Geladen: ${cards.length} Karten'
            '${_deckTitle.isNotEmpty ? " • Titel: $_deckTitle" : ""}';
      });
    } on FormatException catch (e) {
      setState(() {
        _status = 'Format-Fehler: ${e.message}';
        _parsed = [];
      });
    } catch (e) {
      setState(() {
        _status = 'Fehler beim Parsen: $e';
        _parsed = [];
      });
    }
  }

  String _fileNameWithoutExt(String name) {
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  void _startLearning() {
    if (!_hasData) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LernmodusScreen(
          cards: _parsed,
          title: _deckTitle,
          progressKey: _deckTitle,
        ),
      ),
    );
  }

  Widget _buildPreview() {
    if (_parsed.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _status,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final preview = _parsed.take(3).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_status, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          ...preview.map((c) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.style, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Q: ${c.question}\nA: ${c.answer}',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              )),
          if (_parsed.length > preview.length)
            Text('+ ${_parsed.length - preview.length} weitere …',
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  color:
                      Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                )),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWeb = kIsWeb;

    return Scaffold(
      appBar: AppBar(title: const Text('Deck importieren')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Wähle eine JSON-Datei mit deinen Karten aus. '
                  'Diese Seite funktioniert auf ${isWeb ? "Web" : "allen Plattformen"} ohne path_provider.',
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: _pickJsonFile,
                      icon: const Icon(Icons.file_open_rounded),
                      label: const Text('Datei auswählen (.json)'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _pasteJsonManually,
                      icon: const Icon(Icons.paste_rounded),
                      label: const Text('JSON einfügen'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildPreview(),
                const Spacer(),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: TextEditingController(text: _deckTitle),
                        onChanged: (v) => _deckTitle = v.trim().isEmpty ? 'Neues Deck' : v.trim(),
                        decoration: const InputDecoration(
                          labelText: 'Deck-Titel',
                          prefixIcon: Icon(Icons.title),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _hasData ? _startLearning : null,
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Lernmodus starten'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
