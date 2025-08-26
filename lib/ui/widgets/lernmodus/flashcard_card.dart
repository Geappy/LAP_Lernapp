import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../models/flashcard.dart';

class FlashcardCard extends StatelessWidget {
  const FlashcardCard({
    super.key,
    required this.card,
    required this.revealed,
    required this.isFavorite,
    required this.note,
    required this.correctCount,
    required this.onToggleReveal,
    required this.onSwipeRight,
    required this.onSwipeLeft,
    required this.onToggleFavorite,
    required this.onEditNote,
  });

  final Flashcard card;
  final bool revealed;
  final bool isFavorite;
  final String note;
  final int correctCount;

  final VoidCallback onToggleReveal;
  final VoidCallback onSwipeRight;
  final VoidCallback onSwipeLeft;
  final VoidCallback onToggleFavorite;
  final ValueChanged<String> onEditNote;

  Color _bucketColor(int k) {
    if (k >= 2) return Colors.green;
    if (k == 1) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = _bucketColor(correctCount);

    return Dismissible(
      key: ValueKey('card_${card.id}_${revealed ? 1 : 0}_${isFavorite ? 1 : 0}_${note.isNotEmpty ? 1 : 0}'),
      direction: revealed ? DismissDirection.horizontal : DismissDirection.none,
      background: _dismissBg(left: true),
      secondaryBackground: _dismissBg(left: false),
      confirmDismiss: (dir) async {
        if (!revealed) return false;
        if (dir == DismissDirection.startToEnd) {
          HapticFeedback.lightImpact();
          onSwipeRight();
        } else if (dir == DismissDirection.endToStart) {
          HapticFeedback.lightImpact();
          onSwipeLeft();
        }
        return false;
      },
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onToggleReveal,
        onLongPress: () => _openNoteEditor(context),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Theme.of(context).colorScheme.surface,
                Theme.of(context).colorScheme.surfaceContainerHighest,
              ],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderColor.withOpacity(0.6), width: 2.5),
            boxShadow: [
              BoxShadow(
                color: borderColor.withOpacity(0.12),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ((card.number ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        const Icon(Icons.confirmation_number, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          card.number!,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                  ),

                // main content area (question or answer, top-left anchored)
                Expanded(
                  child: Stack(
                    children: [
                      ScrollConfiguration(
                        behavior: const _NoGlow(),
                        child: SingleChildScrollView(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: revealed
                                ? Text(
                                    card.answer,
                                    key: const ValueKey('answer'),
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                      height: 1.2,
                                    ),
                                  )
                                : Text(
                                    card.question,
                                    key: const ValueKey('question'),
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                      height: 1.2,
                                    ),
                                  ),
                          ),
                        ),
                      ),

                      // favorite + note buttons inside top-right corner of content area
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              splashRadius: 24,
                              tooltip: note.isNotEmpty
                                  ? 'Notiz bearbeiten'
                                  : 'Notiz hinzufügen',
                              onPressed: () => _openNoteEditor(context),
                              icon: Icon(
                                note.isNotEmpty
                                    ? Icons.edit_note_rounded
                                    : Icons.note_add_outlined,
                                size: 26,
                                color: note.isNotEmpty
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withOpacity(0.6),
                              ),
                            ),
                            IconButton(
                              splashRadius: 24,
                              tooltip: isFavorite
                                  ? 'Aus Favoriten entfernen'
                                  : 'Zu Favoriten',
                              onPressed: onToggleFavorite,
                              icon: Icon(
                                isFavorite
                                    ? Icons.star_rounded
                                    : Icons.star_border_rounded,
                                size: 26,
                                color: isFavorite
                                    ? Colors.amber
                                    : Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withOpacity(0.6),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                if (note.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _NotePreview(
                    text: note,
                    onTap: () => _openNoteEditor(context),
                  ),
                ],

                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.touch_app, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      revealed
                          ? 'Tippe, um die Frage zu zeigen'
                          : 'Tippe, um die Antwort zu zeigen',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontStyle: FontStyle.italic,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.65),
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

  Widget _dismissBg({required bool left}) {
    return Container(
      alignment: left ? Alignment.centerLeft : Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: (left ? Colors.green : Colors.red).withOpacity(0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(
        left ? Icons.check_rounded : Icons.close_rounded,
        size: 32,
        color: left ? Colors.green : Colors.red,
      ),
    );
  }

  Future<void> _openNoteEditor(BuildContext context) async {
    final controller = TextEditingController(text: note);
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(
              left: 16, right: 16, bottom: bottomInset + 16, top: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.edit_note_rounded),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Notiz zur Karte',
                      style: Theme.of(ctx)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => controller.clear(),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Leeren'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                maxLines: null,
                minLines: 4,
                autofocus: true,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: 'Schreibe deine Gedanken, Eselsbrücken oder Links…',
                  border:
                      OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(ctx).pop(null),
                      icon: const Icon(Icons.close),
                      label: const Text('Abbrechen'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () =>
                          Navigator.of(ctx).pop(controller.text.trim()),
                      icon: const Icon(Icons.save_rounded),
                      label: const Text('Speichern'),
                      style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );

    if (result != null) {
      HapticFeedback.selectionClick();
      onEditNote(result);
    }
  }
}

class _NotePreview extends StatelessWidget {
  const _NotePreview({required this.text, required this.onTap});
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final preview = text.split('\n').first.trim();
    return Material(
      color:
          Theme.of(context).colorScheme.secondaryContainer.withOpacity(0.4),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
          child: Row(
            children: [
              const Icon(Icons.sticky_note_2_outlined, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  preview.isEmpty ? '(Notiz bearbeiten …)' : preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13, fontStyle: FontStyle.italic),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.edit_outlined, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoGlow extends ScrollBehavior {
  const _NoGlow();
  @override
  Widget buildOverscrollIndicator(
      BuildContext context, Widget child, ScrollableDetails details) {
    return child;
  }
}
