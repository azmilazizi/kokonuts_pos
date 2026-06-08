import '../api/api_client.dart';
import '../models/pos_customer.dart';

class CustomerPage {
  const CustomerPage({required this.members, required this.hasMore});
  final List<PosCustomer> members;
  final bool hasMore;
}

class CustomerService {
  CustomerService({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  Future<CustomerPage> fetchMembers(
    String token, {
    int page = 1,
    String? query,
  }) async {
    final params = <String, String>{'page': '$page'};
    if (query != null && query.trim().isNotEmpty) {
      params['q'] = query.trim();
    }
    final response = await _client.getJson(
      '/pos/api/v1/loyalty/members',
      queryParameters: params,
      authToken: token,
    );

    // The API may return the paginator directly or nested under a 'data' key.
    // Resolve the map that contains both the items list and pagination fields.
    final Map<String, dynamic> paginator;
    final top = response.data['data'];
    if (top is Map<String, dynamic>) {
      // Wrapped: { "data": { "data": [...], "current_page": 1, ... } }
      paginator = top;
    } else {
      // Flat: { "data": [...], "current_page": 1, ... }
      paginator = response.data;
    }

    // The items list may be at paginator['data'] or be the first List value.
    final rawList = paginator['data'] is List
        ? paginator['data'] as List
        : paginator.values.whereType<List>().firstOrNull ?? const [];

    final members = <PosCustomer>[];
    for (final entry in rawList) {
      if (entry is Map<String, dynamic>) {
        final c = PosCustomer.fromJson(entry);
        if (c != null) members.add(c);
      }
    }

    // Support { meta: { last_page, current_page } } and flat pagination fields.
    final meta = paginator['meta'];
    final Map<String, dynamic> paginationSource =
        meta is Map<String, dynamic> ? meta : paginator;
    final lastPage = _parseIntField(paginationSource['last_page']);
    final currentPage = _parseIntField(paginationSource['current_page']);
    final hasMore =
        lastPage != null && currentPage != null && currentPage < lastPage;

    return CustomerPage(members: members, hasMore: hasMore);
  }

  static int? _parseIntField(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    return int.tryParse(value.toString());
  }
}
