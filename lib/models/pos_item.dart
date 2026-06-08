class PosItem {
  const PosItem({
    required this.id,
    required this.name,
    required this.price,
    required this.groupId,
    required this.barcode,
    required this.skuCode,
    this.modifierGroupIds = const [],
  });

  final String id;
  final String name;
  final double price;
  final String groupId;
  final String barcode;
  final String skuCode;
  final List<String> modifierGroupIds;

  static PosItem? fromJson(Map<String, dynamic> json) {
    if (json['can_be_sold'] != 'can_be_sold') return null;
    if (json['active'] != '1') return null;

    final name = (json['sku_name'] as String?)?.trim();
    if (name == null || name.isEmpty) return null;

    final rawIds = json['modifier_group_ids'];
    final modifierGroupIds = <String>[];
    if (rawIds is List) {
      for (final id in rawIds) {
        final s = id?.toString();
        if (s != null && s.isNotEmpty) modifierGroupIds.add(s);
      }
    }

    return PosItem(
      id: json['id']?.toString() ?? '',
      name: name,
      price: double.tryParse(json['rate']?.toString() ?? '') ?? 0.0,
      groupId: json['sub_group']?.toString() ?? '0',
      barcode: json['commodity_barcode']?.toString() ?? '',
      skuCode: json['sku_code']?.toString() ?? '',
      modifierGroupIds: modifierGroupIds,
    );
  }
}
