import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

class SopChecklistResult {
  const SopChecklistResult({required this.templateId, required this.isComplete});

  final int templateId;
  final bool isComplete;

  Map<String, dynamic> toJson() => {
        'template_id': templateId,
        'is_complete': isComplete,
      };
}

final _placeholderPattern = RegExp(r'\{\{([^{}]+)\}\}');

String _escapeHtml(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

// SOP text is authored with {{Name}} placeholders referencing an equipment
// group or item. On the POS screen the braces are just noise — this strips
// them and highlights the name instead, in a different color depending on
// whether it names a group or a plain item (falling back to a neutral color
// for a name that no longer matches anything, e.g. a since-deleted item).
String _highlightPlaceholders(
  String html,
  Set<String> groupNames,
  Set<String> itemNames,
) {
  return html.replaceAllMapped(_placeholderPattern, (match) {
    final name = match.group(1)!.trim();
    final String style;
    if (groupNames.contains(name)) {
      style = 'background-color:#E1F5FE;color:#01579B;'
          'padding:1px 6px;border-radius:4px;font-weight:600;';
    } else if (itemNames.contains(name)) {
      style = 'background-color:#FFF3E0;color:#E65100;'
          'padding:1px 6px;border-radius:4px;font-weight:600;';
    } else {
      style = 'background-color:#F5F5F5;color:#757575;'
          'padding:1px 6px;border-radius:4px;';
    }
    return '<span style="$style">${_escapeHtml(name)}</span>';
  });
}

/// Shows the SOP as read-only instructions before Open/Close Shift — there's
/// nothing to check off, staff just read it and tap Continue. [instructions]
/// is HTML authored via the CRM's rich-text editor (bullet/numbered lists,
/// bold/italic), rendered here the same way recipe_dialog.dart renders
/// admin-authored HTML. [groupNames]/[itemNames] are that outlet's Equipment
/// checklist group and item names, used to color-code {{placeholder}} text.
Future<SopChecklistResult> showSopInstructionsDialog(
  BuildContext context, {
  required int templateId,
  required String title,
  required String instructions,
  Set<String> groupNames = const {},
  Set<String> itemNames = const {},
}) async {
  final highlighted = _highlightPlaceholders(instructions, groupNames, itemNames);
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      final size = MediaQuery.of(ctx).size;
      final maxWidth = size.width < 700 ? size.width * 0.94 : 760.0;
      final maxHeight = size.height * 0.9;
      return Dialog(
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
                const Divider(height: 20),
                Flexible(
                  child: SingleChildScrollView(
                    child: HtmlWidget(
                      highlighted,
                      textStyle: const TextStyle(fontSize: 15, height: 1.5, color: Colors.black87),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('CONTINUE'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  return SopChecklistResult(templateId: templateId, isComplete: true);
}
