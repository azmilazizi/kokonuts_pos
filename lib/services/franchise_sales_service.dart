import 'dart:typed_data';

import '../api/api_client.dart';
import '../models/franchise_sale_order.dart';
import '../models/sale_item_option.dart';

class FranchiseSalesService {
  FranchiseSalesService({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  Future<List<SaleItemOption>> fetchItems({
    required String token,
    String query = '',
  }) async {
    final response = await _client.getJson(
      '/pos/api/v1/franchise_sales/items',
      authToken: token,
      queryParameters: query.isEmpty ? null : {'q': query},
    );
    final raw = response.data['data'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(SaleItemOption.fromJson)
        .toList();
  }

  Future<List<FranchiseeOutlet>> fetchFranchiseeOutlets({
    required String token,
    required int franchiseeId,
  }) async {
    final response = await _client.getJson(
      '/pos/api/v1/franchise_sales/franchisees/$franchiseeId/outlets',
      authToken: token,
    );
    final raw = response.data['data'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(FranchiseeOutlet.fromJson)
        .toList();
  }

  Future<List<SaleBuyer>> fetchBuyers({
    required String token,
    String query = '',
  }) async {
    final response = await _client.getJson(
      '/pos/api/v1/franchise_sales/buyers',
      authToken: token,
      queryParameters: query.isEmpty ? null : {'q': query},
    );
    final raw = response.data['data'];
    if (raw is! List) return const [];
    return raw.whereType<Map<String, dynamic>>().map(SaleBuyer.fromJson).toList();
  }

  Future<FranchiseSaleOrder> createOrder({
    required String token,
    required String buyerType,
    int? franchiseeId,
    required int clientId,
    int? destinationWarehouseId,
    required List<Map<String, dynamic>> items, // [{item_id, quantity}]
  }) async {
    final response = await _client.postJson(
      '/pos/api/v1/franchise_sales/orders',
      authToken: token,
      body: {
        'buyer_type': buyerType,
        if (franchiseeId != null) 'franchisee_id': franchiseeId,
        'client_id': clientId,
        if (destinationWarehouseId != null)
          'destination_warehouse_id': destinationWarehouseId,
        'items': items,
      },
    );
    return _order(response.data['data']);
  }

  Future<List<FranchiseSaleOrder>> fetchOrders({required String token}) async {
    final response = await _client.getJson(
      '/pos/api/v1/franchise_sales/orders',
      authToken: token,
    );
    final raw = response.data['data'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(FranchiseSaleOrder.fromJson)
        .toList();
  }

  Future<FranchiseSaleOrder> fetchOrder({
    required String token,
    required int id,
  }) async {
    final response = await _client.getJson(
      '/pos/api/v1/franchise_sales/orders/$id',
      authToken: token,
    );
    return _order(response.data['data']);
  }

  Future<FranchiseSaleOrder> requestQuote({
    required String token,
    required int id,
  }) async {
    final response = await _client.postJson(
      '/pos/api/v1/franchise_sales/orders/$id/quote',
      authToken: token,
    );
    return _order(response.data['data']);
  }

  Future<FranchiseSaleOrder> convertToInvoice({
    required String token,
    required int id,
  }) async {
    final response = await _client.postJson(
      '/pos/api/v1/franchise_sales/orders/$id/invoice',
      authToken: token,
    );
    return _order(response.data['data']);
  }

  Future<FranchiseSaleOrder> recordPayment({
    required String token,
    required int id,
    required double amount,
    required String mode,
    String? date,
  }) async {
    final response = await _client.postJson(
      '/pos/api/v1/franchise_sales/orders/$id/record_payment',
      authToken: token,
      body: {
        'amount': amount,
        'mode': mode,
        if (date != null) 'date': date,
      },
    );
    return _order(response.data['data']);
  }

  Future<FranchiseSaleOrder> deliver({
    required String token,
    required int id,
  }) async {
    final response = await _client.postJson(
      '/pos/api/v1/franchise_sales/orders/$id/deliver',
      authToken: token,
    );
    return _order(response.data['data']);
  }

  /// The invoice as a PDF soft copy — the app hands this to the OS
  /// share/save/print sheet (see Printing.sharePdf in the HQ screen),
  /// nothing here touches the thermal receipt printer.
  Future<Uint8List> fetchInvoicePdf({
    required String token,
    required int orderId,
  }) {
    return _client.getBytes(
      '/pos/api/v1/franchise_sales/orders/$orderId/invoice_pdf',
      authToken: token,
    );
  }

  FranchiseSaleOrder _order(dynamic raw) {
    return FranchiseSaleOrder.fromJson(raw is Map<String, dynamic> ? raw : {});
  }
}
