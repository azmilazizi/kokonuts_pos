import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/checklist_template.dart';

/// Local-only persistence for the equipment checklist: the last-fetched
/// template (offline fallback) and the current home/on-site run state. Kept
/// as SharedPreferences JSON blobs rather than sqflite tables since this data
/// is small and infrequently changed — see catalog_cache.dart for the
/// heavier pattern used for actual catalog data.
class ChecklistRunStore {
  static const _templateKeyPrefix = 'equipment_checklist_template_';
  static const _runStateKey = 'equipment_checklist_run_state';

  Future<void> cacheTemplate(String warehouseKey, ChecklistTemplate template) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_templateKeyPrefix$warehouseKey',
      jsonEncode(template.toJson()),
    );
  }

  Future<ChecklistTemplate?> loadCachedTemplate(String warehouseKey) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_templateKeyPrefix$warehouseKey');
    if (raw == null) return null;
    try {
      return ChecklistTemplate.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<ChecklistRunState> loadRunState() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_runStateKey);
    if (raw == null) return ChecklistRunState.empty();
    try {
      return ChecklistRunState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return ChecklistRunState.empty();
    }
  }

  Future<void> saveState(ChecklistRunState state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_runStateKey, jsonEncode(state.toJson()));
  }

  Future<void> resetRun() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_runStateKey);
  }
}

enum ChecklistPass { home, onsite }

class ChecklistRunState {
  ChecklistRunState({
    required this.templateId,
    required this.home,
    required this.onsite,
    this.startedAt,
    this.homeCompletedAt,
    this.onsiteCompletedAt,
  });

  final int? templateId;
  final Map<int, ChecklistItemStatus> home;
  final Map<int, ChecklistItemStatus> onsite;
  // Set once, the first time any item in this run is touched — proves a
  // "new run" (via Start New Run) is genuinely new, not a reopened old one.
  final DateTime? startedAt;
  // Set the moment a pass becomes fully resolved, cleared the moment it
  // stops being fully resolved — this is what the lock banner shows.
  final DateTime? homeCompletedAt;
  final DateTime? onsiteCompletedAt;

  factory ChecklistRunState.empty() =>
      ChecklistRunState(templateId: null, home: {}, onsite: {});

  factory ChecklistRunState.fromJson(Map<String, dynamic> json) {
    Map<int, ChecklistItemStatus> parsePass(dynamic raw) {
      final map = <int, ChecklistItemStatus>{};
      if (raw is Map) {
        raw.forEach((key, value) {
          final id = int.tryParse(key.toString());
          if (id != null) {
            map[id] = ChecklistItemStatus.fromName(value?.toString());
          }
        });
      }
      return map;
    }

    DateTime? parseDate(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());

    return ChecklistRunState(
      templateId: json['template_id'] != null
          ? int.tryParse(json['template_id'].toString())
          : null,
      home: parsePass(json['home']),
      onsite: parsePass(json['onsite']),
      startedAt: parseDate(json['started_at']),
      homeCompletedAt: parseDate(json['home_completed_at']),
      onsiteCompletedAt: parseDate(json['onsite_completed_at']),
    );
  }

  Map<String, dynamic> toJson() => {
        'template_id': templateId,
        'home': home.map((k, v) => MapEntry(k.toString(), v.name)),
        'onsite': onsite.map((k, v) => MapEntry(k.toString(), v.name)),
        'started_at': startedAt?.toIso8601String(),
        'home_completed_at': homeCompletedAt?.toIso8601String(),
        'onsite_completed_at': onsiteCompletedAt?.toIso8601String(),
      };

  ChecklistItemStatus statusFor(ChecklistPass pass, int itemId) {
    final map = pass == ChecklistPass.home ? home : onsite;
    return map[itemId] ?? ChecklistItemStatus.unchecked;
  }

  DateTime? completedAtFor(ChecklistPass pass) =>
      pass == ChecklistPass.home ? homeCompletedAt : onsiteCompletedAt;

  ChecklistRunState withItemStatus(
    ChecklistPass pass,
    int itemId,
    ChecklistItemStatus status, {
    int? templateId,
  }) {
    final newHome = Map<int, ChecklistItemStatus>.from(home);
    final newOnsite = Map<int, ChecklistItemStatus>.from(onsite);
    if (pass == ChecklistPass.home) {
      newHome[itemId] = status;
    } else {
      newOnsite[itemId] = status;
    }
    return copyWith(
      templateId: templateId,
      home: newHome,
      onsite: newOnsite,
      startedAt: startedAt ?? DateTime.now(),
    );
  }

  ChecklistRunState withCompletion(ChecklistPass pass, bool isComplete) {
    final at = isComplete ? DateTime.now() : null;
    if (pass == ChecklistPass.home) {
      return copyWith(homeCompletedAt: at, clearHomeCompletedAt: !isComplete);
    }
    return copyWith(onsiteCompletedAt: at, clearOnsiteCompletedAt: !isComplete);
  }

  ChecklistRunState copyWith({
    int? templateId,
    Map<int, ChecklistItemStatus>? home,
    Map<int, ChecklistItemStatus>? onsite,
    DateTime? startedAt,
    DateTime? homeCompletedAt,
    bool clearHomeCompletedAt = false,
    DateTime? onsiteCompletedAt,
    bool clearOnsiteCompletedAt = false,
  }) {
    return ChecklistRunState(
      templateId: templateId ?? this.templateId,
      home: home ?? this.home,
      onsite: onsite ?? this.onsite,
      startedAt: startedAt ?? this.startedAt,
      homeCompletedAt:
          clearHomeCompletedAt ? null : (homeCompletedAt ?? this.homeCompletedAt),
      onsiteCompletedAt:
          clearOnsiteCompletedAt ? null : (onsiteCompletedAt ?? this.onsiteCompletedAt),
    );
  }
}
