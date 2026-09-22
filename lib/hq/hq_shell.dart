import 'package:flutter/material.dart';

import '../storage/secure_store.dart';
import 'hq_franchise_sales_screen.dart';
import 'hq_production_screen.dart';

/// Top-level shell shown instead of the retail [RegisterScreen] when the
/// activated device's warehouse is warehouse_type='hq'. Deliberately a
/// separate, independent screen tree (not a retrofit of RegisterScreen's
/// hardcoded sidebar) — HQ back-office actions (Production, Franchise/Client
/// Sales) have nothing to do with customer order-taking.
class HqShell extends StatefulWidget {
  const HqShell({super.key, required this.onSignOut});

  final Future<void> Function() onSignOut;

  @override
  State<HqShell> createState() => _HqShellState();
}

class _HqShellState extends State<HqShell> {
  int _selectedIndex = 0;
  final SecureStore _secureStore = const SecureStore();
  String _warehouseName = '';

  @override
  void initState() {
    super.initState();
    _loadWarehouseName();
  }

  Future<void> _loadWarehouseName() async {
    final name = await _secureStore.readWarehouseName();
    if (!mounted) return;
    setState(() => _warehouseName = name ?? 'HQ');
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      const HqProductionScreen(),
      const HqFranchiseSalesScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text('$_warehouseName · HQ'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: widget.onSignOut,
          ),
        ],
      ),
      body: IndexedStack(index: _selectedIndex, children: screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) =>
            setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.precision_manufacturing_outlined),
            selectedIcon: Icon(Icons.precision_manufacturing),
            label: 'Production',
          ),
          NavigationDestination(
            icon: Icon(Icons.local_shipping_outlined),
            selectedIcon: Icon(Icons.local_shipping),
            label: 'Sell to Franchise/Client',
          ),
        ],
      ),
    );
  }
}
