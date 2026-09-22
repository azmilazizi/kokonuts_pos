import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import '../models/product_recipe.dart';
import '../services/recipe_service.dart';
import '../storage/secure_store.dart';

String _formatRecipeQty(double qty) {
  return qty == qty.roundToDouble()
      ? qty.toStringAsFixed(0)
      : qty.toStringAsFixed(2);
}

// Serving-unit rows (scoop, cup, etc.) read better as a kitchen fraction
// ("1½ scoop") than a decimal; metric BOM rows (kg/g/ml) keep plain decimals
// via _formatRecipeQty, since nobody measures grams in halves/thirds.
final Map<double, String> _fractionGlyphs = {
  0.25: '¼',
  1 / 3: '⅓',
  0.5: '½',
  2 / 3: '⅔',
  0.75: '¾',
};

String _formatServingQty(double qty) {
  const tolerance = 0.04;
  var whole = qty.floor();
  var frac = qty - whole;

  if (frac >= 1 - tolerance) {
    whole += 1;
    frac = 0;
  }
  if (frac < tolerance) {
    return '$whole';
  }
  for (final entry in _fractionGlyphs.entries) {
    if ((frac - entry.key).abs() < tolerance) {
      return whole > 0 ? '$whole${entry.value}' : entry.value;
    }
  }
  return _formatRecipeQty(qty);
}

Widget _buildRecipeSection(String label, List<RecipeIngredient> rows) {
  if (rows.isEmpty) return const SizedBox.shrink();
  return Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Color(0xFF9E9E9E),
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 6),
        ...rows.map((row) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 6, right: 8),
                    child: Icon(Icons.circle, size: 5, color: Colors.black54),
                  ),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        style: const TextStyle(fontSize: 14, color: Colors.black87, height: 1.4),
                        children: [
                          TextSpan(
                            text: '${row.isServingUnit ? _formatServingQty(row.quantity) : _formatRecipeQty(row.quantity)}${row.uom.isNotEmpty ? ' ${row.uom}' : ''}  ',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          TextSpan(text: row.name),
                          if (row.note.isNotEmpty)
                            TextSpan(
                              text: '  (${row.note})',
                              style: const TextStyle(color: Color(0xFF9E9E9E), fontSize: 12),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            )),
      ],
    ),
  );
}

/// Shows a product's resolved recipe (from the backend BOM, respecting
/// Alternate For / Requires against [modifierIds]) in a dialog sized for
/// tablet/phone. Falls back to [instructions] (legacy manually-typed HTML)
/// when the item has no recipe configured, and to a plain message when
/// neither is available.
///
/// Note: the recipe is always resolved against the item's *current* BOM —
/// there's no historical snapshot, so viewing this for an old receipt shows
/// today's recipe for that item/modifier combo, not necessarily what was
/// actually used at the time of that specific sale if the recipe has since
/// been edited.
void showRecipeDialog(
  BuildContext context, {
  required String itemId,
  required String itemName,
  List<String> modifierIds = const [],
  String instructions = '',
}) {
  final size = MediaQuery.of(context).size;
  final maxWidth = size.width < 600 ? size.width * 0.92 : 640.0;
  final maxHeight = size.height * 0.8;

  Future<ProductRecipe> loadRecipe() async {
    final token = await const SecureStore().readToken() ?? '';
    return RecipeService().fetchRecipe(
      token: token,
      itemId: itemId,
      modifierIds: modifierIds,
    );
  }

  showDialog<void>(
    context: context,
    builder: (ctx) => MediaQuery(
      data: MediaQuery.of(ctx).copyWith(viewInsets: EdgeInsets.zero),
      child: Dialog(
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        itemName,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const Divider(height: 1),
                const SizedBox(height: 14),
                Flexible(
                  child: SingleChildScrollView(
                    child: FutureBuilder<ProductRecipe>(
                      future: loadRecipe(),
                      builder: (ctx, snapshot) {
                        if (snapshot.connectionState != ConnectionState.done) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 32),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }

                        final recipe = snapshot.data;
                        if (snapshot.hasError || recipe == null || recipe.isEmpty) {
                          if (instructions.trim().isNotEmpty) {
                            return HtmlWidget(
                              instructions,
                              textStyle: const TextStyle(fontSize: 14, height: 1.45, color: Colors.black87),
                            );
                          }
                          return const Text(
                            'No recipe or instructions added for this item.',
                            style: TextStyle(fontSize: 14, color: Color(0xFF9E9E9E)),
                          );
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildRecipeSection('Mixed Ingredients', recipe.mixedIngredients),
                            _buildRecipeSection('Ingredients', recipe.ingredients),
                            _buildRecipeSection('Packaging', recipe.packaging),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
