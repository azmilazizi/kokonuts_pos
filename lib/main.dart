import 'package:flutter/material.dart';

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
  int _selectedIndex = 0;

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

  void _selectDestination(int index) {
    setState(() {
      _selectedIndex = index;
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
                              isSelected: _selectedIndex == 0,
                              onTap: () => _selectDestination(0),
                            ),
                            _SidebarItem(
                              label: _destinations[1].label,
                              isSelected: _selectedIndex == 1,
                              onTap: () => _selectDestination(1),
                            ),
                            _SidebarItem(
                              label: _destinations[2].label,
                              isSelected: _selectedIndex == 2,
                              onTap: () => _selectDestination(2),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: Divider(height: 1),
                            ),
                            _SidebarItem(
                              label: _destinations[3].label,
                              isSelected: _selectedIndex == 3,
                              onTap: () => _selectDestination(3),
                            ),
                            _SidebarItem(
                              label: _destinations[4].label,
                              isSelected: _selectedIndex == 4,
                              onTap: () => _selectDestination(4),
                            ),
                            _SidebarItem(
                              label: _destinations[5].label,
                              isSelected: _selectedIndex == 5,
                              onTap: () => _selectDestination(5),
                            ),
                            _SidebarItem(
                              label: _destinations[6].label,
                              isSelected: _selectedIndex == 6,
                              onTap: () => _selectDestination(6),
                            ),
                            _SidebarItem(
                              label: _destinations[7].label,
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
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.label,
    required this.onTap,
    this.isSelected = false,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

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
