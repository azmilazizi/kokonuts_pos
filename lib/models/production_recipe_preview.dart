/// One ingredient/component consumed by producing the recipe's item.
class ProductionRecipeComponent {
  const ProductionRecipeComponent({
    required this.componentItemId,
    required this.skuName,
    required this.unitUom,
    required this.perUnitQuantity,
    required this.unitCost,
  });

  final int componentItemId;
  final String skuName;
  final String unitUom;

  /// How much of this component is consumed producing exactly 1 unit of
  /// the recipe's item — multiply by the quantity being produced to get
  /// the default deduction (staff can still override it per run).
  final double perUnitQuantity;
  final double unitCost;

  static ProductionRecipeComponent fromJson(Map<String, dynamic> json) {
    return ProductionRecipeComponent(
      componentItemId:
          int.tryParse(json['component_item_id']?.toString() ?? '') ?? 0,
      skuName: json['sku_name']?.toString() ?? '',
      unitUom: json['unit_uom']?.toString() ?? '',
      perUnitQuantity:
          double.tryParse(json['per_unit_quantity']?.toString() ?? '') ?? 0.0,
      unitCost: double.tryParse(json['unit_cost']?.toString() ?? '') ?? 0.0,
    );
  }
}

/// The Mixed Ingredient recipe (Costing → Mixed Ingredients tab) behind a
/// producible item — what producing it actually consumes.
class ProductionRecipePreview {
  const ProductionRecipePreview({
    this.enabled = false,
    this.totalBatchesYield = 0.0,
    this.yieldUom = '',
    this.components = const [],
  });

  final bool enabled;
  final double totalBatchesYield;
  final String yieldUom;
  final List<ProductionRecipeComponent> components;

  static ProductionRecipePreview fromJson(Map<String, dynamic> json) {
    final rawComponents = json['components'];
    return ProductionRecipePreview(
      enabled: json['enabled'] == true,
      totalBatchesYield:
          double.tryParse(json['total_batches_yield']?.toString() ?? '') ??
              0.0,
      yieldUom: json['yield_uom']?.toString() ?? '',
      components: rawComponents is List
          ? rawComponents
              .whereType<Map<String, dynamic>>()
              .map(ProductionRecipeComponent.fromJson)
              .toList()
          : const [],
    );
  }
}
