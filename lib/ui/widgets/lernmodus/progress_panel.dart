import 'package:flutter/material.dart';
import '../../state/lernmodus_controller.dart';
import 'segment_bar.dart';

class ProgressPanel extends StatefulWidget {
  const ProgressPanel({
    super.key,
    required this.buckets,
    required this.total,
    required this.favoritesCount,
    required this.notesCount,
    required this.randomOrder,
    required this.filter,
    required this.onlyFavorites,
    required this.onChangeFilter,
    required this.onToggleRandom,
    required this.onToggleOnlyFavorites,
  });

  final ({int zero, int one, int twoPlus}) buckets;
  final int total;
  final int favoritesCount;
  final int notesCount;

  final bool randomOrder;
  final FocusFilter filter;
  final bool onlyFavorites;

  final ValueChanged<FocusFilter> onChangeFilter;
  final ValueChanged<bool> onToggleRandom;
  final ValueChanged<bool> onToggleOnlyFavorites;

  @override
  State<ProgressPanel> createState() => _ProgressPanelState();
}

class _ProgressPanelState extends State<ProgressPanel> {
  bool _show = false;

  @override
  Widget build(BuildContext context) {
    final b = widget.buckets;
    final total = widget.total;
    double f(int n) => total == 0 ? 0 : n / total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _show = !_show),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                SizedBox(
                  height: 22,
                  child: Row(
                    children: [
                      SegmentBarPortion(fraction: f(b.zero), color: Colors.red, label: '${b.zero}'),
                      SegmentBarPortion(fraction: f(b.one), color: Colors.orange, label: '${b.one}'),
                      SegmentBarPortion(fraction: f(b.twoPlus), color: Colors.green, label: '${b.twoPlus}'),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Gesamt: $total  •  Favoriten: ${widget.favoritesCount}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                    Row(
                      children: [
                        const Icon(Icons.shuffle, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          widget.randomOrder ? 'Zufällig' : 'Sortiert',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 200),
          crossFadeState: _show ? CrossFadeState.showFirst : CrossFadeState.showSecond,
          firstChild: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              children: [
                Wrap(
                  spacing: 8,
                  children: [
                    _chip(context, 'Alle ($total)', FocusFilter.all),
                    _chip(context, '0× (${b.zero})', FocusFilter.zero, color: Colors.red),
                    _chip(context, '1× (${b.one})', FocusFilter.one, color: Colors.orange),
                    _chip(context, '2+× (${b.twoPlus})', FocusFilter.twoPlus, color: Colors.green),
                  ],
                ),
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  value: widget.randomOrder,
                  onChanged: widget.onToggleRandom,
                  secondary: const Icon(Icons.shuffle),
                  title: const Text('Zufällige Reihenfolge', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    widget.randomOrder
                        ? 'Karten werden in zufälliger, stabiler Reihenfolge angezeigt.'
                        : 'Karten folgen der sortierten Reihenfolge.',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8)),
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
                SwitchListTile.adaptive(
                  value: widget.onlyFavorites,
                  onChanged: widget.onToggleOnlyFavorites,
                  secondary: const Icon(Icons.star_rounded),
                  title: const Text('Nur Favoriten anzeigen', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    'Zeigt nur Karten, die du gespeichert hast.',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8)),
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          secondChild: const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _chip(BuildContext context, String label, FocusFilter f, {Color? color}) {
    final selected = widget.filter == f;
    final c = color ?? Theme.of(context).colorScheme.primary;
    return FilterChip(
      selected: selected,
      label: Text(label),
      onSelected: (_) => widget.onChangeFilter(f),
      selectedColor: c.withOpacity(0.15),
      checkmarkColor: c,
      side: BorderSide(color: c.withOpacity(0.5)),
      showCheckmark: selected,
      labelStyle: TextStyle(
        color: selected ? c : null,
        fontWeight: selected ? FontWeight.w600 : null,
      ),
    );
  }
}
