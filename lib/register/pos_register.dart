import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api/api_exception.dart';
import '../models/pos_customer.dart';
import '../models/pos_group.dart';
import '../models/pos_item.dart';
import '../models/pos_modifier_group.dart';
import '../services/cfd_settings_service.dart';
import '../services/customer_service.dart';
import 'duitnow_payment_dialog.dart';
import '../services/bt_printer_service.dart';
import '../services/label_printer_service.dart';
import '../services/order_service.dart';
import '../services/printer_config_service.dart';
import '../services/receipt_builder.dart';
import '../services/payment_mode_service.dart';
import '../services/sunmi_display_service.dart';
import '../services/sunmi_printer_service.dart';
import '../services/sync_service.dart';
import '../storage/catalog_cache.dart';
import '../storage/order_queue.dart';
import '../storage/secure_store.dart';
import 'syncing_screen.dart';

/// Pre-fetched data passed from the login sync gate to skip the initial load.
class PreloadedPosData {
  const PreloadedPosData({
    required this.items,
    required this.groups,
    required this.modifierGroups,
    required this.paymentModes,
  });
  final List<PosItem> items;
  final List<PosGroup> groups;
  final List<PosModifierGroup> modifierGroups;
  final List<PaymentMode> paymentModes;
}

class PosRegister extends StatefulWidget {
  const PosRegister({
    super.key,
    this.header,
    this.shiftOpen = true,
    this.onOpenShift,
    this.shiftId,
    this.preloadedData,
  });

  final Widget? header;
  final bool shiftOpen;
  final VoidCallback? onOpenShift;
  final String? shiftId;
  final PreloadedPosData? preloadedData;

  @override
  State<PosRegister> createState() => _PosRegisterState();
}

// ─── Models ──────────────────────────────────────────────────────────────────

class _Modifier {
  const _Modifier({required this.id, required this.name, required this.price});
  final String id;
  final String name;
  final double price;
}

class _ModifierGroup {
  const _ModifierGroup({
    required this.name,
    required this.modifiers,
    this.multiSelect = true,
  });
  final String name;
  final List<_Modifier> modifiers;
  final bool multiSelect;
}

class _Product {
  const _Product({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    this.modifierGroups = const [],
  });
  final String id;
  final String name;
  final String category;
  final double price;
  final List<_ModifierGroup> modifierGroups;
  bool get hasModifiers => modifierGroups.isNotEmpty;
}

class _CartItem {
  _CartItem({
    required this.product,
    this.quantity = 1,
    Map<String, Set<String>>? selectedModifiers,
    this.itemDiscountValue = 0.0,
    this.itemDiscountIsPercent = false,
  })  : key = UniqueKey(),
        selectedModifiers = selectedModifiers ?? {};

  final Key key;
  final _Product product;
  int quantity;
  Map<String, Set<String>> selectedModifiers;
  double itemDiscountValue;
  bool itemDiscountIsPercent;

  double get modifierPrice {
    double total = 0;
    for (final group in product.modifierGroups) {
      final sel = selectedModifiers[group.name] ?? {};
      for (final mod in group.modifiers) {
        if (sel.contains(mod.name)) total += mod.price;
      }
    }
    return total;
  }

  double get unitPrice => product.price + modifierPrice;
  double get lineTotal => unitPrice * quantity;

  double get itemDiscount {
    if (itemDiscountValue <= 0) return 0.0;
    final d = itemDiscountIsPercent
        ? lineTotal * itemDiscountValue / 100
        : itemDiscountValue;
    return d.clamp(0.0, lineTotal);
  }

  double get lineTotalAfterDiscount => lineTotal - itemDiscount;
}

// ─── State ───────────────────────────────────────────────────────────────────

class _PosRegisterState extends State<PosRegister>
    with TickerProviderStateMixin {
  static const _kPrimary = Color(0xFFE67E22);
  static const _kGreen = Color(0xFFE67E22);

  List<_Product> _products = [];
  List<String> _categories = [];
  Map<String, String> _groupNames = {};
  bool _isLoadingItems = false;
  String? _itemsError;

  final _labelPrinter = createLabelPrinterService();


  late TabController _tabController;
  TabController? _smallTabController;
  final TextEditingController _searchController = TextEditingController();
  bool _isSearchMode = false;
  bool _showTicketPanel = false;
  final List<_CartItem> _cart = [];
  final TextEditingController _cashController = TextEditingController();
  bool _isPaymentMode = false;
  bool _isPaymentSuccessMode = false;
  bool _isProcessingPayment = false;
  bool _isSendingToKitchen = false;
  double _lastPaidTotal = 0.0;
  double _lastChange = 0.0;
  String _lastReceiptNumber = '';
  String _lastReceiptDate = '';
  String _lastReceiptTime = '';
  String _lastReceiptMethod = '';
  String _lastQueueNumber = '';
  final TextEditingController _emailController = TextEditingController();
  PosCustomer? _selectedCustomer;

  // Bill-level discount
  double _billDiscountValue = 0.0;
  bool _billDiscountIsPercent = false;

  // Payment modes
  List<PaymentMode> _paymentModes = [];
  bool _isLoadingPaymentModes = false;

  // Cashback
  bool _redeemCashback = false;

  // Offline order state
  bool _isOfflineOrder = false;

  Timer? _cfdTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 1, vsync: this);
    _smallTabController = TabController(length: 1, vsync: this);
    SunmiDisplayService().init();
    SunmiDisplayService().showWelcome();
    _loadItems();
    _loadPaymentModes();
    unawaited(_startCfdDisplay());
  }

  @override
  void dispose() {
    _cfdTimer?.cancel();
    _tabController.dispose();
    _smallTabController?.dispose();
    _searchController.dispose();
    _cashController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _startCfdDisplay() async {
    _cfdTimer?.cancel();
    _cfdTimer = null;

    final settings = await CfdSettingsService().getSettings();
    if (settings == null) return;

    final images = settings.imageItems;
    if (images.isEmpty) return;

    await SunmiDisplayService().updatePromoImage(images.first.url);

    if ((settings.displayType == 'slideshow' || settings.displayType == 'playlist') &&
        images.length > 1) {
      var index = 0;
      _cfdTimer = Timer.periodic(Duration(seconds: settings.slideDuration), (_) {
        index = (index + 1) % images.length;
        unawaited(SunmiDisplayService().updatePromoImage(images[index].url));
      });
    }
  }

  Future<void> _loadItems() async {
    setState(() {
      _isLoadingItems = true;
      _itemsError = null;
    });
    try {
      if (widget.preloadedData != null) {
        _applyRawCatalog(
          items: widget.preloadedData!.items,
          groups: widget.preloadedData!.groups,
          modifierGroups: widget.preloadedData!.modifierGroups,
        );
        if (!mounted) return;
        setState(() => _isLoadingItems = false);
        return;
      }

      final token = await const SecureStore().readToken();
      if (token == null || token.isEmpty) throw Exception('Not activated.');

      // Load from local cache immediately — works offline.
      final cached = await CatalogCache.instance.loadCached();
      if (cached.hasData) {
        _applyRawCatalog(
          items: cached.items,
          groups: cached.groups,
          modifierGroups: cached.modifierGroups,
        );
        if (cached.paymentModes.isNotEmpty) {
          _paymentModes = cached.paymentModes;
          _isLoadingPaymentModes = false;
        }
        if (!mounted) return;
        setState(() => _isLoadingItems = false);
        // Refresh silently in background when online.
        unawaited(_refreshCatalogFromApi(token));
        return;
      }

      // No cache yet — fetch from API.
      final fresh = await CatalogCache.instance.refreshFromApi(token);
      _applyRawCatalog(
        items: fresh.items,
        groups: fresh.groups,
        modifierGroups: fresh.modifierGroups,
      );
      if (fresh.paymentModes.isNotEmpty) {
        _paymentModes = fresh.paymentModes;
        _isLoadingPaymentModes = false;
      }
      if (!mounted) return;
      setState(() => _isLoadingItems = false);
    } catch (e, st) {
      debugPrint('_loadItems error: $e\n$st');
      if (!mounted) return;
      if (_products.isNotEmpty) {
        setState(() => _isLoadingItems = false);
      } else {
        setState(() {
          _isLoadingItems = false;
          _itemsError = kDebugMode ? e.toString() : 'Failed to load items.';
        });
      }
    }
  }

  Future<void> _refreshCatalogFromApi(String token) async {
    try {
      final fresh = await CatalogCache.instance.refreshFromApi(token);
      if (!mounted) return;
      _applyRawCatalog(
        items: fresh.items,
        groups: fresh.groups,
        modifierGroups: fresh.modifierGroups,
      );
      if (fresh.paymentModes.isNotEmpty) {
        _paymentModes = fresh.paymentModes;
        _isLoadingPaymentModes = false;
      }
      setState(() {});
    } catch (_) {
      // Silent — cached data is still shown.
    }
  }

  void _applyRawCatalog({
    required List<PosItem> items,
    required List<PosGroup> groups,
    required List<PosModifierGroup> modifierGroups,
  }) {
    final groupNames = <String, String>{
      for (final g in groups) g.id: g.name,
    };
    final modifierGroupMap = <String, PosModifierGroup>{
      for (final g in modifierGroups) g.id: g,
    };
    final seen = <String>{};
    final cats = <String>[];
    for (final item in items) {
      if (seen.add(item.groupId)) cats.add(item.groupId);
    }
    final prods = items.map((item) {
      final mGroups = item.modifierGroupIds
          .map((id) => modifierGroupMap[id])
          .whereType<PosModifierGroup>()
          .map((g) => _ModifierGroup(
                name: g.name,
                multiSelect: !g.isSingleSelect,
                modifiers: g.modifiers
                    .map((m) => _Modifier(id: m.id, name: m.name, price: m.priceAdjustment))
                    .toList(),
              ))
          .toList();
      return _Product(
        id: item.id,
        name: item.name,
        category: item.groupId,
        price: item.price,
        modifierGroups: mGroups,
      );
    }).toList();

    _tabController.dispose();
    _tabController = TabController(
      length: cats.isEmpty ? 1 : cats.length,
      vsync: this,
    );
    _smallTabController?.dispose();
    _smallTabController = TabController(
      length: cats.isEmpty ? 1 : cats.length + 1,
      vsync: this,
    );
    _products = prods;
    _categories = cats;
    _groupNames = groupNames;
  }

  Future<void> _loadPaymentModes() async {
    setState(() => _isLoadingPaymentModes = true);
    try {
      if (widget.preloadedData != null) {
        if (!mounted) return;
        setState(() {
          _paymentModes = widget.preloadedData!.paymentModes;
          _isLoadingPaymentModes = false;
        });
        return;
      }
      // Already populated by _loadItems from cache.
      if (_paymentModes.isNotEmpty) {
        setState(() => _isLoadingPaymentModes = false);
        return;
      }
      final token = await const SecureStore().readToken() ?? '';
      final cached = await CatalogCache.instance.loadCached();
      if (cached.paymentModes.isNotEmpty) {
        if (!mounted) return;
        setState(() {
          _paymentModes = cached.paymentModes;
          _isLoadingPaymentModes = false;
        });
        return;
      }
      final fresh = await CatalogCache.instance.refreshFromApi(token);
      if (!mounted) return;
      setState(() {
        _paymentModes = fresh.paymentModes;
        _isLoadingPaymentModes = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingPaymentModes = false);
    }
  }

  // Force-fetches the full catalog from the API for manual sync.
  // Does not touch _isLoadingItems so the register stays visible behind the dialog.
  Future<void> _forceSyncCatalog() async {
    final token = await const SecureStore().readToken();
    if (token == null || token.isEmpty) throw Exception('Not activated.');
    // Only API/network failures propagate as errors. State-update issues are
    // non-fatal since the fresh data is already written to cache by this point.
    final fresh = await CatalogCache.instance.refreshFromApi(token);
    if (!mounted) return;
    try {
      _applyRawCatalog(
        items: fresh.items,
        groups: fresh.groups,
        modifierGroups: fresh.modifierGroups,
      );
      if (fresh.paymentModes.isNotEmpty) {
        _paymentModes = fresh.paymentModes;
        _isLoadingPaymentModes = false;
      }
      setState(() {});
    } catch (_) {
      // Data is in cache; will be reflected on next rebuild.
    }
  }

  // Verifies payment modes are loaded after catalog sync; falls back to cache if needed.
  Future<void> _forceSyncPaymentModes() async {
    if (_paymentModes.isNotEmpty) return;
    final cached = await CatalogCache.instance.loadCached();
    if (cached.paymentModes.isNotEmpty && mounted) {
      setState(() {
        _paymentModes = cached.paymentModes;
        _isLoadingPaymentModes = false;
      });
    }
  }

  void _showSyncDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog.fullscreen(
        child: SyncingScreen(
          tasks: [
            SyncTask(label: 'Products & categories', run: _forceSyncCatalog),
            SyncTask(label: 'Payment methods', run: _forceSyncPaymentModes),
            SyncTask(label: 'Customer display', run: _startCfdDisplay),
          ],
          onDone: () => Navigator.of(ctx).pop(),
        ),
      ),
    );
  }

  double get _subtotal => _cart.fold(0.0, (s, i) => s + i.lineTotal);
  double get _itemsDiscount => _cart.fold(0.0, (s, i) => s + i.itemDiscount);
  double get _billDiscount {
    if (_billDiscountValue <= 0) return 0.0;
    final d = _billDiscountIsPercent
        ? _subtotal * _billDiscountValue / 100
        : _billDiscountValue;
    return d.clamp(0.0, _subtotal);
  }
  double get _totalDiscount => _itemsDiscount + _billDiscount;
  double get _selectedCustomerPoints => _selectedCustomer?.cashbackBalance ?? 0.0;
  double get _cashbackAmount {
    if (!_redeemCashback) return 0.0;
    final billAfterDiscount = (_subtotal - _totalDiscount).clamp(0.0, double.infinity);
    return _selectedCustomerPoints.clamp(0.0, billAfterDiscount);
  }
  double get _total =>
      (_subtotal - _totalDiscount - _cashbackAmount).clamp(0.0, double.infinity);

  // Returns 4 sensible MYR cash amounts >= total, using integer cents to avoid
  // floating-point rounding issues.
  static List<double> _cashSuggestions(double total) {
    double roundUp(double t, double step) {
      final tCents = (t * 100).round();
      final sCents = (step * 100).round();
      return ((tCents + sCents - 1) ~/ sCents) * sCents / 100.0;
    }

    final seen = <int>{};
    final out = <double>[];

    for (final step in [1.0, 5.0, 10.0, 20.0, 50.0, 100.0, 200.0]) {
      final v = roundUp(total, step);
      final c = (v * 100).round();
      if (seen.add(c)) {
        out.add(v);
        if (out.length == 4) return out;
      }
    }

    // Fill remaining slots with RM100 increments above the last value.
    var cursor = out.last;
    while (out.length < 4) {
      cursor += 100.0;
      final c = (cursor * 100).round();
      if (seen.add(c)) out.add(cursor);
    }

    return out;
  }

  void _tapProduct(_Product product) {
    _showModifierModal(product);
  }

  void _showModifierModal(_Product product, {_CartItem? editItem}) {
    showDialog<void>(
      context: context,
      builder: (ctx) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(viewInsets: EdgeInsets.zero),
        child: _ModifierModal(
          product: product,
          initialSelected: editItem != null
              ? Map.fromEntries(editItem.selectedModifiers.entries
                  .map((e) => MapEntry(e.key, Set<String>.from(e.value))))
              : {},
          initialQuantity: editItem?.quantity ?? 1,
          initialDiscountValue: editItem?.itemDiscountValue ?? 0.0,
          initialDiscountIsPercent: editItem?.itemDiscountIsPercent ?? false,
          onSave: (selected, qty, discountValue, discountIsPercent) {
            setState(() {
              if (editItem != null) {
                editItem.selectedModifiers = selected;
                editItem.quantity = qty;
                editItem.itemDiscountValue = discountValue;
                editItem.itemDiscountIsPercent = discountIsPercent;
              } else {
                _cart.add(_CartItem(
                  product: product,
                  quantity: qty,
                  selectedModifiers: selected,
                  itemDiscountValue: discountValue,
                  itemDiscountIsPercent: discountIsPercent,
                ));
              }
            });
            _syncCartToDisplay();
          },
        ),
      ),
    );
  }

  void _showCustomerModal() {
    final screenHeight = MediaQuery.of(context).size.height;
    showDialog<void>(
      context: context,
      builder: (ctx) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(viewInsets: EdgeInsets.zero),
        child: _CustomerSearchModal(
          screenHeight: screenHeight,
          onSelect: (customer) {
            setState(() => _selectedCustomer = customer);
          },
        ),
      ),
    );
  }

  void _handleCharge() {
    if (_cart.isEmpty) return;
    _cashController.text = '0.00';
    setState(() {
      _isPaymentMode = true;
      _showTicketPanel = false;
    });
    // CFD keeps showing the order (not just the amount) while the cashier selects payment method
  }

  Future<void> _processCashPayment() async {
    final raw = _cashController.text.replaceAll(RegExp(r'[^\d.]'), '');
    final cash = double.tryParse(raw) ?? 0.0;
    if (cash < _total) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cash received is less than the total.')),
      );
      return;
    }
    final change = cash - _total;
    await _completePayment(
      method: 'Cash',
      cashReceived: cash,
      change: change > 0.005 ? change : 0.0,
    );
  }

  Future<void> _processPayment(String method) => _completePayment(method: method);

  Future<void> _showDuitNowDialog() async {
    final now = DateTime.now();
    final ref =
        'RCP-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}'
        '-${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => DuitNowPaymentDialog(
        amount: _total,
        reference: ref,
        onPaymentConfirmed: () => _processPayment('DuitNow QR'),
      ),
    );
  }

  Future<void> _completePayment({
    required String method,
    double cashReceived = 0.0,
    double change = 0.0,
  }) async {
    setState(() => _isProcessingPayment = true);

    final now = DateTime.now();
    final date =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final time =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    try {
      final store = const SecureStore();
      final token = await store.readToken() ?? '';
      final staffIdStr = await store.readStaffId() ?? '';
      final employeeId = int.tryParse(staffIdStr) ?? 0;
      final shiftIdInt = int.tryParse(widget.shiftId ?? '') ?? 0;
      final queueNumber = await store.nextQueueNumber();

      final orderItems = _cart.map((item) {
        final modifiers = <OrderItemModifier>[];
        for (final group in item.product.modifierGroups) {
          final selectedNames = item.selectedModifiers[group.name] ?? {};
          for (final mod in group.modifiers) {
            if (selectedNames.contains(mod.name)) {
              modifiers.add(
                  OrderItemModifier(id: mod.id, name: mod.name, price: mod.price));
            }
          }
        }
        return OrderItem(
          itemId: item.product.id,
          name: item.product.name,
          qty: item.quantity,
          unitPrice: item.product.price,
          lineDiscount: item.itemDiscount,
          modifiers: modifiers,
        );
      }).toList();

      // Try to submit online; queue locally on any network failure.
      OrderResult result;
      var isOffline = false;
      try {
        result = await OrderService().submitOrder(
          token: token,
          shiftId: shiftIdInt,
          employeeId: employeeId,
          customerId: _selectedCustomer?.id,
          paymentMethod: method,
          subtotal: _subtotal,
          billDiscount: _billDiscount,
          cashbackRedeemed: _cashbackAmount,
          total: _total,
          cashReceived: cashReceived > 0 ? cashReceived : _total,
          change: change,
          items: orderItems,
          queueNumber: queueNumber,
        );
      } on ApiException {
        rethrow;
      } catch (_) {
        // Network/offline — save to local queue, complete the sale.
        isOffline = true;
        await OrderQueue.instance.enqueue(PendingOrder(
          createdAt: now,
          shiftId: shiftIdInt,
          employeeId: employeeId,
          customerId: _selectedCustomer?.id,
          paymentMethod: method,
          subtotal: _subtotal,
          billDiscount: _billDiscount,
          cashbackRedeemed: _cashbackAmount,
          total: _total,
          cashReceived: cashReceived > 0 ? cashReceived : _total,
          changeAmount: change,
          queueNumber: queueNumber,
          items: orderItems,
          cashbackCustomerId:
              _cashbackAmount > 0 ? _selectedCustomer?.id : null,
          cashbackAmount: _cashbackAmount,
        ));
        SyncService.instance.pendingCount.value++;
        result = OrderResult(
          receiptId: 0,
          receiptNumber: 'OFFLINE-#$queueNumber',
          queueNumber: queueNumber,
        );
      }

      if (!isOffline && _cashbackAmount > 0 && _selectedCustomer != null) {
        await OrderService().redeemCashback(
          token: token,
          customerId: _selectedCustomer!.id,
          receiptId: result.receiptId,
          amount: _cashbackAmount,
        );
      }

      SunmiPrinterService().printReceipt(
        PrintReceiptData(
          receiptId: result.receiptNumber,
          queueNumber: result.queueNumber,
          cashbackQrUrl: _selectedCustomer == null ? result.cashbackQrUrl : null,
          cashbackQrToken: _selectedCustomer == null ? result.cashbackQrToken : null,
          date: date,
          time: time,
          paymentMethod: method,
          items: _cart
              .map((item) => PrintItem(
                    name: item.product.name,
                    qty: item.quantity,
                    unitPrice: item.unitPrice,
                    lineTotal: item.lineTotalAfterDiscount,
                    discount: item.itemDiscount,
                    modifiers: _modifierList(item),
                  ))
              .toList(),
          total: _total,
          cashReceived: cashReceived > 0 ? cashReceived : _total,
          change: change,
        ),
      );

      if (method == 'Cash') SunmiPrinterService().openCashDrawer();
      SunmiDisplayService().showComplete(totalPaid: _total, queueNumber: result.queueNumber);
      Future.delayed(const Duration(seconds: 10), () {
        if (mounted) SunmiDisplayService().showWelcome();
      });

      if (!mounted) return;
      setState(() {
        _isProcessingPayment = false;
        _isPaymentSuccessMode = true;
        _isOfflineOrder = isOffline;
        _lastPaidTotal = cashReceived > 0 ? cashReceived : _total;
        _lastChange = change;
        _lastReceiptNumber = result.receiptNumber;
        _lastReceiptDate = date;
        _lastReceiptTime = time;
        _lastReceiptMethod = method;
        _lastQueueNumber = result.queueNumber;
        _emailController.clear();
      });
      _printLabels(result.queueNumber);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isProcessingPayment = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Payment failed: ${e.message}')),
      );
    } catch (e) {
      debugPrint('_completePayment error: $e');
      if (!mounted) return;
      setState(() => _isProcessingPayment = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment failed. Please try again.')),
      );
    }
  }

  void _clearCart() {
    setState(() => _cart.clear());
    SunmiDisplayService().showWelcome();
  }

  String _modifierSummary(_CartItem item) {
    final parts = <String>[];
    for (final group in item.product.modifierGroups) {
      parts.addAll(item.selectedModifiers[group.name] ?? {});
    }
    return parts.join(', ');
  }

  Widget _summaryRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 13, color: Color(0xFF757575))),
          Text(value,
              style: TextStyle(
                  fontSize: 13,
                  color: valueColor ?? const Color(0xFF757575))),
        ],
      ),
    );
  }

  void _showBillDiscountModal() {
    final screenHeight = MediaQuery.of(context).size.height;
    double localDiscountValue = _billDiscountValue;
    bool localDiscountIsPercent = _billDiscountIsPercent;
    bool localRedeemCashback = _redeemCashback;

    final discountCtrl = TextEditingController(
      text: localDiscountValue > 0
          ? localDiscountValue.toStringAsFixed(2)
          : '',
    );

    showDialog<void>(
      context: context,
      builder: (ctx) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(viewInsets: EdgeInsets.zero),
        child: StatefulBuilder(
          builder: (ctx, setModal) => Dialog(
            backgroundColor: Colors.white,
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 40, vertical: 60),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 480,
                maxHeight: screenHeight * 0.75,
              ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Full Bill Discount',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          setState(() {
                            _billDiscountValue = localDiscountValue;
                            _billDiscountIsPercent = localDiscountIsPercent;
                            _redeemCashback = localRedeemCashback;
                          });
                          _syncCartToDisplay();
                          Navigator.pop(ctx);
                        },
                      ),
                    ],
                  ),
                  const Divider(height: 1),
                  const SizedBox(height: 16),
                  // Amount row
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: discountCtrl,
                          autofocus: true,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          style: const TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w300,
                          ),
                          decoration: const InputDecoration(
                            hintText: '0.00',
                            hintStyle: TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.w300,
                              color: Color(0xFFBDBDBD),
                            ),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onChanged: (v) => setModal(() =>
                              localDiscountValue =
                                  double.tryParse(v) ?? 0.0),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // RM / % toggle
                      Container(
                        decoration: BoxDecoration(
                          border:
                              Border.all(color: const Color(0xFFE0E0E0)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            _billDiscountTypeBtn(
                                'RM', !localDiscountIsPercent,
                                onTap: () => setModal(
                                    () => localDiscountIsPercent = false)),
                            _billDiscountTypeBtn('%', localDiscountIsPercent,
                                onTap: () => setModal(
                                    () => localDiscountIsPercent = true)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Quick % buttons
                  Row(
                    children: [5, 10, 20, 100].map((pct) {
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(
                                  color: Color(0xFFE0E0E0)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 12),
                            ),
                            onPressed: () => setModal(() {
                              localDiscountIsPercent = true;
                              localDiscountValue = pct.toDouble();
                              discountCtrl.text = '$pct';
                            }),
                            child: Text(
                              '$pct%',
                              style: const TextStyle(
                                color: Color(0xFF212121),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  const Divider(height: 1),
                  // Redeem Cashback toggle (only if customer with points selected)
                  if (_selectedCustomerPoints > 0) ...[
                    const SizedBox(height: 4),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: localRedeemCashback,
                      onChanged: (v) =>
                          setModal(() => localRedeemCashback = v),
                      title: const Text(
                        'Redeem Cashback',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                      activeThumbColor: _kGreen,
                      activeTrackColor: const Color(0xFFFFCC80),
                    ),
                    if (localRedeemCashback)
                      Builder(builder: (_) {
                        final localBillDisc = localDiscountValue > 0
                            ? (localDiscountIsPercent
                                    ? _subtotal * localDiscountValue / 100
                                    : localDiscountValue)
                                .clamp(0.0, _subtotal)
                            : 0.0;
                        final billAfter = (_subtotal - _itemsDiscount - localBillDisc)
                            .clamp(0.0, double.infinity);
                        final effectiveCashback =
                            _selectedCustomerPoints.clamp(0.0, billAfter);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'RM ${effectiveCashback.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.w300,
                                  color: Color(0xFFE67E22),
                                ),
                              ),
                              if (effectiveCashback < _selectedCustomerPoints)
                                Text(
                                  'Balance: RM ${_selectedCustomerPoints.toStringAsFixed(2)}  ·  capped at bill amount',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF9E9E9E),
                                  ),
                                ),
                            ],
                          ),
                        );
                      }),
                    const Divider(height: 1),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
        ),
    ).then((_) {
      // Also apply if dismissed by tapping outside
      setState(() {
        _billDiscountValue = localDiscountValue;
        _billDiscountIsPercent = localDiscountIsPercent;
        _redeemCashback = localRedeemCashback;
      });
      _syncCartToDisplay();
    });
  }

  Widget _billDiscountTypeBtn(String label, bool active,
      {required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF212121) : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : const Color(0xFF757575),
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  List<String> _modifierList(_CartItem item) {
    final parts = <String>[];
    for (final group in item.product.modifierGroups) {
      parts.addAll(item.selectedModifiers[group.name] ?? {});
    }
    return parts;
  }

  static bool _isBtMac(String mac) =>
      RegExp(r'^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$').hasMatch(mac);

  Future<void> _printLabels(String queueNumber) async {
    final kitchenMac = await PrinterConfigService().getKitchenPrinterMac();
    if (kitchenMac == null || kitchenMac.isEmpty) return;

    final now = DateTime.now();
    final dt =
        '${now.year}.${now.month.toString().padLeft(2, '0')}.${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final kitchenItems = _cart
        .map((item) => (
              name: item.product.name,
              qty: item.quantity,
              modifiers: _modifierList(item).join(', '),
            ))
        .toList();

    // Bluetooth thermal printer → ESC/POS kitchen ticket via BT.
    if (_isBtMac(kitchenMac)) {
      try {
        final commands = buildKitchenTicket(
          queueLabel: queueNumber,
          dateTime: dt,
          items: kitchenItems,
        );
        await BtPrinterService().printCommands(kitchenMac, commands);
      } catch (e) {
        debugPrint('BT kitchen print failed: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Kitchen print failed: $e')),
          );
        }
      }
      return;
    }

    // USB label printer (Bixolon) path.
    final totalItems = _cart.length;
    try {
      await _labelPrinter.connect();
      for (var i = 0; i < _cart.length; i++) {
        final item = _cart[i];
        final job = LabelPrintJob(
          queueNumber: queueNumber,
          itemName: item.product.name,
          category: _groupNames[item.product.category] ?? item.product.category,
          modifier: _modifierList(item).join('\n'),
          dateTime: dt,
          itemIndex: i + 1,
          totalItems: totalItems,
        );
        for (var copy = 0; copy < item.quantity; copy++) {
          await _labelPrinter.printLabel(job);
        }
      }
    } catch (e) {
      debugPrint('Label print failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kitchen print failed: $e')),
        );
      }
    } finally {
      await _labelPrinter.disconnect();
    }
  }

  void _syncCartToDisplay() {
    if (_cart.isEmpty) {
      SunmiDisplayService().showWelcome();
    } else {
      SunmiDisplayService().showOrder(
        items: _cart
            .map(
              (item) => <String, dynamic>{
                'name': item.product.name,
                'qty': item.quantity,
                'lineTotal': item.lineTotal,
                'lineTotalAfterDiscount': item.lineTotalAfterDiscount,
                'hasDiscount': item.itemDiscount > 0,
              },
            )
            .toList(),
        total: _total,
        subtotal: _subtotal,
        totalDiscount: _totalDiscount,
        cashbackAmount: _cashbackAmount,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSmall = MediaQuery.of(context).size.width < 700;
    if (isSmall) return _buildSmallLayout(context);

    if (_isPaymentMode) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: 360, child: _buildTicketPanel(paymentMode: true)),
          Container(width: 1, color: const Color(0xFFE0E0E0)),
          Expanded(
            child: _isPaymentSuccessMode
                ? _buildPaymentSuccessPanel()
                : _buildPaymentPanel(),
          ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Column(
            children: [
              if (widget.header != null) widget.header!,
              Expanded(child: _buildProductArea()),
            ],
          ),
        ),
        Container(width: 1, color: const Color(0xFFE0E0E0)),
        SizedBox(
          width: 380,
          child: widget.shiftOpen
              ? _buildTicketPanel()
              : _buildClosedShiftPanel(),
        ),
      ],
    );
  }

  void _onTabReorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    final currentCat = _categories[_tabController.index];
    setState(() {
      final cat = _categories.removeAt(oldIndex);
      _categories.insert(newIndex, cat);
      final selectedIndex = _categories.indexOf(currentCat);
      _tabController.dispose();
      _tabController = TabController(
        length: _categories.length,
        vsync: this,
        initialIndex: selectedIndex.clamp(0, _categories.length - 1),
      );
    });
  }

  Widget _buildTabChip(String cat, int index) {
    final isSelected = _tabController.index == index;
    return GestureDetector(
      onTap: () => _tabController.animateTo(index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isSelected ? _kPrimary : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Text(
          _groupNames[cat] ?? cat,
          style: TextStyle(
            color: isSelected ? _kPrimary : const Color(0xFF757575),
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildProductArea() {
    if (_isLoadingItems) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_itemsError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_itemsError!, style: const TextStyle(color: Color(0xFF757575))),
            const SizedBox(height: 12),
            TextButton(onPressed: _loadItems, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_categories.isEmpty) {
      return const Center(
        child: Text('No items available.', style: TextStyle(color: Color(0xFF757575))),
      );
    }
    return Column(
      children: [
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: _categories.map((cat) => _buildProductGrid(cat)).toList(),
          ),
        ),
        Material(
          color: Colors.white,
          elevation: 2,
          child: SizedBox(
            height: 64,
            child: AnimatedBuilder(
              animation: _tabController,
              builder: (context, _) => ReorderableListView.builder(
                scrollDirection: Axis.horizontal,
                buildDefaultDragHandles: false,
                padding: EdgeInsets.zero,
                itemCount: _categories.length,
                onReorder: _onTabReorder,
                itemBuilder: (context, index) {
                  return ReorderableDelayedDragStartListener(
                    key: ValueKey(_categories[index]),
                    index: index,
                    child: _buildTabChip(_categories[index], index),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildClosedShiftPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Container(
            color: const Color(0xFFF5F6FA),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      border: Border.all(
                        color: const Color(0xFFBDBDBD),
                        width: 2,
                      ),
                      shape: BoxShape.circle,
                    ),
                  ),
                  Container(width: 2, height: 18, color: const Color(0xFFBDBDBD)),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 40,
                      vertical: 22,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFD0D0D0), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Text(
                      'CLOSED',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 5,
                        color: Color(0xFF424242),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        SizedBox(
          width: double.infinity,
          height: 64,
          child: TextButton(
            style: TextButton.styleFrom(
              backgroundColor: _kPrimary,
              foregroundColor: Colors.white,
              shape: const RoundedRectangleBorder(),
            ),
            onPressed: widget.onOpenShift,
            child: const Text(
              'Open Shift',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProductGrid(String category) {
    final products = _products.where((p) => p.category == category).toList();
    return GridView.builder(
      padding: const EdgeInsets.all(10),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1.0,
      ),
      itemCount: products.length,
      itemBuilder: (context, i) => _buildProductTile(products[i]),
    );
  }

  Widget _buildProductTile(_Product product) {
    return Material(
      color: const Color(0xFFEEEEEE),
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: widget.shiftOpen ? () => _tapProduct(product) : null,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                product.name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                'RM ${product.price.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF757575)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Small-screen layout ────────────────────────────────────────────────────

  Widget _buildSmallLayout(BuildContext context) {
    if (_isPaymentMode) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.header != null) widget.header!,
          Expanded(
            child: _isPaymentSuccessMode
                ? _buildPaymentSuccessPanel()
                : _buildPaymentPanel(),
          ),
        ],
      );
    }

    final cartCount = _cart.fold(0, (s, i) => s + i.quantity);
    final isEmpty = _cart.isEmpty;

    return Column(
      children: [
        if (widget.header != null) widget.header!,
        _buildSmallAppBar(cartCount, isEmpty),
        Expanded(
          child: Stack(
            children: [
              Column(
                children: [
                  Expanded(
                    child: ColoredBox(
                      color: const Color(0xFFF8F8F8),
                      child: _buildSmallProductArea(),
                    ),
                  ),
                  _buildSmallCategoryBar(),
                ],
              ),
              if (_showTicketPanel) _buildSmallTicketOverlay(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSmallAppBar(int cartCount, bool isEmpty) {
    void toggleTicket() =>
        setState(() => _showTicketPanel = !_showTicketPanel);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE0E0E0))),
      ),
      child: Row(
        children: [
          // Tappable ticket label area
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: toggleTicket,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 8, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Ticket',
                          style: TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w600),
                        ),
                        if (cartCount > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: _kPrimary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '$cartCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (_selectedCustomer != null)
                      Text(
                        _selectedCustomer!.name,
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFF9E9E9E)),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ),
          ),
          // Add customer
          IconButton(
            icon: const Icon(Icons.person_add_outlined),
            onPressed: _showCustomerModal,
            tooltip: 'Add customer',
          ),
          // More options
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'More options',
            onSelected: (val) {
              switch (val) {
                case 'clear':
                  _clearCart();
                case 'cash_drawer':
                  SunmiPrinterService().openCashDrawer();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Opening cash drawer...'),
                    ),
                  );
                case 'sync':
                  _showSyncDialog(context);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'clear',
                child: Row(children: [
                  Icon(Icons.delete_outline, size: 20),
                  SizedBox(width: 12),
                  Text('Clear ticket'),
                ]),
              ),
              const PopupMenuItem(
                value: 'cash_drawer',
                child: Row(children: [
                  Icon(Icons.point_of_sale_outlined, size: 20),
                  SizedBox(width: 12),
                  Text('Open cash drawer'),
                ]),
              ),
              const PopupMenuItem(
                value: 'sync',
                child: Row(children: [
                  Icon(Icons.sync, size: 20),
                  SizedBox(width: 12),
                  Text('Sync'),
                ]),
              ),
            ],
          ),
          // Chevron toggle
          GestureDetector(
            onTap: toggleTicket,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
              child: Icon(
                _showTicketPanel
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down,
                color: Colors.black54,
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _buildSmallProductArea() {
    if (_isLoadingItems) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_itemsError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_itemsError!,
                style: const TextStyle(color: Color(0xFF757575))),
            const SizedBox(height: 12),
            TextButton(onPressed: _loadItems, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_categories.isEmpty) {
      return const Center(
        child: Text('No items available.',
            style: TextStyle(color: Color(0xFF757575))),
      );
    }
    if (_isSearchMode) {
      return _buildProductListView(null, filter: _searchController.text);
    }
    final ctrl = _smallTabController;
    if (ctrl == null) return const SizedBox.shrink();
    return TabBarView(
      controller: ctrl,
      children: [
        _buildProductListView(null),
        ..._categories.map((cat) => _buildProductListView(cat)),
      ],
    );
  }

  Widget _buildSmallCategoryBar() {
    if (_isSearchMode) {
      return Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFFE0E0E0))),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search items...',
                  prefixIcon: const Icon(Icons.search,
                      color: Color(0xFF9E9E9E), size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      vertical: 8, horizontal: 4),
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              color: const Color(0xFF757575),
              onPressed: () => setState(() {
                _isSearchMode = false;
                _searchController.clear();
              }),
            ),
          ],
        ),
      );
    }

    final ctrl = _smallTabController;
    if (ctrl == null) return const SizedBox.shrink();
    final tabs = [
      'All',
      ..._categories.map((c) => _groupNames[c] ?? c),
    ];

    return Material(
      color: Colors.white,
      elevation: 4,
      shadowColor: const Color(0x1A000000),
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            Expanded(
              child: AnimatedBuilder(
                animation: ctrl,
                builder: (context, _) => ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  itemCount: tabs.length,
                  itemBuilder: (context, index) {
                    final isSelected = ctrl.index == index;
                    return GestureDetector(
                      onTap: () => ctrl.animateTo(index),
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 16),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: isSelected
                                  ? _kPrimary
                                  : Colors.transparent,
                              width: 3,
                            ),
                          ),
                        ),
                        child: Text(
                          tabs[index],
                          style: TextStyle(
                            color: isSelected
                                ? _kPrimary
                                : const Color(0xFF757575),
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.w500,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.search),
              color: const Color(0xFF757575),
              onPressed: () => setState(() => _isSearchMode = true),
              tooltip: 'Search',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSmallTicketOverlay() {
    return Positioned.fill(
      child: Material(
        color: Colors.white,
        child: widget.shiftOpen
            ? _buildTicketPanel(showHeader: false)
            : _buildClosedShiftPanel(),
      ),
    );
  }

  Widget _buildProductListView(String? category, {String filter = ''}) {
    var products = category == null
        ? _products
        : _products.where((p) => p.category == category).toList();

    if (filter.isNotEmpty) {
      final q = filter.toLowerCase();
      products =
          products.where((p) => p.name.toLowerCase().contains(q)).toList();
    }

    if (products.isEmpty) {
      return Center(
        child: Text(
          filter.isNotEmpty
              ? 'No results for "$filter".'
              : 'No items in this category.',
          style: const TextStyle(color: Color(0xFF9E9E9E)),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: products.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, indent: 16, endIndent: 16),
      itemBuilder: (_, i) => _buildProductListTile(products[i]),
    );
  }

  Widget _buildProductListTile(_Product product) {
    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      title: Text(
        product.name,
        style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
      ),
      subtitle: Text(
        'RM ${product.price.toStringAsFixed(2)}',
        style: const TextStyle(color: Color(0xFF9E9E9E), fontSize: 13),
      ),
      trailing: GestureDetector(
        onTap: widget.shiftOpen ? () => _tapProduct(product) : null,
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: widget.shiftOpen ? _kPrimary : Colors.grey.shade300,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.add,
            color:
                widget.shiftOpen ? Colors.white : Colors.grey.shade500,
            size: 18,
          ),
        ),
      ),
      onTap: widget.shiftOpen ? () => _tapProduct(product) : null,
    );
  }

  Widget _buildTicketPanel({bool paymentMode = false, bool showHeader = true}) {
    final isEmpty = _cart.isEmpty;
    return Column(
      children: [
        // Header
        if (showHeader)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Color(0xFFE0E0E0))),
          ),
          child: Row(
            children: [
              const Text(
                'Ticket',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.person_add_outlined),
                onPressed: _showCustomerModal,
                tooltip: 'Add customer',
              ),
              if (!paymentMode)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  tooltip: 'More options',
                  onSelected: (val) {
                    switch (val) {
                      case 'clear':
                        _clearCart();
                      case 'cash_drawer':
                        SunmiPrinterService().openCashDrawer();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Opening cash drawer...'),
                          ),
                        );
                      case 'sync':
                        _showSyncDialog(context);
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'clear',
                      child: Row(children: [
                        Icon(Icons.delete_outline, size: 20),
                        SizedBox(width: 12),
                        Text('Clear ticket'),
                      ]),
                    ),
                    const PopupMenuItem(
                      value: 'cash_drawer',
                      child: Row(children: [
                        Icon(Icons.point_of_sale_outlined, size: 20),
                        SizedBox(width: 12),
                        Text('Open cash drawer'),
                      ]),
                    ),
                    const PopupMenuItem(
                      value: 'sync',
                      child: Row(children: [
                        Icon(Icons.sync, size: 20),
                        SizedBox(width: 12),
                        Text('Sync'),
                      ]),
                    ),
                  ],
                ),
            ],
          ),
        ),
        // Customer strip
        if (_selectedCustomer != null)
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: const Color(0xFFF5F5F5),
            child: Row(
              children: [
                const Icon(Icons.person_outline, size: 16,
                    color: Color(0xFF757575)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${_selectedCustomer!.name}  ·  ${_selectedCustomer!.phone}',
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF757575)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!paymentMode)
                  GestureDetector(
                    onTap: () => setState(() => _selectedCustomer = null),
                    child: const Icon(Icons.close,
                        size: 16, color: Color(0xFF757575)),
                  ),
              ],
            ),
          ),
        // Items
        Expanded(
          child: Container(
            color: Colors.white,
            child: isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.receipt_long,
                            size: 48, color: Colors.grey.shade300),
                        const SizedBox(height: 8),
                        Text('No items added',
                            style:
                                TextStyle(color: Colors.grey.shade400)),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _cart.length,
                    separatorBuilder: (_, __) => const Divider(
                      height: 1,
                      indent: 16,
                      endIndent: 16,
                    ),
                    itemBuilder: (_, i) {
                      final item = _cart[i];
                      return _SlidableCartRow(
                        key: item.key,
                        item: item,
                        summary: _modifierSummary(item),
                        onTap: () => _showModifierModal(
                            item.product,
                            editItem: item),
                        onDelete: () {
                          setState(() => _cart.remove(item));
                          _syncCartToDisplay();
                        },
                      );
                    },
                  ),
          ),
        ),
        // Footer
        Container(
          color: Colors.white,
          child: Column(
            children: [
              const Divider(height: 1),
              if (!isEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Column(
                    children: [
                      _summaryRow('Subtotal',
                          'RM ${_subtotal.toStringAsFixed(2)}'),
                      if (_totalDiscount > 0)
                        _summaryRow(
                          'Discount',
                          '- RM ${_totalDiscount.toStringAsFixed(2)}',
                          valueColor: const Color(0xFFE67E22),
                        ),
                      if (_cashbackAmount > 0)
                        _summaryRow(
                          'Cashback Redeem',
                          '- RM ${_cashbackAmount.toStringAsFixed(2)}',
                          valueColor: const Color(0xFFE67E22),
                        ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                InkWell(
                  onTap: _showBillDiscountModal,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Row(
                          children: [
                            Text(
                              'RM ${_total.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.expand_less,
                                size: 18, color: Color(0xFF9E9E9E)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (!paymentMode)
                SizedBox(
                  width: double.infinity,
                  height: 64,
                  child: widget.shiftOpen
                      ? TextButton(
                          style: TextButton.styleFrom(
                            backgroundColor: isEmpty
                                ? Colors.grey.shade300
                                : _kGreen,
                            foregroundColor: isEmpty
                                ? Colors.grey.shade500
                                : Colors.white,
                            shape: const RoundedRectangleBorder(),
                          ),
                          onPressed: isEmpty ? null : _handleCharge,
                          child: const Text(
                            'CHARGE',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 2,
                            ),
                          ),
                        )
                      : TextButton(
                          style: TextButton.styleFrom(
                            backgroundColor: _kPrimary,
                            foregroundColor: Colors.white,
                            shape: const RoundedRectangleBorder(),
                          ),
                          onPressed: widget.onOpenShift,
                          child: const Text(
                            'Open Shift',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentSuccessPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 3-dot menu row
        Align(
          alignment: Alignment.centerRight,
          child: PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'More options',
            onSelected: (val) async {
              if (val == 'send_kitchen') {
                setState(() => _isSendingToKitchen = true);
                await _printLabels(_lastQueueNumber);
                if (mounted) setState(() => _isSendingToKitchen = false);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'send_kitchen',
                child: Row(children: [
                  _isSendingToKitchen
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.local_cafe_outlined, size: 20),
                  const SizedBox(width: 12),
                  const Text('Send to Kitchen'),
                ]),
              ),
            ],
          ),
        ),
        // All content centered vertically
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Totals row
                LayoutBuilder(
                  builder: (context, constraints) {
                    final useStack = constraints.maxWidth < 460;
                    final totalPaidCol = Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          'RM ${_lastPaidTotal.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 44,
                            fontWeight: FontWeight.w700,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Total paid',
                          style: TextStyle(
                            fontSize: 14,
                            color: Color(0xFF9E9E9E),
                          ),
                        ),
                      ],
                    );
                    final changeCol = _lastChange > 0.005
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                'RM ${_lastChange.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 44,
                                  fontWeight: FontWeight.w400,
                                  height: 1.1,
                                  color: Color(0xFFBDBDBD),
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Change',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Color(0xFF9E9E9E),
                                ),
                              ),
                            ],
                          )
                        : null;
                    if (useStack) {
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          totalPaidCol,
                          if (changeCol != null) ...[
                            const SizedBox(height: 16),
                            changeCol,
                          ],
                        ],
                      );
                    }
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        totalPaidCol,
                        if (changeCol != null) ...[
                          const SizedBox(width: 40),
                          changeCol,
                        ],
                      ],
                    );
                  },
                ),
                const SizedBox(height: 32),
                // Queue number
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE67E22), width: 1.5),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Collection Number',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF9E9E9E),
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _lastQueueNumber,
                        style: const TextStyle(
                          fontSize: 64,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFE67E22),
                          height: 1.1,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                // Email row + SEND RECEIPT
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 220,
                      child: TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        style: const TextStyle(fontSize: 15),
                        decoration: const InputDecoration(
                          prefixIcon: Icon(
                            Icons.email_outlined,
                            color: Color(0xFF9E9E9E),
                          ),
                          hintText: 'Enter email',
                          hintStyle: TextStyle(color: Color(0xFF9E9E9E)),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        final email = _emailController.text.trim();
                        if (email.isNotEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Receipt sent to $email'),
                            ),
                          );
                        }
                      },
                      child: const Text(
                        'SEND RECEIPT',
                        style: TextStyle(
                          color: Color(0xFF9E9E9E),
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 280, child: Divider(height: 1)),
                const SizedBox(height: 8),
                // PRINT RECEIPT
                TextButton.icon(
                  onPressed: () => SunmiPrinterService().printReceipt(
                    PrintReceiptData(
                      receiptId: _lastReceiptNumber,
                      queueNumber: _lastQueueNumber,
                      date: _lastReceiptDate,
                      time: _lastReceiptTime,
                      paymentMethod: _lastReceiptMethod,
                      items: _cart
                          .map(
                            (item) => PrintItem(
                              name: item.product.name,
                              qty: item.quantity,
                              unitPrice: item.unitPrice,
                              lineTotal: item.lineTotalAfterDiscount,
                              discount: item.itemDiscount,
                              modifiers: _modifierList(item),
                            ),
                          )
                          .toList(),
                      total: _lastPaidTotal - _lastChange,
                      cashReceived: _lastPaidTotal,
                      change: _lastChange,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF424242),
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
                  ),
                  icon: const Icon(Icons.print_outlined, size: 20),
                  label: const Text(
                    'PRINT RECEIPT',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_isOfflineOrder)
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 0, 32, 12),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE67E22)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_queue, size: 16, color: Color(0xFFE67E22)),
                  SizedBox(width: 6),
                  Text(
                    'Order saved offline — will sync when connected.',
                    style: TextStyle(fontSize: 12, color: Color(0xFFE67E22)),
                  ),
                ],
              ),
            ),
          ),
        // NEW SALE button pinned at bottom
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
          child: SizedBox(
            height: 56,
            child: ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _isPaymentMode = false;
                  _isPaymentSuccessMode = false;
                  _isOfflineOrder = false;
                  _cart.clear();
                  _billDiscountValue = 0.0;
                  _billDiscountIsPercent = false;
                  _redeemCashback = false;
                  _selectedCustomer = null;
                  _cashController.text = '0.00';
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _kGreen,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              icon: const Icon(Icons.check, size: 22),
              label: const Text(
                'NEW SALE',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentPanel() {
    final total = _total;
    final suggestions = _cashSuggestions(total);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // App bar
        Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Color(0xFFE0E0E0))),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Color(0xFF212121)),
                onPressed: _isProcessingPayment
                    ? null
                    : () => setState(() => _isPaymentMode = false),
                tooltip: 'Back',
              ),
              const Spacer(),
              TextButton(
                onPressed: () {},
                child: const Text(
                  'SPLIT',
                  style: TextStyle(
                    color: Color(0xFFE67E22),
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
        ),
        // Content
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(40, 40, 40, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Total amount
                Text(
                  'RM ${total.toStringAsFixed(2)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 52,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Total amount due',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 15),
                ),
                const SizedBox(height: 40),
                if (_paymentModes.any((m) => m.isCash)) ...[
                  // Cash received label
                  const Text(
                    'Cash received',
                    style: TextStyle(
                      color: _kGreen,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Cash input + charge button
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _cashController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [_CashInputFormatter()],
                          style: const TextStyle(fontSize: 16),
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.money_outlined),
                            prefixText: 'RM',
                            border: UnderlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton(
                        onPressed: _isProcessingPayment ? null : _processCashPayment,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 18,
                          ),
                        ),
                        child: _isProcessingPayment
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text(
                                'CHARGE',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1,
                                ),
                              ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Cash suggestion buttons
                  Row(
                    children: suggestions.map((amount) {
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: OutlinedButton(
                            onPressed: _isProcessingPayment
                                ? null
                                : () {
                                    _cashController.text =
                                        amount.toStringAsFixed(2);
                                    _processCashPayment();
                                  },
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                vertical: 14,
                              ),
                            ),
                            child: Text(
                              'RM ${amount.toStringAsFixed(2)}',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 32),
                ],
                if (_isLoadingPaymentModes)
                  const Center(child: CircularProgressIndicator())
                else
                  ...() {
                    final nonCash = _paymentModes.where((m) => !m.isCash).toList();
                    final widgets = <Widget>[];
                    for (int i = 0; i < nonCash.length; i++) {
                      final mode = nonCash[i];
                      widgets.add(_paymentMethodButton(
                        icon: _iconForPaymentMode(mode.name),
                        label: mode.name.toUpperCase(),
                        onPressed: _isProcessingPayment
                            ? null
                            : () {
                                if (mode.name == 'DuitNow QR') {
                                  _showDuitNowDialog();
                                } else {
                                  _processPayment(mode.name);
                                }
                              },
                      ));
                      if (i < nonCash.length - 1) widgets.add(const SizedBox(height: 8));
                    }
                    return widgets;
                  }(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  IconData _iconForPaymentMode(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('card')) return Icons.credit_card;
    if (lower.contains('qr') || lower.contains('duit')) return Icons.qr_code_2;
    return Icons.payment;
  }

  Widget _paymentMethodButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: TextButton.icon(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          backgroundColor: const Color(0xFFF0F0F0),
          foregroundColor: Colors.black87,
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        icon: Icon(icon),
        label: Text(
          label,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }
}

// ─── Swipe-to-reveal-delete row ───────────────────────────────────────────────

class _SlidableCartRow extends StatefulWidget {
  const _SlidableCartRow({
    required super.key,
    required this.item,
    required this.summary,
    required this.onTap,
    required this.onDelete,
  });

  final _CartItem item;
  final String summary;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  State<_SlidableCartRow> createState() => _SlidableCartRowState();
}

class _SlidableCartRowState extends State<_SlidableCartRow> {
  static const double _buttonWidth = 72.0;
  double _dx = 0.0;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Stack(
        children: [
          // Delete button (behind)
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: _buttonWidth,
            child: ColoredBox(
              color: Colors.red.shade400,
              child: IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.white),
                onPressed: widget.onDelete,
              ),
            ),
          ),
          // Sliding content (in front)
          GestureDetector(
            onHorizontalDragUpdate: (d) => setState(() {
              _dx = (_dx + d.delta.dx).clamp(-_buttonWidth, 0.0);
            }),
            onHorizontalDragEnd: (d) => setState(() {
              _dx = _dx < -_buttonWidth / 2 ? -_buttonWidth : 0.0;
            }),
            onTap: () {
              if (_dx != 0.0) {
                setState(() => _dx = 0.0);
              } else {
                widget.onTap();
              }
            },
            child: Transform.translate(
              offset: Offset(_dx, 0),
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${widget.item.product.name}  ×  ${widget.item.quantity}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 14,
                            ),
                          ),
                          if (widget.summary.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              widget.summary,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF9E9E9E),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (widget.item.itemDiscount > 0)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'RM ${widget.item.lineTotal.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF9E9E9E),
                              decoration: TextDecoration.lineThrough,
                              decorationColor: Color(0xFF9E9E9E),
                            ),
                          ),
                          Text(
                            'RM ${widget.item.lineTotalAfterDiscount.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: Color(0xFFE67E22),
                            ),
                          ),
                        ],
                      )
                    else
                      Text(
                        'RM ${widget.item.lineTotal.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Modifier Modal ───────────────────────────────────────────────────────────

class _ModifierModal extends StatefulWidget {
  const _ModifierModal({
    required this.product,
    required this.initialSelected,
    required this.initialQuantity,
    required this.onSave,
    this.initialDiscountValue = 0.0,
    this.initialDiscountIsPercent = false,
  });

  final _Product product;
  final Map<String, Set<String>> initialSelected;
  final int initialQuantity;
  final double initialDiscountValue;
  final bool initialDiscountIsPercent;
  final void Function(
    Map<String, Set<String>> selected,
    int quantity,
    double discountValue,
    bool discountIsPercent,
  ) onSave;

  @override
  State<_ModifierModal> createState() => _ModifierModalState();
}

class _ModifierModalState extends State<_ModifierModal> {
  static const _kGreen = Color(0xFFE67E22);

  late final Map<String, Set<String>> _selected;
  late int _quantity;
  late final TextEditingController _discountCtrl;
  bool _discountIsPercent = false;

  @override
  void initState() {
    super.initState();
    _selected = {};
    for (final e in widget.initialSelected.entries) {
      _selected[e.key] = Set<String>.from(e.value);
    }
    _quantity = widget.initialQuantity;
    _discountIsPercent = widget.initialDiscountIsPercent;
    _discountCtrl = TextEditingController(
      text: widget.initialDiscountValue > 0
          ? widget.initialDiscountValue.toStringAsFixed(2)
          : '',
    );
  }

  @override
  void dispose() {
    _discountCtrl.dispose();
    super.dispose();
  }

  double get _discountValue => double.tryParse(_discountCtrl.text) ?? 0.0;

  double get _modifierPrice {
    double total = 0;
    for (final group in widget.product.modifierGroups) {
      final sel = _selected[group.name] ?? {};
      for (final mod in group.modifiers) {
        if (sel.contains(mod.name)) total += mod.price;
      }
    }
    return total;
  }

  void _toggle(_ModifierGroup group, _Modifier mod) {
    setState(() {
      final sel = _selected.putIfAbsent(group.name, () => {});
      if (group.multiSelect) {
        if (!sel.remove(mod.name)) sel.add(mod.name);
      } else {
        sel
          ..clear()
          ..add(mod.name);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final unitPrice = widget.product.price + _modifierPrice;
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 640,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Text(
                      '${widget.product.name}  RM ${unitPrice.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      widget.onSave(
                        Map.fromEntries(_selected.entries.map(
                          (e) => MapEntry(e.key, Set<String>.from(e.value)),
                        )),
                        _quantity,
                        _discountValue,
                        _discountIsPercent,
                      );
                      Navigator.pop(context);
                    },
                    child: const Text(
                      'SAVE',
                      style: TextStyle(
                        color: _kGreen,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildItemDiscount(),
                    _buildQuantity(),
                    ...widget.product.modifierGroups.map(_buildGroup),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemDiscount() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 16, bottom: 10),
          child: Text(
            'Item Discount',
            style: TextStyle(
              color: _kGreen,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
        ),
        Row(
          children: [
            // Amount input
            Expanded(
              child: TextField(
                controller: _discountCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w300,
                ),
                decoration: const InputDecoration(
                  hintText: '0.00',
                  hintStyle: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w300,
                    color: Color(0xFFBDBDBD),
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            // RM / % toggle
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFE0E0E0)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  _discountTypeBtn('RM', !_discountIsPercent),
                  _discountTypeBtn('%', _discountIsPercent),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Quick % buttons
        Row(
          children: [5, 10, 20, 100].map((pct) {
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFE0E0E0)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 12),
                  ),
                  onPressed: () => setState(() {
                    _discountIsPercent = true;
                    _discountCtrl.text = '$pct';
                  }),
                  child: Text(
                    '$pct%',
                    style: const TextStyle(
                      color: Color(0xFF212121),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        const Divider(height: 1),
      ],
    );
  }

  Widget _discountTypeBtn(String label, bool active) {
    return GestureDetector(
      onTap: () => setState(() => _discountIsPercent = label == '%'),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF212121) : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : const Color(0xFF757575),
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildGroup(_ModifierGroup group) {
    final mods = group.modifiers;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 10),
          child: Text(
            group.name,
            style: const TextStyle(
              color: _kGreen,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
        ),
        for (int i = 0; i < mods.length; i += 2) ...[
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _buildModifierTile(
                    group,
                    mods[i],
                    (_selected[group.name] ?? {}).contains(mods[i].name),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: i + 1 < mods.length
                      ? _buildModifierTile(
                          group,
                          mods[i + 1],
                          (_selected[group.name] ?? {})
                              .contains(mods[i + 1].name),
                        )
                      : const SizedBox(),
                ),
              ],
            ),
          ),
          if (i + 2 < mods.length) const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _buildModifierTile(
    _ModifierGroup group,
    _Modifier mod,
    bool isSelected,
  ) {
    return InkWell(
      onTap: () => _toggle(group, mod),
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? _kGreen : const Color(0xFFE0E0E0),
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
          color: isSelected ? const Color(0xFFFFF3E0) : Colors.white,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(mod.name, style: const TextStyle(fontSize: 13)),
            ),
            Text(
              mod.price == 0
                  ? 'RM0.00'
                  : '+RM${mod.price.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 12,
                color: mod.price == 0
                    ? const Color(0xFF9E9E9E)
                    : const Color(0xFFE67E22),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuantity() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 16, bottom: 10),
          child: Text(
            'Quantity',
            style: TextStyle(
              color: _kGreen,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
        ),
        SizedBox(
          height: 52,
          child: Row(
            children: [
              _qtyBtn(Icons.remove, () {
                if (_quantity > 1) setState(() => _quantity--);
              }),
              Expanded(
                child: Container(
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    border: Border(
                      top: BorderSide(color: Color(0xFFE0E0E0)),
                      bottom: BorderSide(color: Color(0xFFE0E0E0)),
                    ),
                  ),
                  child: Text(
                    '$_quantity',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              _qtyBtn(Icons.add, () => setState(() => _quantity++)),
            ],
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _qtyBtn(IconData icon, VoidCallback onTap) {
    return SizedBox(
      width: 52,
      height: 52,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          shape: const RoundedRectangleBorder(),
          side: const BorderSide(color: Color(0xFFE0E0E0)),
        ),
        onPressed: onTap,
        child: Icon(icon, color: Colors.black87),
      ),
    );
  }
}

// ─── Customer Search Modal ────────────────────────────────────────────────────

class _CustomerSearchModal extends StatefulWidget {
  const _CustomerSearchModal({required this.onSelect, required this.screenHeight});

  final void Function(PosCustomer) onSelect;
  final double screenHeight;

  @override
  State<_CustomerSearchModal> createState() => _CustomerSearchModalState();
}

class _CustomerSearchModalState extends State<_CustomerSearchModal> {
  final _queryCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  Timer? _debounce;
  List<PosCustomer> _results = [];
  bool _isLoadingFirst = false;
  bool _isLoadingMore = false;
  bool _hasMore = false;
  int _page = 1;
  int _generation = 0;
  String _activeQuery = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _loadPage(reset: true);
  }

  @override
  void dispose() {
    _queryCtrl.dispose();
    _scrollCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
            _scrollCtrl.position.maxScrollExtent - 120 &&
        _hasMore &&
        !_isLoadingMore &&
        !_isLoadingFirst) {
      _loadPage();
    }
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _loadPage(reset: true),
    );
  }

  Future<void> _loadPage({bool reset = false}) async {
    if (!reset && (_isLoadingFirst || _isLoadingMore)) return;
    final query = _queryCtrl.text;
    if (reset) _generation++;
    final int gen = _generation;
    if (reset) {
      setState(() {
        _isLoadingFirst = true;
        _isLoadingMore = false;
        _page = 1;
        _results = [];
        _error = null;
        _activeQuery = query;
      });
    } else {
      setState(() => _isLoadingMore = true);
    }
    try {
      final token = await const SecureStore().readToken() ?? '';
      final fetched = await CustomerService().fetchMembers(
        token,
        page: _page,
        query: _activeQuery.trim().isNotEmpty ? _activeQuery : null,
      );
      if (!mounted || gen != _generation) return;
      setState(() {
        _results = reset ? fetched.members : [..._results, ...fetched.members];
        _hasMore = fetched.hasMore;
        _page++;
        _isLoadingFirst = false;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (!mounted || gen != _generation) return;
      setState(() {
        _isLoadingFirst = false;
        _isLoadingMore = false;
        _error = 'Failed to load members. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 60),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 560, maxHeight: widget.screenHeight * 0.75),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Expanded(
                    child: Text(
                      'Add customer to ticket',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            // Search field
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _queryCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search by name or phone',
                  prefixIcon: _isLoadingFirst
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : const Icon(Icons.person_search),
                  border: const UnderlineInputBorder(),
                ),
                onChanged: _onQueryChanged,
              ),
            ),
            const Divider(height: 1),
            // Results
            Flexible(
              child: _isLoadingFirst
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _error!,
                                  style: const TextStyle(color: Color(0xFF9E9E9E)),
                                ),
                                const SizedBox(height: 12),
                                TextButton(
                                  onPressed: () => _loadPage(reset: true),
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : _results.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(24),
                                child: Text(
                                  'No members found.',
                                  style: TextStyle(color: Color(0xFF9E9E9E)),
                                ),
                              ),
                            )
                          : ListView.separated(
                              controller: _scrollCtrl,
                              shrinkWrap: true,
                              itemCount: _results.length + (_isLoadingMore ? 1 : 0),
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1, indent: 64),
                              itemBuilder: (_, i) {
                                if (i == _results.length) {
                                  return const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 16),
                                    child: Center(
                                      child: SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      ),
                                    ),
                                  );
                                }
                                final customer = _results[i];
                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: Colors.grey.shade300,
                                    child: Icon(Icons.person,
                                        color: Colors.grey.shade600),
                                  ),
                                  title: Text(customer.name),
                                  subtitle: Text(customer.phone),
                                  trailing: customer.cashbackBalance > 0
                                      ? Text(
                                          'RM ${customer.cashbackBalance.toStringAsFixed(2)}',
                                          style: TextStyle(
                                            color: Colors.grey.shade500,
                                            fontSize: 13,
                                          ),
                                        )
                                      : null,
                                  onTap: () {
                                    widget.onSelect(customer);
                                    Navigator.pop(context);
                                  },
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Calculator-style cash input: digits fill from the right, decimal fixed at 2 places.
/// e.g. typing 1 → "0.01", then 5 → "0.15", then 0 → "1.50"
class _CashInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^\d]'), '');
    final cents = int.tryParse(digits) ?? 0;
    final formatted = (cents / 100).toStringAsFixed(2);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
