import 'package:flutter/material.dart';
import '../../../models/deck.dart';

class DeckCard extends StatelessWidget {
  const DeckCard({
    super.key,
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
                  switch (v) {
                    case 'details':
                      onDetails();
                      break;
                    case 'rename':
                      onRename();
                      break;
                    case 'delete':
                      onDelete();
                      break;
                  }
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