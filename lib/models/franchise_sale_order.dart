class SaleBuyer {
  const SaleBuyer({
    required this.buyerType,
    required this.clientId,
    required this.franchiseeId,
    required this.name,
  });

  final String buyerType; // 'franchisee' or 'client'
  final int clientId;
  final int? franchiseeId;
  final String name;

  static SaleBuyer fromJson(Map<String, dynamic> json) {
    return SaleBuyer(
      buyerType: json['buyer_type']?.toString() ?? 'client',
      clientId: int.tryParse(json['client_id']?.toString() ?? '') ?? 0,
      franchiseeId: json['franchisee_id'] == null
          ? null
          : int.tryParse(json['franchisee_id'].toString()),
      name: json['name']?.toString() ?? '',
    );
  }
}

class FranchiseeOutlet {
  const FranchiseeOutlet({required this.id, required this.name});

  final int id;
  final String name;

  static FranchiseeOutlet fromJson(Map<String, dynamic> json) {
    return FranchiseeOutlet(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      name: json['name']?.toString() ?? '',
    );
  }
}

class SaleOrderItem {
  const SaleOrderItem({
    required this.itemId,
    required this.skuName,
    required this.unitUom,
    required this.quantity,
    required this.hqUnitCost,
    required this.unitPrice,
  });

  final int itemId;
  final String skuName;
  final String unitUom;
  final double quantity;
  final double hqUnitCost;
  final double unitPrice;

  static SaleOrderItem fromJson(Map<String, dynamic> json) {
    return SaleOrderItem(
      itemId: int.tryParse(json['item_id']?.toString() ?? '') ?? 0,
      skuName: json['sku_name']?.toString() ?? '',
      unitUom: json['unit_uom']?.toString() ?? '',
      quantity: double.tryParse(json['quantity']?.toString() ?? '') ?? 0.0,
      hqUnitCost: double.tryParse(json['hq_unit_cost']?.toString() ?? '') ?? 0.0,
      unitPrice: double.tryParse(json['unit_price']?.toString() ?? '') ?? 0.0,
    );
  }
}

/// Status progresses: draft -> quoted -> invoiced -> paid -> delivered.
class FranchiseSaleOrder {
  const FranchiseSaleOrder({
    required this.id,
    required this.buyerType,
    required this.buyerName,
    required this.destinationName,
    required this.status,
    required this.estimateId,
    required this.invoiceId,
    required this.items,
  });

  final int id;
  final String buyerType;
  final String buyerName;
  final String? destinationName;
  final String status;
  final int? estimateId;
  final int? invoiceId;
  final List<SaleOrderItem> items;

  double get total =>
      items.fold(0.0, (sum, item) => sum + item.quantity * item.unitPrice);

  bool get canQuote => status == 'draft';
  bool get canInvoice => status == 'quoted';
  bool get canRecordPayment => status == 'invoiced';
  bool get canDeliver => status == 'paid';
  bool get isDelivered => status == 'delivered';

  static FranchiseSaleOrder fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return FranchiseSaleOrder(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      buyerType: json['buyer_type']?.toString() ?? 'client',
      buyerName: json['buyer_name']?.toString() ?? '',
      destinationName: json['destination_name']?.toString(),
      status: json['status']?.toString() ?? 'draft',
      estimateId: json['estimate_id'] == null
          ? null
          : int.tryParse(json['estimate_id'].toString()),
      invoiceId: json['invoice_id'] == null
          ? null
          : int.tryParse(json['invoice_id'].toString()),
      items: rawItems is List
          ? rawItems
              .whereType<Map<String, dynamic>>()
              .map(SaleOrderItem.fromJson)
              .toList()
          : const [],
    );
  }
}
