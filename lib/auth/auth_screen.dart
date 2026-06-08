import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../storage/secure_store.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.onAuthenticated});

  final VoidCallback onAuthenticated;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  static const int _passcodeLength = 4;
  late final TabController _tabController;
  String _loginCode = '';
  String _clockCode = '';
  bool _isSubmitting = false;
  String? _errorMessage;
  final ApiClient _apiClient = ApiClient();
  final SecureStore _secureStore = const SecureStore();

  // TODO: replace with live clocked-in staff from clock-in/out API
  final List<_ClockedInStaff> _clockedInStaff = const [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusManager.instance.primaryFocus?.unfocus();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _handleDigit(String digit) {
    if (_isSubmitting) {
      return;
    }
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
    if (_isSubmitting) {
      return;
    }
    setState(() {
      if (_tabController.index == 0) {
        _loginCode = '';
      } else {
        _clockCode = '';
      }
    });
  }

  void _handleBackspace() {
    if (_isSubmitting) {
      return;
    }
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

  Future<void> _submitLoginCode() async {
    if (_isSubmitting) {
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final token = await _secureStore.readToken();
      if (token == null || token.isEmpty) {
        throw ApiException('Device not activated.');
      }
      await _apiClient.postJson(
        '/pos/api/v1/verify_passcode',
        body: {'passcode': _loginCode},
        authToken: token,
      );
      widget.onAuthenticated();
    } on ApiException catch (e) {
      setState(() {
        _errorMessage = e.statusCode == 401 || e.statusCode == 403
            ? 'Incorrect passcode.'
            : 'Login failed. Please try again.';
        _loginCode = '';
      });
    } catch (_) {
      setState(() {
        _errorMessage = 'Could not connect. Please try again.';
        _loginCode = '';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _submitClockCode() async {
    if (_isSubmitting) {
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final token = await _secureStore.readToken();
      await _apiClient.postJson(
        '/timesheets/api/check_in_out_passcode',
        body: {'passcode': _clockCode},
        authToken: token,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Clock in/out request submitted.')),
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Clock in/out failed. Please try again.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _clockCode = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF2B2622), Color(0xFF1B1714)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 980;

                if (!isWide) {
                  return SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 32,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _buildAuthCard(context),
                        const SizedBox(height: 32),
                        _buildClockedInPanel(isWide: false),
                      ],
                    ),
                  );
                }

                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 32,
                  ),
                  child: LayoutBuilder(
                    builder: (context, innerConstraints) {
                      return SizedBox(
                        height: innerConstraints.maxHeight,
                        width: innerConstraints.maxWidth,
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.center,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: 920,
                                maxHeight: innerConstraints.maxHeight,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _buildAuthCard(context),
                                  const SizedBox(width: 48),
                                  _buildClockedInPanel(),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
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
              color: Colors.black.withValues(alpha: 0.15),
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
                                ? 'Enter your POS passcode to continue.'
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
                      final code = _tabController.index == 0
                          ? _loginCode
                          : _clockCode;
                      return _PasscodeDots(
                        codeLength: code.length,
                        totalDots: _passcodeLength,
                      );
                    },
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE6E0DB)),
            SizedBox(
              height: 264,
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
                    style: const TextStyle(color: Colors.white, fontSize: 14),
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
  const _PasscodeDots({required this.codeLength, required this.totalDots});

  final int codeLength;
  final int totalDots;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(totalDots, (index) {
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
      }),
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final keyWidth = constraints.maxWidth / 3;
        final keyHeight = constraints.maxHeight / 4;
        final childAspectRatio =
            keyWidth / (keyHeight == 0 ? keyWidth : keyHeight);
        return GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: childAspectRatio,
          ),
          itemCount: keys.length,
          itemBuilder: (context, index) {
            final key = keys[index];
            Widget child;
            VoidCallback? onTap;
            if (key == 'clear') {
              child = const Icon(
                Icons.close,
                size: 26,
                color: Color(0xFF7C7773),
              );
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
            return Material(
              color: Colors.transparent,
              child: Ink(
                decoration: const BoxDecoration(
                  color: Color(0xFFF7F4F2),
                  border: Border(
                    right: BorderSide(color: Color(0xFFE8E4E1)),
                    bottom: BorderSide(color: Color(0xFFE8E4E1)),
                  ),
                ),
                child: InkWell(
                  onTap: onTap,
                  splashColor: const Color(0xFFE67516).withValues(alpha: 0.18),
                  highlightColor: const Color(
                    0xFFE67516,
                  ).withValues(alpha: 0.1),
                  child: Center(child: child),
                ),
              ),
            );
          },
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
