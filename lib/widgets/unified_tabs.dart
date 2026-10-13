import 'package:flutter/material.dart';

import '../core/app_theme.dart';

/// Single underline-tab language used across the app.
///
/// Light variant (on white): active [AppTheme.accentOrange] w700 14sp with a
/// 36x3 rounded indicator, inactive [AppTheme.textSecondary] w600.
/// Dark variant (on navy, e.g. Orders): active white w700, inactive white70.
class UnifiedTabs extends StatelessWidget {
  const UnifiedTabs({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
    this.dark = false,
    this.expanded = false,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final bool dark;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final activeColor =
        dark ? AppTheme.backgroundWhite : AppTheme.accentOrange;
    final inactiveColor =
        dark ? Colors.white70 : AppTheme.textSecondary;
    final tabs = List.generate(labels.length, (i) {
      final selected = i == selectedIndex;
      final tab = InkWell(
        onTap: () => onChanged(i),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                labels[i],
                style: TextStyle(
                  fontSize: 14,
                  fontWeight:
                      selected ? FontWeight.w700 : FontWeight.w600,
                  color: selected ? activeColor : inactiveColor,
                ),
              ),
              const SizedBox(height: 6),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 3,
                width: selected ? 36 : 0,
                decoration: BoxDecoration(
                  color: dark
                      ? AppTheme.backgroundWhite
                      : AppTheme.accentOrange,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ],
          ),
        ),
      );
      if (expanded) return Expanded(child: Center(child: tab));
      return tab;
    });
    if (expanded) {
      return Row(children: tabs);
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: tabs),
    );
  }
}

/// Store-section pills — Tawseel-One-like horizontal pills with Saree identity
/// (navy + orange). Few items expand edge-to-edge to fill the width; many
/// items scroll sideways.
class StoreSectionPills extends StatelessWidget {
  const StoreSectionPills({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
    this.maxExpanded = 4,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final int maxExpanded;

  @override
  Widget build(BuildContext context) {
    final pills = List.generate(labels.length, (i) {
      final selected = i == selectedIndex;
      return Padding(
        padding: EdgeInsetsDirectional.only(
          start: i == 0 ? 0 : 8,
          end: i == labels.length - 1 ? 0 : 0,
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          child: Material(
            color: selected
                ? AppTheme.accentOrange
                : AppTheme.surfaceGrey,
            borderRadius: BorderRadius.circular(12),
            elevation: 0,
            shadowColor: AppTheme.accentOrange.withValues(alpha: 0.3),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => onChanged(i),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: selected
                    ? BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.accentOrange.withValues(
                              alpha: 0.35,
                            ),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      )
                    : BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppTheme.primaryNavy.withValues(
                            alpha: 0.08,
                          ),
                        ),
                      ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (selected)
                      const Padding(
                        padding: EdgeInsetsDirectional.only(end: 6),
                        child: Icon(
                          Icons.check_rounded,
                          size: 15,
                          color: Colors.white,
                        ),
                      ),
                    Flexible(
                      child: Text(
                        labels[i],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: selected
                              ? Colors.white
                              : AppTheme.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    });

    // Few sections → distribute edge-to-edge across the screen width.
    if (labels.length <= maxExpanded) {
      return Row(
        children: [
          for (var i = 0; i < pills.length; i++) Expanded(child: pills[i]),
        ],
      );
    }
    // Many sections → sideways scroll.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: pills),
    );
  }
}
