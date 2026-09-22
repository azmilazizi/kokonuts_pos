/// An item as sellable in the Franchise/Client Sales cart — distinct from
/// [PosItem] (the retail catalog), since goods HQ ships out are often
/// raw_ingredient-typed intermediate items the retail can_be_sold filter
/// would hide.
class SaleItemOption {
  const SaleItemOption({
    required this.itemId,
    required this.skuName,
    required this.unitUom,
  });

  final int itemId;
  final String skuName;
  final String unitUom;

  static SaleItemOption fromJson(Map<String, dynamic> json) {
    return SaleItemOption(
      itemId: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      skuName: json['sku_name']?.toString() ?? '',
      unitUom: json['unit_uom']?.toString() ?? '',
    );
  }
}
