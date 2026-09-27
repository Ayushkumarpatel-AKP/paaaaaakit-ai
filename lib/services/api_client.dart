import 'dart:convert';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:http/http.dart' as http;

/// Thrown when the backend is unreachable or returns an error.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// Thin typed wrapper around the PackIT AI FastAPI backend.
///
/// Every screen calls into this; when the backend is down the screens keep
/// their bundled sample data, so the demo never hard-fails.
///
/// Point it elsewhere at build time:
/// `flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000`
class ApiClient {
  ApiClient._();

  static final ApiClient instance = ApiClient._();

  static const String _definedBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );

  /// Android emulators reach the host machine via 10.0.2.2, not localhost.
  static String get baseUrl {
    if (_definedBaseUrl.isNotEmpty) return _definedBaseUrl;
    if (kIsWeb) return 'http://localhost:8000';
    return defaultTargetPlatform == TargetPlatform.android
        ? 'http://10.0.2.2:8000'
        : 'http://localhost:8000';
  }

  static const Duration _timeout = Duration(seconds: 12);

  /// Set to true by the last successful request; the UI uses this to show an
  /// "offline / sample data" badge.
  bool lastCallSucceeded = false;
  String? lastError;

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final normalized = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$baseUrl$normalized').replace(
      queryParameters: query?.map((k, v) => MapEntry(k, '$v')),
    );
  }

  Future<Map<String, dynamic>> _decode(http.Response response) async {
    if (response.statusCode >= 400) {
      throw ApiException(
        'backend returned ${response.statusCode}: ${response.body}',
        statusCode: response.statusCode,
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) return decoded;
    return {'data': decoded};
  }

  Future<List<dynamic>> _decodeList(http.Response response) async {
    if (response.statusCode >= 400) {
      throw ApiException(
        'backend returned ${response.statusCode}: ${response.body}',
        statusCode: response.statusCode,
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is List) return decoded;
    throw ApiException('expected a JSON list');
  }

  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    try {
      final response = await http.get(_uri(path, query)).timeout(_timeout);
      final result = await _decode(response);
      lastCallSucceeded = true;
      return result;
    } catch (error) {
      lastCallSucceeded = false;
      lastError = error.toString();
      rethrow;
    }
  }

  Future<List<dynamic>> getList(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    try {
      final response = await http.get(_uri(path, query)).timeout(_timeout);
      final result = await _decodeList(response);
      lastCallSucceeded = true;
      return result;
    } catch (error) {
      lastCallSucceeded = false;
      lastError = error.toString();
      rethrow;
    }
  }

  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    try {
      final response = await http
          .post(
            _uri(path),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      final result = await _decode(response);
      lastCallSucceeded = true;
      return result;
    } catch (error) {
      lastCallSucceeded = false;
      lastError = error.toString();
      rethrow;
    }
  }

  // -------------------------------------------------------------------------
  // Endpoints
  // -------------------------------------------------------------------------

  Future<Map<String, dynamic>> health() => getJson('/health');

  Future<Map<String, dynamic>> createProduct(Map<String, dynamic> spec) =>
      postJson('/products', spec);

  Future<Map<String, dynamic>> getProduct(String productId) =>
      getJson('/products/$productId');

  Future<Map<String, dynamic>> generateRecommendations(String productId) =>
      postJson('/recommendations/generate', {'productId': productId});

  Future<Map<String, dynamic>> latestRecommendations(String productId) =>
      getJson('/recommendations/$productId');

  Future<Map<String, dynamic>> simulateDigitalTwin(
    Map<String, dynamic> request,
  ) => postJson('/simulate/digital-twin', request);

  Future<Map<String, dynamic>> simulateShelfLife(
    Map<String, dynamic> request,
  ) => postJson('/simulate/shelf-life', request);

  Future<Map<String, dynamic>> recalculateStack({
    required List<Map<String, dynamic>> layers,
    double areaM2 = 0.05,
    int units = 1000,
    String? productId,
  }) => postJson('/layerstack/recalculate', {
    'layers': layers,
    'areaM2': areaM2,
    'units': units,
    if (productId != null) 'productId': productId,
  });

  Future<Map<String, dynamic>> calculateLca(Map<String, dynamic> request) =>
      postJson('/lca/calculate', request);

  /// Shared material database with Indian-market film prices (₹/kg).
  Future<List<dynamic>> lcaMaterials() => getList('/lca/materials');

  Future<Map<String, dynamic>> analyzeImage({
    required List<int> bytes,
    required String filename,
    String? productId,
  }) async {
    try {
      final request = http.MultipartRequest('POST', _uri('/audit/analyze'))
        ..files.add(
          http.MultipartFile.fromBytes('image', bytes, filename: filename),
        );
      if (productId != null) request.fields['productId'] = productId;

      final streamed = await request.send().timeout(_timeout);
      final response = await http.Response.fromStream(streamed);
      final result = await _decode(response);
      lastCallSucceeded = true;
      return result;
    } catch (error) {
      lastCallSucceeded = false;
      lastError = error.toString();
      rethrow;
    }
  }

  Future<Map<String, dynamic>> sendChatMessage({
    required String sessionId,
    required String message,
    String? productId,
    String? simId,
  }) => postJson('/chat/message', {
    'sessionId': sessionId,
    'message': message,
    if (productId != null) 'productId': productId,
    if (simId != null) 'simId': simId,
  });

  Future<List<dynamic>> getChatMessages(String sessionId) =>
      getList('/chat/$sessionId/messages');

  Future<Map<String, dynamic>> suppliers({
    String? material,
    String? location,
    String? certification,
    double? plantLat,
    double? plantLng,
    String shippingMode = 'road',
    double massKg = 1000,
  }) => getJson(
    '/suppliers',
    query: {
      if (material != null && material.isNotEmpty) 'material': material,
      if (location != null && location.isNotEmpty) 'location': location,
      if (certification != null && certification.isNotEmpty)
        'certification': certification,
      if (plantLat != null) 'plantLat': plantLat,
      if (plantLng != null) 'plantLng': plantLng,
      'shippingMode': shippingMode,
      'massKg': massKg,
    },
  );

  Future<Map<String, dynamic>> sendRfq(
    String supplierId,
    Map<String, dynamic> body,
  ) => postJson('/suppliers/$supplierId/rfq', body);

  Future<Map<String, dynamic>> dashboardSummary({String userId = 'demo-user'}) =>
      getJson('/dashboard/summary', query: {'userId': userId});

  Future<List<dynamic>> recentFeed({
    String userId = 'demo-user',
    int limit = 10,
  }) => getList('/dashboard/recent-feed', query: {
    'userId': userId,
    'limit': limit,
  });

  Future<Map<String, dynamic>> history({
    String userId = 'demo-user',
    String? search,
    String? category,
    int limit = 50,
  }) => getJson(
    '/history',
    query: {
      'userId': userId,
      if (search != null && search.isNotEmpty) 'search': search,
      if (category != null && category.isNotEmpty) 'category': category,
      'limit': limit,
    },
  );

  /// URL the app opens to download a generated PDF report.
  String reportExportUrl(String projectId) =>
      '$baseUrl/reports/export/$projectId';
}
