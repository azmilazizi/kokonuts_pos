enum ChecklistItemStatus {
  unchecked,
  checked,
  excluded;

  static ChecklistItemStatus fromName(String? name) {
    switch (name) {
      case 'checked':
        return ChecklistItemStatus.checked;
      case 'excluded':
        return ChecklistItemStatus.excluded;
      default:
        return ChecklistItemStatus.unchecked;
    }
  }
}

class ChecklistItem {
  const ChecklistItem({
    required this.id,
    required this.label,
    this.description,
    this.groupId,
    this.sortOrder = 0,
  });

  final int id;
  final String label;
  final String? description;
  final int? groupId;
  final int sortOrder;

  factory ChecklistItem.fromJson(Map<String, dynamic> json) {
    return ChecklistItem(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      label: json['label']?.toString() ?? '',
      description: json['description']?.toString(),
      groupId: json['group_id'] != null
          ? int.tryParse(json['group_id'].toString())
          : null,
      sortOrder: int.tryParse(json['sort_order']?.toString() ?? '') ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'description': description,
        'group_id': groupId,
        'sort_order': sortOrder,
      };
}

class ChecklistGroup {
  const ChecklistGroup({
    required this.id,
    required this.name,
    this.transportRole,
    this.onsiteRole,
    this.items = const [],
  });

  final int id;
  final String name;
  final String? transportRole;
  final String? onsiteRole;
  final List<ChecklistItem> items;

  factory ChecklistGroup.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return ChecklistGroup(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      name: json['name']?.toString() ?? '',
      transportRole: json['transport_role']?.toString(),
      onsiteRole: json['onsite_role']?.toString(),
      items: rawItems is List
          ? rawItems
              .whereType<Map<String, dynamic>>()
              .map(ChecklistItem.fromJson)
              .toList()
          : const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'transport_role': transportRole,
        'onsite_role': onsiteRole,
        'items': items.map((i) => i.toJson()).toList(),
      };
}

class ChecklistTemplate {
  const ChecklistTemplate({
    required this.id,
    required this.type,
    this.warehouseId,
    required this.name,
    this.groups = const [],
    this.standaloneItems = const [],
    this.sopText,
  });

  final int id;
  final String type;
  final int? warehouseId;
  final String name;
  final List<ChecklistGroup> groups;
  final List<ChecklistItem> standaloneItems;
  // Opening/Closing SOP templates are free text instead of groups/items —
  // groups/standaloneItems stay empty for those and this carries the
  // instructions instead. Equipment templates use groups/items and leave
  // this null.
  final String? sopText;

  List<ChecklistItem> get allItems => [
        for (final g in groups) ...g.items,
        ...standaloneItems,
      ];

  factory ChecklistTemplate.fromJson(Map<String, dynamic> json) {
    final rawGroups = json['groups'];
    final rawItems = json['items'];
    return ChecklistTemplate(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      type: json['type']?.toString() ?? '',
      warehouseId: json['warehouse_id'] != null
          ? int.tryParse(json['warehouse_id'].toString())
          : null,
      name: json['name']?.toString() ?? '',
      groups: rawGroups is List
          ? rawGroups
              .whereType<Map<String, dynamic>>()
              .map(ChecklistGroup.fromJson)
              .toList()
          : const [],
      standaloneItems: rawItems is List
          ? rawItems
              .whereType<Map<String, dynamic>>()
              .map(ChecklistItem.fromJson)
              .toList()
          : const [],
      sopText: json['sop_text']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'warehouse_id': warehouseId,
        'name': name,
        'groups': groups.map((g) => g.toJson()).toList(),
        'items': standaloneItems.map((i) => i.toJson()).toList(),
        'sop_text': sopText,
      };
}
