import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/bt_printer_service.dart';
import '../services/printer_config_service.dart';
import '../services/sunmi_display_service.dart';

enum _SettingTab { printers, customerDisplays, taxes, general }

enum _DeviceType { bluetooth, usb }

// ─── Printer config ───────────────────────────────────────────────────────────

class _PrinterConfig {
  _PrinterConfig({
    this.receiptPrinter = false,
    this.kitchenPrinter = false,
    this.paperWidth = PaperWidth.w58mm,
  });
  bool receiptPrinter;
  bool kitchenPrinter;
  PaperWidth paperWidth;

  String get indicator {
    if (receiptPrinter && kitchenPrinter) return 'Receipt · Kitchen';
    if (receiptPrinter) return 'Receipt';
    if (kitchenPrinter) return 'Kitchen';
    return '';
  }
}

// ─── Discovered device ────────────────────────────────────────────────────────

class _DiscoveredDevice {
  const _DiscoveredDevice({
    required this.name,
    required this.detail,
    required this.key,
    required this.type,
  });
  final String name;
  final String detail;
  // Unique key: BT MAC address or USB kernel path.
  final String key;
  final _DeviceType type;
}

// ─── Discovery channel ────────────────────────────────────────────────────────

class _Discovery {
  static const _ch = MethodChannel('kokonuts/printer_discovery');

  static Future<List<_DiscoveredDevice>> scanBluetooth() async {
    try {
      final raw = await _ch.invokeListMethod<Object>('scanBluetooth') ?? [];
      return raw.whereType<Map>().map((m) {
        final name = m['name']?.toString() ?? 'Unknown';
        final addr = m['address']?.toString() ?? '';
        final type = m['type']?.toString() ?? '';
        return _DiscoveredDevice(
          name: name,
          detail: [addr, if (type.isNotEmpty) type].join(' · '),
          key: addr.isNotEmpty ? addr : name,
          type: _DeviceType.bluetooth,
        );
      }).toList();
    } on PlatformException {
      return [];
    }
  }

  static Future<List<_DiscoveredDevice>> scanUsb() async {
    try {
      final raw = await _ch.invokeListMethod<Object>('scanUsb') ?? [];
      return raw.whereType<Map>().map((m) {
        final name = m['name']?.toString() ?? 'USB Device';
        final mfr = m['manufacturer']?.toString() ?? '';
        final devPath = m['deviceName']?.toString() ?? '';
        return _DiscoveredDevice(
          name: name,
          detail: mfr,
          key: devPath.isNotEmpty ? devPath : name,
          type: _DeviceType.usb,
        );
      }).toList();
    } on PlatformException {
      return [];
    }
  }

  static Future<void> resetUsbPermissions() async {
    try {
      await _ch.invokeMethod('resetUsbPermissions');
    } on PlatformException {
      // ignore
    }
  }
}

// ─── Settings screen ──────────────────────────────────────────────────────────

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.onSignOut,
    required this.toggleSidebar,
    required this.isSidebarVisible,
    this.activationEmail,
  });

  final Future<void> Function() onSignOut;
  final VoidCallback toggleSidebar;
  final bool isSidebarVisible;
  final String? activationEmail;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _kGreen = Color(0xFFE67E22);
  static const _kBlue = Color(0xFFE67E22);

  _SettingTab? _selectedTab;

  // ── Bluetooth ─────────────────────────────────────────────────────────────
  List<_DiscoveredDevice> _btDevices = [];
  bool _isScanningBt = false;
  bool _btScanned = false;

  // ── USB ───────────────────────────────────────────────────────────────────
  List<_DiscoveredDevice> _usbDevices = [];
  bool _isScanningUsb = false;
  bool _usbScanned = false;

  // ── Printer config per device ─────────────────────────────────────────────
  final Map<String, _PrinterConfig> _printerConfigs = {};
  String? _receiptMac;
  String? _kitchenMac;

  // ── Customer display ──────────────────────────────────────────────────────
  static const _kDisplayPrefKey = 'customer_display_enabled';
  // null = still detecting, true/false = detection complete
  bool? _hasSecondaryDisplay;
  bool _customerDisplayEnabled = false;

  // ── General ───────────────────────────────────────────────────────────────
  bool _darkModeEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadSavedConfigs();
    _initDisplayState();
  }

  Future<void> _initDisplayState() async {
    final hasDisplay = await SunmiDisplayService().hasSecondaryDisplay();
    final prefs = await SharedPreferences.getInstance();
    final savedEnabled = prefs.getBool(_kDisplayPrefKey) ?? true;
    if (!mounted) return;
    setState(() {
      _hasSecondaryDisplay = hasDisplay;
      _customerDisplayEnabled = hasDisplay && savedEnabled;
    });
  }

  Future<void> _toggleCustomerDisplay(bool enabled) async {
    setState(() => _customerDisplayEnabled = enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kDisplayPrefKey, enabled);
    await SunmiDisplayService().setEnabled(enabled);
  }

  Future<void> _loadSavedConfigs() async {
    final svc = PrinterConfigService();

    final results = await Future.wait([
      svc.getReceiptPrinterMac(),
      svc.getKitchenPrinterMac(),
      svc.getSavedDevices(bluetooth: true),
      svc.getSavedDevices(bluetooth: false),
    ]);

    final receiptMac = results[0] as String?;
    final kitchenMac = results[1] as String?;
    final savedBt = results[2] as List<Map<String, String>>;
    final savedUsb = results[3] as List<Map<String, String>>;

    // Load saved paper width for every known BT device key.
    final allKeys = {
      ...savedBt.map((d) => d['key']).whereType<String>(),
      if (receiptMac != null) receiptMac,
      if (kitchenMac != null) kitchenMac,
    };
    final widths = <String, PaperWidth>{};
    for (final key in allKeys) {
      widths[key] = await svc.getBtPaperWidth(key);
    }

    if (!mounted) return;
    setState(() {
      // Restore previously discovered devices so they appear without scanning.
      final macRe = RegExp(r'^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$');
      final btDeviceMap = <String, _DiscoveredDevice>{};
      for (final d in savedBt) {
        final key = d['key'];
        if (key == null || key.isEmpty) continue;
        btDeviceMap[key] = _DiscoveredDevice(
          name: d['name'] ?? '',
          detail: d['detail'] ?? '',
          key: key,
          type: _DeviceType.bluetooth,
        );
      }
      // Ensure assigned BT printers always have a row even if the last scan
      // missed them (printer off, BT initialising, permission hiccup, etc.).
      // Exclude the Sunmi key — it has its own static card.
      for (final mac in [receiptMac, kitchenMac]) {
        if (mac != null &&
            mac != PrinterConfigService.kSunmiKey &&
            macRe.hasMatch(mac) &&
            !btDeviceMap.containsKey(mac)) {
          btDeviceMap[mac] = _DiscoveredDevice(
            name: mac,
            detail: '',
            key: mac,
            type: _DeviceType.bluetooth,
          );
        }
      }
      _btDevices = btDeviceMap.values.toList();
      _receiptMac = receiptMac;
      _kitchenMac = kitchenMac;

      final usbDeviceMap = <String, _DiscoveredDevice>{};
      for (final d in savedUsb) {
        final key = d['key'];
        if (key == null || key.isEmpty) continue;
        usbDeviceMap[key] = _DiscoveredDevice(
          name: d['name'] ?? '',
          detail: d['detail'] ?? '',
          key: key,
          type: _DeviceType.usb,
        );
      }
      // Inject fallback rows for assigned USB printers missing from saved list.
      // BT assignments are MAC addresses (AA:BB:CC:DD:EE:FF); anything else is USB.
      // Exclude the Sunmi key — it has its own static card.
      for (final key in [receiptMac, kitchenMac]) {
        if (key != null &&
            key != PrinterConfigService.kSunmiKey &&
            !macRe.hasMatch(key) &&
            !btDeviceMap.containsKey(key) &&
            !usbDeviceMap.containsKey(key)) {
          usbDeviceMap[key] = _DiscoveredDevice(
            name: key,
            detail: '',
            key: key,
            type: _DeviceType.usb,
          );
        }
      }
      _usbDevices = usbDeviceMap.values.toList();

      // Restore printer role assignments for BT/USB devices.
      if (receiptMac != null && receiptMac != PrinterConfigService.kSunmiKey) {
        final existing = _printerConfigs[receiptMac];
        _printerConfigs[receiptMac] = _PrinterConfig(
          receiptPrinter: true,
          kitchenPrinter: existing?.kitchenPrinter ?? false,
          paperWidth: widths[receiptMac] ?? PaperWidth.w58mm,
        );
      }
      if (kitchenMac != null && kitchenMac != PrinterConfigService.kSunmiKey) {
        final existing = _printerConfigs[kitchenMac];
        _printerConfigs[kitchenMac] = _PrinterConfig(
          receiptPrinter: existing?.receiptPrinter ?? false,
          kitchenPrinter: true,
          paperWidth: widths[kitchenMac] ?? PaperWidth.w58mm,
        );
      }

    });
  }

  Future<void> _scanBluetooth() async {
    setState(() {
      _isScanningBt = true;
      _btScanned = false;
    });
    final devices = await _Discovery.scanBluetooth();
    if (!mounted) return;
    setState(() {
      _btDevices = devices;
      _isScanningBt = false;
      _btScanned = true;
    });
    await PrinterConfigService().saveDevices(
      bluetooth: true,
      devices: devices
          .map((d) => {'name': d.name, 'detail': d.detail, 'key': d.key})
          .toList(),
    );
  }

  Future<void> _scanUsb() async {
    setState(() {
      _isScanningUsb = true;
      _usbScanned = false;
    });
    final devices = await _Discovery.scanUsb();
    if (!mounted) return;
    setState(() {
      _usbDevices = devices;
      _isScanningUsb = false;
      _usbScanned = true;
    });
    await PrinterConfigService().saveDevices(
      bluetooth: false,
      devices: devices
          .map((d) => {'name': d.name, 'detail': d.detail, 'key': d.key})
          .toList(),
    );
  }

  Future<void> _resetUsbPermissions() async {
    await _Discovery.resetUsbPermissions();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('USB permissions reset. Replug devices and scan again.')),
    );
    setState(() {
      _usbDevices = [];
      _usbScanned = false;
    });
  }

  void _openPrinterConfig(_DiscoveredDevice device) {
    final existing = _printerConfigs[device.key];
    showDialog<void>(
      context: context,
      builder: (_) => _PrinterConfigModal(
        deviceName: device.name,
        initialConfig: _PrinterConfig(
          receiptPrinter: existing?.receiptPrinter ?? false,
          kitchenPrinter: existing?.kitchenPrinter ?? false,
          paperWidth: existing?.paperWidth ?? PaperWidth.w58mm,
        ),
        showPaperWidth: true,
        onTestPrint: device.type == _DeviceType.bluetooth
            ? (width) => BtPrinterService().printTest(device.key, paperWidth: width)
            : null,
        onSave: (updated) async {
          setState(() => _printerConfigs[device.key] = updated);

          final svc = PrinterConfigService();

          // Persist paper width for BT devices.
          if (device.type == _DeviceType.bluetooth) {
            await svc.setBtPaperWidth(device.key, updated.paperWidth);
          }

          if (updated.receiptPrinter) {
            await svc.setReceiptPrinterMac(device.key);
          } else {
            final current = await svc.getReceiptPrinterMac();
            if (current == device.key) await svc.setReceiptPrinterMac(null);
          }

          if (updated.kitchenPrinter) {
            await svc.setKitchenPrinterMac(device.key);
          } else {
            final current = await svc.getKitchenPrinterMac();
            if (current == device.key) await svc.setKitchenPrinterMac(null);
          }

          await _loadSavedConfigs();
        },
      ),
    );
  }

  String get _sectionTitle {
    switch (_selectedTab) {
      case null:
        return 'Settings';
      case _SettingTab.printers:
        return 'Printers';
      case _SettingTab.customerDisplays:
        return 'Customer displays';
      case _SettingTab.taxes:
        return 'Taxes';
      case _SettingTab.general:
        return 'General';
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isSmall = MediaQuery.of(context).size.width < 700;

    if (isSmall) {
      if (_selectedTab == null) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            Expanded(child: _buildNav()),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSmallContentHeader(),
          Expanded(child: _buildContent()),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 440, child: _buildNav()),
              Container(width: 1, color: const Color(0xFFE0E0E0)),
              Expanded(child: _buildContent()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSmallContentHeader() {
    return Container(
      height: 68,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE0E0E0))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Color(0xFF212121)),
            onPressed: () => setState(() => _selectedTab = null),
          ),
          const SizedBox(width: 4),
          Text(
            _sectionTitle,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Color(0xFF212121),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 68,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE0E0E0))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          SizedBox(
            height: 48,
            width: 48,
            child: IgnorePointer(
              ignoring: widget.isSidebarVisible,
              child: Opacity(
                opacity: widget.isSidebarVisible ? 0 : 1,
                child: IconButton(
                  icon: const Icon(Icons.menu, color: Color(0xFF212121)),
                  onPressed: widget.toggleSidebar,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'Settings',
            style: TextStyle(
              color: Color(0xFF212121),
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Text(
            _sectionTitle,
            style: const TextStyle(
              color: Color(0xFFE67E22),
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
    );
  }

  Widget _buildNav() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SettingsNavItem(
                icon: Icons.print,
                label: 'Printers',
                isSelected: _selectedTab == _SettingTab.printers,
                onTap: () =>
                    setState(() => _selectedTab = _SettingTab.printers),
              ),
              const Divider(height: 1),
              _SettingsNavItem(
                icon: Icons.monitor,
                label: 'Customer displays',
                isSelected: _selectedTab == _SettingTab.customerDisplays,
                onTap: () => setState(
                  () => _selectedTab = _SettingTab.customerDisplays,
                ),
              ),
              const Divider(height: 1),
              _SettingsNavItem(
                icon: Icons.percent,
                label: 'Taxes',
                isSelected: _selectedTab == _SettingTab.taxes,
                onTap: () =>
                    setState(() => _selectedTab = _SettingTab.taxes),
              ),
              const Divider(height: 1),
              _SettingsNavItem(
                icon: Icons.settings,
                label: 'General',
                isSelected: _selectedTab == _SettingTab.general,
                onTap: () =>
                    setState(() => _selectedTab = _SettingTab.general),
              ),
              const Divider(height: 1),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildContent() {
    switch (_selectedTab ?? _SettingTab.printers) {
      case _SettingTab.printers:
        return _buildPrintersContent();
      case _SettingTab.customerDisplays:
        return _buildCustomerDisplaysContent();
      case _SettingTab.taxes:
        return _buildTaxesContent();
      case _SettingTab.general:
        return _buildGeneralContent();
    }
  }

  // ─── Printers tab ─────────────────────────────────────────────────────────

  Widget _buildPrintersContent() {
    return Container(
      color: const Color(0xFFF5F6FA),
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // ── Assigned Printers ─────────────────────────────────────────────
          const Text(
            'ASSIGNED PRINTERS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: Color(0xFF757575),
            ),
          ),
          const SizedBox(height: 8),
          ..._buildAssignedCards(),
          const SizedBox(height: 28),

          // ── Bluetooth ─────────────────────────────────────────────────────
          _sectionHeaderRow(
            label: 'Bluetooth Printers',
            icon: Icons.bluetooth_searching,
            buttonLabel: 'Scan',
            loading: _isScanningBt,
            onTap: _scanBluetooth,
          ),
          const SizedBox(height: 8),
          if (_isScanningBt)
            _loadingCard('Scanning for paired Bluetooth printers…')
          else if (_btScanned && _btDevices.isEmpty)
            _emptyCard(
              icon: Icons.bluetooth_disabled,
              message:
                  'No paired Bluetooth printers found.\n'
                  'Pair your printer via Android Settings first.',
            )
          else
            ..._btDevices.map(
              (d) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _deviceCard(
                  device: d,
                  icon: Icons.bluetooth,
                  iconColor: _kBlue,
                ),
              ),
            ),
          const SizedBox(height: 28),

          // ── USB ──────────────────────────────────────────────────────────
          Row(
            children: [
              const Expanded(
                child: Text(
                  'USB PRINTERS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: Color(0xFF757575),
                  ),
                ),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: const Color(0xFF757575)),
                onPressed: _isScanningUsb ? null : _resetUsbPermissions,
                icon: const Icon(Icons.lock_reset, size: 16),
                label: const Text('Reset'),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: _kBlue),
                onPressed: _isScanningUsb ? null : _scanUsb,
                icon: _isScanningUsb
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.usb, size: 16),
                label: const Text('Scan'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_isScanningUsb)
            _loadingCard('Scanning for connected USB devices…')
          else if (_usbScanned && _usbDevices.isEmpty)
            _emptyCard(
              icon: Icons.usb_off,
              message:
                  'No USB devices detected.\n'
                  'If your printer is already connected, unplug it, '
                  'plug it back in, then press Scan again.',
            )
          else
            ..._usbDevices.map(
              (d) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _deviceCard(
                  device: d,
                  icon: Icons.print,
                  iconColor: const Color(0xFF795548),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ─── Assigned Printers section ────────────────────────────────────────────

  List<Widget> _buildAssignedCards() {
    final deviceByKey = {
      for (final d in [..._btDevices, ..._usbDevices]) d.key: d,
    };

    String nameFor(String key) => deviceByKey[key]?.name ?? key;

    void openConfig(String key) {
      final device = deviceByKey[key];
      if (device != null) _openPrinterConfig(device);
    }

    Widget card({
      required String roleLabel,
      required IconData roleIcon,
      required String? assignedKey,
    }) {
      final isAssigned = assignedKey != null;

      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: isAssigned ? () => openConfig(assignedKey) : null,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE0E0E0)),
              ),
              child: Row(
                children: [
                  Icon(
                    roleIcon,
                    size: 20,
                    color: isAssigned
                        ? _kGreen
                        : const Color(0xFFBDBDBD),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          roleLabel,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF9E9E9E),
                          ),
                        ),
                        Text(
                          isAssigned ? nameFor(assignedKey) : 'Not assigned',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: isAssigned
                                ? const Color(0xFF212121)
                                : const Color(0xFFBDBDBD),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isAssigned)
                    const Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: Color(0xFFBDBDBD),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return [
      card(
        roleLabel: 'Receipt',
        roleIcon: Icons.receipt_long_outlined,
        assignedKey: _receiptMac,
      ),
      card(
        roleLabel: 'Kitchen',
        roleIcon: Icons.local_cafe_outlined,
        assignedKey: _kitchenMac,
      ),
    ];
  }

  // ─── Device card ──────────────────────────────────────────────────────────

  Widget _deviceCard({
    required _DiscoveredDevice device,
    required IconData icon,
    required Color iconColor,
  }) {
    final config = _printerConfigs[device.key];
    final indicator = config?.indicator ?? '';

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _openPrinterConfig(device),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE0E0E0)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: iconColor),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.name,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    if (device.detail.isNotEmpty)
                      Text(
                        device.detail,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF9E9E9E),
                        ),
                      ),
                  ],
                ),
              ),
              if (indicator.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  indicator,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF9E9E9E),
                  ),
                ),
              ],
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right,
                size: 18,
                color: Color(0xFFBDBDBD),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Shared helpers ───────────────────────────────────────────────────────

  Widget _sectionHeaderRow({
    required String label,
    required IconData icon,
    required String buttonLabel,
    required bool loading,
    required VoidCallback onTap,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: Color(0xFF757575),
            ),
          ),
        ),
        TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: _kBlue),
          onPressed: loading ? null : onTap,
          icon: loading
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(icon, size: 16),
          label: Text(buttonLabel),
        ),
      ],
    );
  }

  Widget _loadingCard(String message) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Text(message, style: const TextStyle(color: Color(0xFF757575))),
        ],
      ),
    );
  }

  Widget _emptyCard({required IconData icon, required String message}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: const Color(0xFFBDBDBD)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFF9E9E9E),
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Other tabs ───────────────────────────────────────────────────────────

  Widget _buildCustomerDisplaysContent() {
    final detecting = _hasSecondaryDisplay == null;
    final hasDisplay = _hasSecondaryDisplay == true;

    String subtitle;
    Color subtitleColor;
    if (detecting) {
      subtitle = 'Detecting display…';
      subtitleColor = const Color(0xFF9E9E9E);
    } else if (!hasDisplay) {
      subtitle = 'No secondary display detected';
      subtitleColor = const Color(0xFF9E9E9E);
    } else if (_customerDisplayEnabled) {
      subtitle = 'Customer display is active';
      subtitleColor = _kGreen;
    } else {
      subtitle = 'Display off — secondary screen showing default';
      subtitleColor = const Color(0xFF9E9E9E);
    }

    return Container(
      color: const Color(0xFFF5F6FA),
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE0E0E0)),
            ),
            child: SwitchListTile(
              value: _customerDisplayEnabled,
              onChanged: (detecting || !hasDisplay)
                  ? null
                  : _toggleCustomerDisplay,
              title: const Text('Customer facing display'),
              subtitle: detecting
                  ? Row(
                      children: [
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        ),
                        const SizedBox(width: 8),
                        Text(subtitle,
                            style: TextStyle(
                                color: subtitleColor, fontSize: 13)),
                      ],
                    )
                  : Text(subtitle,
                      style:
                          TextStyle(color: subtitleColor, fontSize: 13)),
              activeThumbColor: _kGreen,
              activeTrackColor: const Color(0xFFFFCC80),
            ),
          ),
          if (!detecting && !hasDisplay) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      size: 14, color: Color(0xFFBDBDBD)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Connect a secondary display to this device to enable the customer-facing screen.',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF9E9E9E)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTaxesContent() {
    return Container(
      color: const Color(0xFFF5F6FA),
      child: const Center(
        child: Text(
          'Tax configuration coming soon.',
          style: TextStyle(color: Color(0xFF9E9E9E)),
        ),
      ),
    );
  }

  Widget _buildGeneralContent() {
    return Container(
      color: const Color(0xFFF5F6FA),
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE0E0E0)),
            ),
            child: SwitchListTile(
              value: _darkModeEnabled,
              onChanged: (v) => setState(() => _darkModeEnabled = v),
              title: const Text('Dark mode'),
              activeThumbColor: _kGreen,
              activeTrackColor: const Color(0xFFFFCC80),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Printer config modal ─────────────────────────────────────────────────────

class _PrinterConfigModal extends StatefulWidget {
  const _PrinterConfigModal({
    required this.deviceName,
    required this.initialConfig,
    required this.onSave,
    this.onTestPrint,
    this.showPaperWidth = false,
  });

  final String deviceName;
  final _PrinterConfig initialConfig;
  final ValueChanged<_PrinterConfig> onSave;
  final Future<void> Function(PaperWidth)? onTestPrint;
  final bool showPaperWidth;

  @override
  State<_PrinterConfigModal> createState() => _PrinterConfigModalState();
}

class _PrinterConfigModalState extends State<_PrinterConfigModal> {
  static const _kGreen = Color(0xFFE67E22);

  late bool _receipt;
  late bool _kitchen;
  late PaperWidth _paperWidth;
  bool _isTesting = false;

  @override
  void initState() {
    super.initState();
    _receipt = widget.initialConfig.receiptPrinter;
    _kitchen = widget.initialConfig.kitchenPrinter;
    _paperWidth = widget.initialConfig.paperWidth;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      title: Text(
        widget.deviceName,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Divider(height: 1),
          SwitchListTile(
            value: _receipt,
            onChanged: (v) => setState(() => _receipt = v),
            title: const Text('Receipt Printer'),
            subtitle: const Text('Prints customer receipts after payment.'),
            activeThumbColor: _kGreen,
            activeTrackColor: const Color(0xFFFFCC80),
          ),
          const Divider(height: 1, indent: 16),
          SwitchListTile(
            value: _kitchen,
            onChanged: (v) => setState(() => _kitchen = v),
            title: const Text('Kitchen Printer'),
            subtitle: const Text('Sends order tickets to the kitchen.'),
            activeThumbColor: _kGreen,
            activeTrackColor: const Color(0xFFFFCC80),
          ),
          if (widget.showPaperWidth) ...[
            const Divider(height: 1, indent: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Paper Width',
                            style: TextStyle(fontSize: 15)),
                        SizedBox(height: 2),
                        Text('Match your paper roll size.',
                            style: TextStyle(
                                fontSize: 13,
                                color: Color(0xFF9E9E9E))),
                      ],
                    ),
                  ),
                  _PaperWidthToggle(
                    value: _paperWidth,
                    onChanged: (w) => setState(() => _paperWidth = w),
                  ),
                ],
              ),
            ),
          ],
          if (widget.onTestPrint != null) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFBDBDBD)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  onPressed: _isTesting
                      ? null
                      : () async {
                          setState(() => _isTesting = true);
                          try {
                            await widget.onTestPrint!(_paperWidth);
                          } finally {
                            if (mounted) setState(() => _isTesting = false);
                          }
                        },
                  icon: _isTesting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.print_outlined, size: 16),
                  label: Text(_isTesting ? 'Printing…' : 'Test Print'),
                ),
              ),
            ),
          ],
          const Divider(height: 1),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: _kGreen),
          onPressed: () {
            widget.onSave(
              _PrinterConfig(
                receiptPrinter: _receipt,
                kitchenPrinter: _kitchen,
                paperWidth: _paperWidth,
              ),
            );
            Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

// ─── Paper width toggle ───────────────────────────────────────────────────────

class _PaperWidthToggle extends StatelessWidget {
  const _PaperWidthToggle({required this.value, required this.onChanged});

  final PaperWidth value;
  final ValueChanged<PaperWidth> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE0E0E0)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _btn(PaperWidth.w58mm),
          _btn(PaperWidth.w80mm),
        ],
      ),
    );
  }

  Widget _btn(PaperWidth pw) {
    final active = value == pw;
    return GestureDetector(
      onTap: () => onChanged(pw),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF212121) : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          pw.label,
          style: TextStyle(
            color: active ? Colors.white : const Color(0xFF757575),
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

// ─── Nav item ─────────────────────────────────────────────────────────────────

class _SettingsNavItem extends StatelessWidget {
  const _SettingsNavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = isSelected ? const Color(0xFFE67E22) : Colors.black87;
    return Material(
      color: isSelected ? const Color(0xFFF5F5F5) : Colors.white,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 56,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(width: 16),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 15,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
