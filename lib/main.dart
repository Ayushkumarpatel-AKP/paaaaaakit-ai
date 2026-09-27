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
  }

  /// Creates the product on the backend so every downstream screen (auditor,
  /// recommendations, digital twin, LCA, reports) has a real `productId`.
  Future<void> _registerProduct(
    Map<String, dynamic> completeData,
    FoodProduct matched,
  ) async {
    final shelfLifeDays = _resolveShelfLifeDays(completeData);
    final storageTemp =
        ((completeData['storageTemp'] as num?)?.toDouble() ?? 25.0);
    final categoryName = matched.category.name;

    final highSensitivity = const {
      'meatSeafood',
      'dairy',
      'readyToEat',
      'bakery',
    }.contains(categoryName);

    try {
      final product = await AppSession.instance.api.createProduct({
        'name': completeData['name'] ?? matched.name,
        'category': categoryName,
        'waterActivity': matched.waterActivity.clamp(0.10, 0.99),
        'fatContent': (completeData['oilFat'] as num?)?.toDouble() ??
            matched.oilFatContent,
        'oxygenSensitivity': highSensitivity ? 'high' : 'medium',
        'lightSensitivity': highSensitivity ? 'high' : 'medium',
        'targetShelfLifeDays': shelfLifeDays,
        'minTempC': storageTemp - 5,
        'maxTempC': storageTemp + 5,
        'packagingFormat': '${matched.category.label} flexible laminate',
        'budgetPer1kUnits': 40.0,
      });
      AppSession.instance.rememberProduct('${product['id']}');
    } catch (_) {
      // Offline: clear any stale id so screens fall back to sample data.
      AppSession.instance.clear();
    }
  }

  int _resolveShelfLifeDays(Map<String, dynamic> data) {
    final value = (data['desiredShelfLife'] as num?)?.toDouble() ?? 6.0;
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
            // Find or synthesize food product
            final productName = completeData['name'] ?? 'Potato Chips';
            final matched = SampleData.products.firstWhere(
              (p) =>
                  p.name.toLowerCase().contains(productName.toString().toLowerCase()),
              orElse: () => SampleData.products[0],
            );
            await _registerProduct(completeData, matched);
            _navigateTo('recommendation_result', arguments: matched);
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
