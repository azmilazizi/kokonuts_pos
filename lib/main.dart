import 'package:flutter/material.dart';

import 'api/api_client.dart';
import 'api/app_config.dart';

void main() {
  runApp(const PosApp());
}

class PosApp extends StatelessWidget {
  const PosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kokonuts POS',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2C6E9E)),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const RegisterScreen(),
    );
  }
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  bool _isSidebarVisible = true;
  int _selectedIndex = 5;
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _totalSalesController = TextEditingController();
  final List<_PaymentEntry> _paymentEntries = [];
  final ApiClient _apiClient = ApiClient();
  DateTime _selectedDate = DateTime.now();
  ApiStatus? _syncStatus;
  bool _isSyncLoading = false;

  static const List<String> _paymentMethods = [
    'Cash',
    'Credit Card',
    'Debit Card',
    'Mobile Wallet',
    'Gift Card',
  ];

  static const List<_SidebarDestination> _destinations = [
    _SidebarDestination(
      label: 'Register',
      icon: Icons.point_of_sale,
      description: 'We are building the Register experience. '
          'Please check back soon.',
    ),
    _SidebarDestination(
      label: 'Transactions',
      icon: Icons.receipt_long,
      description: 'Review past transactions and customer receipts.',
    ),
    _SidebarDestination(
      label: 'Manage Products',
      icon: Icons.inventory_2,
      description: 'Add, update, and organize your product catalog.',
    ),
    _SidebarDestination(
      label: 'Close Shift',
      icon: Icons.lock_clock,
      description: 'Close out the current shift and reconcile totals.',
    ),
    _SidebarDestination(
      label: 'Sales Report',
      icon: Icons.analytics,
      description: 'Analyze sales performance and export summaries.',
    ),
    _SidebarDestination(
      label: 'Manual Entry',
      icon: Icons.edit_note,
      description: 'Enter sales or adjustments manually.',
    ),
    _SidebarDestination(
      label: 'Sync',
      icon: Icons.sync,
      description: 'Sync data across devices and services.',
    ),
    _SidebarDestination(
      label: 'Settings',
      icon: Icons.settings,
      description: 'Customize preferences and manage staff access.',
    ),
  ];

  void _toggleSidebar() {
    setState(() {
      _isSidebarVisible = !_isSidebarVisible;
    });
  }

  @override
  void initState() {
    super.initState();
    _dateController.text = _formatDate(_selectedDate);
    _paymentEntries.add(
      _PaymentEntry(method: _paymentMethods.first),
    );
    _refreshSyncStatus();
  }

  @override
  void dispose() {
    _dateController.dispose();
    _totalSalesController.dispose();
    for (final entry in _paymentEntries) {
      entry.amountController.dispose();
    }
    super.dispose();
  }

  void _selectDestination(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _dateController.text = _formatDate(picked);
      });
    }
  }

  void _addPaymentEntry() {
    setState(() {
      _paymentEntries.add(
        _PaymentEntry(method: _paymentMethods.first),
      );
    });
  }

  Widget _buildManualEntryContent() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Manual Entry',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Capture the day\'s totals and payment breakdown.',
            style: TextStyle(color: Color(0xFF5F6368)),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _dateController,
            readOnly: true,
            decoration: const InputDecoration(
              labelText: 'Date',
              prefixIcon: Icon(Icons.calendar_today),
              border: OutlineInputBorder(),
            ),
            onTap: _pickDate,
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _totalSalesController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Total Sales',
              prefixText: '\$ ',
              prefixIcon: Icon(Icons.attach_money),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Payment Methods',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          ..._paymentEntries.asMap().entries.map(
            (entry) {
              final index = entry.key;
              final payment = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: payment.method,
                        items: _paymentMethods
                            .map(
                              (method) => DropdownMenuItem<String>(
                                value: method,
                                child: Text(method),
                              ),
                            )
                            .toList(),
                        decoration: const InputDecoration(
                          labelText: 'Method',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          setState(() {
                            payment.method = value;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: payment.amountController,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Amount',
                          prefixText: '\$ ',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _addPaymentEntry,
              icon: const Icon(Icons.add),
              label: const Text('Add payment method'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _refreshSyncStatus() async {
    setState(() {
      _isSyncLoading = true;
    });

    final status = await _apiClient.ping();
    if (!mounted) {
      return;
    }

    setState(() {
      _syncStatus = status;
      _isSyncLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    const sidebarWidth = 260.0;
    const username = 'Alex Tan';
    final screenWidth = MediaQuery.of(context).size.width;
    final destination = _destinations[_selectedIndex];

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: SafeArea(
        child: Stack(
          children: [
            if (_isSidebarVisible)
              SizedBox(
                width: sidebarWidth,
                child: Container(
                  color: Colors.white,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                        child: Row(
                          children: [
                            TextButton(
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                foregroundColor: const Color(0xFF2C6E9E),
                                backgroundColor: const Color(0xFFE7F1F9),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                textStyle: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              onPressed: () {},
                              child: const Text('Sign Out'),
                            ),
                            const Spacer(),
                            Text(
                              username,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF2D2D2D),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          children: [
                            _SidebarItem(
                              label: _destinations[0].label,
                              icon: _destinations[0].icon,
                              isSelected: _selectedIndex == 0,
                              onTap: () => _selectDestination(0),
                            ),
                            _SidebarItem(
                              label: _destinations[1].label,
                              icon: _destinations[1].icon,
                              isSelected: _selectedIndex == 1,
                              onTap: () => _selectDestination(1),
                            ),
                            _SidebarItem(
                              label: _destinations[2].label,
                              icon: _destinations[2].icon,
                              isSelected: _selectedIndex == 2,
                              onTap: () => _selectDestination(2),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: Divider(height: 1),
                            ),
                            _SidebarItem(
                              label: _destinations[3].label,
                              icon: _destinations[3].icon,
                              isSelected: _selectedIndex == 3,
                              onTap: () => _selectDestination(3),
                            ),
                            _SidebarItem(
                              label: _destinations[4].label,
                              icon: _destinations[4].icon,
                              isSelected: _selectedIndex == 4,
                              onTap: () => _selectDestination(4),
                            ),
                            _SidebarItem(
                              label: _destinations[5].label,
                              icon: _destinations[5].icon,
                              isSelected: _selectedIndex == 5,
                              onTap: () => _selectDestination(5),
                            ),
                            _SidebarItem(
                              label: _destinations[6].label,
                              icon: _destinations[6].icon,
                              isSelected: _selectedIndex == 6,
                              onTap: () => _selectDestination(6),
                            ),
                            _SidebarItem(
                              label: _destinations[7].label,
                              icon: _destinations[7].icon,
                              isSelected: _selectedIndex == 7,
                              onTap: () => _selectDestination(7),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            AnimatedSlide(
              offset: Offset(_isSidebarVisible ? sidebarWidth / screenWidth : 0, 0),
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _isSidebarVisible ? _toggleSidebar : null,
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 20,
                      ),
                      child: Row(
                        children: [
                          if (!_isSidebarVisible)
                            Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: IconButton(
                                tooltip: 'Show sidebar',
                                icon: const Icon(Icons.menu),
                                color: const Color(0xFF2C6E9E),
                                onPressed: _toggleSidebar,
                              ),
                            ),
                          Text(
                            destination.label,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: Container(
                          width: 520,
                          padding: const EdgeInsets.all(32),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.08),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: destination.label == 'Manual Entry'
                              ? _buildManualEntryContent()
                              : Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      destination.icon,
                                      size: 64,
                                      color: const Color(0xFF2C6E9E),
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      destination.label,
                                      style: const TextStyle(
                                        fontSize: 26,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      destination.description,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Color(0xFF5F6368),
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDestinationCard(_SidebarDestination destination) {
    return Container(
      width: 520,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            destination.icon,
            size: 64,
            color: const Color(0xFF2C6E9E),
          ),
          const SizedBox(height: 16),
          Text(
            destination.label,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            destination.description,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF5F6368),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncCard() {
    final status = _syncStatus;
    final isReachable = status?.isReachable ?? false;
    final statusColor = _isSyncLoading
        ? const Color(0xFF9E9E9E)
        : isReachable
            ? const Color(0xFF2E7D32)
            : const Color(0xFFC62828);
    final statusText = _isSyncLoading
        ? 'Checking CRM API connectivity...'
        : status == null
            ? 'Connection status not checked yet.'
            : isReachable
                ? 'CRM API reachable (HTTP ${status.statusCode ?? 'OK'}).'
                : 'Unable to reach CRM API'
                    '${status.errorMessage == null ? '.' : ': ${status.errorMessage}'}';

    return Container(
      width: 560,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'CRM REST API',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            AppConfig.baseUrl,
            style: const TextStyle(
              color: Color(0xFF5F6368),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  statusText,
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              ElevatedButton.icon(
                onPressed: _isSyncLoading ? null : _refreshSyncStatus,
                icon: const Icon(Icons.sync),
                label: const Text('Test Connection'),
              ),
              OutlinedButton.icon(
                onPressed: _isSyncLoading ? null : _refreshSyncStatus,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Next steps: configure authentication headers and map CRM endpoints to '
            'the POS data models.',
            style: TextStyle(
              color: Color(0xFF5F6368),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.label,
    required this.onTap,
    required this.icon,
    this.isSelected = false,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final textColor = isSelected ? const Color(0xFF2C6E9E) : Colors.black87;
    final fontWeight = isSelected ? FontWeight.w600 : FontWeight.w500;

    return Material(
      color: isSelected ? const Color(0xFFE7F1F9) : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        leading: Icon(
          icon,
          color: textColor,
          size: 20,
        ),
        title: Text(
          label,
          style: TextStyle(
            color: textColor,
            fontWeight: fontWeight,
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}

class _SidebarDestination {
  const _SidebarDestination({
    required this.label,
    required this.icon,
    required this.description,
  });

  final String label;
  final IconData icon;
  final String description;
}

class _PaymentEntry {
  _PaymentEntry({required this.method})
      : amountController = TextEditingController();

  String method;
  final TextEditingController amountController;
}
