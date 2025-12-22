import 'package:flutter/material.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.onAuthenticated});

  final VoidCallback onAuthenticated;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  static const int _passcodeLength = 4;
  static const _backgroundIcons = [
    Icons.shopping_bag_outlined,
    Icons.storefront_outlined,
    Icons.percent,
    Icons.card_giftcard,
    Icons.qr_code_2,
    Icons.local_mall_outlined,
    Icons.receipt_long_outlined,
    Icons.local_offer_outlined,
    Icons.sell_outlined,
  ];

  late final TabController _tabController;
  String _loginCode = '';
  String _clockCode = '';

  final List<_ClockedInStaff> _clockedInStaff = const [
    _ClockedInStaff('John Doe', '07/01/2025 02:37 PM'),
    _ClockedInStaff('Kiran Kaur', '10/06/2025 02:41 PM'),
    _ClockedInStaff('Siti Aminah', '12/06/2025 02:58 PM'),
    _ClockedInStaff('Daniel Lim', '15/06/2025 03:12 PM'),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _handleDigit(String digit) {
    setState(() {
      if (_tabController.index == 0) {
        if (_loginCode.length < _passcodeLength) {
          _loginCode += digit;
        }
        if (_loginCode.length == _passcodeLength) {
          _submitLoginCode();
        }
      } else {
        if (_clockCode.length < _passcodeLength) {
          _clockCode += digit;
        }
        if (_clockCode.length == _passcodeLength) {
          _submitClockCode();
        }
      }
    });
  }

  void _handleClear() {
    setState(() {
      if (_tabController.index == 0) {
        _loginCode = '';
      } else {
        _clockCode = '';
      }
    });
  }

  void _handleBackspace() {
    setState(() {
      if (_tabController.index == 0) {
        if (_loginCode.isNotEmpty) {
          _loginCode = _loginCode.substring(0, _loginCode.length - 1);
        }
      } else {
        if (_clockCode.isNotEmpty) {
          _clockCode = _clockCode.substring(0, _clockCode.length - 1);
        }
      }
    });
  }

  void _submitLoginCode() {
    widget.onAuthenticated();
  }

  void _submitClockCode() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Clock in/out request submitted.'),
      ),
    );
    _clockCode = '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF2B2622),
                  Color(0xFF1B1714),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          Positioned.fill(
            child: Opacity(
              opacity: 0.08,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final crossAxisCount =
                      (constraints.maxWidth / 160).clamp(4, 10).floor();
                  return GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(24),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                    ),
                    itemCount: 60,
                    itemBuilder: (context, index) {
                      final icon = _backgroundIcons[
                          index % _backgroundIcons.length];
                      return Icon(
                        icon,
                        size: 48,
                        color: Colors.white,
                      );
                    },
                  );
                },
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 980;
                final content = isWide
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildAuthCard(context),
                          const SizedBox(width: 48),
                          _buildClockedInPanel(),
                        ],
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildAuthCard(context),
                          const SizedBox(height: 32),
                          _buildClockedInPanel(isWide: false),
                        ],
                      );
                return Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 32,
                    ),
                    child: content,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthCard(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Color(0xFFE6E0DB)),
                ),
              ),
              child: TabBar(
                controller: _tabController,
                indicatorColor: const Color(0xFFE67516),
                labelColor: const Color(0xFF1F1A16),
                unselectedLabelColor: const Color(0xFF8E8681),
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                ),
                tabs: const [
                  Tab(text: 'LOG IN'),
                  Tab(text: 'CLOCK IN/OUT'),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                children: [
                  Container(
                    width: 92,
                    height: 92,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE9EDF6),
                      borderRadius: BorderRadius.circular(46),
                    ),
                    child: const Icon(
                      Icons.lock,
                      size: 48,
                      color: Color(0xFF9AA5C9),
                    ),
                  ),
                  const SizedBox(height: 20),
                  AnimatedBuilder(
                    animation: _tabController,
                    builder: (context, child) {
                      final isLogin = _tabController.index == 0;
                      return Column(
                        children: [
                          Text(
                            isLogin ? 'Shift Closed' : 'Clock In / Out',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            isLogin
                                ? 'Enter your manager passcode to continue.'
                                : 'Enter your staff code to clock in or out.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xFF7B7672),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 18),
                  AnimatedBuilder(
                    animation: _tabController,
                    builder: (context, child) {
                      final code =
                          _tabController.index == 0 ? _loginCode : _clockCode;
                      return _PasscodeDots(
                        codeLength: code.length,
                        totalDots: _passcodeLength,
                      );
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE6E0DB)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _Keypad(
                onDigitPressed: _handleDigit,
                onClear: _handleClear,
                onBackspace: _handleBackspace,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClockedInPanel({bool isWide = true}) {
    return SizedBox(
      width: isWide ? 280 : 320,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'CLOCKED IN',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          const Divider(color: Color(0xFF5C534E), height: 1),
          const SizedBox(height: 12),
          ..._clockedInStaff.map(
            (staff) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    staff.name,
                    style: const TextStyle(
                      color: Color(0xFFE67516),
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    staff.timestamp,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Divider(color: Color(0xFF5C534E), height: 1),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PasscodeDots extends StatelessWidget {
  const _PasscodeDots({
    required this.codeLength,
    required this.totalDots,
  });

  final int codeLength;
  final int totalDots;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        totalDots,
        (index) {
          final isFilled = index < codeLength;
          return Container(
            width: 12,
            height: 12,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isFilled ? const Color(0xFF6D6D6D) : Colors.transparent,
              border: Border.all(color: const Color(0xFF9A9390)),
            ),
          );
        },
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({
    required this.onDigitPressed,
    required this.onClear,
    required this.onBackspace,
  });

  final ValueChanged<String> onDigitPressed;
  final VoidCallback onClear;
  final VoidCallback onBackspace;

  @override
  Widget build(BuildContext context) {
    const keys = [
      '1',
      '2',
      '3',
      '4',
      '5',
      '6',
      '7',
      '8',
      '9',
      'clear',
      '0',
      'back',
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 1.3,
      ),
      itemCount: keys.length,
      itemBuilder: (context, index) {
        final key = keys[index];
        Widget child;
        VoidCallback? onTap;
        if (key == 'clear') {
          child = const Icon(Icons.close, size: 26, color: Color(0xFF7C7773));
          onTap = onClear;
        } else if (key == 'back') {
          child = const Icon(
            Icons.backspace_outlined,
            size: 24,
            color: Color(0xFF7C7773),
          );
          onTap = onBackspace;
        } else {
          child = Text(
            key,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: Color(0xFF2D2A28),
            ),
          );
          onTap = () => onDigitPressed(key);
        }
        return InkWell(
          onTap: onTap,
          child: Container(
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: Color(0xFFE6E0DB)),
                right: BorderSide(color: Color(0xFFE6E0DB)),
              ),
            ),
            child: Center(child: child),
          ),
        );
      },
    );
  }
}

class _ClockedInStaff {
  const _ClockedInStaff(this.name, this.timestamp);

  final String name;
  final String timestamp;
}
