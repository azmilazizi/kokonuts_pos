import '../api/api_client.dart';
import 'receipt_service.dart';

/// One pending delivery-platform print job from `GET /pos/api/v1/print_jobs`.
///
/// The embedded `receipt` payload is "identical to a dine-in
/// /pos/api/v1/receipt/:number response", so the existing [ReceiptSummary]
/// and [ReceiptDetail] parsers are reused directly against it.
class PrintJob {
  const PrintJob({
    required this.jobId,
    required this.source,
    required this.createdAt,
    required this.receiptJson,
  });

  final int jobId;
  final String source;
  final DateTime createdAt;
  final Map<String, dynamic> receiptJson;

  ReceiptSummary? get summary => ReceiptSummary.fromJson(receiptJson);
  ReceiptDetail get detail => ReceiptDetail.fromJson(receiptJson)!;

  String get receiptNumber => receiptJson['receipt_number']?.toString() ?? '';

  String get printCollectionNumber =>
      receiptJson['print_collection_number']?.toString() ??
      (receiptNumber.isNotEmpty ? receiptNumber : '$jobId');

  double get totalMoney {
    final s = summary;
    if (s != null) return s.totalMoney;
    return double.tryParse(receiptJson['total_money']?.toString() ?? '') ??
        0.0;
  }

  String get paymentMethodLabel {
    final pm = summary?.paymentMethod;
    if (pm != null && pm.isNotEmpty) return pm;
    return sourceLabel;
  }

  DateTime get _effectiveDate => summary?.receiptDate ?? createdAt;

  /// "6/5/26" — matches the format used elsewhere for printed receipts.
  String get dateLabel {
    final d = _effectiveDate;
    return '${d.month}/${d.day}/${d.year % 100}';
  }

  /// "10:30 AM"
  String get timeLabel {
    final d = _effectiveDate;
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    final ampm = d.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }

  /// Human-readable platform name for display (receipt payment line, badges).
  String get sourceLabel => deliverySourceLabel(source);

  static PrintJob fromJson(Map<String, dynamic> json) {
    final receipt = json['receipt'];
    return PrintJob(
      jobId: int.tryParse(json['job_id']?.toString() ?? '') ?? 0,
      source: json['source']?.toString() ?? '',
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
              DateTime.now(),
      receiptJson:
          receipt is Map<String, dynamic> ? receipt : <String, dynamic>{},
    );
  }
}

class PrintJobService {
  PrintJobService({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  Future<List<PrintJob>> fetchPendingJobs(String token) async {
    final response = await _client.getJson(
      '/pos/api/v1/print_jobs',
      authToken: token,
    );
    final outer =
        (response.data['data'] as Map<String, dynamic>?) ?? response.data;
    final rawJobs = outer['jobs'];
    final jobs = <PrintJob>[];
    if (rawJobs is List) {
      for (final e in rawJobs) {
        if (e is Map<String, dynamic>) jobs.add(PrintJob.fromJson(e));
      }
    }
    return jobs;
  }

  Future<void> ackJob(
    String token,
    int jobId, {
    required bool success,
    String? error,
  }) async {
    await _client.postForm(
      '/pos/api/v1/print_jobs/$jobId/ack',
      fields: success
          ? {'status': 'printed'}
          : {'status': 'failed', 'error': error ?? 'Unknown error'},
      authToken: token,
    );
  }
}
