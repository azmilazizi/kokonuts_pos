class BundleModifier {
  const BundleModifier({
    required this.id,
    required this.name,
    required this.priceAdjustment,
    required this.sortOrder,
    required this.optionType,
    required this.sourceId,
  });

  final String id;
  final String name;
  final double priceAdjustment;
  final int sortOrder;
  final String optionType;
  final int sourceId;

  static BundleModifier fromJson(Map<String, dynamic> json) {
    return BundleModifier(
      id: json['id']?.toString() ?? '',
      name: (json['name'] as String?)?.trim() ?? '',
      priceAdjustment:
          double.tryParse(json['price_adjustment']?.toString() ?? '') ?? 0.0,
      sortOrder: int.tryParse(json['sort_order']?.toString() ?? '') ?? 0,
      optionType: json['option_type']?.toString() ?? '',
      sourceId: int.tryParse(json['source_id']?.toString() ?? '') ?? 0,
    );
  }
}

class BundleModifierGroup {
  const BundleModifierGroup({
    required this.id,
    required this.name,
    required this.selectionType,
    required this.minSelections,
    required this.maxSelections,
    required this.modifiers,
  });

  final String id;
  final String name;
  final String selectionType;
  final int minSelections;
  final int maxSelections;
  final List<BundleModifier> modifiers;

  bool get isSingleSelect => selectionType == 'single';

  static BundleModifierGroup fromJson(Map<String, dynamic> json) {
    final rawModifiers = json['modifiers'];
    final modifiers = <BundleModifier>[];
    if (rawModifiers is List) {
      for (final m in rawModifiers) {
        if (m is Map<String, dynamic>) {
          modifiers.add(BundleModifier.fromJson(m));
        }
      }
      modifiers.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    }
    return BundleModifierGroup(
      id: json['id']?.toString() ?? '',
      name: (json['name'] as String?)?.trim() ?? '',
      selectionType: json['selection_type']?.toString() ?? 'single',
      minSelections:
          int.tryParse(json['min_selections']?.toString() ?? '') ?? 0,
      maxSelections:
          int.tryParse(json['max_selections']?.toString() ?? '') ?? 1,
      modifiers: modifiers,
    );
  }
}

class PosModifier {
  const PosModifier({
    required this.id,
    required this.name,
    required this.priceAdjustment,
    required this.sortOrder,
  });

  final String id;
  final String name;
  final double priceAdjustment;
  final int sortOrder;

  static PosModifier? fromJson(Map<String, dynamic> json) {
    if (json['active'] != '1') return null;
    final name = (json['name'] as String?)?.trim();
    if (name == null || name.isEmpty) return null;
    return PosModifier(
      id: json['id']?.toString() ?? '',
      name: name,
      priceAdjustment:
          double.tryParse(json['price_adjustment']?.toString() ?? '') ?? 0.0,
      sortOrder: int.tryParse(json['sort_order']?.toString() ?? '') ?? 0,
    );
  }
}

class PosModifierGroup {
  const PosModifierGroup({
    required this.id,
    required this.name,
    required this.selectionType,
    required this.minSelections,
    required this.maxSelections,
    required this.modifiers,
  });

  final String id;
  final String name;
  final String selectionType;
  final int minSelections;
  final int maxSelections;
  final List<PosModifier> modifiers;

  bool get isSingleSelect => selectionType == 'single';

  static PosModifierGroup? fromJson(Map<String, dynamic> json) {
    if (json['active'] != '1') return null;
    final name = (json['name'] as String?)?.trim();
    if (name == null || name.isEmpty) return null;

    final rawModifiers = json['modifiers'];
    final modifiers = <PosModifier>[];
    if (rawModifiers is List) {
      for (final m in rawModifiers) {
        if (m is Map<String, dynamic>) {
          final mod = PosModifier.fromJson(m);
          if (mod != null) modifiers.add(mod);
        }
      }
      modifiers.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    }

    return PosModifierGroup(
      id: json['id']?.toString() ?? '',
      name: name,
      selectionType: json['selection_type']?.toString() ?? 'single',
      minSelections:
          int.tryParse(json['min_selections']?.toString() ?? '') ?? 0,
      maxSelections:
          int.tryParse(json['max_selections']?.toString() ?? '') ?? 1,
      modifiers: modifiers,
    );
  }
}
