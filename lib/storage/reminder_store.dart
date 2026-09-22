import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/reminder.dart';

/// Local, per-device restock reminders — "top up X before tomorrow" notes
/// with a reason, cleared individually once actually restocked. Kept local
/// (SharedPreferences) rather than server-side: this is a personal nudge for
/// whoever runs this device, not data other outlets or the CRM need to see,
/// so there's no reason to pay for a backend round-trip to read or write it.
class ReminderStore {
  static const _key = 'restock_reminders';

  // Sidebar badge reads this directly (ValueListenableBuilder) instead of
  // main.dart re-querying storage on every rebuild — kept in sync by every
  // mutating call below, and primed once via refreshCount() on app start.
  static final ValueNotifier<int> countNotifier = ValueNotifier<int>(0);

  Future<List<Reminder>> loadReminders() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw) as List;
      final reminders = decoded
          .whereType<Map<String, dynamic>>()
          .map(Reminder.fromJson)
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return reminders;
    } catch (_) {
      return [];
    }
  }

  Future<void> refreshCount() async {
    countNotifier.value = (await loadReminders()).length;
  }

  Future<void> _save(List<Reminder> reminders) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(reminders.map((r) => r.toJson()).toList()),
    );
    countNotifier.value = reminders.length;
  }

  Future<void> addReminder(String itemLabel, String reason) async {
    final reminders = await loadReminders();
    reminders.insert(
      0,
      Reminder(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        itemLabel: itemLabel,
        reason: reason,
        createdAt: DateTime.now(),
      ),
    );
    await _save(reminders);
  }

  Future<void> clearReminder(String id) async {
    final reminders = await loadReminders();
    reminders.removeWhere((r) => r.id == id);
    await _save(reminders);
  }

  Future<void> clearAll() async {
    await _save([]);
  }
}
