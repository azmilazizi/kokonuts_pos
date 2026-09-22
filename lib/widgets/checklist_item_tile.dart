import 'package:flutter/material.dart';

import '../models/checklist_template.dart';

/// Shared tri-state row used by both the SOP checklist dialog and the
/// standalone Equipment Checklist screen — tap toggles checked, long-press
/// toggles excluded.
class ChecklistItemTile extends StatelessWidget {
  const ChecklistItemTile({
    super.key,
    required this.item,
    required this.status,
    required this.onTap,
    required this.onLongPress,
  });

  final ChecklistItem item;
  final ChecklistItemStatus status;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final Icon icon;
    switch (status) {
      case ChecklistItemStatus.checked:
        icon = const Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 26);
        break;
      case ChecklistItemStatus.excluded:
        icon = const Icon(Icons.remove_circle, color: Color(0xFFBDBDBD), size: 26);
        break;
      case ChecklistItemStatus.unchecked:
        icon = const Icon(Icons.radio_button_unchecked, color: Color(0xFFBDBDBD), size: 26);
        break;
    }
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            icon,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.label,
                    style: TextStyle(
                      fontSize: 15,
                      decoration: status == ChecklistItemStatus.excluded
                          ? TextDecoration.lineThrough
                          : null,
                      color: status == ChecklistItemStatus.excluded
                          ? const Color(0xFF9E9E9E)
                          : Colors.black87,
                    ),
                  ),
                  if ((item.description ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        item.description!,
                        style: const TextStyle(fontSize: 12, color: Color(0xFF9E9E9E)),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Section header with a derived "n/m" rollup (excluded items removed from
/// the denominator). Pass [onToggle] to make it a collapse/expand control —
/// [collapsed] then drives which chevron shows.
class ChecklistGroupHeader extends StatelessWidget {
  const ChecklistGroupHeader({
    super.key,
    required this.title,
    required this.done,
    required this.total,
    this.collapsed = false,
    this.onToggle,
  });

  final String title;
  final int done;
  final int total;
  final bool collapsed;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 2),
      child: Row(
        children: [
          if (onToggle != null)
            Icon(
              collapsed ? Icons.chevron_right : Icons.expand_more,
              size: 20,
              color: const Color(0xFF757575),
            ),
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF757575),
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$done/$total',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: total > 0 && done == total
                  ? const Color(0xFF4CAF50)
                  : const Color(0xFFEF6C00),
            ),
          ),
        ],
      ),
    );

    if (onToggle == null) return content;
    return InkWell(onTap: onToggle, child: content);
  }
}
