import 'dart:async';

import 'delivery_print_service.dart';
import 'print_job_service.dart';

/// Polls `GET /pos/api/v1/print_jobs` every ~3s and prints/acks each pending
/// delivery-platform order. Owned by the authenticated app shell
/// (`_RegisterScreenState`) — started on login, disposed on sign-out,
/// mirroring `SyncService`'s start()/dispose() lifecycle.
class DeliveryPrintJobPoller {
  DeliveryPrintJobPoller({
    PrintJobService? jobService,
    DeliveryPrintService? printService,
  })  : _jobService = jobService ?? PrintJobService(),
        _printService = printService ?? DeliveryPrintService();

  final PrintJobService _jobService;
  final DeliveryPrintService _printService;

  Timer? _timer;
  bool _busy = false;

  void start({
    required Future<String?> Function() tokenProvider,
    required void Function(PrintJob job, String error) onFailure,
    required void Function(PrintJob job, String error) onKitchenWarning,
  }) {
    _timer?.cancel();
    _timer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _tick(tokenProvider, onFailure, onKitchenWarning),
    );
  }

  Future<void> _tick(
    Future<String?> Function() tokenProvider,
    void Function(PrintJob job, String error) onFailure,
    void Function(PrintJob job, String error) onKitchenWarning,
  ) async {
    if (_busy) return;
    _busy = true;
    try {
      final token = await tokenProvider();
      if (token == null || token.isEmpty) return;

      final jobs = await _jobService.fetchPendingJobs(token);
      for (final job in jobs) {
        try {
          final result = await _printService.printJob(job);
          await _jobService.ackJob(token, job.jobId, success: true);
          if (!result.kitchenOk) {
            onKitchenWarning(job, result.kitchenError ?? 'Kitchen print failed');
          }
        } catch (e) {
          try {
            await _jobService.ackJob(
              token,
              job.jobId,
              success: false,
              error: e.toString(),
            );
          } catch (_) {
            // Ack itself failed (e.g. transient network) — the backend will
            // re-offer this job next poll since it was never acked.
          }
          onFailure(job, e.toString());
        }
      }
    } catch (_) {
      // Poll-level error (network blip, etc.) — ignore and retry next tick.
    } finally {
      _busy = false;
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
