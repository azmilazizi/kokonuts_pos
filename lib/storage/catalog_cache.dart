import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../models/pos_group.dart';
import '../models/pos_item.dart';
import '../models/pos_modifier_group.dart';
import '../services/items_service.dart';
import '../services/payment_mode_service.dart';
import 'local_db.dart';

class CatalogSnapshot {
  const CatalogSnapshot({
    required this.items,
    required this.groups,
    required this.modifierGroups,
    required this.paymentModes,
  });

  final List<PosItem> items;
  final List<PosGroup> groups;
  final List<PosModifierGroup> modifierGroups;
  final List<PaymentMode> paymentModes;

  bool get hasData => items.isNotEmpty;
}

class CatalogCache {
  static final CatalogCache instance = CatalogCache._();
  CatalogCache._();

  Future<CatalogSnapshot> loadCached() async {
    final db = await LocalDb.instance.db;
    final items = await _loadItems(db);
    final groups = await _loadGroups(db);
    final modifierGroups = await _loadModifierGroups(db);
    final paymentModes = await _loadPaymentModes(db);
    return CatalogSnapshot(
      items: items,
      groups: groups,
      modifierGroups: modifierGroups,
      paymentModes: paymentModes,
    );
  }

  Future<CatalogSnapshot> refreshFromApi(String token) async {
    final service = ItemsService();
    final results = await Future.wait([
      service.fetchItems(token),
      service.fetchGroups(token),
      service.fetchModifierGroups(token),
    ]);

    // Payment modes are fetched separately so a failure there never blocks
    // items from loading.
    List<PaymentMode> paymentModes = [];
    try {
      paymentModes = await PaymentModeService().fetchPaymentModes(token);
    } catch (_) {}

    final snapshot = CatalogSnapshot(
      items: results[0] as List<PosItem>,
      groups: results[1] as List<PosGroup>,
      modifierGroups: results[2] as List<PosModifierGroup>,
      paymentModes: paymentModes,
    );
    // A concurrent background refresh may already hold the DB write lock.
    // A failed cache write is non-fatal — the snapshot is still valid and
    // will be applied to the UI immediately; the next refresh will retry.
    try {
      await _save(snapshot);
    } catch (_) {}
    return snapshot;
  }

  Future<void> _save(CatalogSnapshot snapshot) async {
    final db = await LocalDb.instance.db;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      await txn.delete('catalog_items');
      for (final item in snapshot.items) {
        await txn.insert('catalog_items', {
          'id': item.id,
          'name': item.name,
          'price': item.price,
          'group_id': item.groupId,
          'modifier_group_ids': jsonEncode(item.modifierGroupIds),
          'bundle_modifier_groups': jsonEncode(item.bundleModifierGroups
              .map((g) => {
                    'id': g.id,
                    'name': g.name,
                    'selection_type': g.selectionType,
                    'min_selections': g.minSelections.toString(),
                    'max_selections': g.maxSelections.toString(),
                    'active': '1',
                    'modifiers': g.modifiers
                        .map((m) => {
                              'id': m.id,
                              'name': m.name,
                              'price_adjustment':
                                  m.priceAdjustment.toStringAsFixed(2),
                              'sort_order': m.sortOrder.toString(),
                              'option_type': m.optionType,
                              'source_id': m.sourceId,
                            })
                        .toList(),
                  })
              .toList()),
          'updated_ms': now,
        });
      }

      await txn.delete('catalog_groups');
      for (final g in snapshot.groups) {
        await txn.insert('catalog_groups', {
          'id': g.id,
          'name': g.name,
          'updated_ms': now,
        });
      }

      await txn.delete('catalog_modifier_groups');
      await txn.delete('catalog_modifiers');
      for (final mg in snapshot.modifierGroups) {
        await txn.insert('catalog_modifier_groups', {
          'id': mg.id,
          'name': mg.name,
          'selection_type': mg.selectionType,
          'min_selections': mg.minSelections,
          'max_selections': mg.maxSelections,
          'updated_ms': now,
        });
        for (final mod in mg.modifiers) {
          await txn.insert('catalog_modifiers', {
            'id': mod.id,
            'modifier_group_id': mg.id,
            'name': mod.name,
            'price_adjustment': mod.priceAdjustment,
            'sort_order': mod.sortOrder,
          });
        }
      }

      await txn.delete('catalog_payment_modes');
      for (final pm in snapshot.paymentModes) {
        await txn.insert('catalog_payment_modes', {
          'id': pm.id,
          'name': pm.name,
        });
      }
    });
  }

  Future<List<PosItem>> _loadItems(Database db) async {
    final rows = await db.query('catalog_items');
    return rows.map((row) {
      final ids = jsonDecode(row['modifier_group_ids'] as String) as List;
      final rawBundle =
          jsonDecode(row['bundle_modifier_groups'] as String? ?? '[]') as List;
      final bundleGroups = rawBundle
          .whereType<Map<String, dynamic>>()
          .map(BundleModifierGroup.fromJson)
          .toList();
      return PosItem(
        id: row['id'] as String,
        name: row['name'] as String,
        price: (row['price'] as num).toDouble(),
        groupId: row['group_id'] as String,
        barcode: '',
        skuCode: '',
        modifierGroupIds: ids.map((e) => e.toString()).toList(),
        bundleModifierGroups: bundleGroups,
      );
    }).toList();
  }

  Future<List<PosGroup>> _loadGroups(Database db) async {
    final rows = await db.query('catalog_groups');
    return rows
        .map((row) => PosGroup(
              id: row['id'] as String,
              name: row['name'] as String,
            ))
        .toList();
  }

  Future<List<PosModifierGroup>> _loadModifierGroups(Database db) async {
    final mgRows = await db.query('catalog_modifier_groups');
    final modRows = await db.query('catalog_modifiers');

    final modsByGroup = <String, List<PosModifier>>{};
    for (final row in modRows) {
      final groupId = row['modifier_group_id'] as String;
      modsByGroup.putIfAbsent(groupId, () => []).add(PosModifier(
            id: row['id'] as String,
            name: row['name'] as String,
            priceAdjustment: (row['price_adjustment'] as num).toDouble(),
            sortOrder: row['sort_order'] as int,
          ));
    }

    return mgRows.map((row) {
      final id = row['id'] as String;
      return PosModifierGroup(
        id: id,
        name: row['name'] as String,
        selectionType: row['selection_type'] as String,
        minSelections: row['min_selections'] as int,
        maxSelections: row['max_selections'] as int,
        modifiers: modsByGroup[id] ?? [],
      );
    }).toList();
  }

  Future<List<PaymentMode>> _loadPaymentModes(Database db) async {
    final rows = await db.query('catalog_payment_modes');
    return rows
        .map((row) => PaymentMode(
              id: row['id'] as String,
              name: row['name'] as String,
            ))
        .toList();
  }
}
