import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'models/food_item.dart';
import 'data/sample_data.dart';
import 'services/app_session.dart';
import 'screens/splash_screen.dart';
import 'screens/home_dashboard_screen.dart';
import 'screens/product_input_screen.dart';
import 'screens/storage_conditions_screen.dart';
import 'screens/recommendation_result_screen.dart';
import 'screens/packaging_customizer_screen.dart';
import 'screens/digital_twin_simulator_screen.dart';
import 'screens/shelf_life_prediction_screen.dart';
import 'screens/packaging_auditor_screen.dart';
import 'screens/ai_chat_assistant_screen.dart';
import 'screens/supplier_traceability_screen.dart';
import 'screens/history_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PackITApp());
}

class PackITApp extends StatefulWidget {
  const PackITApp({super.key});

  @override
  State<PackITApp> createState() => _PackITAppState();
}

class _PackITAppState extends State<PackITApp> {
  bool _isDarkMode = false;
  bool _hasStarted = false;

  void _toggleTheme() {
    setState(() {
      _isDarkMode = !_isDarkMode;
    });
  }

  void _handleGetStarted() {
    setState(() {
      _hasStarted = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'PackIT AI - Smart Packaging Assistant',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: _isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: _hasStarted
          ? MainShell(
              isDarkMode: _isDarkMode,
              onToggleTheme: _toggleTheme,
            )
          : SplashScreen(onGetStarted: _handleGetStarted),
    );
  }
}

class MainShell extends StatefulWidget {
  final bool isDarkMode;
  final VoidCallback onToggleTheme;

  const MainShell({
    super.key,
    required this.isDarkMode,
    required this.onToggleTheme,
  });

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentTabIndex = 0;
  String _activeScreenRoute = 'home'; // 'home', 'product_input', etc.
  Map<String, dynamic> _currentProductData = {};
  FoodProduct _currentProduct = SampleData.products[0];

  void _navigateTo(String route, {dynamic arguments}) {
    setState(() {
      _activeScreenRoute = route;
      if (arguments is Map<String, dynamic>) {
        _currentProductData = arguments;
      } else if (arguments is FoodProduct) {
        _currentProduct = arguments;
      }
    });
  }  /// The category the user picked in the wizard. `completeData['category']` is a
  /// [FoodCategory] enum; older callers may pass a label string.
  FoodCategory _categoryFrom(Map<String, dynamic> data, FoodCategory fallback) {
    final raw = data['category'];
    if (raw is FoodCategory) return raw;
    final text = '${raw ?? ''}'.toLowerCase();
    if (text.isEmpty) return fallback;
    for (final category in FoodCategory.values) {
      if (text.contains(category.name.toLowerCase()) ||
          text.contains(category.label.toLowerCase())) {
        return category;
      }
    }
    return fallback;
  }

  /// Water activity is not measured anywhere in the wizard, so estimate it from
  /// the food family and moisture content. Fresh/perishable families sit near
  /// 1.0; dry products follow their moisture content. Replace with a real
  /// measurement when one becomes available.
  double _estimateWaterActivity(FoodCategory category, double moisturePct) {
    switch (category) {
      case FoodCategory.dairy:
      case FoodCategory.beverages:
      case FoodCategory.meatSeafood:
      case FoodCategory.readyToEat:
      case FoodCategory.fruitsVegetables:
        return 0.97;
      case FoodCategory.snacks:
      case FoodCategory.bakery:
      case FoodCategory.grainsPulses:
      case FoodCategory.others:
        return (0.20 + moisturePct * 0.03).clamp(0.10, 0.95);
    }
  }

  /// Best-effort template lookup by name. Only supplies values the wizard does
  /// not collect — never anything that drives the physics.
  FoodProduct _closestSample(String name) {
    final needle = name.trim().toLowerCase();
    if (needle.isEmpty) return SampleData.products[0];
    return SampleData.products.firstWhere(
      (p) =>
          p.name.toLowerCase().contains(needle) ||
          needle.contains(p.name.toLowerCase()),
      orElse: () => SampleData.products[0],
    );
  }

  /// Builds the product the user actually described, using a bundled sample only
  /// as a template for the fields the wizard never collects (reference layer
  /// stack, messaging strings).
  FoodProduct _productFromInputs(
    Map<String, dynamic> data,
    FoodProduct template,
  ) {
    final category = _categoryFrom(data, template.category);
    final name = '${data['name'] ?? ''}'.trim();
    return FoodProduct(
      id: template.id,
      name: name.isEmpty ? template.name : name,
      category: category,
      imageUrl: '${data['imageUrl'] ?? template.imageUrl}',
      moistureContent: (data['moisture'] as num?)?.toDouble() ??
          template.moistureContent,
      oilFatContent:
          (data['oilFat'] as num?)?.toDouble() ?? template.oilFatContent,
      phValue: (data['ph'] as num?)?.toDouble() ?? template.phValue,
      waterActivity: template.waterActivity,
      defaultShelfLifeMonths: template.defaultShelfLifeMonths,
      recommendedLayers: template.recommendedLayers,
      otr: template.otr,
      wvtr: template.wvtr,
      totalThickness: template.totalThickness,
      sealability: template.sealability,
      mechanicalStrength: template.mechanicalStrength,
      mapSuitability: template.mapSuitability,
      matchScore: template.matchScore,
    );
  }

  /// Creates the product on the backend so every downstream screen (auditor,
  /// recommendations, digital twin, LCA, reports) has a real `productId`.
  ///
  /// Every field comes from what the user entered in the wizard — `matched` is
  /// only a fallback for values the form does not collect.
  Future<void> _registerProduct(
    Map<String, dynamic> completeData,
    FoodProduct matched,
  ) async {
    final shelfLifeDays = _resolveShelfLifeDays(completeData);
    final storageTemp =
        ((completeData['storageTemp'] as num?)?.toDouble() ?? 25.0);
    final humidity =
        ((completeData['humidity'] as num?)?.toDouble() ?? 60.0);
    final category = _categoryFrom(completeData, matched.category);

    final moisture = (completeData['moisture'] as num?)?.toDouble() ?? 0.0;
    final fat = (completeData['oilFat'] as num?)?.toDouble() ?? 0.0;
    final ph = (completeData['ph'] as num?)?.toDouble() ?? 7.0;
    final budget = (completeData['budgetMax'] as num?)?.toDouble() ?? 0.0;
    final productName = '${completeData['name'] ?? ''}'.trim();

    // Sensitivity is derived from the product's own numbers instead of a
    // hardcoded list of category names.
    final oxygenSensitivity = fat >= 20
        ? 'high'
        : (fat >= 5 || moisture >= 30 ? 'medium' : 'low');
    final lightSensitivity = (fat >= 20 || storageTemp > 30) ? 'high' : 'medium';

    try {
      final product = await AppSession.instance.api.createProduct({
        'name': productName.isEmpty ? matched.name : productName,
        'category': category.name,
        'waterActivity': _estimateWaterActivity(category, moisture),
        'fatContent': fat,
        'oxygenSensitivity': oxygenSensitivity,
        'lightSensitivity': lightSensitivity,
        'targetShelfLifeDays': shelfLifeDays,
        'minTempC': storageTemp - 5,
        'maxTempC': storageTemp + 5,
        'packagingFormat': '${category.label} flexible laminate',
        'budgetPer1kUnits': budget,
        // Consumed once the backend schema accepts them.
        'moisturePct': moisture,
        'ph': ph,
        'relativeHumidityPct': humidity,
      });
      AppSession.instance.rememberProduct('${product['id']}');
    } catch (_) {
      // Offline: clear any stale id so screens fall back to sample data.
      AppSession.instance.clear();
    }
  }

  int _resolveShelfLifeDays(Map<String, dynamic> data) {
    // The wizard writes `expectedShelfLife`; keep the old key as a fallback.
    final value = (data['expectedShelfLife'] ?? data['desiredShelfLife'] as num?)
            ?.toDouble() ??
        6.0;
    final unit = '${data['shelfLifeUnit'] ?? 'Months'}';
    final days = switch (unit) {
      'Days' => value,
      'Years' => value * 365,
      _ => value * 30,
    };
    return days.round().clamp(1, 3650);
  }

  void _navigateBack() {
    setState(() {
      if (_activeScreenRoute == 'storage_conditions') {
        _activeScreenRoute = 'product_input';
      } else if (_activeScreenRoute == 'recommendation_result') {
        _activeScreenRoute = 'storage_conditions';
      } else {
        _activeScreenRoute = 'home';
      }
    });
  }

  Widget _buildBody() {
    switch (_activeScreenRoute) {
      case 'product_input':
        return ProductInputScreen(
          onNext: (data) => _navigateTo('storage_conditions', arguments: data),
          onBack: _navigateBack,
        );

      case 'storage_conditions':
        return StorageConditionsScreen(
          productData: _currentProductData,
          onBack: _navigateBack,
          onGetRecommendation: (completeData) async {
            // A bundled sample is used only as a template for the fields the
            // wizard never asks for (reference layer stack, marketing copy).
            final template = _closestSample('${completeData['name'] ?? ''}');
            // The product the user actually described. This — not the sample —
            // drives the backend spec, the mockup family and every number the
            // result screen shows.
            final described = _productFromInputs(completeData, template);
            await _registerProduct(completeData, described);
            _navigateTo('recommendation_result', arguments: described);
          },
        );

      case 'recommendation_result':
        return RecommendationResultScreen(
          product: _currentProduct,
          onBack: _navigateBack,
          onViewSimulation: () => _navigateTo('digital_twin'),
          onCustomizePackaging: () => _navigateTo('customizer_3d'),
        );

      case 'customizer_3d':
        return PackagingCustomizerScreen(
          // Drives the mockup family: a chips product only sees chips shapes,
          // a dairy product only sees cartons/bottles.
          aiRecommendedProduct: _currentProduct,
          onBack: () => _navigateTo('home'),
          onGenerated: () => _navigateTo('recommendation_result',
              arguments: _currentProduct),
        );

      case 'digital_twin':
        return DigitalTwinSimulatorScreen(
          onBack: () => _navigateTo('home'),
        );

      case 'shelf_life':
        return ShelfLifePredictionScreen(
          onBack: () => _navigateTo('home'),
        );

      case 'packaging_auditor':
        return PackagingAuditorScreen(
          onBack: () => _navigateTo('home'),
        );

      case 'ai_chat':
        return AiChatAssistantScreen(
          onBack: () => _navigateTo('home'),
          onNavigate: _navigateTo,
        );

      case 'suppliers':
        return SupplierTraceabilityScreen(
          onBack: () => _navigateTo('home'),
        );

      case 'home':
      default:
        if (_currentTabIndex == 1) {
          return AiChatAssistantScreen(
            onBack: () => setState(() => _currentTabIndex = 0),
            onNavigate: _navigateTo,
          );
        } else if (_currentTabIndex == 2) {
          return HistoryScreen(
            onNavigate: _navigateTo,
          );
        } else if (_currentTabIndex == 3) {
          return SupplierTraceabilityScreen(
            onBack: () => setState(() => _currentTabIndex = 0),
          );
        }
        return HomeDashboardScreen(
          onToggleTheme: widget.onToggleTheme,
          onNavigateTab: (tabIndex) => setState(() => _currentTabIndex = tabIndex),
          onNavigate: _navigateTo,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final showBottomNav = _activeScreenRoute == 'home';

    return Scaffold(
      body: _buildBody(),
      bottomNavigationBar: showBottomNav
          ? Container(
              decoration: BoxDecoration(
                color: isDark ? AppTheme.surfaceDark : Colors.white,
                border: Border(
                  top: BorderSide(
                    color: isDark
                        ? AppTheme.cardBorderDark
                        : AppTheme.cardBorderLight,
                  ),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildNavItem(0, Icons.home_rounded, 'Home'),
                      _buildNavItem(1, Icons.chat_bubble_outline_rounded, 'Chat'),
                      _buildNavItem(2, Icons.timeline_rounded, 'History'),
                      _buildNavItem(3, Icons.person_outline_rounded, 'Profile'),
                    ],
                  ),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _currentTabIndex == index && _activeScreenRoute == 'home';

    return InkWell(
      onTap: () {
        setState(() {
          _currentTabIndex = index;
          _activeScreenRoute = 'home';
        });
      },
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected
                  ? const Color(0xFF4F46E5)
                  : const Color(0xFF94A3B8),
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                color: isSelected
                    ? const Color(0xFF4F46E5)
                    : const Color(0xFF94A3B8),
              ),
            ),
            if (isSelected)
              Container(
                margin: const EdgeInsets.only(top: 2),
                width: 4,
                height: 4,
                decoration: const BoxDecoration(
                  color: Color(0xFF4F46E5),
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
