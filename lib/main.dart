import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api/api_client.dart';
import 'api/api_exception.dart';
import 'api/app_config.dart';
import 'auth/auth_screen.dart';
import 'onboarding/activation_screen.dart';
import 'models/pos_group.dart';
import 'models/pos_item.dart';
import 'models/pos_modifier_group.dart';
import 'register/pos_register.dart';
import 'register/syncing_screen.dart';
import 'services/delivery_print_job_poller.dart';
import 'services/items_service.dart';
import 'services/payment_mode_service.dart';
import 'services/print_job_service.dart';
import 'services/sunmi_printer_service.dart';
import 'services/sync_service.dart';
import 'settings/settings_screen.dart';
import 'onboarding/splash_screen.dart';
import 'services/label_printer_service.dart';
import 'services/printer_config_service.dart';
import 'services/receipt_service.dart';

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
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE67E22)),
        useMaterial3: true,
        fontFamily: 'Roboto',
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 48),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
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
  final SecureStore _secureStore = const SecureStore();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startDecisionFuture = _evaluateStart();
    _startStatusCheckTimer();
    SyncService.instance.start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _statusCheckTimer?.cancel();
    SyncService.instance.dispose();
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
    final hasActivationDetails =
        activationEmail != null &&
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
    try {
      await ApiClient().postJson('/pos/api/v1/me', authToken: token);
      return true;
    } on ApiException catch (e) {
      // Token explicitly rejected — force reactivation.
      if (e.statusCode == 401 || e.statusCode == 403) return false;
      // Server/network error — assume still valid to avoid mid-shift lockout.
      return true;
    } catch (_) {
      return true;
    }
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
      _startDecisionFuture = Future.value(
        const _StartDecision(showActivation: false),
      );
    });
  }

  void _handleAuthenticated() {
    setState(() {
      _isAuthenticated = true;
    });
    _verifyStatusAndHandleReactivation();
  }

  Future<void> _handleSignOut() async {
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
  int _selectedIndex = 0;
  final ApiClient _apiClient = ApiClient();
  final SecureStore _secureStore = const SecureStore();
  final TextInputFormatter _currencyFormatter = _CurrencyTextInputFormatter();
  ApiStatus? _syncStatus;
  bool _isSyncLoading = false;
  bool _isSigningOut = false;
  String? _warehouseCode;
  String? _activationEmail;


  // Initial sync gate shown right after login.
  bool _showInitialSync = true;
  List<PosItem>? _preloadedItems;
  List<PosGroup>? _preloadedGroups;
  List<PosModifierGroup>? _preloadedModifiers;
  List<PaymentMode>? _preloadedPaymentModes;

  bool _shiftOpen = false;
  String? _shiftId;
  DateTime? _shiftOpenedAt;
  DateTime? _shiftClosedAt;

  // Receipt list state
  List<ReceiptSummary> _receipts = [];
  bool _isLoadingReceipts = false;
  bool _isLoadingMoreReceipts = false;
  String? _receiptsError;
  int _receiptsPage = 1;
  bool _hasMoreReceipts = false;

  // Receipt detail state
  ReceiptSummary? _selectedReceipt;
  ReceiptDetail? _selectedReceiptDetail;
  bool _isLoadingDetail = false;
  bool _isSendingToKitchen = false;
  final _labelPrinter = createLabelPrinterService();

  // Refund / cancel state
  bool _isRefundMode = false;
  bool _isProcessingRefund = false;
  final Map<int, int> _refundQtys = {};
  final TextEditingController _receiptSearchController =
      TextEditingController();
  Timer? _searchDebounce;
  final Map<String, String> _receiptStatuses = {};
  final Map<String, String> _receiptReasons = {};
  String? _pendingRefundReason;

  // Delivery (GrabFood/foodpanda/ShopeeFood) print job polling.
  final _deliveryPoller = DeliveryPrintJobPoller();

  static const List<_SidebarDestination> _destinations = [
    _SidebarDestination(
      label: 'Register',
      icon: Icons.point_of_sale,
      description:
          'We are building the Register experience. '
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
    _refreshSyncStatus();
    _loadWarehouseDetails();
    _loadShiftState();
    _receiptSearchController.addListener(_onReceiptSearchChanged);
    _deliveryPoller.start(
      tokenProvider: () => _secureStore.readToken(),
      onFailure: _handleDeliveryPrintFailure,
      onKitchenWarning: _handleDeliveryKitchenWarning,
    );
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _receiptSearchController.dispose();
    _deliveryPoller.dispose();
    super.dispose();
  }

  void _handleDeliveryPrintFailure(PrintJob job, String error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showMaterialBanner(
      MaterialBanner(
        content: Text(
          '${job.sourceLabel} order ${job.receiptNumber} failed to print. '
          'Please print manually from Transactions.',
        ),
        leading: const Icon(Icons.error_outline, color: Colors.red),
        actions: [
          TextButton(
            onPressed: () =>
                ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
            child: const Text('Dismiss'),
          ),
        ],
      ),
    );
  }

  void _handleDeliveryKitchenWarning(PrintJob job, String error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Kitchen ticket failed for ${job.receiptNumber} — send manually '
          'from Transactions.',
        ),
      ),
    );
  }

  void _onReceiptSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      if (_selectedIndex == 1) _loadReceipts(reset: true);
    });
  }

  void _selectDestination(int index) {
    if (index == 3 && !_shiftOpen) return;
    setState(() {
      _selectedIndex = index;
      _isSidebarVisible = false;
    });
    if (index == 1) _loadReceipts();
  }

  Future<void> _loadWarehouseDetails() async {
    final results = await Future.wait([
      _secureStore.readWarehouseCode(),
      _secureStore.readActivationEmail(),
    ]);
    if (!mounted) return;
    setState(() {
      _warehouseCode = results[0];
      _activationEmail = results[1];

    });
  }

  Future<void> _prefetchItems() async {
    final token = await _secureStore.readToken();
    if (token == null || token.isEmpty) return;
    final svc = ItemsService();
    final items = await svc.fetchItems(token);
    final groups = await svc.fetchGroups(token);
    final modifiers = await svc.fetchModifierGroups(token);
    if (!mounted) return;
    setState(() {
      _preloadedItems = items;
      _preloadedGroups = groups;
      _preloadedModifiers = modifiers;
    });
  }

  Future<void> _prefetchPaymentModes() async {
    final token = await _secureStore.readToken() ?? '';
    final modes = await PaymentModeService().fetchPaymentModes(token);
    if (!mounted) return;
    setState(() => _preloadedPaymentModes = modes);
  }

  // Thin wrappers with error suppression for use as SyncTask callbacks.
  // Errors are caught here so the task shows a checkmark even on transient
  // failures — the register will still attempt to load from cache or API on
  // its own, and the user can retry manually from the register.
  Future<void> _prefetchItemsSafe() async {
    try {
      await _prefetchItems();
    } catch (_) {}
  }

  Future<void> _prefetchPaymentModesSafe() async {
    try {
      await _prefetchPaymentModes();
    } catch (_) {}
  }

  Future<void> _loadShiftState() async {
    // Apply cached state immediately so the UI doesn't flash closed on startup.
    final prefs = await SharedPreferences.getInstance();
    final cachedOpen = prefs.getBool('shift_is_open') ?? false;
    final cachedId = prefs.getString('shift_id');
    final cachedOpenedAt = prefs.getString('shift_opened_at');
    if (mounted) {
      setState(() {
        _shiftOpen = cachedOpen;
        _shiftId = cachedId;
        _shiftOpenedAt =
            cachedOpenedAt != null ? DateTime.tryParse(cachedOpenedAt) : null;
      });
    }

    // Whether this device already believes it has an open shift.
    // Used below to guard against a multi-device bug: all devices share the
    // same auth token, so /shifts/current reflects the account-wide "current"
    // shift. If another device closes its shift, /shifts/current returns null
    // for everyone — which must NOT be mistaken for our own shift being closed.
    final hadLocalShift = cachedOpen && cachedId != null;

    // Verify with API and reconcile.
    try {
      final token = await _secureStore.readToken();
      final response = await _apiClient.getJson(
        '/pos/api/v1/shifts/current',
        authToken: token,
      );
      final rawData = response.data['data'];
      final data = rawData as Map<String, dynamic>?;

      if (data == null || data['id'] == null) {
        // Server has no active shift. Only clear our state if we didn't
        // already have a shift open — another device may have just closed its
        // own shift, which should not affect ours.
        if (!hadLocalShift) {
          await prefs.setBool('shift_is_open', false);
          await prefs.remove('shift_id');
          await prefs.remove('shift_opened_at');
          if (mounted) {
            setState(() {
              _shiftOpen = false;
              _shiftId = null;
              _shiftOpenedAt = null;
            });
          }
        }
      } else {
        final shiftId = data['id']?.toString();
        final openedAtRaw = data['opened_at']?.toString();
        final openedAt =
            openedAtRaw != null ? DateTime.tryParse(openedAtRaw) : null;

        // If we already have a locally-cached shift that differs from what the
        // server returned, the server shift belongs to another device on the
        // same account. Keep our own local state and ignore the foreign shift.
        if (hadLocalShift && shiftId != cachedId) {
          return;
        }

        await prefs.setBool('shift_is_open', true);
        if (shiftId != null) await prefs.setString('shift_id', shiftId);
        if (openedAtRaw != null) {
          await prefs.setString('shift_opened_at', openedAtRaw);
        }

        if (mounted) {
          setState(() {
            _shiftOpen = true;
            _shiftId = shiftId;
            _shiftOpenedAt = openedAt ?? _shiftOpenedAt;
          });
        }
      }
    } on ApiException catch (e) {
      if (e.statusCode == 404) {
        // Server has no active shift. Same guard as above — don't clear our
        // local shift state if we believed one was open on this device.
        if (!hadLocalShift) {
          await prefs.setBool('shift_is_open', false);
          await prefs.remove('shift_id');
          await prefs.remove('shift_opened_at');
          if (mounted) {
            setState(() {
              _shiftOpen = false;
              _shiftId = null;
              _shiftOpenedAt = null;
            });
          }
        }
      }
      // Other errors (500, network) → keep cached state to avoid mid-shift lockout.
    } catch (_) {
      // Network failure → keep cached state.
    }
  }

  void _openShift() {
    SunmiPrinterService().openCashDrawer();
    _showOpeningAmountDialog();
  }

  Future<void> _closeShift(double actualCash) async {
    final token = await _secureStore.readToken();

    // If _shiftId is missing, try to recover it from the server.
    String? shiftId = _shiftId;
    if (shiftId == null) {
      final response = await _apiClient.getJson(
        '/pos/api/v1/shifts/current',
        authToken: token,
      );
      final shiftData = (response.data['data'] as Map<String, dynamic>?) ?? response.data;
      shiftId = shiftData['id']?.toString();
    }

    if (shiftId == null) {
      throw ApiException('No active shift found.', statusCode: 404);
    }

    await _apiClient.postJson(
      '/pos/api/v1/shifts/$shiftId/close',
      body: {'actual_cash': actualCash},
      authToken: token,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('shift_is_open', false);
    await prefs.remove('shift_id');
    await prefs.remove('shift_opened_at');
    if (!mounted) return;
    setState(() {
      _shiftOpen = false;
      _shiftId = null;
      _shiftOpenedAt = null;
      _shiftClosedAt = DateTime.now();
      _selectedIndex = 0;
    });
  }

  // ── Receipt loading ───────────────────────────────────────────────────────

  Future<void> _loadReceipts({bool reset = false}) async {
    if (_isLoadingReceipts || _isLoadingMoreReceipts) return;
    if (reset) {
      setState(() {
        _receipts = [];
        _receiptsPage = 1;
        _hasMoreReceipts = false;
        _receiptsError = null;
      });
    }
    setState(() => _isLoadingReceipts = true);
    try {
      final token = await _secureStore.readToken() ?? '';
      final page = await ReceiptService().fetchReceipts(
        token,
        page: _receiptsPage,
        limit: 20,
        q: _receiptSearchController.text.trim().isEmpty
            ? null
            : _receiptSearchController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _receipts = [..._receipts, ...page.items];
        _receiptsPage = page.page + 1;
        _hasMoreReceipts = page.page < page.pageCount;
        _isLoadingReceipts = false;
        _receiptsError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingReceipts = false;
        _receiptsError = 'Failed to load receipts.';
      });
    }
  }

  Future<void> _loadMoreReceipts() async {
    if (_isLoadingReceipts || _isLoadingMoreReceipts || !_hasMoreReceipts) {
      return;
    }
    setState(() => _isLoadingMoreReceipts = true);
    try {
      final token = await _secureStore.readToken() ?? '';
      final page = await ReceiptService().fetchReceipts(
        token,
        page: _receiptsPage,
        limit: 20,
        q: _receiptSearchController.text.trim().isEmpty
            ? null
            : _receiptSearchController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _receipts = [..._receipts, ...page.items];
        _receiptsPage = page.page + 1;
        _hasMoreReceipts = page.page < page.pageCount;
        _isLoadingMoreReceipts = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingMoreReceipts = false);
    }
  }

  Future<void> _loadReceiptDetail(String receiptNumber) async {
    try {
      final token = await _secureStore.readToken() ?? '';
      final detail =
          await ReceiptService().fetchReceiptDetail(token, receiptNumber);
      if (!mounted) return;
      setState(() {
        _selectedReceiptDetail = detail;
        _isLoadingDetail = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingDetail = false);
    }
  }

  Future<void> _sendToKitchen(
      ReceiptSummary receipt, ReceiptDetail detail) async {
    final kitchenMac = await PrinterConfigService().getKitchenPrinterMac();
    if (kitchenMac == null || kitchenMac.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No kitchen printer configured.')),
      );
      return;
    }
    final now = receipt.receiptDate;
    final dt =
        '${now.year}.${now.month.toString().padLeft(2, '0')}.${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final totalItems = detail.lineItems.length;
    try {
      await _labelPrinter.connect();
      for (var i = 0; i < detail.lineItems.length; i++) {
        final item = detail.lineItems[i];
        final job = LabelPrintJob(
          queueNumber: detail.queueNumber ?? '${receipt.id % 1000}',
          itemName: item.itemName,
          category: '',
          modifier: item.modifierNames.join('\n'),
          dateTime: dt,
          itemIndex: i + 1,
          totalItems: totalItems,
        );
        for (var copy = 0; copy < item.quantity.round(); copy++) {
          await _labelPrinter.printLabel(job);
        }
      }
    } catch (e) {
      debugPrint('Kitchen print failed: $e');
    } finally {
      await _labelPrinter.disconnect();
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sent to kitchen.')),
    );
  }

  Future<void> _processCancel(ReceiptSummary receipt, String reason) async {
    final rn = receipt.receiptNumber;
    try {
      final token = await _secureStore.readToken() ?? '';
      await ReceiptService().cancelReceipt(token, receipt.id);
      if (!mounted) return;
      setState(() {
        _receiptStatuses[rn] = 'cancelled';
        _receiptReasons[rn] = reason;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to cancel: ${e.message}')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to cancel transaction.')),
      );
    }
  }

  Future<void> _processRefund() async {
    final receipt = _selectedReceipt!;
    final detail = _selectedReceiptDetail!;
    final rn = receipt.receiptNumber;

    final refundItems = _refundQtys.entries
        .where((e) => e.value > 0 && e.key < detail.lineItems.length)
        .map((e) => (
              lineItemId: detail.lineItems[e.key].id,
              quantity: e.value,
            ))
        .toList();

    final refundTotal = _refundQtys.entries.fold<double>(0, (sum, e) {
      if (e.key >= detail.lineItems.length) return sum;
      final item = detail.lineItems[e.key];
      final qty = item.quantity;
      return sum + (qty > 0 ? e.value * item.totalMoney / qty : 0);
    });

    setState(() => _isProcessingRefund = true);
    try {
      final token = await _secureStore.readToken() ?? '';
      await ReceiptService().refundReceipt(token, detail.id, refundTotal, refundItems);
      if (!mounted) return;
      SunmiPrinterService().openCashDrawer();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Refund of RM${refundTotal.toStringAsFixed(2)} processed.'),
        ),
      );
      setState(() {
        _receiptStatuses[rn] = 'refunded';
        if (_pendingRefundReason != null) {
          _receiptReasons[rn] = _pendingRefundReason!;
        }
        _isRefundMode = false;
        _isProcessingRefund = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to process refund: ${e.message}')),
      );
      setState(() => _isProcessingRefund = false);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to process refund.')),
      );
      setState(() => _isProcessingRefund = false);
    }
  }

  /// Groups `_receipts` by date for the list view.
  List<(String, List<ReceiptSummary>)> _groupedReceipts() {
    final map = <String, List<ReceiptSummary>>{};
    for (final r in _receipts) {
      map.putIfAbsent(r.dateGroup, () => []).add(r);
    }
    return map.entries.map((e) => (e.key, e.value)).toList();
  }

  // ── Shift ─────────────────────────────────────────────────────────────────

  Future<void> _closeShiftWithFeedback(
      BuildContext context, double actualCash) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _closeShift(actualCash);
    } on ApiException catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to close shift: ${e.message}')),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Failed to close shift.')),
      );
    }
  }

  void _showOpeningAmountDialog() {
    final amountCtrl = TextEditingController(text: '0.00');
    bool isSubmitting = false;
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 40,
            vertical: 60,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          backgroundColor: Colors.white,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 480,
              maxHeight: MediaQuery.of(ctx).size.height * 0.6,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      bottom: BorderSide(color: Color(0xFFE0E0E0)),
                    ),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(12),
                    ),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                      Expanded(
                        child: Center(
                          child: Text(
                            _shiftClosedAt != null
                                ? 'Closed since ${_formatOpenedSince(_shiftClosedAt!)}'
                                : 'Open Shift',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: ElevatedButton(
                          onPressed: isSubmitting
                              ? null
                              : () async {
                                  final amount =
                                      double.tryParse(
                                        amountCtrl.text.replaceAll(',', ''),
                                      ) ??
                                      0.0;
                                  final messenger =
                                      ScaffoldMessenger.of(context);
                                  setDialog(() => isSubmitting = true);
                                  try {
                                    final token =
                                        await _secureStore.readToken();
                                    final res = await _apiClient.postJson(
                                      '/pos/api/v1/shifts/open',
                                      body: {'opening_float': amount},
                                      authToken: token,
                                    );
                                    final resData = (res.data['data'] as Map<String, dynamic>?) ?? res.data;
                                    final shiftId =
                                        resData['id']?.toString();
                                    final prefs =
                                        await SharedPreferences.getInstance();
                                    await prefs.setBool('shift_is_open', true);
                                    if (shiftId != null) {
                                      await prefs.setString(
                                          'shift_id', shiftId);
                                    }
                                    await prefs.setString(
                                      'shift_opened_at',
                                      DateTime.now().toIso8601String(),
                                    );
                                    if (!mounted) return;
                                    Navigator.pop(ctx);
                                    setState(() {
                                      _shiftOpen = true;
                                      _shiftId = shiftId;
                                      _shiftOpenedAt = DateTime.now();
                                    });
                                  } on ApiException catch (e) {
                                    if (!mounted) return;
                                    setDialog(() => isSubmitting = false);
                                    messenger.showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Failed to open shift: ${e.message}',
                                        ),
                                      ),
                                    );
                                  } catch (_) {
                                    if (!mounted) return;
                                    setDialog(() => isSubmitting = false);
                                    messenger.showSnackBar(
                                      const SnackBar(
                                        content: Text('Failed to open shift.'),
                                      ),
                                    );
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE67E22),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                          ),
                          child: const Text(
                            'CONFIRM',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Amount input
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Opening Amount',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF424242),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: amountCtrl,
                        autofocus: true,
                        keyboardType: TextInputType.number,
                        inputFormatters: [_currencyFormatter],
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 52,
                          fontWeight: FontWeight.w300,
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onChanged: (_) => setDialog(() {}),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatOpenedAt(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '$h:$m $ampm, ${weekdays[dt.weekday - 1]} ${months[dt.month - 1]} ${dt.day} ${dt.year}';
  }

  String _formatOpenedSince(DateTime dt) {
    final h = (dt.hour % 12 == 0 ? 12 : dt.hour % 12).toString().padLeft(
      2,
      '0',
    );
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${weekdays[dt.weekday - 1]} $h:$m $ampm, ${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  void _showClosingAmountDialog() {
    SunmiPrinterService().openCashDrawer();
    final amountCtrl = TextEditingController(text: '0.00');
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 40,
            vertical: 60,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          backgroundColor: Colors.white,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 480,
              maxHeight: MediaQuery.of(ctx).size.height * 0.6,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      bottom: BorderSide(color: Color(0xFFE0E0E0)),
                    ),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(12),
                    ),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                      Expanded(
                        child: Center(
                          child: Text(
                            _shiftOpenedAt != null
                                ? 'Opened since ${_formatOpenedSince(_shiftOpenedAt!)}'
                                : 'Close Shift',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: ElevatedButton(
                          onPressed: () {
                            final amount =
                                double.tryParse(
                                  amountCtrl.text.replaceAll(',', ''),
                                ) ??
                                0.0;
                            Navigator.pop(ctx);
                            _showAmountConfirmationDialog(amount);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE67E22),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                          ),
                          child: const Text(
                            'CONFIRM',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Amount input
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Text(
                        'Closing Amount',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF424242),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: amountCtrl,
                        autofocus: true,
                        keyboardType: TextInputType.number,
                        inputFormatters: [_currencyFormatter],
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 52,
                          fontWeight: FontWeight.w300,
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onChanged: (_) => setDialog(() {}),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showAmountConfirmationDialog(double amount) {
    bool isSubmitting = false;
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        title: const Text(
          'Amount Confirmation',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
          textAlign: TextAlign.center,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure the amount is ${amount.toStringAsFixed(2)}?'),
            const SizedBox(height: 12),
            const Text(
              'Note: Please check if you have any open orders.\n'
              'If you do have open orders, we recommend you close them',
              style: TextStyle(fontSize: 13, color: Color(0xFF757575)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
            child: const Text(
              'CANCEL',
              style: TextStyle(
                color: Color(0xFF757575),
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: isSubmitting
                ? null
                : () async {
                    setDialog(() => isSubmitting = true);
                    await _closeShiftWithFeedback(ctx, amount);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE67E22),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'CONTINUE',
              style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.5),
            ),
          ),
        ],
      ),
    ),
  );
  }

  Widget _buildCloseShiftContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildPageAppBar('Close Shift'),
        Expanded(
          child: Container(
            color: const Color(0xFFF5F6FA),
            child: Center(
              child: _shiftOpen
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          "Yes, we're",
                          style: TextStyle(
                            fontSize: 26,
                            color: Color(0xFF757575),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'OPEN',
                          style: TextStyle(
                            fontSize: 64,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF2D2D2D),
                            letterSpacing: -1,
                          ),
                        ),
                        if (_shiftOpenedAt != null) ...[
                          const SizedBox(height: 48),
                          const Text(
                            'OPENED AT',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 2,
                              color: Color(0xFF9E9E9E),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            width: 180,
                            height: 1,
                            color: const Color(0xFFE0E0E0),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _formatOpenedAt(_shiftOpenedAt!),
                            style: const TextStyle(
                              fontSize: 15,
                              color: Color(0xFF424242),
                            ),
                          ),
                        ],
                        const SizedBox(height: 32),
                        ElevatedButton(
                          onPressed: _showClosingAmountDialog,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE67E22),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 32,
                              vertical: 14,
                            ),
                          ),
                          child: const Text(
                            'Close Shift',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.lock_clock,
                          size: 80,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'No Open Shift',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF2D2D2D),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Open a shift to start selling',
                          style: TextStyle(color: Color(0xFF9E9E9E)),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ],
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

  Widget _buildPageAppBar(String title) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE0E0E0))),
      ),
      child: Row(
        children: [
          SizedBox(
            height: 48,
            width: 48,
            child: IgnorePointer(
              ignoring: _isSidebarVisible,
              child: Opacity(
                opacity: _isSidebarVisible ? 0 : 1,
                child: IconButton(
                  tooltip: 'Show sidebar',
                  icon: const Icon(Icons.menu),
                  color: const Color(0xFFE67E22),
                  onPressed: _toggleSidebar,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionsContent() {
    if (_isRefundMode && _selectedReceipt != null && _selectedReceiptDetail != null) {
      return _buildRefundPanel();
    }

    final isSmall = MediaQuery.of(context).size.width < 700;

    if (isSmall) {
      if (_selectedReceipt != null) {
        return _buildReceiptDetail();
      }
      return _buildReceiptsList();
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 440, child: _buildReceiptsList()),
        Container(width: 1, color: const Color(0xFFE0E0E0)),
        Expanded(child: _buildReceiptDetail()),
      ],
    );
  }

  Widget _buildReceiptsList() {
    final groups = _groupedReceipts();
    final totalItems = groups.fold<int>(0, (s, g) => s + 1 + g.$2.length);
    // +1 for load-more row when applicable
    final itemCount = totalItems + (_hasMoreReceipts ? 1 : 0);

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Color(0xFFE0E0E0))),
          ),
          child: Row(
            children: [
              SizedBox(
                height: 48,
                width: 48,
                child: IgnorePointer(
                  ignoring: _isSidebarVisible,
                  child: Opacity(
                    opacity: _isSidebarVisible ? 0 : 1,
                    child: IconButton(
                      icon: const Icon(Icons.menu),
                      color: const Color(0xFFE67E22),
                      onPressed: _toggleSidebar,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Receipts',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        // Search
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _receiptSearchController,
            decoration: InputDecoration(
              hintText: 'Search collection number',
              prefixIcon: const Icon(Icons.search, size: 20),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
              ),
              filled: true,
              fillColor: const Color(0xFFF5F5F5),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
        // Body
        Expanded(
          child: _isLoadingReceipts && _receipts.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _receiptsError != null && _receipts.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_receiptsError!,
                              style: const TextStyle(color: Color(0xFF9E9E9E))),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: () => _loadReceipts(reset: true),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    )
                  : groups.isEmpty
                      ? const Center(
                          child: Text('No receipts found.',
                              style: TextStyle(color: Color(0xFF9E9E9E))),
                        )
                      : RefreshIndicator(
                          onRefresh: () => _loadReceipts(reset: true),
                          child: ListView.builder(
                          itemCount: itemCount,
                          itemBuilder: (context, index) {
                            // Load-more row at the very end
                            if (index == totalItems) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                child: Center(
                                  child: _isLoadingMoreReceipts
                                      ? const CircularProgressIndicator()
                                      : TextButton(
                                          onPressed: _loadMoreReceipts,
                                          child: const Text('Load more'),
                                        ),
                                ),
                              );
                            }
                            int cursor = 0;
                            for (final group in groups) {
                              if (index == cursor) {
                                return Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                                  child: Text(
                                    group.$1,
                                    style: const TextStyle(
                                      color: Color(0xFFE67E22),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                );
                              }
                              cursor++;
                              for (final receipt in group.$2) {
                                if (index == cursor) {
                                  final rn = receipt.receiptNumber;
                                  final isSelected =
                                      _selectedReceipt?.receiptNumber == rn;
                                  return Column(
                                    children: [
                                      InkWell(
                                        onTap: () {
                                          setState(() {
                                            _selectedReceipt = receipt;
                                            _selectedReceiptDetail = null;
                                            _isLoadingDetail = true;
                                            _isRefundMode = false;
                                          });
                                          _loadReceiptDetail(rn);
                                        },
                                        child: Container(
                                          color: isSelected
                                              ? const Color(0xFFF0F4FF)
                                              : Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 12,
                                          ),
                                          child: Row(
                                            children: [
                                              Container(
                                                width: 40,
                                                height: 40,
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFF5F5F5),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: Icon(
                                                  receipt.paymentType
                                                              .toUpperCase() ==
                                                          'CASH'
                                                      ? Icons.payments
                                                      : Icons.credit_card,
                                                  size: 20,
                                                  color: const Color(0xFF757575),
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        Text(
                                                          receipt.formattedTotal,
                                                          style: const TextStyle(
                                                            fontWeight:
                                                                FontWeight.w600,
                                                          ),
                                                        ),
                                                        if (receipt.sourceLabel.isNotEmpty &&
                                                            receipt.source.toUpperCase() != 'POS') ...[
                                                          const SizedBox(width: 8),
                                                          _buildSourceBadge(
                                                              receipt.sourceLabel),
                                                        ],
                                                      ],
                                                    ),
                                                    Text(
                                                      receipt.formattedTime,
                                                      style: const TextStyle(
                                                        fontSize: 13,
                                                        color: Color(0xFF9E9E9E),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.end,
                                                children: [
                                                  Text(
                                                    '#${receipt.queueNumber ?? ''}',
                                                    style: const TextStyle(
                                                      fontSize: 13,
                                                      color: Color(0xFF9E9E9E),
                                                    ),
                                                  ),
                                                  if (_receiptStatuses[rn] !=
                                                      null) ...[
                                                    const SizedBox(height: 4),
                                                    Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                        horizontal: 8,
                                                        vertical: 2,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: _receiptStatuses[
                                                                    rn] ==
                                                                'cancelled'
                                                            ? const Color(
                                                                0xFFFFEBEE)
                                                            : const Color(
                                                                0xFFE8F5E9),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(10),
                                                      ),
                                                      child: Text(
                                                        _receiptStatuses[rn] ==
                                                                'cancelled'
                                                            ? 'Cancelled'
                                                            : 'Refunded',
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color: _receiptStatuses[
                                                                      rn] ==
                                                                  'cancelled'
                                                              ? const Color(
                                                                  0xFFD32F2F)
                                                              : const Color(
                                                                  0xFF388E3C),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const Divider(
                                          height: 1, indent: 68, endIndent: 0),
                                    ],
                                  );
                                }
                                cursor++;
                              }
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                        ),
        ),
      ],
    );
  }

  static const Map<String, Color> _sourceBadgeColors = {
    'GrabFood': Color(0xFF00B14F),
    'foodpanda': Color(0xFFD70F64),
    'ShopeeFood': Color(0xFFEE4D2D),
  };

  Widget _buildSourceBadge(String sourceLabel) {
    final color = _sourceBadgeColors[sourceLabel] ?? const Color(0xFF757575);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        sourceLabel,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _buildReceiptDetail() {
    final receipt = _selectedReceipt;
    if (receipt == null) {
      return Container(
        color: const Color(0xFFF5F6FA),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.receipt_long, size: 64, color: Colors.grey.shade300),
              const SizedBox(height: 16),
              const Text(
                'Select a receipt to view details',
                style: TextStyle(color: Color(0xFF9E9E9E)),
              ),
            ],
          ),
        ),
      );
    }

    final rn = receipt.receiptNumber;
    final detail = _selectedReceiptDetail;
    final statusKey = _receiptStatuses[rn];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // App bar
        Container(
          height: 68,
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Color(0xFFE0E0E0))),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Color(0xFF212121)),
                onPressed: () => setState(() => _selectedReceipt = null),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        '#${receipt.queueNumber ?? ''}',
                        style: const TextStyle(
                          color: Color(0xFF212121),
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (receipt.sourceLabel.isNotEmpty &&
                        receipt.source.toUpperCase() != 'POS') ...[
                      const SizedBox(width: 8),
                      _buildSourceBadge(receipt.sourceLabel),
                    ],
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Color(0xFF212121)),
                tooltip: 'More options',
                onSelected: (val) async {
                  if ((val == 'print' || val == 'print_cashback') && detail != null) {
                    final payment = detail.payments.isNotEmpty
                        ? detail.payments.first
                        : null;
                    final isFdOrder = receipt.source.isNotEmpty &&
                        receipt.source.toUpperCase() != 'POS';
                    SunmiPrinterService().printReceipt(
                      PrintReceiptData(
                        receiptId: rn,
                        queueNumber: detail.queueNumber,
                        collectionLabel: isFdOrder
                            ? receipt.shortOrderNumber
                            : null,
                        date: receipt.shortDatetime.split(' ').first,
                        time: receipt.formattedTime,
                        paymentMethod: receipt.paymentMethod,
                        cashbackQrUrl: val == 'print_cashback' ? detail.cashbackQrUrl : null,
                        cashbackQrToken: val == 'print_cashback' ? detail.cashbackQrToken : null,
                        items: detail.lineItems
                            .map((item) => PrintItem(
                                  name: item.itemName,
                                  qty: item.quantity.round(),
                                  unitPrice: item.unitPrice,
                                  lineTotal: item.totalMoney,
                                  discount: ((item.unitPrice * item.quantity) -
                                          item.totalMoney)
                                      .clamp(0.0, double.infinity),
                                  modifiers: item.modifierNames,
                                ))
                            .toList(),
                        total: receipt.totalMoney,
                        subtotal: detail.subtotal,
                        discount: detail.totalDiscount,
                        deliveryFee: detail.deliveryFee + detail.grabfoodDeliveryFee,
                        cashReceived: payment?.moneyAmount ?? receipt.totalMoney,
                        change: payment?.cashBack ?? 0.0,
                      ),
                    );
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Printing receipt...')),
                      );
                    }
                  } else if (val == 'send_kitchen' && detail != null) {
                    setState(() => _isSendingToKitchen = true);
                    await _sendToKitchen(receipt, detail);
                    if (mounted) setState(() => _isSendingToKitchen = false);
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'print',
                    enabled: detail != null,
                    child: const Row(
                      children: [
                        Icon(Icons.print, size: 20),
                        SizedBox(width: 12),
                        Text('Print Receipt'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'print_cashback',
                    enabled: detail != null,
                    child: const Row(
                      children: [
                        Icon(Icons.qr_code, size: 20),
                        SizedBox(width: 12),
                        Text('Print Receipt with Cashback'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'send_kitchen',
                    enabled: detail != null,
                    child: Row(
                      children: [
                        _isSendingToKitchen
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.local_cafe_outlined, size: 20),
                        const SizedBox(width: 12),
                        const Text('Send to Kitchen'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // Receipt card
        Expanded(
          child: Container(
            color: const Color(0xFFF5F6FA),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x14000000),
                          blurRadius: 12,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Total amount
                        Center(
                          child: Text(
                            receipt.formattedTotal,
                            style: const TextStyle(
                              fontSize: 48,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Center(
                          child: Text(
                            'Total',
                            style: TextStyle(color: Color(0xFF9E9E9E)),
                          ),
                        ),
                        const Divider(height: 40),
                        // Employee / POS
                        Text(
                          'Employee: ${receipt.employeeName}',
                          style: const TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'POS: ${_warehouseCode ?? ''}',
                          style: const TextStyle(fontSize: 14),
                        ),
                        if (receipt.sourceLabel.isNotEmpty &&
                            receipt.source.toUpperCase() != 'POS' &&
                            receipt.queueNumber != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Queue: #${receipt.queueNumber}',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ],
                        const Divider(height: 40),
                        // Line items (or loading spinner)
                        if (_isLoadingDetail)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else if (detail != null) ...[
                          for (final item in detail.lineItems) ...[
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    item.itemName,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w500),
                                  ),
                                ),
                                Text(
                                    'RM${item.totalMoney.toStringAsFixed(2)}'),
                              ],
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.only(top: 2, bottom: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${item.quantity.toStringAsFixed(0)} × RM${item.unitPrice.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                        fontSize: 13,
                                        color: Color(0xFF9E9E9E)),
                                  ),
                                  for (final mod in item.modifierNames)
                                    Text(
                                      mod,
                                      style: const TextStyle(
                                          fontSize: 13,
                                          color: Color(0xFF9E9E9E)),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ],
                        const Divider(height: 24),
                        // Subtotal / discount / delivery fee breakdown
                        if (detail != null) ...[
                          Row(
                            children: [
                              const Expanded(child: Text('Subtotal')),
                              Text('RM${detail.subtotal.toStringAsFixed(2)}'),
                            ],
                          ),
                          if (detail.totalDiscount > 0) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Expanded(
                                  child: Text('Discount',
                                      style: TextStyle(color: Color(0xFF388E3C))),
                                ),
                                Text(
                                  '-RM${detail.totalDiscount.toStringAsFixed(2)}',
                                  style: const TextStyle(color: Color(0xFF388E3C)),
                                ),
                              ],
                            ),
                          ],
                          if (detail.grabfoodDeliveryFee > 0) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Expanded(child: Text('Delivery Fee')),
                                Text('RM${detail.grabfoodDeliveryFee.toStringAsFixed(2)}'),
                              ],
                            ),
                          ],
                          if (receipt.sourceLabel.isNotEmpty &&
                              receipt.source.toUpperCase() != 'POS')
                            const Divider(height: 24)
                          else
                            const SizedBox(height: 8),
                        ],
                        // Total row
                        Row(
                          children: [
                            const Expanded(
                              child: Text('Total',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold)),
                            ),
                            Text(
                              'RM${receipt.totalMoney.toStringAsFixed(2)}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Payment rows from detail
                        if (detail != null)
                          for (final p in detail.payments) ...[
                            Row(
                              children: [
                                Expanded(child: Text(p.paymentName)),
                                Text('RM${p.moneyAmount.toStringAsFixed(2)}'),
                              ],
                            ),
                            if (p.cashBack > 0) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Expanded(
                                      child: Text('Change',
                                          style: TextStyle(
                                              color: Color(0xFF9E9E9E)))),
                                  Text(
                                    'RM${p.cashBack.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                        color: Color(0xFF9E9E9E)),
                                  ),
                                ],
                              ),
                            ],
                          ]
                        else
                          Row(
                            children: [
                              Expanded(child: Text(receipt.paymentMethod)),
                              Text(
                                  'RM${receipt.totalMoney.toStringAsFixed(2)}'),
                            ],
                          ),
                        const SizedBox(height: 20),
                        // Status badge or action buttons
                        if (statusKey != null)
                          Center(
                            child: Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: statusKey == 'cancelled'
                                        ? const Color(0xFFFFEBEE)
                                        : const Color(0xFFE8F5E9),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    statusKey == 'cancelled'
                                        ? 'Cancelled'
                                        : 'Refunded',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                      color: statusKey == 'cancelled'
                                          ? const Color(0xFFD32F2F)
                                          : const Color(0xFF388E3C),
                                    ),
                                  ),
                                ),
                                if (_receiptReasons[rn] != null) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    'Reason: ${_receiptReasons[rn]}',
                                    style: const TextStyle(
                                        fontSize: 13,
                                        color: Color(0xFF757575)),
                                  ),
                                ],
                              ],
                            ),
                          )
                        else if (receipt.sourceLabel.isEmpty ||
                            receipt.source.toUpperCase() == 'POS')
                          Builder(builder: (context) {
                            final isSmall =
                                MediaQuery.of(context).size.width < 700;
                            final refundBtn = OutlinedButton(
                              onPressed: detail == null
                                  ? null
                                  : () =>
                                      _showReasonModal(receipt, type: 'refund'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 14),
                                side: const BorderSide(
                                    color: Color(0xFFE67E22)),
                                foregroundColor: const Color(0xFFE67E22),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6)),
                              ),
                              child: const Text('Issue Refund',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w600)),
                            );
                            final cancelBtn = ElevatedButton(
                              onPressed: () =>
                                  _showReasonModal(receipt, type: 'cancel'),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 14),
                                backgroundColor: const Color(0xFFE67E22),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6)),
                              ),
                              child: const Text('Cancel Transaction',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w600)),
                            );
                            if (isSmall) {
                              return Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.stretch,
                                children: [
                                  refundBtn,
                                  const SizedBox(height: 10),
                                  cancelBtn,
                                ],
                              );
                            }
                            return Row(children: [
                              Expanded(child: refundBtn),
                              const SizedBox(width: 12),
                              Expanded(child: cancelBtn),
                            ]);
                          }),
                        const Divider(height: 40),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                receipt.shortDatetime,
                                style: const TextStyle(
                                    color: Color(0xFF9E9E9E), fontSize: 13),
                              ),
                            ),
                            Text(
                              rn,
                              style: const TextStyle(
                                  color: Color(0xFF9E9E9E), fontSize: 13),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showReasonModal(ReceiptSummary receipt, {required String type}) {
    String? selectedReason;
    const reasons = [
      'Incorrect item',
      'Incorrect variants',
      'Incorrect payment type',
      'Incorrect quantity',
      'Other',
    ];
    final title = type == 'cancel'
        ? 'Reason For Cancel Transaction'
        : 'Reason For Issue Refund';

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Dialog(
          backgroundColor: Colors.white,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 40,
            vertical: 60,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640, maxHeight: 560),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                      Expanded(
                        child: Center(
                          child: Text(
                            title,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      ElevatedButton(
                        onPressed: selectedReason == null
                            ? null
                            : () {
                                Navigator.pop(ctx);
                                if (type == 'cancel') {
                                  _processCancel(receipt, selectedReason!);
                                } else {
                                  final items =
                                      _selectedReceiptDetail?.lineItems ?? [];
                                  setState(() {
                                    _pendingRefundReason = selectedReason;
                                    _isRefundMode = true;
                                    _refundQtys.clear();
                                    for (int i = 0; i < items.length; i++) {
                                      _refundQtys[i] =
                                          items[i].quantity.round();
                                    }
                                  });
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: selectedReason == null
                              ? Colors.grey.shade300
                              : const Color(0xFFE67E22),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.only(
                                topRight: Radius.circular(28)),
                          ),
                          padding:
                              const EdgeInsets.symmetric(horizontal: 28),
                        ),
                        child: const Text('CONFIRM',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1)),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(32),
                    child: GridView.count(
                      crossAxisCount: 3,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 1.8,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      children: reasons.map((reason) {
                        final selected = selectedReason == reason;
                        return GestureDetector(
                          onTap: () =>
                              setModal(() => selectedReason = reason),
                          child: Container(
                            decoration: BoxDecoration(
                              color: selected
                                  ? const Color(0xFFFFF3E0)
                                  : Colors.white,
                              border: Border.all(
                                color: selected
                                    ? const Color(0xFFE67E22)
                                    : const Color(0xFFE0E0E0),
                                width: selected ? 2 : 1,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: Text(
                                reason,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRefundPanel() {
    final receipt = _selectedReceipt!;
    final items = _selectedReceiptDetail!.lineItems;
    final rn = receipt.receiptNumber;

    final refundTotal = _refundQtys.entries.fold<double>(0, (sum, e) {
      if (e.key >= items.length) return sum;
      final item = items[e.key];
      final qty = item.quantity;
      return sum + (qty > 0 ? e.value * item.totalMoney / qty : 0);
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 68,
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Color(0xFFE0E0E0))),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Color(0xFF212121)),
                onPressed: () => setState(() => _isRefundMode = false),
              ),
              const SizedBox(width: 4),
              Text(
                'Refund $rn',
                style: const TextStyle(
                    color: Color(0xFF212121),
                    fontSize: 18,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            color: const Color(0xFFF5F6FA),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: const [
                            BoxShadow(
                                color: Color(0x14000000),
                                blurRadius: 12,
                                offset: Offset(0, 4))
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.fromLTRB(20, 20, 20, 4),
                              child: Text('Select items to refund',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15)),
                            ),
                            const Divider(height: 1),
                            for (int i = 0; i < items.length; i++) ...[
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 12),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(items[i].itemName,
                                              style: const TextStyle(
                                                  fontSize: 14)),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${items[i].quantity.toStringAsFixed(0)} × RM${items[i].unitPrice.toStringAsFixed(2)}',
                                            style: const TextStyle(
                                                color: Color(0xFF9E9E9E),
                                                fontSize: 13),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Row(children: [
                                      IconButton(
                                        icon: const Icon(Icons.remove,
                                            size: 16),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(
                                            minWidth: 32, minHeight: 32),
                                        onPressed: (_refundQtys[i] ?? 0) > 0
                                            ? () => setState(() =>
                                                _refundQtys[i] =
                                                    _refundQtys[i]! - 1)
                                            : null,
                                      ),
                                      SizedBox(
                                        width: 28,
                                        child: Text(
                                          '${_refundQtys[i] ?? 0}',
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 15),
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.add, size: 16),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(
                                            minWidth: 32, minHeight: 32),
                                        onPressed:
                                            (_refundQtys[i] ?? 0) <
                                                    items[i].quantity.round()
                                                ? () => setState(() =>
                                                    _refundQtys[i] =
                                                        _refundQtys[i]! + 1)
                                                : null,
                                      ),
                                    ]),
                                    const SizedBox(width: 8),
                                    SizedBox(
                                      width: 72,
                                      child: Text(
                                        'RM${((_refundQtys[i] ?? 0) * items[i].totalMoney / items[i].quantity).toStringAsFixed(2)}',
                                        textAlign: TextAlign.end,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w500),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (i < items.length - 1)
                                const Divider(height: 1, indent: 16),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: const [
                            BoxShadow(
                                color: Color(0x14000000),
                                blurRadius: 12,
                                offset: Offset(0, 4))
                          ],
                        ),
                        child: Row(children: [
                          const Text('Refund total',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 16)),
                          const Spacer(),
                          Text('RM${refundTotal.toStringAsFixed(2)}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 20,
                                  color: Color(0xFFE67E22))),
                        ]),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: refundTotal == 0
                                ? Colors.grey.shade300
                                : const Color(0xFFE67E22),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: refundTotal == 0 || _isProcessingRefund
                              ? null
                              : _processRefund,
                          child: const Text('PROCESS REFUND',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_showInitialSync) {
      return SyncingScreen(
        tasks: [
          SyncTask(label: 'Shift status', run: _loadShiftState),
          SyncTask(label: 'Products & categories', run: _prefetchItemsSafe),
          SyncTask(label: 'Payment methods', run: _prefetchPaymentModesSafe),
        ],
        onDone: () => setState(() => _showInitialSync = false),
      );
    }

    const sidebarWidth = 260.0;
    final destination = _destinations[_selectedIndex];

    final Widget mainContent;
    if (_selectedIndex == 0) {
      final preloaded = (_preloadedItems != null &&
              _preloadedGroups != null &&
              _preloadedModifiers != null &&
              _preloadedPaymentModes != null)
          ? PreloadedPosData(
              items: _preloadedItems!,
              groups: _preloadedGroups!,
              modifierGroups: _preloadedModifiers!,
              paymentModes: _preloadedPaymentModes!,
            )
          : null;
      mainContent = PosRegister(
        header: _buildPageAppBar(destination.label),
        shiftOpen: _shiftOpen,
        onOpenShift: _openShift,
        shiftId: _shiftId,
        preloadedData: preloaded,
      );
    } else if (_selectedIndex == 1) {
      mainContent = _buildTransactionsContent();
    } else if (_selectedIndex == 3) {
      mainContent = _buildCloseShiftContent();
    } else if (_selectedIndex == 4) {
      mainContent = SettingsScreen(
        onSignOut: _signOut,
        toggleSidebar: _toggleSidebar,
        isSidebarVisible: _isSidebarVisible,
        activationEmail: _activationEmail,
      );
    } else {
      mainContent = Column(
        children: [
          _buildPageAppBar(destination.label),
          Expanded(
            child: Center(
              child: Container(
                width: 640,
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
                      color: const Color(0xFFE67E22),
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
                      style: const TextStyle(color: Color(0xFF5F6368)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

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
                  child: Container(color: Colors.black.withOpacity(0.45)),
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
                                foregroundColor: const Color(0xFFE67E22),
                                backgroundColor: const Color(0xFFFFF3E0),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                textStyle: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              onPressed: _isSigningOut ? null : _signOut,
                              child: const Text('Log Out'),
                            ),
                            const Spacer(),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ListView(
                          padding: EdgeInsets.zero,
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
                              disabled: !_shiftOpen,
                              onTap: () => _selectDestination(3),
                            ),
                            _SidebarItem(
                              label: _destinations[4].label,
                              icon: _destinations[4].icon,
                              isSelected: _selectedIndex == 4,
                              onTap: () => _selectDestination(4),
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
      width: 640,
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
          Icon(destination.icon, size: 64, color: const Color(0xFFE67E22)),
          const SizedBox(height: 16),
          Text(
            destination.label,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Text(
            destination.description,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF5F6368)),
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
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            AppConfig.baseUrl,
            style: const TextStyle(color: Color(0xFF5F6368), fontSize: 16),
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
                child: Text(statusText, style: const TextStyle(fontSize: 14)),
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
            style: TextStyle(color: Color(0xFF5F6368)),
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
    this.disabled = false,
  });

  final String label;
  final bool isSelected;
  final bool disabled;
  final VoidCallback onTap;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final active = isSelected && !disabled;
    final textColor = disabled
        ? Colors.grey.shade400
        : active
        ? const Color(0xFFE67E22)
        : Colors.black87;

    return Material(
      color: active ? const Color(0xFFFFF3E0) : Colors.transparent,
      child: InkWell(
        onTap: disabled ? null : onTap,
        child: SizedBox(
          height: 52,
          child: Row(
            children: [
              Container(
                width: 3,
                color: active ? const Color(0xFFE67E22) : Colors.transparent,
              ),
              const SizedBox(width: 16),
              Icon(icon, color: textColor, size: 20),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: textColor,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
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

class _CurrencyTextInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      const value = '0.00';
      return const TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
    }

    final cents = int.parse(digits);
    final value = (cents / 100).toStringAsFixed(2);
    return TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }
}

