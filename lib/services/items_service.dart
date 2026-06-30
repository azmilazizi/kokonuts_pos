import '../api/api_client.dart';
import '../models/pos_group.dart';
import '../models/pos_item.dart';
import '../models/pos_modifier_group.dart';

class ItemsService {
  ItemsService({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  Future<List<PosItem>> fetchItems(String token) async {
    final response = await _client.getJson(
      '/pos/api/v1/items',
      authToken: token,
    );
    final raw = response.data['data'] ?? response.data['items'] ?? response.data.values.firstOrNull;
    if (raw is! List) return [];
    final items = <PosItem>[];
    for (final entry in raw) {
      if (entry is Map<String, dynamic>) {
        final item = PosItem.fromJson(entry);
        if (item != null) items.add(item);
      }
    }
    return items;
  }

  Future<List<PosGroup>> fetchGroups(String token) async {
    final response = await _client.getJson(
      '/pos/api/v1/sub_groups',
      authToken: token,
    );
    final raw = response.data['data'] ?? response.data['sub_groups'] ?? response.data.values.firstOrNull;
    if (raw is! List) return [];
    final groups = <PosGroup>[];
    for (final entry in raw) {
      if (entry is Map<String, dynamic>) {
        final group = PosGroup.fromJson(entry);
        if (group != null) groups.add(group);
      }
    }
    return groups;
  }

  Future<List<BundleModifierGroup>> fetchBundleModifierGroups(
      String token, String itemId) async {
    final response = await _client.getJson(
      '/pos/api/item/$itemId',
      authToken: token,
    );
    final raw = response.data['bundle_modifier_groups'];
    if (raw is! List) return [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(BundleModifierGroup.fromJson)
        .toList();
  }

  Future<List<PosModifierGroup>> fetchModifierGroups(String token) async {
    final response = await _client.getJson(
      '/pos/api/v1/modifiers',
      authToken: token,
    );
    final raw = response.data['data'] ?? response.data['modifiers'] ?? response.data.values.firstOrNull;
    if (raw is! List) return [];
    final groups = <PosModifierGroup>[];
    for (final entry in raw) {
      if (entry is Map<String, dynamic>) {
        final group = PosModifierGroup.fromJson(entry);
        if (group != null) groups.add(group);
      }
    }
    return groups;
  }
}
