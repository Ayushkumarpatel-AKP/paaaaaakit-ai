import 'api_client.dart';

/// Lightweight in-memory session state shared across screens.
///
/// Holds the ids that chain the flow together (product -> simulation ->
/// recommendations) plus whether the backend answered, so screens can show an
/// "offline / sample data" hint instead of pretending.
class AppSession {
  AppSession._();

  static final AppSession instance = AppSession._();

  final ApiClient api = ApiClient.instance;

  /// Backend `productId` for the product currently being engineered.
  String? productId;

  /// Latest digital-twin `simId` (used by the chat assistant context).
  String? simId;

  /// Latest shelf-life prediction in days, when the backend answered.
  double? predictedShelfLifeDays;

  /// Stable chat session id.
  final String chatSessionId =
      'sess_${DateTime.now().millisecondsSinceEpoch}';

  /// True when the most recent backend call succeeded.
  bool get isOnline => api.lastCallSucceeded;

  String? get lastError => api.lastError;

  void rememberProduct(String id) => productId = id;

  /// Returns the active product id, creating a demo product when a screen is
  /// opened directly from the dashboard and no wizard run has happened yet.
  Future<String?> ensureProduct() async {
    if (productId != null) return productId;
    try {
      final created = await api.createProduct({
        'name': 'Digital Twin Demo',
        'category': 'snacks',
        'waterActivity': 0.3,
        'fatContent': 25.0,
        'oxygenSensitivity': 'high',
        'lightSensitivity': 'medium',
        'targetShelfLifeDays': 180,
        'minTempC': 15,
        'maxTempC': 30,
        'packagingFormat': 'Flexible laminate pouch',
        'budgetPer1kUnits': 40,
      });
      rememberProduct('${created['id']}');
      return productId;
    } catch (_) {
      return null;
    }
  }

  void rememberSimulation(String id) => simId = id;

  void clear() {
    productId = null;
    simId = null;
    predictedShelfLifeDays = null;
  }
}
