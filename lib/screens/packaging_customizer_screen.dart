import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/app_session.dart';
import '../utils/currency.dart';
import '../widgets/live_results_panel.dart';
import '../widgets/package_3d_viewer.dart';
import '../models/food_item.dart';

enum PackagingFormFactor {
  standUpPouch('Stand-Up Pouch', Icons.safety_check_rounded, Color(0xFFF59E0B)),
  vacuumPack('Vacuum Pack', Icons.air_rounded, Color(0xFF3B82F6)),
  petContainer('PET Container', Icons.clear_all_rounded, Color(0xFF10B981)),
  laminatedFilm('Laminated Film', Icons.layers_clear_outlined, Color(0xFF8B5CF6)),
  blisterPack('Blister Pack', Icons.view_in_ar_rounded, Color(0xFFEF4444));

  final String label;
  final IconData icon;
  final Color color;
  const PackagingFormFactor(this.label, this.icon, this.color);
}

class PackagingCustomizerScreen extends StatefulWidget {
  final VoidCallback onBack;
  final VoidCallback onGenerated;
  final FoodProduct? aiRecommendedProduct;

  const PackagingCustomizerScreen({
    super.key,
    required this.onBack,
    required this.onGenerated,
    this.aiRecommendedProduct,
  });

  @override
  State<PackagingCustomizerScreen> createState() =>
      _PackagingCustomizerScreenState();
}

class _PackagingCustomizerScreenState extends State<PackagingCustomizerScreen> {
  int _selectedTab = 0; // 0: Material, 1: Thickness, 2: Design, 3: Size, 4: Barrier, 5: Sustainability
  
  PackagingFormFactor _selectedFormFactor = PackagingFormFactor.standUpPouch;
  String _selectedMaterial = 'metallized';
  
  double _filmThickness = 99.0;
  double _packSizeGrams = 50.0;
  
  // Design customization
  String _designLayout = 'full_print';
  bool _hasMatteFinish = false;
  bool _hasGlossSpot = false;
  
  // Printing options
  String _printColorMode = 'full_color';
  int _printSides = 1;
  
  // Barrier layers
  bool _hasOxygenBarrier = true;
  bool _hasMoistureBarrier = true;
  bool _hasLightBarrier = false;
  
  // Sustainability
  bool _preferRecyclable = true;
  bool _preferCompostable = false;
  bool _preferMonoMaterial = false;

  Map<String, dynamic>? _stack;
  bool _loading = false;
  bool _isLive = false;
  String? _customMaterialName;
  String? _customMaterialNotes;

  // Materials database for reference
  final Map<String, Map<String, dynamic>> _availableMaterials = {
    'metallized': {
      'name': 'Metallized PET + LDPE',
      'barrier': 'High Oxygen & Moisture',
      'recyclable': 'Yes (Specialized)',
      'costPerKg': 300,
      'thicknessRange': '12-150 µm',
      'icon': Icons.auto_awesome_rounded,
      'color': const Color(0xFFF59E0B),
    },
    'standard': {
      'name': 'PET + LDPE',
      'barrier': 'Standard',
      'recyclable': 'Yes',
      'costPerKg': 220,
      'thicknessRange': '10-100 µm',
      'icon': Icons.layers_clear_outlined,
      'color': const Color(0xFF3B82F6),
    },
    'bio': {
      'name': 'PLA + Nanocellulose',
      'barrier': 'Medium (Compostable)',
      'recyclable': 'Industrial Compost',
      'costPerKg': 320,
      'thicknessRange': '15-80 µm',
      'icon': Icons.eco_rounded,
      'color': const Color(0xFF10B981),
    },
    'alu_foil': {
      'name': 'Aluminium Foil Laminate',
      'barrier': 'Ultra High (Zero permeability)',
      'recyclable': 'No (Complex)',
      'costPerKg': 340,
      'thicknessRange': '6-100 µm',
      'icon': Icons.shield_rounded,
      'color': const Color(0xFF94A3B8),
    },
    'evoh': {
      'name': 'EVOH Barrier Laminate',
      'barrier': 'Very High Oxygen',
      'recyclable': 'Yes (Specialized)',
      'costPerKg': 480,
      'thicknessRange': '5-50 µm',
      'icon': Icons.science_rounded,
      'color': const Color(0xFF8B5CF6),
    },
  };

  @override
  void initState() {
    super.initState();
    _loadStack();
    _applyAiRecommendation();
  }

  /// Apply AI recommendation if provided
  void _applyAiRecommendation() {
    if (widget.aiRecommendedProduct != null) {
      final product = widget.aiRecommendedProduct!;
      
      // Determine form factor based on product characteristics
      if (product.category == FoodCategory.dairy || product.moistureContent > 50) {
        _selectedFormFactor = PackagingFormFactor.petContainer;
      } else if (product.defaultShelfLifeMonths > 6 || product.oilFatContent > 30) {
        _selectedFormFactor = PackagingFormFactor.standUpPouch;
        _selectedMaterial = 'metallized';
        _filmThickness = 99.0;
      } else if (product.category == FoodCategory.meatSeafood) {
        _selectedFormFactor = PackagingFormFactor.vacuumPack;
        _selectedMaterial = 'evoh';
      } else {
        _selectedFormFactor = PackagingFormFactor.standUpPouch;
      }
      
      setState(() {});
    }
  }

  /// Builds a layer stack for the selected material at the chosen total gauge.
  List<Map<String, dynamic>> _currentLayers() {
    final total = _filmThickness;
    switch (_selectedMaterial) {
      case 'standard':
        return [
          {'material': 'pet', 'thicknessUm': 12.0},
          {'material': 'ldpe', 'thicknessUm': (total - 12).clamp(10.0, 200.0)},
        ];
      case 'bio':
        return [
          {'material': 'pla', 'thicknessUm': 20.0},
          {'material': 'nanocellulose', 'thicknessUm': 15.0},
          {'material': 'pla', 'thicknessUm': (total - 35).clamp(10.0, 200.0)},
        ];
      case 'alu_foil':
        return [
          {'material': 'pet', 'thicknessUm': 12.0},
          {'material': 'alu_foil', 'thicknessUm': 7.0},
          {'material': 'ldpe', 'thicknessUm': (total - 19).clamp(10.0, 200.0)},
        ];
      case 'evoh':
        return [
          {'material': 'pet', 'thicknessUm': 12.0},
          {'material': 'evoh', 'thicknessUm': 15.0},
          {'material': 'ldpe', 'thicknessUm': (total - 27).clamp(10.0, 200.0)},
        ];
      default: // metallized
        return [
          {'material': 'pet', 'thicknessUm': 12.0},
          {'material': 'met_pet', 'thicknessUm': 12.0},
          {'material': 'ldpe', 'thicknessUm': (total - 24).clamp(10.0, 200.0)},
        ];
    }
  }

  /// Server-side series permeability so this screen, the digital twin and the
  /// LCA screen always agree.
  Future<void> _loadStack() async {
    setState(() => _loading = true);
    try {
      final productId = await AppSession.instance.ensureProduct();
      final result = await AppSession.instance.api.recalculateStack(
        layers: _currentLayers(),
        areaM2: 0.05,
        units: 1000,
        productId: productId,
      );
      if (!mounted) return;
      setState(() {
        _stack = result;
        _isLive = true;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLive = false;
        _loading = false;
      });
    }
  }

  Widget _buildBackendPanel(bool isDark) {
    final result = _stack;
    final rows = <MapEntry<String, String>>[];
    if (result != null) {
      rows.addAll([
        MapEntry('Total thickness', '${result['totalThickness']} µm'),
        MapEntry('Series OTR', '${result['seriesOTR']} cc/m²/day'),
        MapEntry('Series MVTR', '${result['seriesMVTR']} g/m²/day'),
        MapEntry('Stack weight (1k)', '${result['stackWeight']} kg'),
        MapEntry(
          'Estimated price (1k units)',
          '${formatInr((result['estimatedCost'] as num?) ?? 0)} ',
        ),
        MapEntry('Recyclability', '${result['recyclabilityScore']} / 100'),
      ]);
    }

    return LiveResultsPanel(
      title: 'Series permeability (backend)',
      subtitle: _isLive
          ? '1/TR = Σ(dᵢ/Pᵢ) over the selected stack · 0.05 m² per pack'
          : 'Backend layer-stack service unavailable',
      isLive: _isLive,
      loading: _loading,
      rows: rows,
      footnote: _isLive
          ? 'Same material database the digital twin and LCA screens use.'
          : null,
      onRun: _loadStack,
    );
  }

  Widget _buildFormFactorSelector(List<PackagingFormFactor> visibleFactors) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.view_in_ar_rounded, color: Color(0xFF4F46E5), size: 18),
              const SizedBox(width: 8),
              Text(
                'AI Recommended Format',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              const Spacer(),
              if (_isLive)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(width: 4, height: 4, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF10B981))),
                      SizedBox(width: 4),
                      Text(
                        'AI Selected',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF10B981)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: visibleFactors.map((factor) {
              final isSelected = _selectedFormFactor == factor;
              return ChoiceChip(
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      factor.icon,
                      size: 16,
                      color: isSelected ? Colors.white : factor.color,
                    ),
                    const SizedBox(width: 6),
                    Text(factor.label),
                  ],
                ),
                selected: isSelected,
                onSelected: (selected) {
                  if (selected) {
                    setState(() => _selectedFormFactor = factor);
                  }
                },
                selectedColor: factor.color,
                labelStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? Colors.white : (isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155)),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: isSelected ? factor.color : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final materialInfo = _availableMaterials[_selectedMaterial];

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: widget.onBack,
        ),
        title: const Text(
          'Customize Your Packaging',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              setState(() {
                _selectedMaterial = 'metallized';
                _filmThickness = 99.0;
                _packSizeGrams = 50.0;
                _designLayout = 'full_print';
                _hasMatteFinish = false;
                _hasGlossSpot = false;
                _printColorMode = 'full_color';
                _printSides = 1;
                _hasOxygenBarrier = true;
                _hasMoistureBarrier = true;
                _hasLightBarrier = false;
                _preferRecyclable = true;
                _preferCompostable = false;
                _preferMonoMaterial = false;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('🔄 Reset to AI recommended defaults'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded),
            onPressed: () => _showCustomMaterialDialog(context, isDark),
          ),
        ],
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.surfaceDark : Colors.white,
          border: Border(
            top: BorderSide(
              color: isDark ? AppTheme.cardBorderDark : AppTheme.cardBorderLight,
            ),
          ),
        ),
        child: Container(
          width: double.infinity,
          height: 54,
          decoration: AppTheme.gradientButtonDecoration(),
          child: ElevatedButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '🎉 Custom packaging configured: ${_selectedFormFactor.label} | ${materialInfo?['name'] ?? _selectedMaterial} | ${_filmThickness.toInt()}µm | ₹${_estimateCost()}',
                  ),
                  backgroundColor: const Color(0xFF10B981),
                ),
              );
              widget.onGenerated();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Generate Custom Packaging',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                SizedBox(width: 8),
                Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
              ],
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildBackendPanel(isDark),

              const SizedBox(height: 14),

              // Form Factor Selection (AI Recommended)
              _buildFormFactorSelector(
                _selectedFormFactor == PackagingFormFactor.standUpPouch
                    ? PackagingFormFactor.values.take(3).toList()
                    : PackagingFormFactor.values.skip(1).toList(),
              ),

              const SizedBox(height: 14),

              // Top Category Tabs
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      _buildTopTab(0, 'Material'),
                      _buildTopTab(1, 'Thickness'),
                      _buildTopTab(2, 'Design'),
                      _buildTopTab(3, 'Size'),
                      _buildTopTab(4, 'Barrier'),
                      _buildTopTab(5, 'Sustainability'),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // 3D Viewer
              Package3DViewer(
                productName: widget.aiRecommendedProduct?.name ?? 'Product',
                materialType: _selectedMaterial,
                filmThickness: _filmThickness,
                packSizeGrams: _packSizeGrams,
              ),

              const SizedBox(height: 18),

              // Customization Tab Content
              _buildTabContent(_selectedTab, isDark, materialInfo!),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabContent(int tab, bool isDark, Map<String, dynamic> materialInfo) {
    switch (tab) {
      case 0:
        return _buildMaterialTab(isDark, materialInfo);
      case 1:
        return _buildThicknessTab(isDark);
      case 2:
        return _buildDesignTab(isDark);
      case 3:
        return _buildSizeTab(isDark);
      case 4:
        return _buildBarrierTab(isDark);
      case 5:
        return _buildSustainabilityTab(isDark);
      default:
        return _buildMaterialTab(isDark, materialInfo);
    }
  }

  Widget _buildMaterialTab(bool isDark, Map<String, dynamic> materialInfo) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Choose Packaging Material',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 10),

          // Material Info Card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      materialInfo['name'] ?? 'Material',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '₹${materialInfo['costPerKg']} / kg',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF10B981),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.security_rounded, size: 14, color: Color(0xFF64748B)),
                    const SizedBox(width: 4),
                    Text(
                      'Barrier: ${materialInfo['barrier']}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.recycling_rounded, size: 14, color: Color(0xFF64748B)),
                    const SizedBox(width: 4),
                    Text(
                      'Recyclable: ${materialInfo['recyclable']}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.straighten_rounded, size: 14, color: Color(0xFF64748B)),
                    const SizedBox(width: 4),
                    Text(
                      'Thickness range: ${materialInfo['thicknessRange']}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Material Selector Cards
          Text(
            'Select Material Type',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 10),

          GridView.count(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: _availableMaterials.entries.map((entry) {
              final isSelected = _selectedMaterial == entry.key;
              return _buildMaterialOptionCard(
                id: entry.key,
                title: entry.value['name'] ?? '',
                barrier: entry.value['barrier'] ?? '',
                recyclable: entry.value['recyclable'] ?? '',
                icon: entry.value['icon'] as IconData,
                color: entry.value['color'] as Color,
                isSelected: isSelected,
                isDark: isDark,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildMaterialOptionCard({
    required String id,
    required String title,
    required String barrier,
    required String recyclable,
    required IconData icon,
    required Color color,
    required bool isSelected,
    required bool isDark,
  }) {
    return InkWell(
      onTap: () => setState(() => _selectedMaterial = id),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFEEF2FF)
              : (isDark ? const Color(0xFF1E293B) : Colors.white),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF4F46E5)
                : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: const Color(0xFF4F46E5).withValues(alpha: 0.15),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                color: isSelected ? const Color(0xFF4F46E5) : (isDark ? Colors.white : const Color(0xFF1E293B)),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.security_rounded, size: 12, color: Color(0xFF94A3B8)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    barrier,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.recycling_rounded, size: 12, color: Color(0xFF94A3B8)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    recyclable,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThicknessTab(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Film Thickness',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF818CF8).withValues(alpha: 0.5)),
                ),
                child: Text(
                  '${_filmThickness.toInt()} µm',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF4F46E5),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: const Color(0xFF4F46E5),
              inactiveTrackColor: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
              thumbColor: const Color(0xFF4F46E5),
              overlayColor: const Color(0xFF4F46E5).withValues(alpha: 0.2),
            ),
            child: Slider(
              value: _filmThickness,
              min: 30,
              max: 150,
              divisions: 24,
              onChanged: (val) => setState(() => _filmThickness = val),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '30 µm (Thin)',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
              ),
              Text(
                '150 µm (Thick)',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Thickness Guidelines',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 8),
                _buildThicknessGuide('30-50 µm', 'Light snacks, single serve', isDark),
                _buildThicknessGuide('50-80 µm', 'Standard snacks, dry goods', isDark),
                _buildThicknessGuide('80-100 µm', 'Recommended for most products', isDark),
                _buildThicknessGuide('100-150 µm', 'High barrier, long shelf life', isDark),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThicknessGuide(String range, String useCase, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFF4F46E5),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              useCase,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              ),
            ),
          ),
          Text(
            range,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF4F46E5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesignTab(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Design Customization',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 12),

          // Design Layout
          _buildDesignOption(
            'full_print',
            'Full Print Design',
            'Complete coverage with custom artwork',
            Icons.cleaning_services_rounded,
            const Color(0xFF4F46E5),
            isDark,
          ),
          _buildDesignOption(
            'single_color',
            'Single Color',
            'Minimal branding with one color',
            Icons.palette_outlined,
            const Color(0xFF3B82F6),
            isDark,
          ),
          _buildDesignOption(
            'natural',
            'Natural/Plain',
            'Clear or natural film look',
            Icons.nature_rounded,
            const Color(0xFF10B981),
            isDark,
          ),

          const SizedBox(height: 16),

          // Finish Options
          Text(
            'Surface Finish',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildSwitchOption(
                'Matte Finish',
                'Smooth, non-reflective surface',
                Icons.format_paint_rounded,
                _hasMatteFinish,
                isDark,
              ),
              const SizedBox(width: 12),
              _buildSwitchOption(
                'Gloss Spot',
                'Glossy highlight on logo/brand',
                Icons.auto_fix_high_rounded,
                _hasGlossSpot,
                isDark,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDesignOption(
    String value,
    String title,
    String description,
    IconData icon,
    Color color,
    bool isDark,
  ) {
    final isSelected = _designLayout == value;
    return InkWell(
      onTap: () => setState(() => _designLayout = value),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.15)
              : (isDark ? const Color(0xFF1E293B) : Colors.white),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                      color: isSelected ? color : (isDark ? Colors.white : const Color(0xFF1E293B)),
                    ),
                  ),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 10,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle_rounded, color: Color(0xFF4F46E5), size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchOption(
    String title,
    String subtitle,
    IconData icon,
    bool isSelected,
    bool isDark,
  ) {
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => isSelected = !isSelected),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF4F46E5).withValues(alpha: 0.15)
                : (isDark ? const Color(0xFF1E293B) : Colors.white),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? const Color(0xFF4F46E5) : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: isSelected ? const Color(0xFF4F46E5) : const Color(0xFF94A3B8)),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? const Color(0xFF4F46E5) : (isDark ? Colors.white : const Color(0xFF1E293B)),
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 9,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSizeTab(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Pack Size',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF818CF8).withValues(alpha: 0.5)),
                ),
                child: Text(
                  '${_packSizeGrams.toInt()} g',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF4F46E5),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: const Color(0xFF4F46E5),
              inactiveTrackColor: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
              thumbColor: const Color(0xFF4F46E5),
              overlayColor: const Color(0xFF4F46E5).withValues(alpha: 0.2),
            ),
            child: Slider(
              value: _packSizeGrams,
              min: 20,
              max: 250,
              divisions: 23,
              onChanged: (val) => setState(() => _packSizeGrams = val),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '20 g (Small)',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
              ),
              Text(
                '250 g (Large)',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBarrierTab(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Barrier Layers',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Select protection requirements for your product:',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 14),

          _buildBarrierOption(
            'Oxygen Barrier',
            'Prevents oxidation and rancidity',
            'Critical for products with oil/fat content',
            Icons.security_rounded,
            const Color(0xFFF59E0B),
            _hasOxygenBarrier,
            isDark,
          ),
          const SizedBox(height: 10),
          _buildBarrierOption(
            'Moisture Barrier',
            'Prevents moisture ingress and loss',
            'Essential for crispy and dry products',
            Icons.water_drop_rounded,
            const Color(0xFF3B82F6),
            _hasMoistureBarrier,
            isDark,
          ),
          const SizedBox(height: 10),
          _buildBarrierOption(
            'Light Barrier',
            'Blocks UV and visible light',
            'Important for light-sensitive products',
            Icons.wb_sunny_outlined,
            const Color(0xFF10B981),
            _hasLightBarrier,
            isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildBarrierOption(
    String title,
    String description,
    String note,
    IconData icon,
    Color color,
    bool isSelected,
    bool isDark,
  ) {
    return InkWell(
      onTap: () => setState(() => isSelected = !isSelected),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.15)
              : (isDark ? const Color(0xFF1E293B) : Colors.white),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isSelected ? color : (isDark ? Colors.white : const Color(0xFF1E293B)),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    ),
                  ),
                  Text(
                    note,
                    style: TextStyle(
                      fontSize: 9,
                      color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: isSelected ? color : (isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9)),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? color : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                ),
              ),
              child: Icon(
                isSelected ? Icons.check_rounded : Icons.add,
                size: 14,
                color: isSelected ? Colors.white : const Color(0xFF94A3B8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSustainabilityTab(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sustainability Preferences',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Help us recommend eco-friendly options:',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 14),

          _buildSustainabilityOption(
            'Recyclable Materials',
            'Priority on materials that can be recycled',
            Icons.recycling_rounded,
            const Color(0xFF3B82F6),
            _preferRecyclable,
            isDark,
          ),
          const SizedBox(height: 10),
          _buildSustainabilityOption(
            'Compostable Materials',
            'Bio-based materials that compost industrially',
            Icons.eco_rounded,
            const Color(0xFF10B981),
            _preferCompostable,
            isDark,
          ),
          const SizedBox(height: 10),
          _buildSustainabilityOption(
            'Mono-Material Design',
            'Single material type for easier recycling',
            Icons.format_align_left_rounded,
            const Color(0xFF8B5CF6),
            _preferMonoMaterial,
            isDark,
          ),
          const SizedBox(height: 16),

          // Sustainability Score Estimate
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [const Color(0xFF1E1B4B), const Color(0xFF312E81)]
                    : [const Color(0xFFEEF2FF), const Color(0xFFE0E7FF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF818CF8).withValues(alpha: 0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.eco_outlined, color: Color(0xFF4F46E5), size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Estimated Sustainability Score',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.eco_rounded, color: Color(0xFF10B981), size: 24),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'B+ Grade',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF10B981),
                          ),
                        ),
                        Text(
                          'Good eco-profile with selected options',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSustainabilityOption(
    String title,
    String description,
    IconData icon,
    Color color,
    bool isSelected,
    bool isDark,
  ) {
    return InkWell(
      onTap: () => setState(() => isSelected = !isSelected),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.15)
              : (isDark ? const Color(0xFF1E293B) : Colors.white),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isSelected ? color : (isDark ? Colors.white : const Color(0xFF1E293B)),
                    ),
                  ),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 10,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle_rounded, color: Color(0xFF4F46E5), size: 18),
          ],
        ),
      ),
    );
  }

  double _estimateCost() {
    // Simple cost estimation based on material and thickness
    final baseCost = _filmThickness * 0.02; // Base cost per pack
    final materialMultiplier = _selectedMaterial == 'bio' ? 1.3 : _selectedMaterial == 'alu_foil' ? 1.5 : 1.0;
    return baseCost * materialMultiplier;
  }

  void _showCustomMaterialDialog(BuildContext context, bool isDark) {
    final nameController = TextEditingController();
    final notesController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF4F46E5),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: const Row(
                  children: [
                    Text(
                      'Add Custom Material',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(width: 8),
                    Icon(Icons.add, color: Colors.white, size: 18),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Material Name',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        hintText: 'e.g. Custom Bio-Coating',
                        border: OutlineInputBorder(),
                        filled: true,
                      ),
                    ),
                    const SizedBox(height: 16),

                    Text(
                      'Material Properties (Notes)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: notesController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        hintText: 'Describe barrier properties, cost, recyclability...',
                        border: OutlineInputBorder(),
                        filled: true,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              if (nameController.text.isNotEmpty) {
                                setState(() {
                                  _customMaterialName = nameController.text;
                                  _customMaterialNotes = notesController.text;
                                });
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('✅ Custom material "$_customMaterialName" added to analysis'),
                                    backgroundColor: const Color(0xFF10B981),
                                  ),
                                );
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF4F46E5),
                            ),
                            child: const Text('Add Material'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, size: 16, color: Color(0xFFB45309)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Custom materials will be included in AI analysis. If reliable data is not available, the system will notify you.',
                              style: TextStyle(
                                fontSize: 11,
                                color: const Color(0xFF92400E),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTopTab(int index, String title) {
    final isSelected = _selectedTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF4F46E5) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
              color: isSelected ? Colors.white : const Color(0xFF64748B),
            ),
          ),
        ),
      ),
    );
  }
}
