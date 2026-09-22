import 'dart:convert';

import 'package:flutter/material.dart';

import '../api/api_exception.dart';
import '../models/production_recipe_preview.dart';
import '../models/production_run.dart';
import '../models/production_source.dart';
import '../services/production_service.dart';
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

class HqProductionScreen extends StatefulWidget {
  const HqProductionScreen({super.key});

  @override
  State<HqProductionScreen> createState() => _HqProductionScreenState();
}

class _HqProductionScreenState extends State<HqProductionScreen> {
  final ProductionService _service = ProductionService();
  final SecureStore _secureStore = const SecureStore();

  String? _token;
  bool _isLoading = true;
  String? _errorMessage;
  List<ProductionSource> _sources = const [];
  List<ProductionRun> _runs = const [];

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
      final results = await Future.wait([
        _service.fetchSources(token: token ?? ''),
        _service.fetchRuns(token: token ?? ''),
      ]);
      if (!mounted) return;
      setState(() {
        _sources = results[0] as List<ProductionSource>;
        _runs = results[1] as List<ProductionRun>;
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

  Future<void> _openProductionForm(ProductionSource source) async {
    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _ProductionForm(
        item: source,
        token: _token ?? '',
        service: _service,
      ),
    );
    if (submitted == true) {
      _load();
    }
  }

  Future<void> _voidRun(ProductionRun run) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Void production run?'),
        content: Text(
          'This reverses run #${run.id}: restores the components it '
          'deducted and removes ${run.producedQuantity} ${run.producedName} '
          'from stock.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Void'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _service.voidRun(token: _token ?? '', runId: run.id);
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyError(e))),
      );
    }
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

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Producible items', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_sources.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'No items are set up for manufacturing yet. An item needs '
                'Manufacturing, Sold, and Inventory all enabled (Sales → '
                'Items) to show up here.',
              ),
            )
          else
            ..._sources.map((source) => Card(
                  child: ListTile(
                    title: Text(source.skuName),
                    subtitle: Text(
                      'On hand: ${source.currentStock} ${source.unitUom}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openProductionForm(source),
                  ),
                )),
          const SizedBox(height: 24),
          Text('Recent runs', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_runs.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('No production runs recorded yet.'),
            )
          else
            ..._runs.map((run) => Card(
                  child: ListTile(
                    title: Text(
                      '${run.producedQuantity} × ${run.producedName}'
                      '${run.isVoided ? '  (voided)' : ''}',
                    ),
                    subtitle: Text(
                      run.deductions.isEmpty
                          ? ''
                          : 'Used: ${run.deductions.map((d) => '${d.quantity} ${d.itemName}').join(', ')}',
                    ),
                    trailing: run.isVoided
                        ? null
                        : TextButton(
                            onPressed: () => _voidRun(run),
                            child: const Text('Void'),
                          ),
                  ),
                )),
        ],
      ),
    );
  }
}

class _ProductionForm extends StatefulWidget {
  const _ProductionForm({
    required this.item,
    required this.token,
    required this.service,
  });

  final ProductionSource item;
  final String token;
  final ProductionService service;

  @override
  State<_ProductionForm> createState() => _ProductionFormState();
}

class _ProductionFormState extends State<_ProductionForm> {
  final TextEditingController _quantityController = TextEditingController();
  final Map<int, TextEditingController> _overrideControllers = {};
  ProductionRecipePreview? _preview;
  bool _isLoadingPreview = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  @override
  void dispose() {
    _quantityController.dispose();
    for (final c in _overrideControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadPreview() async {
    try {
      final preview = await widget.service.fetchRecipePreview(
        token: widget.token,
        itemId: widget.item.itemId,
      );
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _isLoadingPreview = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = _friendlyError(e);
        _isLoadingPreview = false;
      });
    }
  }

  double get _producedQuantity =>
      double.tryParse(_quantityController.text) ?? 0.0;

  double _theoreticalConsumption(ProductionRecipeComponent component) =>
      _producedQuantity * component.perUnitQuantity;

  TextEditingController _controllerFor(ProductionRecipeComponent component) {
    return _overrideControllers.putIfAbsent(
      component.componentItemId,
      () => TextEditingController(),
    );
  }

  Future<void> _submit() async {
    if (_producedQuantity <= 0) {
      setState(() => _errorMessage = 'Enter a quantity greater than zero.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final overrides = <int, double>{};
    for (final entry in _overrideControllers.entries) {
      final text = entry.value.text.trim();
      if (text.isNotEmpty) {
        final value = double.tryParse(text);
        if (value != null) overrides[entry.key] = value;
      }
    }

    try {
      await widget.service.createRun(
        token: widget.token,
        itemId: widget.item.itemId,
        quantity: _producedQuantity,
        componentOverrides: overrides,
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
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Produce ${widget.item.skuName}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text('On hand: ${widget.item.currentStock} ${widget.item.unitUom}'),
            const SizedBox(height: 16),
            TextField(
              controller: _quantityController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Quantity produced (${widget.item.unitUom})',
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            if (_isLoadingPreview)
              const Center(child: CircularProgressIndicator())
            else if (_preview == null || !_preview!.enabled)
              const Text(
                'No Mixed Ingredient recipe configured for this item yet. '
                'Set one up in Costing → Mixed Ingredients.',
              )
            else ...[
              Text('Ingredients consumed', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              ..._preview!.components.map((component) {
                final theoretical = _theoreticalConsumption(component);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(
                    controller: _controllerFor(component),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: component.skuName,
                      helperText:
                          'Recipe: ${theoretical.toStringAsFixed(3)} ${component.unitUom} — '
                          'leave blank to use it, or enter what was actually used',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                );
              }),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _isSubmitting ? null : _submit,
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Record production'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
