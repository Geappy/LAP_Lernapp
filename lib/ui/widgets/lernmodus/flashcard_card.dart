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
  final VoidCallback onSwipeRight; // “right / correct” (only when revealed)
  final VoidCallback onSwipeLeft;  // “left / wrong”    (only when revealed)
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

    // only allow swipe when the answer is revealed (to avoid accidental grading)
    final dismissDirection =
        revealed ? DismissDirection.horizontal : DismissDirection.none;

    final key = ValueKey(
      'card_${card.id}_${revealed ? 1 : 0}_${isFavorite ? 1 : 0}_${note.isNotEmpty ? 1 : 0}',
    );

    return Dismissible(
      key: key,
      direction: dismissDirection,
      background: _dismissBg(left: true),
      secondaryBackground: _dismissBg(left: false),
      confirmDismiss: (dir) async {
        if (!revealed) return false;
        if (dir == DismissDirection.startToEnd) {
          HapticFeedback.lightImpact();
          onSwipeRight(); // correct
        } else if (dir == DismissDirection.endToStart) {
          HapticFeedback.lightImpact();
          onSwipeLeft(); // wrong
        }
        return false; // don’t remove the widget; we handled it
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
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // top row: meta + actions (kept OUTSIDE the text area)
                _HeaderRow(
                  number: card.number,
                  isFavorite: isFavorite,
                  hasNote: note.trim().isNotEmpty,
                  onToggleFavorite: onToggleFavorite,
                  onEditNotePressed: () => _openNoteEditor(context),
                ),
                const SizedBox(height: 8),

                // the single-content area: either question OR answer
                Expanded(
                  child: _CardContentArea(
                    revealed: revealed,
                    question: card.question,
                    answer: card.answer,
                  ),
                ),

                // optional note preview (small, below text, no overlap)
                if (note.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _NotePreview(
                    text: note,
                    onTap: () => _openNoteEditor(context),
                  ),
                ],

                const SizedBox(height: 6),
                // little hint row
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
            left: 16,
            right: 16,
            bottom: bottomInset + 16,
            top: 8,
          ),
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
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
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
                  hintText:
                      'Schreibe deine Gedanken, Eselsbrücken oder Links…',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
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
                        minimumSize: const Size.fromHeight(48),
                      ),
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

/// Top row with card number (if any) and action buttons.
/// Kept separate from the main text to avoid overlap.
class _HeaderRow extends StatelessWidget {
  const _HeaderRow({
    required this.number,
    required this.isFavorite,
    required this.hasNote,
    required this.onToggleFavorite,
    required this.onEditNotePressed,
  });

  final String? number;
  final bool isFavorite;
  final bool hasNote;
  final VoidCallback onToggleFavorite;
  final VoidCallback onEditNotePressed;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if ((number ?? '').isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: onSurface.withOpacity(0.06),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.confirmation_number, size: 14),
                const SizedBox(width: 6),
                Text(
                  number!,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                    color: onSurface.withOpacity(0.75),
                  ),
                ),
              ],
            ),
          ),
        const Spacer(),
        IconButton(
          splashRadius: 22,
          tooltip: hasNote ? 'Notiz bearbeiten' : 'Notiz hinzufügen',
          onPressed: onEditNotePressed,
          icon: Icon(
            hasNote ? Icons.edit_note_rounded : Icons.note_add_outlined,
            size: 24,
            color: hasNote
                ? Theme.of(context).colorScheme.primary
                : onSurface.withOpacity(0.7),
          ),
        ),
        IconButton(
          splashRadius: 22,
          tooltip: isFavorite ? 'Aus Favoriten entfernen' : 'Zu Favoriten',
          onPressed: onToggleFavorite,
          icon: Icon(
            isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
            size: 24,
            color: isFavorite
                ? Colors.amber
                : onSurface.withOpacity(0.7),
          ),
        ),
      ],
    );
  }
}

/// The main content area that shows either the question OR the answer.
/// - It’s scrollable (no overflow)
/// - It animates between sides
class _CardContentArea extends StatelessWidget {
  const _CardContentArea({
    required this.revealed,
    required this.question,
    required this.answer,
  });

  final bool revealed;
  final String question;
  final String answer;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textStyle = const TextStyle(fontSize: 18, height: 1.35);

    final widgetShown = _ScrollableText(
      text: revealed ? answer : question,
      textStyle: textStyle,
      hintColor: cs.onSurface.withOpacity(0.35),
    );

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, anim) {
        // A subtle scale+fade; feels like a flip without heavy 3D
        return FadeTransition(
          opacity: anim,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.98, end: 1.0).animate(anim),
            child: child,
          ),
        );
      },
      child: widgetShown,
    );
  }
}

/// Scrollable text box with soft edge gradient and no overscroll glow.
class _ScrollableText extends StatelessWidget {
  const _ScrollableText({
    required this.text,
    required this.textStyle,
    required this.hintColor,
  });

  final String text;
  final TextStyle textStyle;
  final Color hintColor;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(
            color: hintColor,
            width: 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          children: [
            ScrollConfiguration(
              behavior: const _NoGlowBehavior(),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Text(text, style: textStyle),
              ),
            ),
            // bottom fade to hint there’s more
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Theme.of(context)
                            .colorScheme
                            .surface
                            .withOpacity(0.0),
                        Theme.of(context)
                            .colorScheme
                            .surface
                            .withOpacity(0.0),
                      ],
                      stops: const [0.0, 0.0],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotePreview extends StatelessWidget {
  const _NotePreview({
    required this.text,
    required this.onTap,
  });

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final preview = text.split('\n').first.trim();
    return Material(
      color: Theme.of(context)
          .colorScheme
          .secondaryContainer
          .withOpacity(0.4),
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
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                  ),
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
  Widget buildOverscrollIndicator(
      BuildContext context, Widget child, ScrollableDetails details) {
    // just return the child → disables the glow
    return child;
  }
}
