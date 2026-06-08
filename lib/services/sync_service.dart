import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../storage/order_queue.dart';
import '../storage/secure_store.dart';
import 'order_service.dart';

class SyncService {
  static final SyncService instance = SyncService._();
  SyncService._();

  final ValueNotifier<int> pendingCount = ValueNotifier(0);

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _isSyncing = false;

  Future<void> start() async {
    await _refreshPendingCount();
    _connectivitySub =
        Connectivity().onConnectivityChanged.listen((results) async {
      if (_isOnline(results)) {
        await triggerSync();
      }
    });
    // Attempt sync immediately if already online.
    final current = await Connectivity().checkConnectivity();
    if (_isOnline(current)) {
      unawaited(triggerSync());
    }
  }

  void dispose() {
    _connectivitySub?.cancel();
  }

  Future<void> triggerSync() async {
    if (_isSyncing) return;
    _isSyncing = true;
    try {
      final token = await const SecureStore().readToken() ?? '';
      if (token.isEmpty) return;

      final pending = await OrderQueue.instance.getPending();
      for (final order in pending) {
        try {
          final result = await OrderService().submitOrder(
            token: token,
            shiftId: order.shiftId,
            employeeId: order.employeeId,
            customerId: order.customerId,
            paymentMethod: order.paymentMethod,
            subtotal: order.subtotal,
            billDiscount: order.billDiscount,
            cashbackRedeemed: order.cashbackRedeemed,
            total: order.total,
            cashReceived: order.cashReceived,
            change: order.changeAmount,
            items: order.items,
            queueNumber: order.queueNumber,
          );
          await OrderQueue.instance.markSynced(
            order.id!,
            receiptNumber: result.receiptNumber,
            receiptId: result.receiptId,
          );
          // Redeem cashback that was deferred when offline.
          if (order.cashbackCustomerId != null && order.cashbackAmount > 0) {
            try {
              await OrderService().redeemCashback(
                token: token,
                customerId: order.cashbackCustomerId!,
                receiptId: result.receiptId,
                amount: order.cashbackAmount,
              );
            } catch (_) {
              // Best-effort — cashback sync failure doesn't block the order.
            }
          }
        } catch (e) {
          await OrderQueue.instance.markFailed(order.id!, e.toString());
        }
      }
    } finally {
      _isSyncing = false;
      await _refreshPendingCount();
    }
  }

  Future<void> _refreshPendingCount() async {
    final count = await OrderQueue.instance.getPendingCount();
    pendingCount.value = count;
  }

  bool _isOnline(List<ConnectivityResult> results) {
    return results.any((r) =>
        r == ConnectivityResult.wifi ||
        r == ConnectivityResult.mobile ||
        r == ConnectivityResult.ethernet);
  }
}
