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
    required this.onEditNote, // expects new note text
  });

  final Flashcard card;
  final bool revealed;
  final bool isFavorite;
  final String note;
  final int correctCount;

  final VoidCallback onToggleReveal;
  final VoidCallback onSwipeRight; // "right" = correct
  final VoidCallback onSwipeLeft;  // "left"  = wrong
  final VoidCallback onToggleFavorite;
  final ValueChanged<String> onEditNote;

  Color get _borderColor {
    if (correctCount >= 2) return Colors.green;
    if (correctCount == 1) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    final listChild = _CardInner(
      card: card,
      revealed: revealed,
      isFavorite: isFavorite,
      note: note,
      borderColor: _borderColor,
      onToggleReveal: onToggleReveal,
      onToggleFavorite: onToggleFavorite,
      onTapEditNote: () => _openNoteEditor(context, initial: note),
    );

    // Enable swipe only when the answer is revealed
    if (!revealed) {
      return listChild;
    }

    return Dismissible(
      key: ValueKey('fc_${card.id}_${revealed ? 1 : 0}_${isFavorite ? 1 : 0}'),
      direction: DismissDirection.horizontal,
      background: _swipeBg(context, Icons.check_rounded, Colors.green, Alignment.centerLeft),
      secondaryBackground: _swipeBg(context, Icons.close_rounded, Colors.red, Alignment.centerRight),
      confirmDismiss: (dir) async {
        HapticFeedback.lightImpact();
        if (dir == DismissDirection.startToEnd) {
          onSwipeRight(); // correct
        } else if (dir == DismissDirection.endToStart) {
          onSwipeLeft(); // wrong
        }
        return false; // we handle progression externally
      },
      child: listChild,
    );
  }

  Widget _swipeBg(BuildContext ctx, IconData icon, Color color, Alignment align) {
    return Container(
      alignment: align,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(icon, size: 32, color: color),
    );
  }

  Future<void> _openNoteEditor(BuildContext context, {required String initial}) async {
    final controller = TextEditingController(text: initial);
    final res = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final bottom = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, bottom + 16),
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
                autofocus: true,
                minLines: 4,
                maxLines: null,
                decoration: InputDecoration(
                  hintText: 'Schreibe Gedanken, Eselsbrücken, Links …',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(ctx, null),
                      icon: const Icon(Icons.close),
                      label: const Text('Abbrechen'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.pop(ctx, controller.text.trim()),
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

    if (res != null) {
      onEditNote(res);
      HapticFeedback.selectionClick();
    }
  }
}

class _CardInner extends StatelessWidget {
  const _CardInner({
    required this.card,
    required this.revealed,
    required this.isFavorite,
    required this.note,
    required this.borderColor,
    required this.onToggleReveal,
    required this.onToggleFavorite,
    required this.onTapEditNote,
  });

  final Flashcard card;
  final bool revealed;
  final bool isFavorite;
  final String note;
  final Color borderColor;

  final VoidCallback onToggleReveal;
  final VoidCallback onToggleFavorite;
  final VoidCallback onTapEditNote;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onToggleReveal, // tap flips between Q/A; only one is visible
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [cs.surface, cs.surfaceContainerHighest],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColor.withOpacity(0.6), width: 2.5),
          boxShadow: [BoxShadow(color: borderColor.withOpacity(0.12), blurRadius: 16, offset: const Offset(0, 8))],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Header: number (if any) + actions
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if ((card.number ?? '').isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: cs.secondaryContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.confirmation_number, size: 14),
                          const SizedBox(width: 6),
                          Text(
                            card.number!,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                              color: cs.onSecondaryContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const Spacer(),
                  IconButton(
                    tooltip: note.trim().isEmpty ? 'Notiz hinzufügen' : 'Notiz bearbeiten',
                    onPressed: onTapEditNote,
                    icon: Icon(
                      note.trim().isEmpty ? Icons.note_add_outlined : Icons.edit_note_rounded,
                      size: 24,
                      color: note.trim().isEmpty ? cs.onSurface.withOpacity(0.65) : cs.primary,
                    ),
                  ),
                  IconButton(
                    tooltip: isFavorite ? 'Aus Favoriten entfernen' : 'Zu Favoriten',
                    onPressed: onToggleFavorite,
                    icon: Icon(
                      isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                      size: 24,
                      color: isFavorite ? Colors.amber : cs.onSurface.withOpacity(0.65),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Content area: ONLY question OR ONLY answer. Scrolls if long.
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: ScrollConfiguration(
                    behavior: const _NoGlowBehavior(),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                      child: Text(
                        revealed ? card.answer : card.question,
                        textAlign: TextAlign.start,
                        style: TextStyle(
                          fontSize: revealed ? 18 : 20,
                          height: 1.35,
                          fontWeight: revealed ? FontWeight.w400 : FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 10),

              // Hint bar when hidden
              if (!revealed)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: cs.outline.withOpacity(0.35)),
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
                          color: cs.onSurface.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ),

              // Note preview (always below text, never overlaps it)
              if (note.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                _NotePreview(text: note, onTap: onTapEditNote),
              ],
            ],
          ),
        ),
      ),
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

class _NoGlowBehavior extends ScrollBehavior {
  const _NoGlowBehavior();

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) {
    // just return the child → disables the glow
    return child;
  }
}

