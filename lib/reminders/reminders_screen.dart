import 'package:flutter/material.dart';

import '../models/reminder.dart';
import '../services/checklist_service.dart';
import '../storage/checklist_run_store.dart';
import '../storage/reminder_store.dart';
import '../storage/secure_store.dart';

const _kOtherItemOption = 'Other (type below)';
const _kReasonOptions = [
  'Restock',
  'To Bring',
  'Others',
];

/// Restock reminders — a persistent, per-device "don't forget to top this up"
/// list. Deliberately simple: add an item + reason, see it in the list with
/// when it was flagged, clear it once actually restocked. The sidebar badge
/// (see ReminderStore.countNotifier) is what makes this hard to forget —
/// it stays lit until each entry is cleared, unlike a one-time popup.
class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key, required this.header});

  final Widget header;

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  final _store = ReminderStore();
  bool _isLoading = true;
  List<Reminder> _reminders = [];
  List<String> _equipmentItems = [];

  @override
  void initState() {
    super.initState();
    _load();
    _loadEquipmentItems();
  }

  Future<void> _load() async {
    final reminders = await _store.loadReminders();
    if (!mounted) return;
    setState(() {
      _reminders = reminders;
      _isLoading = false;
    });
  }

  // Sourced from the equipment checklist template so "Item" can be a
  // dropdown instead of free text. Best-effort: an empty list just falls
  // back to a plain text field in the dialog below.
  Future<void> _loadEquipmentItems() async {
    const secureStore = SecureStore();
    final token = await secureStore.readToken() ?? '';
    final warehouseKey = await secureStore.readWarehouseId() ?? 'default';

    var template = await ChecklistService().fetchTemplate(token, 'equipment');
    template ??= await ChecklistRunStore().loadCachedTemplate(warehouseKey);

    final labels = <String>{
      for (final item in template?.allItems ?? const [])
        if (item.label.isNotEmpty) item.label,
    }.toList()
      ..sort();

    if (!mounted) return;
    setState(() => _equipmentItems = labels);
  }

  Future<void> _clear(String id) async {
    await _store.clearReminder(id);
    await _load();
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Reminders?'),
        content: Text('This removes all ${_reminders.length} reminder(s).'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('CLEAR ALL'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _store.clearAll();
    await _load();
  }

  Future<void> _addReminder() async {
    final itemOtherCtrl = TextEditingController();
    final reasonOtherCtrl = TextEditingController();
    String? selectedItem;
    String? selectedReason;
    final hasEquipmentItems = _equipmentItems.isNotEmpty;

    final added = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final itemIsOther = !hasEquipmentItems || selectedItem == _kOtherItemOption;
          return AlertDialog(
            title: const Text('Add Reminder'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hasEquipmentItems)
                    DropdownButtonFormField<String>(
                      initialValue: selectedItem,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Item'),
                      items: [
                        for (final label in _equipmentItems)
                          DropdownMenuItem(
                            value: label,
                            child: Text(label, overflow: TextOverflow.ellipsis),
                          ),
                        const DropdownMenuItem(
                          value: _kOtherItemOption,
                          child: Text(_kOtherItemOption),
                        ),
                      ],
                      onChanged: (value) =>
                          setDialogState(() => selectedItem = value),
                    ),
                  if (itemIsOther) ...[
                    if (hasEquipmentItems) const SizedBox(height: 12),
                    TextField(
                      controller: itemOtherCtrl,
                      autofocus: !hasEquipmentItems,
                      decoration: const InputDecoration(labelText: 'Item'),
                    ),
                  ],
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedReason,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Reason'),
                    items: [
                      for (final reason in _kReasonOptions)
                        DropdownMenuItem(value: reason, child: Text(reason)),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => selectedReason = value),
                  ),
                  if (selectedReason == 'Others') ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: reasonOtherCtrl,
                      decoration: const InputDecoration(labelText: 'Specify reason'),
                      maxLines: 2,
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('CANCEL'),
              ),
              ElevatedButton(
                onPressed: () {
                  final itemName =
                      itemIsOther ? itemOtherCtrl.text.trim() : (selectedItem ?? '');
                  if (itemName.isEmpty) return;
                  Navigator.pop(ctx, true);
                },
                child: const Text('ADD'),
              ),
            ],
          );
        },
      ),
    );
    if (added != true) return;

    final itemIsOther = !hasEquipmentItems || selectedItem == _kOtherItemOption;
    final itemName = itemIsOther ? itemOtherCtrl.text.trim() : (selectedItem ?? '');
    final reason = selectedReason == 'Others'
        ? reasonOtherCtrl.text.trim()
        : (selectedReason ?? '');

    await _store.addReminder(itemName, reason);
    await _load();
  }

  String _formatTimestamp(DateTime dt) {
    final local = dt.toLocal();
    final h = (local.hour % 12 == 0 ? 12 : local.hour % 12).toString();
    final m = local.minute.toString().padLeft(2, '0');
    final ampm = local.hour >= 12 ? 'PM' : 'AM';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${local.day} ${months[local.month - 1]}, $h:$m $ampm';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        widget.header,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _reminders.isEmpty
                      ? 'No restock reminders'
                      : '${_reminders.length} restock reminder${_reminders.length == 1 ? '' : 's'}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF424242),
                  ),
                ),
              ),
              if (_reminders.isNotEmpty)
                TextButton(
                  onPressed: _clearAll,
                  child: const Text('CLEAR ALL'),
                ),
              TextButton.icon(
                onPressed: _addReminder,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('ADD'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _reminders.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle_outline,
                                size: 40, color: Color(0xFFA5D6A7)),
                            SizedBox(height: 12),
                            Text(
                              "You're all caught up — nothing flagged to restock.",
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Color(0xFF9E9E9E)),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: _reminders.length,
                      itemBuilder: (context, index) {
                        final reminder = _reminders[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: const BorderSide(color: Color(0xFFEEEEEE)),
                          ),
                          child: ExpansionTile(
                            leading: const Icon(Icons.error_outline,
                                color: Color(0xFFE67E22)),
                            title: Text(
                              reminder.itemLabel,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              'Flagged ${_formatTimestamp(reminder.createdAt)}',
                              style: const TextStyle(fontSize: 12, color: Color(0xFF9E9E9E)),
                            ),
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      reminder.reason.isEmpty
                                          ? 'No reason given.'
                                          : reminder.reason,
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: reminder.reason.isEmpty
                                            ? const Color(0xFF9E9E9E)
                                            : Colors.black87,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: TextButton(
                                        onPressed: () => _clear(reminder.id),
                                        child: const Text('CLEAR'),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
