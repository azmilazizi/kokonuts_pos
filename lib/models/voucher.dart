enum VoucherType { discountPercent, fixedAmount, bonusPoint, freeItem }

class VoucherDetails {
  const VoucherDetails({
    required this.code,
    required this.title,
    required this.type,
    required this.value,
    this.expiresAt,
    this.minSpend,
    this.freeItemId,
    this.freeItemName,
    this.freeItemMaxQty = 1,
  });

  final String code;
  final String title;
  final VoucherType type;
  final double value;
  final DateTime? expiresAt;
  final double? minSpend;
  final String? freeItemId;
  final String? freeItemName;
  final int freeItemMaxQty;

  static VoucherDetails? fromJson(Map<String, dynamic> json) {
    final typeStr =
        (json['reward_type'] ?? json['type'])?.toString() ?? '';
    final VoucherType type;
    switch (typeStr) {
      case 'discount_percent':
        type = VoucherType.discountPercent;
      case 'discount_fixed':
      case 'fixed_amount':
        type = VoucherType.fixedAmount;
      case 'bonus_point':
        type = VoucherType.bonusPoint;
      case 'free_item':
        type = VoucherType.freeItem;
      default:
        return null;
    }
    final rawValue = json['reward_value'] ?? json['value'];
    return VoucherDetails(
      code: json['code']?.toString() ?? '',
      title: json['title']?.toString() ??
          json['promotion_title']?.toString() ??
          '',
      type: type,
      value: (rawValue as num?)?.toDouble() ?? 0.0,
      expiresAt: json['expires_at'] != null
          ? DateTime.tryParse(json['expires_at'].toString())
          : null,
      minSpend: json['min_spend'] != null
          ? (json['min_spend'] as num?)?.toDouble()
          : null,
      freeItemId: json['item_id']?.toString(),
      freeItemName: json['item_name']?.toString() ?? json['reward_item']?.toString(),
      freeItemMaxQty: (json['max_qty'] as int?) ?? 1,
    );
  }
}
