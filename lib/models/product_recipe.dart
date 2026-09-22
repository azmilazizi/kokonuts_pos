class RecipeIngredient {
  const RecipeIngredient({
    required this.name,
    required this.quantity,
    required this.uom,
    this.note = '',
    this.isServingUnit = false,
  });

  final String name;
  final double quantity;
  final String uom;
  final String note;
  final bool isServingUnit;

  static RecipeIngredient fromJson(Map<String, dynamic> json) {
    return RecipeIngredient(
      name: json['name']?.toString().trim() ?? '',
      quantity: double.tryParse(json['quantity']?.toString() ?? '') ?? 0.0,
      uom: json['uom']?.toString().trim() ?? '',
      note: json['note']?.toString().trim() ?? '',
      isServingUnit: json['is_serving_unit'] == true,
    );
  }
}

class ProductRecipe {
  const ProductRecipe({
    this.mixedIngredients = const [],
    this.ingredients = const [],
    this.packaging = const [],
  });

  final List<RecipeIngredient> mixedIngredients;
  final List<RecipeIngredient> ingredients;
  final List<RecipeIngredient> packaging;

  bool get isEmpty =>
      mixedIngredients.isEmpty && ingredients.isEmpty && packaging.isEmpty;

  static ProductRecipe fromJson(Map<String, dynamic> json) {
    final sections = json['sections'];
    if (sections is! Map<String, dynamic>) return const ProductRecipe();

    List<RecipeIngredient> parseList(dynamic raw) {
      if (raw is! List) return const [];
      return raw
          .whereType<Map<String, dynamic>>()
          .map(RecipeIngredient.fromJson)
          .toList();
    }

    return ProductRecipe(
      mixedIngredients: parseList(sections['mixed_ingredients']),
      ingredients: parseList(sections['ingredients']),
      packaging: parseList(sections['packaging']),
    );
  }
}
