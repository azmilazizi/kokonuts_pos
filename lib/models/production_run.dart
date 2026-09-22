/// The item produced by this run, and how much. JSON keys stay
/// source_item_id/source_name/source_quantity/output_* to match the backend
/// column names (unchanged since before the Mixed-Ingredients rework), but
/// they now mean "the item/quantity produced," not "the raw item consumed."
class ProductionRunOutput {
  const ProductionRunOutput({
    required this.outputItemId,
    required this.outputName,
    required this.unitUom,
    required this.quantityProduced,
    required this.unitCostSnapshot,
  });

  final int outputItemId;
  final String outputName;
  final String unitUom;
  final double quantityProduced;
  final double unitCostSnapshot;

  static ProductionRunOutput fromJson(Map<String, dynamic> json) {
    return ProductionRunOutput(
      outputItemId: int.tryParse(json['output_item_id']?.toString() ?? '') ?? 0,
      outputName: json['output_name']?.toString() ?? '',
      unitUom: json['output_unit_uom']?.toString() ?? '',
      quantityProduced:
          double.tryParse(json['quantity_produced']?.toString() ?? '') ?? 0.0,
      unitCostSnapshot:
          double.tryParse(json['unit_cost_snapshot']?.toString() ?? '') ?? 0.0,
    );
  }
}

/// One recipe component actually deducted by this run.
class ProductionRunDeduction {
  const ProductionRunDeduction({
    required this.itemId,
    required this.itemName,
    required this.unitUom,
    required this.quantity,
  });

  final int itemId;
  final String itemName;
  final String unitUom;
  final double quantity;

  static ProductionRunDeduction fromJson(Map<String, dynamic> json) {
    return ProductionRunDeduction(
      itemId: int.tryParse(json['inventory_item_id']?.toString() ?? '') ?? 0,
      itemName: json['item_name']?.toString() ?? '',
      unitUom: json['unit_uom']?.toString() ?? '',
      quantity: double.tryParse(json['quantity']?.toString() ?? '') ?? 0.0,
    );
  }
}

class ProductionRun {
  const ProductionRun({
    required this.id,
    required this.producedItemId,
    required this.producedName,
    required this.producedQuantity,
    required this.status,
    required this.note,
    required this.createdAt,
    this.outputs = const [],
    this.deductions = const [],
  });

  final int id;
  final int producedItemId;
  final String producedName;
  final double producedQuantity;
  final String status;
  final String note;
  final String createdAt;
  final List<ProductionRunOutput> outputs;
  final List<ProductionRunDeduction> deductions;

  bool get isVoided => status == 'voided';

  static ProductionRun fromJson(Map<String, dynamic> json) {
    final rawOutputs = json['outputs'];
    final rawDeductions = json['deductions'];
    return ProductionRun(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      producedItemId: int.tryParse(json['source_item_id']?.toString() ?? '') ?? 0,
      producedName: json['source_name']?.toString() ?? '',
      producedQuantity:
          double.tryParse(json['source_quantity']?.toString() ?? '') ?? 0.0,
      status: json['status']?.toString() ?? 'completed',
      note: json['note']?.toString() ?? '',
      createdAt: json['created_at']?.toString() ?? '',
      outputs: rawOutputs is List
          ? rawOutputs
              .whereType<Map<String, dynamic>>()
              .map(ProductionRunOutput.fromJson)
              .toList()
          : const [],
      deductions: rawDeductions is List
          ? rawDeductions
              .whereType<Map<String, dynamic>>()
              .map(ProductionRunDeduction.fromJson)
              .toList()
          : const [],
    );
  }
}
