import 'package:flutter/material.dart';

class NotePreview extends StatelessWidget {
  const NotePreview({super.key, required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final preview = text.split('\n').first.trim();
    return Material(
      color: Theme.of(context).colorScheme.secondaryContainer.withOpacity(0.4),
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
