import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/duitnow_service.dart';
import '../services/sunmi_display_service.dart';
import '../storage/secure_store.dart';

enum _DuitNowState { loading, waiting, paid, error }

class DuitNowPaymentDialog extends StatefulWidget {
  const DuitNowPaymentDialog({
    super.key,
    required this.amount,
    required this.reference,
    required this.onPaymentConfirmed,
  });

  final double amount;
  final String reference;
  final VoidCallback onPaymentConfirmed;

  @override
  State<DuitNowPaymentDialog> createState() => _DuitNowPaymentDialogState();
}

class _DuitNowPaymentDialogState extends State<DuitNowPaymentDialog> {
  final _service = DuitNowService();
  _DuitNowState _state = _DuitNowState.loading;
  String? _purchaseId;
  String? _errorMessage;
  String _token = '';
  Uint8List? _qrBytes;
  Timer? _pollTimer;
  bool _cancelling = false;

  @override
  void initState() {
    super.initState();
    _createPayment();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _createPayment() async {
    try {
      _token = await const SecureStore().readToken() ?? '';
      final result = await _service.createPayment(
        token: _token,
        amount: widget.amount,
        reference: widget.reference,
      );
      _purchaseId = result.purchaseId;
      final qrBytes = await _service.fetchQrImage(
        token: _token,
        purchaseId: result.purchaseId,
      );
      await SunmiDisplayService().showDuitNowQr(qrBytes, widget.amount);
      if (!mounted) return;
      setState(() {
        _qrBytes = qrBytes;
        _state = _DuitNowState.waiting;
      });
      _startPolling(_token);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _DuitNowState.error;
        _errorMessage = e.toString();
      });
    }
  }

  void _startPolling(String token) {
    _pollTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) async {
      if (_purchaseId == null) return;
      try {
        final status = await _service.pollStatus(
          token: token,
          purchaseId: _purchaseId!,
        );
        if (status.isPaid) {
          _pollTimer?.cancel();
          if (!mounted) return;
          setState(() => _state = _DuitNowState.paid);
          // Brief moment to show confirmation before handing off
          await Future.delayed(const Duration(milliseconds: 600));
          if (!mounted) return;
          widget.onPaymentConfirmed();
          Navigator.of(context).pop();
        }
      } catch (_) {
        // Ignore transient network errors — keep polling
      }
    });
  }

  Future<void> _cancel() async {
    if (_cancelling) return;
    setState(() => _cancelling = true);
    _pollTimer?.cancel();
    if (_purchaseId != null) {
      try {
        await _service.cancelPayment(token: _token, purchaseId: _purchaseId!);
      } catch (_) {}
    }
    // Restore order display on CFD (hide QR overlay)
    await SunmiDisplayService().hideDuitNowQr();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        child: IntrinsicWidth(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 36),
            child: _buildContent(),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    switch (_state) {
      case _DuitNowState.loading:
        return const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text('Preparing DuitNow QR...', style: TextStyle(fontSize: 16)),
          ],
        );

      case _DuitNowState.waiting:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_qrBytes != null)
              Image.memory(_qrBytes!, width: 264, height: 264)
            else
              const SizedBox(
                width: 264,
                height: 264,
                child: Center(child: CircularProgressIndicator()),
              ),
            const SizedBox(height: 16),
            const Text(
              'DuitNow QR',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'RM ${widget.amount.toStringAsFixed(2)}',
              style: const TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: Color(0xFFE67E22),
              ),
            ),
            if (MediaQuery.of(context).size.width >= 700) ...[
              const SizedBox(height: 20),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Text(
                    'Waiting for customer to scan...',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 6),
            const Text(
              'QR code is shown on the customer display',
              style: TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            OutlinedButton.icon(
              onPressed: _cancelling ? null : _cancel,
              icon: _cancelling
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.red,
                      ),
                    )
                  : const Icon(Icons.cancel_outlined, color: Colors.red),
              label: const Text('Cancel Payment'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
            ),
          ],
        );

      case _DuitNowState.paid:
        return const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 64, color: Colors.green),
            SizedBox(height: 16),
            Text(
              'Payment Confirmed!',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text('Processing order...', style: TextStyle(color: Colors.grey)),
          ],
        );

      case _DuitNowState.error:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            const Text(
              'Failed to create QR',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
            const SizedBox(height: 24),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
    }
  }
}
