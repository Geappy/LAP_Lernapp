// lib/screens/widgets/lernmodus/flashcard_card.dart
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
  final Future<void> Function(String newText) onEditNote;

  Color get _borderColor {
    if (correctCount >= 2) return Colors.green;
    if (correctCount == 1) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Dismissible(
      key: ValueKey('flash_${card.id}_${revealed ? 1 : 0}_${isFavorite ? 1 : 0}'),
      direction: revealed ? DismissDirection.horizontal : DismissDirection.none,
      background: _dismissBg(Colors.green, Alignment.centerLeft, Icons.check_rounded),
      secondaryBackground: _dismissBg(Colors.red, Alignment.centerRight, Icons.close_rounded),
      confirmDismiss: (dir) async {
        if (!revealed) return false;
        HapticFeedback.lightImpact();
        if (dir == DismissDirection.startToEnd) {
          onSwipeRight();
        } else if (dir == DismissDirection.endToStart) {
          onSwipeLeft();
        }
        return false; // never actually remove
      },
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onToggleReveal,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [cs.surface, cs.surfaceContainerHighest],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _borderColor.withOpacity(0.6), width: 2.5),
            boxShadow: [
              BoxShadow(
                color: _borderColor.withOpacity(0.12),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            // ↓ less top padding to pull header up
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // HEADER: number • note • favorite (tighter + higher)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if ((card.number ?? '').isNotEmpty)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.confirmation_number, size: 15),
                          const SizedBox(width: 4),
                          Text(
                            card.number!,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: cs.onSurface.withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                    const Spacer(),
                    // tighter icon button (note)
                    IconButton(
                      tooltip: note.trim().isEmpty ? 'Notiz hinzufügen' : 'Notiz bearbeiten',
                      onPressed: () async {
                        HapticFeedback.selectionClick();
                        final newText = await _editNoteSheet(context, initial: note);
                        if (newText != null) await onEditNote(newText);
                      },
                      icon: Icon(
                        note.trim().isEmpty ? Icons.note_add_outlined : Icons.edit_note_rounded,
                        size: 22,
                        color: note.trim().isEmpty ? cs.onSurface.withOpacity(0.6) : cs.primary,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                      splashRadius: 20,
                    ),
                    // tighter icon button (favorite)
                    IconButton(
                      tooltip: isFavorite ? 'Aus Favoriten entfernen' : 'Zu Favoriten',
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        onToggleFavorite();
                      },
                      icon: Icon(
                        isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                        size: 22,
                        color: isFavorite ? Colors.amber : cs.onSurface.withOpacity(0.6),
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                      splashRadius: 20,
                    ),
                  ],
                ),

                // tighter divider spacing
                Divider(height: 1, color: cs.outline.withOpacity(0.25)),
                const SizedBox(height: 6),

                // CONTENT: either Question OR Answer (never both)
                // Scrolls if too long => no overflow
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(right: 6),
                    physics: const BouncingScrollPhysics(),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Text(
                        revealed ? card.answer : card.question,
                        textAlign: TextAlign.left,
                        style: TextStyle(
                          fontSize: revealed ? 18 : 22,
                          height: revealed ? 1.35 : 1.2,
                          fontWeight: revealed ? FontWeight.w400 : FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                // HINT ROW
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.touch_app, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        revealed ? 'Tippe, um die Frage zu sehen' : 'Tippe, um die Antwort zu sehen',
                        style: TextStyle(
                          fontSize: 13,
                          fontStyle: FontStyle.italic,
                          color: cs.onSurface.withOpacity(0.65),
                        ),
                      ),
                    ],
                  ),
                ),

                // Optional one-line note preview
                if (note.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _NotePreview(
                    text: note,
                    onTap: () async {
                      final newText = await _editNoteSheet(context, initial: note);
                      if (newText != null) await onEditNote(newText);
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dismissBg(Color c, Alignment a, IconData icon) {
    return Container(
      alignment: a,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: c.withOpacity(0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(icon, size: 32, color: c),
    );
  }

  Future<String?> _editNoteSheet(BuildContext context, {required String initial}) async {
    final controller = TextEditingController(text: initial);
    return showModalBottomSheet<String>(
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
                    child: Text(
                      'Notiz zur Karte',
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
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
  }
}

class _NotePreview extends StatelessWidget {
  const _NotePreview({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final preview = text.split('\n').first.trim();

    return Material(
      color: cs.secondaryContainer.withOpacity(0.4),
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
                  style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic),
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
