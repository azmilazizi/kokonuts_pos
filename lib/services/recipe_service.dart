import '../api/api_client.dart';
import '../models/product_recipe.dart';

class RecipeService {
  RecipeService({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  Future<ProductRecipe> fetchRecipe({
    required String token,
    required String itemId,
    List<String> modifierIds = const [],
  }) async {
    final query = <String, String>{
      if (modifierIds.isNotEmpty) 'modifier_ids': modifierIds.join(','),
    };
    final response = await _client.getJson(
      '/pos/api/v1/items/$itemId/recipe',
      queryParameters: query.isEmpty ? null : query,
      authToken: token,
    );
    final raw = response.data['data'];
    if (raw is! Map<String, dynamic>) return const ProductRecipe();
    return ProductRecipe.fromJson(raw);
  }
}
