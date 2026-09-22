class ProductionSource {
  const ProductionSource({
    required this.itemId,
    required this.skuCode,
    required this.skuName,
    required this.unitUom,
    required this.currentStock,
  });

  final int itemId;
  final String skuCode;
  final String skuName;
  final String unitUom;
  final double currentStock;

  static ProductionSource fromJson(Map<String, dynamic> json) {
    return ProductionSource(
      itemId: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      skuCode: json['sku_code']?.toString() ?? '',
      skuName: json['sku_name']?.toString() ?? '',
      unitUom: json['unit_uom']?.toString() ?? '',
      currentStock:
          double.tryParse(json['current_stock']?.toString() ?? '') ?? 0.0,
    );
  }
}
