import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../models/flashcard.dart';
import 'note_preview.dart';

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

  Color _bucketColor(int correct) {
    if (correct >= 2) return Colors.green;
    if (correct == 1) return Colors.orange;
    return Colors.red;
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
          padding: EdgeInsets.only(left: 16, right: 16, bottom: bottomInset + 16, top: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.edit_note_rounded),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Notiz zur Karte',
                        style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
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
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
                      onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
                      icon: const Icon(Icons.save_rounded),
                      label: const Text('Speichern'),
                      style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
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
      onEditNote(result);
      HapticFeedback.selectionClick();
    }
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = _bucketColor(correctCount);

    final key = ValueKey(
      'card_${card.id}_${revealed ? 1 : 0}_${isFavorite ? 1 : 0}_${note.isNotEmpty ? 1 : 0}',
    );

    return Dismissible(
      key: key,
      direction: revealed ? DismissDirection.horizontal : DismissDirection.none,
      background: _bg(context, Icons.check_rounded, Colors.green, Alignment.centerLeft),
      secondaryBackground: _bg(context, Icons.close_rounded, Colors.red, Alignment.centerRight),
      confirmDismiss: (dir) async {
        if (!revealed) return false;
        if (dir == DismissDirection.startToEnd) {
          HapticFeedback.lightImpact();
          onSwipeRight();
        } else if (dir == DismissDirection.endToStart) {
          HapticFeedback.lightImpact();
          onSwipeLeft();
        }
        return false; // we handle transitions ourselves
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
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if ((card.number ?? '').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6, right: 64),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.confirmation_number, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              card.number!,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Text(
                      card.question,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, height: 1.2),
                    ),
                    const SizedBox(height: 14),
                    Divider(height: 1, color: Theme.of(context).colorScheme.outline.withOpacity(0.25)),
                    const SizedBox(height: 10),
                    AnimatedCrossFade(
                      duration: const Duration(milliseconds: 200),
                      crossFadeState:
                          revealed ? CrossFadeState.showFirst : CrossFadeState.showSecond,
                      firstChild: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(card.answer, style: const TextStyle(fontSize: 18, height: 1.35)),
                          if (note.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            NotePreview(text: note, onTap: () => _openNoteEditor(context)),
                          ],
                        ],
                      ),
                      secondChild: Column(
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Theme.of(context).colorScheme.outline.withOpacity(0.35),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.touch_app, size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  'Tippe, um die Antwort anzuzeigen',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontStyle: FontStyle.italic,
                                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.65),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (note.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            NotePreview(text: note, onTap: () => _openNoteEditor(context)),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        splashRadius: 24,
                        tooltip: note.isNotEmpty ? 'Notiz bearbeiten' : 'Notiz hinzufügen',
                        onPressed: () => _openNoteEditor(context),
                        icon: Icon(
                          note.isNotEmpty ? Icons.edit_note_rounded : Icons.note_add_outlined,
                          size: 26,
                          color: note.isNotEmpty
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                      IconButton(
                        splashRadius: 24,
                        tooltip: isFavorite ? 'Aus Favoriten entfernen' : 'Zu Favoriten',
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          onToggleFavorite();
                        },
                        icon: Icon(
                          isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                          size: 26,
                          color: isFavorite
                              ? Colors.amber
                              : Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bg(BuildContext context, IconData icon, Color color, Alignment align) {
    return Container(
      alignment: align,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(icon, size: 32),
    );
  }
}
