import '../api/api_client.dart';
import '../storage/secure_store.dart';

class CfdMediaItem {
  const CfdMediaItem({required this.type, required this.url, this.duration});
  final String type;
  final String url;
  final int? duration;
}

class CfdSettings {
  const CfdSettings({
    required this.displayType,
    required this.slideDuration,
    required this.mediaItems,
  });
  final String displayType;
  final int slideDuration;
  final List<CfdMediaItem> mediaItems;

  List<CfdMediaItem> get imageItems =>
      mediaItems.where((m) => m.type == 'image' && m.url.isNotEmpty).toList();
}

class CfdSettingsService {
  static final CfdSettingsService _instance = CfdSettingsService._();
  factory CfdSettingsService() => _instance;
  CfdSettingsService._();

  final _api = ApiClient();
  final _store = const SecureStore();

  Future<CfdSettings?> getSettings() async {
    try {
      final token = await _store.readToken();
      final response = await _api.getJson(
        '/pos/api/v1/cfd_settings',
        authToken: token,
      );
      final data =
          (response.data['data'] as Map<String, dynamic>?) ?? response.data;
      final rawItems = data['media_items'] as List<dynamic>? ?? [];
      final mediaItems = rawItems
          .map((item) => CfdMediaItem(
                type: item['type'] as String? ?? 'image',
                url: item['url'] as String? ?? '',
                duration: (item['duration'] as num?)?.toInt(),
              ))
          .where((item) => item.url.isNotEmpty)
          .toList();
      return CfdSettings(
        displayType: data['display_type'] as String? ?? 'static_image',
        slideDuration: (data['slide_duration'] as num?)?.toInt() ?? 5,
        mediaItems: mediaItems,
      );
    } catch (_) {
      return null;
    }
  }
}
