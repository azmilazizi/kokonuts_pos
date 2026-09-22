import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../api/api_exception.dart';
import '../models/franchise_sale_order.dart';
import '../models/sale_item_option.dart';
import '../services/franchise_sales_service.dart';
import '../services/payment_mode_service.dart';
import '../storage/secure_store.dart';

String _friendlyError(Object error) {
  if (error is ApiException) {
    try {
      final decoded = jsonDecode(error.message);
      if (decoded is Map && decoded['error'] != null) {
        return decoded['error'].toString();
      }
    } catch (_) {
      // Fall through to the raw message below.
    }
    return error.message;
  }
  return 'Something went wrong. Please try again.';
}

class HqFranchiseSalesScreen extends StatefulWidget {
  const HqFranchiseSalesScreen({super.key});

  @override
  State<HqFranchiseSalesScreen> createState() =>
      _HqFranchiseSalesScreenState();
}

class _HqFranchiseSalesScreenState extends State<HqFranchiseSalesScreen> {
  final FranchiseSalesService _service = FranchiseSalesService();
  final SecureStore _secureStore = const SecureStore();

  String? _token;
  bool _isLoading = true;
  String? _errorMessage;
  List<FranchiseSaleOrder> _orders = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final token = await _secureStore.readToken();
      _token = token;
      final orders = await _service.fetchOrders(token: token ?? '');
      if (!mounted) return;
      setState(() {
        _orders = orders;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = _friendlyError(e);
        _isLoading = false;
      });
    }
  }

  Future<void> _startNewSale() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) =>
            _NewSaleScreen(token: _token ?? '', service: _service),
      ),
    );
    if (created == true) {
      _load();
    }
  }

  Future<void> _advance(
    FranchiseSaleOrder order,
    Future<FranchiseSaleOrder> Function() action,
  ) async {
    try {
      await action();
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyError(e))),
      );
    }
  }

  Future<void> _recordPayment(FranchiseSaleOrder order) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _RecordPaymentSheet(
        token: _token ?? '',
        defaultAmount: order.total,
      ),
    );
    if (result == null) return;

    await _advance(
      order,
      () => _service.recordPayment(
        token: _token ?? '',
        id: order.id,
        amount: result['amount'] as double,
        mode: result['mode'] as String,
      ),
    );
  }

  Future<void> _viewInvoicePdf(FranchiseSaleOrder order) async {
    try {
      final bytes = await _service.fetchInvoicePdf(
        token: _token ?? '',
        orderId: order.id,
      );
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'invoice_${order.invoiceId}.pdf',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyError(e))),
      );
    }
  }

  Widget _actionButton(FranchiseSaleOrder order) {
    if (order.canQuote) {
      return FilledButton(
        onPressed: () => _advance(
          order,
          () => _service.requestQuote(token: _token ?? '', id: order.id),
        ),
        child: const Text('Create Quotation'),
      );
    }
    if (order.canInvoice) {
      return FilledButton(
        onPressed: () => _advance(
          order,
          () => _service.convertToInvoice(token: _token ?? '', id: order.id),
        ),
        child: const Text('Convert to Invoice'),
      );
    }
    if (order.canRecordPayment) {
      return FilledButton(
        onPressed: () => _recordPayment(order),
        child: const Text('Record Payment'),
      );
    }
    if (order.canDeliver) {
      return FilledButton(
        onPressed: () => _advance(
          order,
          () => _service.deliver(token: _token ?? '', id: order.id),
        ),
        child: const Text('Deliver'),
      );
    }
    return const Chip(label: Text('Delivered'));
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_errorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: _orders.isEmpty
            ? ListView(
                children: const [
                  Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'No sale orders yet. Tap + to sell to a franchise or client.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _orders.length,
                itemBuilder: (context, index) {
                  final order = _orders[index];
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  order.buyerName.isNotEmpty
                                      ? order.buyerName
                                      : (order.buyerType == 'franchisee'
                                          ? 'Franchisee sale #${order.id}'
                                          : 'Client sale #${order.id}'),
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                              ),
                              if (order.invoiceId != null)
                                IconButton(
                                  icon: const Icon(Icons.picture_as_pdf_outlined),
                                  tooltip: 'View invoice PDF',
                                  onPressed: () => _viewInvoicePdf(order),
                                ),
                              Chip(label: Text(order.status)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          ...order.items.map(
                            (item) => Text(
                              '${item.quantity} × ${item.skuName} @ ${item.unitPrice.toStringAsFixed(2)}',
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Total: ${order.total.toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: _actionButton(order),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _startNewSale,
        icon: const Icon(Icons.add),
        label: const Text('New Sale'),
      ),
    );
  }
}

class _RecordPaymentSheet extends StatefulWidget {
  const _RecordPaymentSheet({required this.token, required this.defaultAmount});

  final String token;
  final double defaultAmount;

  @override
  State<_RecordPaymentSheet> createState() => _RecordPaymentSheetState();
}

class _RecordPaymentSheetState extends State<_RecordPaymentSheet> {
  late final TextEditingController _amountController =
      TextEditingController(text: widget.defaultAmount.toStringAsFixed(2));
  List<PaymentMode> _modes = const [];
  String? _selectedModeId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadModes();
  }

  Future<void> _loadModes() async {
    final modes = await PaymentModeService().fetchPaymentModes(widget.token);
    if (!mounted) return;
    setState(() {
      _modes = modes;
      _selectedModeId = modes.isNotEmpty ? modes.first.id : null;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Record payment', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Amount received',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else
            DropdownButtonFormField<String>(
              value: _selectedModeId,
              decoration: const InputDecoration(
                labelText: 'Payment method',
                border: OutlineInputBorder(),
              ),
              items: _modes
                  .map((m) => DropdownMenuItem(value: m.id, child: Text(m.name)))
                  .toList(),
              onChanged: (value) => setState(() => _selectedModeId = value),
            ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _selectedModeId == null
                  ? null
                  : () {
                      final amount = double.tryParse(_amountController.text) ?? 0;
                      Navigator.of(context).pop({
                        'amount': amount,
                        'mode': _selectedModeId,
                      });
                    },
              child: const Text('Confirm payment'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CartLine {
  _CartLine({required this.item, required this.quantity});
  final SaleItemOption item;
  double quantity;
}

class _NewSaleScreen extends StatefulWidget {
  const _NewSaleScreen({required this.token, required this.service});

  final String token;
  final FranchiseSalesService service;

  @override
  State<_NewSaleScreen> createState() => _NewSaleScreenState();
}

class _NewSaleScreenState extends State<_NewSaleScreen> {
  final TextEditingController _buyerSearchController = TextEditingController();
  final TextEditingController _itemSearchController = TextEditingController();

  List<SaleBuyer> _buyerResults = const [];
  SaleBuyer? _selectedBuyer;
  List<FranchiseeOutlet> _outlets = const [];
  FranchiseeOutlet? _selectedOutlet;

  List<SaleItemOption> _itemResults = const [];
  final List<_CartLine> _cart = [];

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _buyerSearchController.dispose();
    _itemSearchController.dispose();
    super.dispose();
  }

  Future<void> _searchBuyers(String q) async {
    final results = await widget.service.fetchBuyers(token: widget.token, query: q);
    if (!mounted) return;
    setState(() => _buyerResults = results);
  }

  Future<void> _selectBuyer(SaleBuyer buyer) async {
    setState(() {
      _selectedBuyer = buyer;
      _outlets = const [];
      _selectedOutlet = null;
    });

    if (buyer.buyerType == 'franchisee' && buyer.franchiseeId != null) {
      final outlets = await widget.service.fetchFranchiseeOutlets(
        token: widget.token,
        franchiseeId: buyer.franchiseeId!,
      );
      if (!mounted) return;
      setState(() {
        _outlets = outlets;
        _selectedOutlet = outlets.length == 1 ? outlets.first : null;
      });
    }
  }

  Future<void> _searchItems(String q) async {
    final results = await widget.service.fetchItems(token: widget.token, query: q);
    if (!mounted) return;
    setState(() => _itemResults = results);
  }

  void _addToCart(SaleItemOption item) {
    setState(() {
      final existing = _cart.where((l) => l.item.itemId == item.itemId);
      if (existing.isEmpty) {
        _cart.add(_CartLine(item: item, quantity: 1));
      }
    });
  }

  bool get _canSubmit {
    if (_selectedBuyer == null || _cart.isEmpty) return false;
    if (_selectedBuyer!.buyerType == 'franchisee' && _selectedOutlet == null) {
      return false;
    }
    return true;
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await widget.service.createOrder(
        token: widget.token,
        buyerType: _selectedBuyer!.buyerType,
        franchiseeId: _selectedBuyer!.franchiseeId,
        clientId: _selectedBuyer!.clientId,
        destinationWarehouseId: _selectedOutlet?.id,
        items: _cart
            .map((l) => {'item_id': l.item.itemId, 'quantity': l.quantity})
            .toList(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = _friendlyError(e);
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Sale')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Buyer', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_selectedBuyer != null)
            ListTile(
              tileColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              title: Text(_selectedBuyer!.name),
              subtitle: Text(_selectedBuyer!.buyerType == 'franchisee'
                  ? 'Franchisee'
                  : 'Client'),
              trailing: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() {
                  _selectedBuyer = null;
                  _outlets = const [];
                  _selectedOutlet = null;
                }),
              ),
            )
          else ...[
            TextField(
              controller: _buyerSearchController,
              decoration: const InputDecoration(
                labelText: 'Search franchisee or client',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: _searchBuyers,
            ),
            ..._buyerResults.map(
              (b) => ListTile(
                title: Text(b.name),
                subtitle: Text(b.buyerType == 'franchisee' ? 'Franchisee' : 'Client'),
                onTap: () => _selectBuyer(b),
              ),
            ),
          ],
          if (_selectedBuyer?.buyerType == 'franchisee' && _outlets.length > 1) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<FranchiseeOutlet>(
              value: _selectedOutlet,
              decoration: const InputDecoration(
                labelText: 'Deliver to outlet',
                border: OutlineInputBorder(),
              ),
              items: _outlets
                  .map((o) => DropdownMenuItem(value: o, child: Text(o.name)))
                  .toList(),
              onChanged: (value) => setState(() => _selectedOutlet = value),
            ),
          ],
          if (_selectedBuyer?.buyerType == 'franchisee' && _outlets.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'This franchisee has no outlet assigned yet — assign one in the CRM before selling to them.',
                style: TextStyle(color: Colors.red),
              ),
            ),
          const SizedBox(height: 24),
          Text('Items', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _itemSearchController,
            decoration: const InputDecoration(
              labelText: 'Search items',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: _searchItems,
          ),
          ..._itemResults.map(
            (item) => ListTile(
              title: Text(item.skuName),
              trailing: const Icon(Icons.add_circle_outline),
              onTap: () => _addToCart(item),
            ),
          ),
          if (_cart.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Cart', style: Theme.of(context).textTheme.titleMedium),
            ..._cart.map(
              (line) => ListTile(
                title: Text(line.item.skuName),
                subtitle: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () => setState(() {
                        if (line.quantity > 1) line.quantity -= 1;
                      }),
                    ),
                    Text('${line.quantity}'),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: () => setState(() => line.quantity += 1),
                    ),
                  ],
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => setState(() => _cart.remove(line)),
                ),
              ),
            ),
          ],
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _canSubmit && !_isSubmitting ? _submit : null,
            child: _isSubmitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Create draft sale order'),
          ),
        ],
      ),
    );
  }
}
