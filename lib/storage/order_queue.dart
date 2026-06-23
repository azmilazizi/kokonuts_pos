import 'dart:convert';

import '../services/order_service.dart';
import 'local_db.dart';

class PendingOrder {
  const PendingOrder({
    this.id,
    required this.createdAt,
    required this.shiftId,
    required this.employeeId,
    this.customerId,
    required this.paymentMethod,
    required this.subtotal,
    required this.billDiscount,
    required this.cashbackRedeemed,
    required this.total,
    required this.cashReceived,
    required this.changeAmount,
    required this.queueNumber,
    required this.items,
    this.cashbackCustomerId,
    this.cashbackAmount = 0.0,
  });

  final int? id;
  final DateTime createdAt;
  final int shiftId;
  final int employeeId;
  final int? customerId;
  final String paymentMethod;
  final double subtotal;
  final double billDiscount;
  final double cashbackRedeemed;
  final double total;
  final double cashReceived;
  final double changeAmount;
  final String queueNumber;
  final List<OrderItem> items;
  final int? cashbackCustomerId;
  final double cashbackAmount;
}

class OrderQueue {
  static final OrderQueue instance = OrderQueue._();
  OrderQueue._();

  Future<int> enqueue(PendingOrder order) async {
    final db = await LocalDb.instance.db;
    return db.insert('pending_orders', {
      'created_ms': order.createdAt.millisecondsSinceEpoch,
      'shift_id': order.shiftId,
      'employee_id': order.employeeId,
      'customer_id': order.customerId,
      'payment_method': order.paymentMethod,
      'subtotal': order.subtotal,
      'bill_discount': order.billDiscount,
      'cashback_redeemed': order.cashbackRedeemed,
      'total': order.total,
      'cash_received': order.cashReceived,
      'change_amount': order.changeAmount,
      'queue_number': order.queueNumber,
      'items_json': jsonEncode(order.items.map(_itemToJson).toList()),
      'cashback_customer_id': order.cashbackCustomerId,
      'cashback_amount': order.cashbackAmount,
      'status': 'pending',
      'retry_count': 0,
    });
  }

  Future<List<PendingOrder>> getPending() async {
    final db = await LocalDb.instance.db;
    final rows = await db.query(
      'pending_orders',
      where: 'status = ?',
      whereArgs: ['pending'],
      orderBy: 'created_ms ASC',
    );
    return rows.map(_rowToOrder).toList();
  }

  Future<int> getPendingCount() async {
    final db = await LocalDb.instance.db;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as c FROM pending_orders WHERE status = ?',
      ['pending'],
    );
    return (result.first['c'] as int?) ?? 0;
  }

  Future<void> markSynced(
    int id, {
    required String receiptNumber,
    required int receiptId,
  }) async {
    final db = await LocalDb.instance.db;
    await db.update(
      'pending_orders',
      {
        'status': 'synced',
        'synced_ms': DateTime.now().millisecondsSinceEpoch,
        'receipt_number': receiptNumber,
        'receipt_id': receiptId,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<String?> getQueueNumberForReceipt(String receiptNumber) async {
    final db = await LocalDb.instance.db;
    final rows = await db.query(
      'pending_orders',
      columns: ['queue_number'],
      where: 'receipt_number = ?',
      whereArgs: [receiptNumber],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['queue_number']?.toString();
  }

  Future<void> markFailed(int id, String error) async {
    final db = await LocalDb.instance.db;
    await db.rawUpdate(
      'UPDATE pending_orders SET retry_count = retry_count + 1, last_error = ? WHERE id = ?',
      [error, id],
    );
  }

  static Map<String, dynamic> _itemToJson(OrderItem item) => {
        'item_id': item.itemId,
        'name': item.name,
        'qty': item.qty,
        'unit_price': item.unitPrice,
        'line_discount': item.lineDiscount,
        'modifiers': item.modifiers
            .map((m) => {
                  'id': m.id,
                  'name': m.name,
                  'price': m.price,
                })
            .toList(),
      };

  static PendingOrder _rowToOrder(Map<String, dynamic> row) {
    final itemsRaw = jsonDecode(row['items_json'] as String) as List;
    final items = itemsRaw.map((j) {
      final modsRaw = j['modifiers'] as List;
      return OrderItem(
        itemId: j['item_id']?.toString() ?? '',
        name: j['name'] as String,
        qty: j['qty'] as int,
        unitPrice: (j['unit_price'] as num).toDouble(),
        lineDiscount: (j['line_discount'] as num).toDouble(),
        modifiers: modsRaw
            .map((m) => OrderItemModifier(
                  id: m['id']?.toString() ?? '',
                  name: m['name'] as String,
                  price: (m['price'] as num).toDouble(),
                ))
            .toList(),
      );
    }).toList();

    return PendingOrder(
      id: row['id'] as int,
      createdAt:
          DateTime.fromMillisecondsSinceEpoch(row['created_ms'] as int),
      shiftId: row['shift_id'] as int,
      employeeId: row['employee_id'] as int,
      customerId: row['customer_id'] as int?,
      paymentMethod: row['payment_method'] as String,
      subtotal: (row['subtotal'] as num).toDouble(),
      billDiscount: (row['bill_discount'] as num).toDouble(),
      cashbackRedeemed: (row['cashback_redeemed'] as num).toDouble(),
      total: (row['total'] as num).toDouble(),
      cashReceived: (row['cash_received'] as num).toDouble(),
      changeAmount: (row['change_amount'] as num).toDouble(),
      queueNumber: row['queue_number']?.toString() ?? '',
      items: items,
      cashbackCustomerId: row['cashback_customer_id'] as int?,
      cashbackAmount: (row['cashback_amount'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
