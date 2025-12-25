import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_exception.dart';
import 'app_config.dart';

class ApiClient {
  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Uri buildUri(String path, [Map<String, String>? queryParameters]) {
    final base = Uri.parse(AppConfig.baseUrl);
    return base.replace(
      path: _normalizePath(base.path, path),
      queryParameters: queryParameters,
    );
  }

  Future<ApiResponse> getJson(String path,
      {Map<String, String>? queryParameters,
      Map<String, String>? headers,
      String? authToken}) async {
    final uri = buildUri(path, queryParameters);
    final response = await _client
        .get(uri, headers: _defaultHeaders(headers, authToken: authToken))
        .timeout(AppConfig.requestTimeout);
    return _decodeResponse(response);
  }

  Future<ApiResponse> postJson(String path,
      {Object? body, Map<String, String>? headers, String? authToken}) async {
    final uri = buildUri(path);
    final response = await _client
        .post(
          uri,
          headers: _defaultHeaders(headers, authToken: authToken),
          body: body == null ? null : jsonEncode(body),
        )
        .timeout(AppConfig.requestTimeout);
    return _decodeResponse(response);
  }

  Future<ApiStatus> ping() async {
    final uri = buildUri('/');
    try {
      final response = await _client
          .head(uri)
          .timeout(AppConfig.requestTimeout);
      return ApiStatus(
        isReachable: response.statusCode >= 200 && response.statusCode < 400,
        statusCode: response.statusCode,
      );
    } catch (error) {
      return ApiStatus(isReachable: false, errorMessage: error.toString());
    }
  }

  Map<String, String> _defaultHeaders(
    Map<String, String>? headers, {
    String? authToken,
  }) {
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (authToken != null && authToken.isNotEmpty) 'authtoken': authToken,
      if (headers != null) ...headers,
    };
  }

  ApiResponse _decodeResponse(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        response.body.isEmpty ? 'Unexpected response.' : response.body,
        statusCode: response.statusCode,
      );
    }

    if (response.body.isEmpty) {
      return const ApiResponse({});
    }

    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      return ApiResponse(decoded);
    }

    return ApiResponse({'data': decoded});
  }

  String _normalizePath(String basePath, String path) {
    if (path.isEmpty) {
      return basePath;
    }
    if (path.startsWith('/')) {
      return path;
    }
    if (basePath.isEmpty || basePath == '/') {
      return '/$path';
    }
    return '$basePath/$path';
  }
}

class ApiResponse {
  const ApiResponse(this.data);

  final Map<String, dynamic> data;
}

class ApiStatus {
  ApiStatus({
    required this.isReachable,
    this.statusCode,
    this.errorMessage,
  });

  final bool isReachable;
  final int? statusCode;
  final String? errorMessage;
}
