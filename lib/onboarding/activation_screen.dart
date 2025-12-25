import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../storage/secure_store.dart';

class ActivationScreen extends StatefulWidget {
  const ActivationScreen({super.key, required this.onActivated});

  final VoidCallback onActivated;

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen> {
  final TextEditingController _storeCodeController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final ApiClient _apiClient = ApiClient();
  final SecureStore _secureStore = const SecureStore();
  bool _isPasswordVisible = false;
  bool _isSubmitting = false;
  String? _errorMessage;

  bool? _parseBool(dynamic value) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (['true', '1', 'yes'].contains(normalized)) {
        return true;
      }
      if (['false', '0', 'no'].contains(normalized)) {
        return false;
      }
    }
    return null;
  }

  bool _extractActivationResult(Map<String, dynamic> responseData) {
    final candidates = [
      responseData['data'],
      responseData['result'],
      responseData['success'],
      responseData['status'],
    ];
    for (final candidate in candidates) {
      final parsed = _parseBool(candidate);
      if (parsed != null) {
        return parsed;
      }
      if (candidate is Map<String, dynamic>) {
        for (final key in ['status', 'success', 'result', 'data']) {
          final nestedParsed = _parseBool(candidate[key]);
          if (nestedParsed != null) {
            return nestedParsed;
          }
        }
      }
    }
    return false;
  }

  @override
  void dispose() {
    _storeCodeController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    if (_isSubmitting) {
      return;
    }
    final storeCode = _storeCodeController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (storeCode.isEmpty || email.isEmpty || password.isEmpty) {
      setState(() {
        _errorMessage = 'Please fill in the store code, email, and password.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final response = await _apiClient.postJson(
        '/omni_sales/api/v1/install/verify',
        body: {
          'warehouse_code': storeCode,
          'email': email,
          'password': password,
        },
      );
      final responseData = response.data;
      if (!_extractActivationResult(responseData)) {
        throw ApiException('Activation was rejected.');
      }
      final Map<String, dynamic> responsePayload =
          responseData['data'] is Map<String, dynamic>
          ? responseData['data'] as Map<String, dynamic>
          : responseData['result'] is Map<String, dynamic>
          ? responseData['result'] as Map<String, dynamic>
          : responseData;
      final Map<String, dynamic>? authentication =
          responsePayload['authentication'] is Map<String, dynamic>
          ? responsePayload['authentication'] as Map<String, dynamic>
          : null;
      final Map<String, dynamic>? authHeaders = authentication != null
          ? authentication['headers'] as Map<String, dynamic>?
          : null;
      final authToken =
          responsePayload['auth_token'] ??
          responsePayload['token'] ??
          authentication?['token'] ??
          authentication?['authtoken'] ??
          authentication?['Authorization'] ??
          authHeaders?['authtoken'] ??
          authHeaders?['Authorization'];
      final staffId = responsePayload['staff_id'];
      final warehouseCode =
          responsePayload['warehouse_code'] ?? responsePayload['warehouseCode'];
      final warehouseId =
          responsePayload['warehouse_id'] ?? responsePayload['warehouseId'];
      if (authToken == null || staffId == null) {
        throw ApiException('Activation response missing token or staff id.');
      }
      await Future.wait([
        _secureStore.writeAuth(
          token: authToken.toString(),
          staffId: staffId.toString(),
        ),
        _secureStore.writeActivationDetails(
          email: email,
          warehouseCode: (warehouseCode ?? storeCode).toString(),
          warehouseId: warehouseId?.toString(),
        ),
      ]);
      widget.onActivated();
    } catch (error) {
      setState(() {
        _errorMessage = 'Activation failed. Please check your details.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Widget _buildCard(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Card(
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: const Color(0xFFFBE9D7),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(
                  Icons.storefront,
                  size: 64,
                  color: Color(0xFFF57C00),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Activate your register',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 28),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'STORE CODE',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: const Color(0xFF6D6D6D),
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _storeCodeController,
                decoration: InputDecoration(
                  hintText: 'KKNTS-001',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'EMAIL',
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: const Color(0xFF6D6D6D),
                                letterSpacing: 1.1,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            hintText: 'john.doe@gmail.com',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            suffixIcon: _emailController.text.isEmpty
                                ? null
                                : IconButton(
                                    icon: const Icon(Icons.close),
                                    onPressed: () {
                                      _emailController.clear();
                                      setState(() {});
                                    },
                                  ),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PASSWORD',
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: const Color(0xFF6D6D6D),
                                letterSpacing: 1.1,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _passwordController,
                          obscureText: !_isPasswordVisible,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _isPasswordVisible
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                              onPressed: () {
                                setState(() {
                                  _isPasswordVisible = !_isPasswordVisible;
                                });
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              if (_errorMessage != null) ...[
                Text(
                  _errorMessage!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
              ],
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF57C00),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _isSubmitting ? null : _activate,
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : const Text(
                          'Continue',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF2E2A25), Color(0xFF1E1B18)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            child: _buildCard(context),
          ),
        ),
      ),
    );
  }
}
