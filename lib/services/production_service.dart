import '../api/api_client.dart';
import '../models/production_recipe_preview.dart';
import '../models/production_run.dart';
import '../models/production_source.dart';

class ProductionService {
  ProductionService({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  Future<List<ProductionSource>> fetchSources({required String token}) async {
    final response = await _client.getJson(
      '/pos/api/v1/production/sources',
      authToken: token,
    );
    final raw = response.data['data'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(ProductionSource.fromJson)
        .toList();
  }

  Future<ProductionRecipePreview> fetchRecipePreview({
    required String token,
    required int itemId,
  }) async {
    final response = await _client.getJson(
      '/pos/api/v1/production/sources/$itemId/recipe',
      authToken: token,
    );
    final raw = response.data['data'];
    if (raw is! Map<String, dynamic>) return const ProductionRecipePreview();
    return ProductionRecipePreview.fromJson(raw);
  }

  Future<ProductionRun> createRun({
    required String token,
    required int itemId,
    required double quantity,
    Map<int, double> componentOverrides = const {},
    String? note,
  }) async {
    final response = await _client.postJson(
      '/pos/api/v1/production/runs',
      authToken: token,
      body: {
        'item_id': itemId,
        'quantity': quantity,
        if (componentOverrides.isNotEmpty)
          'component_overrides': componentOverrides.map(
            (itemId, qty) => MapEntry(itemId.toString(), qty),
          ),
        if (note != null && note.isNotEmpty) 'note': note,
      },
    );
    final raw = response.data['data'];
    return ProductionRun.fromJson(raw is Map<String, dynamic> ? raw : {});
  }

  Future<List<ProductionRun>> fetchRuns({required String token}) async {
    final response = await _client.getJson(
      '/pos/api/v1/production/runs',
      authToken: token,
    );
    final raw = response.data['data'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(ProductionRun.fromJson)
        .toList();
  }

  Future<void> voidRun({required String token, required int runId}) async {
    await _client.postJson(
      '/pos/api/v1/production/runs/$runId/void',
      authToken: token,
    );
  }
}
