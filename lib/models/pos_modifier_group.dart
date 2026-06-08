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
