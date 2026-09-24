import 'package:flutter/material.dart';

import '../services/checklist_service.dart';
import '../storage/secure_store.dart';
import '../widgets/sop_instructions_dialog.dart';

/// Standalone SOP reference — the Opening/Closing SOP text used to be a
/// forced step before opening/closing a shift; it's now just a lookup staff
/// can open anytime from the sidebar, under Settings.
class SopScreen extends StatelessWidget {
  const SopScreen({super.key, required this.header});

  final Widget header;

  static const _kGreen = Color(0xFFE67E22);

  // Fetches the SOP template for [type] and shows its instructions read-only.
  Future<void> _showSop(BuildContext context, String type, String title) async {
    const secureStore = SecureStore();
    final token = await secureStore.readToken();
    final template = await ChecklistService().fetchTemplate(token ?? '', type);
    final instructions = template?.sopText?.trim();
    if (template == null || instructions == null || instructions.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No SOP configured for this outlet yet.')),
        );
      }
      return;
    }
    if (!context.mounted) return;

    // Best-effort: lets {{placeholder}} text be color-coded as a group vs an
    // item. If this fetch fails, placeholders just render in the neutral
    // "unrecognized" style — never blocks showing the SOP itself.
    Set<String> groupNames = const {};
    Set<String> itemNames = const {};
    try {
      final equipment = await ChecklistService().fetchTemplate(token ?? '', 'equipment');
      if (equipment != null) {
        groupNames = equipment.groups.map((g) => g.name).toSet();
        itemNames = equipment.allItems.map((i) => i.label).toSet();
      }
    } catch (_) {
      // Ignore — placeholders fall back to the neutral highlight style.
    }
    if (!context.mounted) return;

    await showSopInstructionsDialog(
      context,
      templateId: template.id,
      title: title,
      instructions: instructions,
      groupNames: groupNames,
      itemNames: itemNames,
    );
  }

  Widget _sopTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: ListTile(
        leading: Icon(icon, color: _kGreen),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        header,
        Expanded(
          child: Container(
            color: const Color(0xFFF5F6FA),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const Text(
                  'STANDARD OPERATING PROCEDURES',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: Color(0xFF757575),
                  ),
                ),
                const SizedBox(height: 8),
                _sopTile(
                  context,
                  icon: Icons.wb_sunny_outlined,
                  title: 'Opening SOP',
                  subtitle: 'Steps to follow when opening the shift',
                  onTap: () => _showSop(context, 'sop_open', 'Opening SOP'),
                ),
                const SizedBox(height: 12),
                _sopTile(
                  context,
                  icon: Icons.nights_stay_outlined,
                  title: 'Closing SOP',
                  subtitle: 'Steps to follow when closing the shift',
                  onTap: () => _showSop(context, 'sop_close', 'Closing SOP'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
