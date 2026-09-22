import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../models/checklist_template.dart';

class ChecklistService {
  ChecklistService({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  /// Fetches the active checklist template for [type] ('sop_open',
  /// 'sop_close', or 'equipment'), scoped to the caller's outlet by the
  /// backend. Returns null on any failure or when none is configured —
  /// callers must treat that as "nothing to show", never as a blocker.
  Future<ChecklistTemplate?> fetchTemplate(String token, String type) async {
    try {
      final response = await _client.getJson(
        '/pos/api/v1/checklists/template/$type',
        authToken: token,
      );
      final data = response.data['data'];
      if (data is! Map<String, dynamic>) return null;
      return ChecklistTemplate.fromJson(data);
    } on ApiException {
      return null;
    } catch (_) {
      return null;
    }
  }
}
