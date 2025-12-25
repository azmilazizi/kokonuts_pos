import 'dart:async';

import 'package:flutter/material.dart';
import 'api/api_client.dart';
import 'api/app_config.dart';
import 'auth/auth_screen.dart';
import 'onboarding/activation_screen.dart';
import 'onboarding/splash_screen.dart';
import 'storage/secure_store.dart';

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
      home: const AppStart(),
    );
  }
}

class AppStart extends StatefulWidget {
  const AppStart({super.key});

  @override
  State<AppStart> createState() => _AppStartState();
}

class _AppStartState extends State<AppStart> with WidgetsBindingObserver {
  late Future<_StartDecision> _startDecisionFuture;
  bool _isAuthenticated = false;
  bool _hasShownReactivationNotice = false;
  bool _isCheckingStatus = false;
  Timer? _statusCheckTimer;
  final ApiClient _apiClient = ApiClient();
  final SecureStore _secureStore = const SecureStore();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startDecisionFuture = _evaluateStart();
    _startStatusCheckTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _statusCheckTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _verifyStatusAndHandleReactivation();
    }
  }

  Future<_StartDecision> _evaluateStart() async {
    final activationEmail = await _secureStore.readActivationEmail();
    final activationToken = await _secureStore.readToken();
    final hasActivationDetails = activationEmail != null &&
        activationEmail.isNotEmpty &&
        activationToken != null &&
        activationToken.isNotEmpty;
    if (!hasActivationDetails) {
      return const _StartDecision(showActivation: true);
    }

    try {
      final isValid = await _checkActivationStatus(
        email: activationEmail,
        token: activationToken,
      );
      if (isValid) {
        return const _StartDecision(showActivation: false);
      }
    } catch (_) {
      // Ignore and fall through to reactivation flow.
    }

    await Future.wait([
      _secureStore.clearAuth(),
      _secureStore.clearActivation(),
    ]);
    return const _StartDecision(
      showActivation: true,
      showReactivationNotice: true,
    );
  }

  void _startStatusCheckTimer() {
    _statusCheckTimer?.cancel();
    _statusCheckTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _verifyStatusAndHandleReactivation(),
    );
  }

  Future<void> _verifyStatusAndHandleReactivation() async {
    if (_isCheckingStatus) {
      return;
    }
    _isCheckingStatus = true;
    try {
      final activationEmail = await _secureStore.readActivationEmail();
      final activationToken = await _secureStore.readToken();
      if (activationEmail == null ||
          activationEmail.isEmpty ||
          activationToken == null ||
          activationToken.isEmpty) {
        return;
      }

      final isActivationValid = await _checkActivationStatus(
        email: activationEmail,
        token: activationToken,
      );
      if (!isActivationValid) {
        await _handleReactivationRequired();
        return;
      }

      if (!_isAuthenticated) {
        return;
      }
    } finally {
      _isCheckingStatus = false;
    }
  }

  Future<bool> _checkActivationStatus({
    required String email,
    required String token,
  }) async {
    final response = await _apiClient.postJson(
      '/omni_sales/api/v1/install/cross_check',
      body: {
        'token': token,
        'email': email,
      },
    );
    return _parseBooleanResponse(response.data);
  }

  bool _parseBooleanResponse(Map<String, dynamic> responseData) {
    final dataPayload = responseData['data'];
    if (dataPayload is bool) {
      return dataPayload;
    }
    if (responseData['result'] is bool) {
      return responseData['result'] as bool;
    }
    if (responseData['success'] is bool) {
      return responseData['success'] as bool;
    }
    if (responseData['status'] is bool) {
      return responseData['status'] as bool;
    }
    return false;
  }

  Future<void> _handleReactivationRequired() async {
    await Future.wait([
      _secureStore.clearAuth(),
      _secureStore.clearActivation(),
    ]);
    if (!mounted) {
      return;
    }
    setState(() {
      _isAuthenticated = false;
      _startDecisionFuture = Future.value(
        const _StartDecision(
          showActivation: true,
          showReactivationNotice: true,
        ),
      );
    });
  }

  void _handleActivated() {
    setState(() {
      _startDecisionFuture =
          Future.value(const _StartDecision(showActivation: false));
    });
  }

  void _handleAuthenticated() {
    setState(() {
      _isAuthenticated = true;
    });
    _verifyStatusAndHandleReactivation();
  }

  Future<void> _handleSignOut() async {
    await _secureStore.clearAuth();
    if (!mounted) {
      return;
    }
    setState(() {
      _isAuthenticated = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_StartDecision>(
      future: _startDecisionFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SplashScreen();
        }

        final decision = snapshot.data!;

        if (decision.showReactivationNotice && !_hasShownReactivationNotice) {
          _hasShownReactivationNotice = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Device activation required'),
                content: const Text(
                  'A new device has been activated. '
                  'This device requires reactivation.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('OK'),
                  ),
                ],
              ),
            );
          });
        }

        if (decision.showActivation) {
          return ActivationScreen(onActivated: _handleActivated);
        }

        if (!_isAuthenticated) {
          return AuthScreen(onAuthenticated: _handleAuthenticated);
        }

        return RegisterScreen(onSignOut: _handleSignOut);
      },
    );
  }
}

class _StartDecision {
  const _StartDecision({
    required this.showActivation,
    this.showReactivationNotice = false,
  });

  final bool showActivation;
  final bool showReactivationNotice;
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, required this.onSignOut});

  final Future<void> Function() onSignOut;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  bool _isSidebarVisible = false;
  int _selectedIndex = 5;
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _totalSalesController = TextEditingController();
  final List<_PaymentEntry> _paymentEntries = [];
  final ApiClient _apiClient = ApiClient();
  DateTime _selectedDate = DateTime.now();
  ApiStatus? _syncStatus;
  bool _isSyncLoading = false;
  bool _isSigningOut = false;

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

  Future<void> _signOut() async {
    if (_isSigningOut) {
      return;
    }
    setState(() {
      _isSigningOut = true;
    });
    try {
      await widget.onSignOut();
    } finally {
      if (mounted) {
        setState(() {
          _isSigningOut = false;
          _isSidebarVisible = false;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _dateController.text = _formatDate(_selectedDate);
    _totalSalesController.addListener(_onPaymentEntriesChanged);
    _paymentEntries.add(_createPaymentEntry());
    _refreshSyncStatus();
  }

  @override
  void dispose() {
    _dateController.dispose();
    _totalSalesController.removeListener(_onPaymentEntriesChanged);
    _totalSalesController.dispose();
    for (final entry in _paymentEntries) {
      entry.amountController.removeListener(_onPaymentEntriesChanged);
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
      _paymentEntries.add(_createPaymentEntry());
    });
  }

  _PaymentEntry _createPaymentEntry() {
    final entry = _PaymentEntry(method: _paymentMethods.first);
    entry.amountController.addListener(_onPaymentEntriesChanged);
    return entry;
  }

  void _onPaymentEntriesChanged() {
    setState(() {});
  }

  double _parseAmount(String value) {
    final normalized = value.replaceAll(',', '').trim();
    return double.tryParse(normalized) ?? 0;
  }

  double get _totalSalesAmount {
    return _parseAmount(_totalSalesController.text);
  }

  double get _paymentTotal {
    return _paymentEntries.fold(
      0,
      (sum, entry) => sum + _parseAmount(entry.amountController.text),
    );
  }

  double _remainingForIndex(int index) {
    final previousTotal = _paymentEntries
        .take(index)
        .fold(0.0, (sum, entry) => sum + _parseAmount(entry.amountController.text));
    final remaining = _totalSalesAmount - previousTotal;
    return remaining > 0 ? remaining : 0.0;
  }

  String _formatCurrency(double amount) {
    return amount.toStringAsFixed(2);
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
              final remaining = _remainingForIndex(index);
              final hintText = _totalSalesAmount > 0
                  ? _formatCurrency(remaining)
                  : null;
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
                        decoration: InputDecoration(
                          labelText: 'Amount',
                          hintText: hintText,
                          prefixText: '\$ ',
                          border: const OutlineInputBorder(),
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
          const SizedBox(height: 12),
          Builder(
            builder: (context) {
              final remaining = _totalSalesAmount - _paymentTotal;
              final isComplete = remaining == 0 && _totalSalesAmount > 0;
              final remainingLabel = remaining >= 0
                  ? 'Remaining balance: \$ ${_formatCurrency(remaining)}'
                  : 'Over by: \$ ${_formatCurrency(remaining.abs())}';
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    remainingLabel,
                    style: TextStyle(
                      color: isComplete
                          ? const Color(0xFF2E7D32)
                          : const Color(0xFFC62828),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: isComplete ? () {} : null,
                    child: const Text('Submit manual entry'),
                  ),
                ],
              );
            },
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
    final destination = _destinations[_selectedIndex];
    final mainContent = Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 20,
          ),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: SizedBox(
                  height: 48,
                  width: 48,
                  child: IgnorePointer(
                    ignoring: _isSidebarVisible,
                    child: Opacity(
                      opacity: _isSidebarVisible ? 0 : 1,
                      child: IconButton(
                        tooltip: 'Show sidebar',
                        icon: const Icon(Icons.menu),
                        color: const Color(0xFF2C6E9E),
                        onPressed: _toggleSidebar,
                      ),
                    ),
                  ),
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
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: SafeArea(
        child: Stack(
          children: [
            mainContent,
            AnimatedOpacity(
              opacity: _isSidebarVisible ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                ignoring: !_isSidebarVisible,
                child: GestureDetector(
                  onTap: _toggleSidebar,
                  child: Container(
                    color: Colors.black.withOpacity(0.45),
                  ),
                ),
              ),
            ),
            AnimatedSlide(
              offset: _isSidebarVisible ? Offset.zero : const Offset(-1, 0),
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              child: SizedBox(
                width: sidebarWidth,
                child: Material(
                  elevation: 4,
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
                              onPressed: _isSigningOut ? null : _signOut,
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
