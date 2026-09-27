import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/food_item.dart';
import '../data/sample_data.dart';
import '../utils/currency.dart';

class ProductInputScreen extends StatefulWidget {
  final Function(Map<String, dynamic> productData) onNext;
  final VoidCallback onBack;

  const ProductInputScreen({
    super.key,
    required this.onNext,
    required this.onBack,
  });

  @override
  State<ProductInputScreen> createState() => _ProductInputScreenState();
}

class _ProductInputScreenState extends State<ProductInputScreen> {
  final TextEditingController _nameController =
      TextEditingController(text: 'Potato Chips');
  FoodCategory _selectedCategory = FoodCategory.snacks;
  double _moisture = 3.0;
  double _oilFat = 35.0;
  double _ph = 6.5;
  String? _selectedImage =
      'https://images.unsplash.com/photo-1566478989037-eec170784d0b?w=600&auto=format&fit=crop&q=80';

  // New fields as per requirements
  double _expectedShelfLife = 6.0;
  String _shelfLifeUnit = 'Months';
  double _transportDistance = 100.0;
  String _transportUnit = 'km';
  int _budgetMin = 1000;
  int _budgetMax = 5000;
  final String _budgetUnit = 'per 1k units';
  final TextEditingController _specialIngredientsController =
      TextEditingController(text: '');

  final int _currentStep = 1;

  @override
  void dispose() {
    _nameController.dispose();
    _specialIngredientsController.dispose();
    super.dispose();
  }

  void _selectPreset(FoodProduct product) {
    setState(() {
      _nameController.text = product.name;
      _selectedCategory = product.category;
      _moisture = product.moistureContent;
      _oilFat = product.oilFatContent;
      _ph = product.phValue;
      _selectedImage = product.imageUrl;
      _expectedShelfLife = product.defaultShelfLifeMonths.toDouble();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: widget.onBack,
        ),
        title: Text(
          'Product Details',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        centerTitle: true,
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
              widget.onNext({
                'name': _nameController.text.trim().isEmpty
                    ? 'Potato Chips'
                    : _nameController.text.trim(),
                'category': _selectedCategory,
                'moisture': _moisture,
                'oilFat': _oilFat,
                'ph': _ph,
                'imageUrl': _selectedImage ??
                    'https://images.unsplash.com/photo-1566478989037-eec170784d0b?w=600&auto=format&fit=crop&q=80',
                'expectedShelfLife': _expectedShelfLife,
                'shelfLifeUnit': _shelfLifeUnit,
                'transportDistance': _transportDistance,
                'transportUnit': _transportUnit,
                'budgetMin': _budgetMin,
                'budgetMax': _budgetMax,
                'budgetUnit': _budgetUnit,
                'specialIngredients': _specialIngredientsController.text.trim(),
              });
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
                  'Analyze Product & Get AI Recommendations',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                SizedBox(width: 8),
                Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 18),
              ],
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Step Progress Indicator
              _buildStepIndicator(isDark),
              const SizedBox(height: 20),

              // Product Search Field
              Text(
                'Select or Enter Food Product',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF818CF8)),
                  suffixIcon: _nameController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () => setState(() => _nameController.clear()),
                        )
                      : null,
                  hintText: 'e.g. Potato Chips, Tomato, Milk...',
                ),
                onChanged: (val) => setState(() {}),
              ),

              const SizedBox(height: 16),

              // Categories Chips
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: FoodCategory.values.map((category) {
                  final isSelected = _selectedCategory == category;
                  return ChoiceChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          category.icon,
                          size: 14,
                          color: isSelected ? Colors.white : const Color(0xFF64748B),
                        ),
                        const SizedBox(width: 6),
                        Text(category.label),
                      ],
                    ),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _selectedCategory = category);
                        final match = SampleData.products.firstWhere(
                          (p) => p.category == category,
                          orElse: () => SampleData.products[0],
                        );
                        _selectPreset(match);
                      }
                    },
                    selectedColor: const Color(0xFF4F46E5),
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected
                          ? Colors.white
                          : (isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155)),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(
                        color: isSelected
                            ? const Color(0xFF4F46E5)
                            : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                      ),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 20),

              // Upload Product Image Box
              Text(
                'Upload Product Image (Optional)',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('📷 Product image captured and analyzed successfully!'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  height: 110,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFF818CF8).withValues(alpha: 0.5),
                      style: BorderStyle.solid,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_selectedImage != null) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            _selectedImage!,
                            width: 70,
                            height: 70,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(Icons.image, size: 40),
                          ),
                        ),
                        const SizedBox(width: 14),
                      ],
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF4F46E5).withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.camera_alt_rounded,
                              color: Color(0xFF4F46E5),
                              size: 20,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Tap to upload image',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF4F46E5),
                            ),
                          ),
                          Text(
                            'Supports PNG, JPG, WEBP (Max 10MB)',
                            style: TextStyle(
                              fontSize: 10,
                              color: isDark ? Colors.white54 : Colors.black45,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // === SECTION: Product Composition Analysis ===
              Text(
                'Product Composition Analysis',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 12),

              // Moisture Content
              _buildParameterField(
                label: 'Moisture Content (%)',
                value: _moisture,
                min: 0,
                max: 100,
                unit: '%',
                icon: Icons.water_drop_outlined,
                color: const Color(0xFF3B82F6),
                onChanged: (val) => setState(() => _moisture = val),
                helpText: 'Critical for microbial growth and shelf life',
              ),
              const SizedBox(height: 12),

              // Oil/Fat Content
              _buildParameterField(
                label: 'Oil/Fat Content (%)',
                value: _oilFat,
                min: 0,
                max: 100,
                unit: '%',
                icon: Icons.opacity_outlined,
                color: const Color(0xFFF59E0B),
                onChanged: (val) => setState(() => _oilFat = val),
                helpText: 'High fat = oxidation risk, needs barrier',
              ),
              const SizedBox(height: 12),

              // pH Value
              _buildParameterField(
                label: 'pH Value',
                value: _ph,
                min: 1,
                max: 14,
                unit: '',
                icon: Icons.science_outlined,
                color: const Color(0xFF10B981),
                onChanged: (val) => setState(() => _ph = val),
                helpText: 'Acid foods (<4.6) need less barrier vs low-acid',
              ),

              const SizedBox(height: 24),

              // === SECTION: Shelf Life & Storage Requirements ===
              Text(
                'Shelf Life & Storage Requirements',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 12),

              // Expected Shelf Life
              _buildShelfLifeSelector(isDark),
              const SizedBox(height: 16),

              // Transport Distance
              _buildTransportDistanceField(isDark),

              const SizedBox(height: 24),

              // === SECTION: Budget & Custom Requirements ===
              Text(
                'Budget & Custom Requirements',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 12),

              // Budget Range
              _buildBudgetRangeField(isDark),
              const SizedBox(height: 16),

              // Special Ingredients / Custom Notes
              Text(
                'Special Ingredients / Custom Notes (Optional)',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _specialIngredientsController,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'e.g. Contains nuts, export quality, organic certification...',
                  border: OutlineInputBorder(),
                  filled: true,
                ),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepIndicator(bool isDark) {
    return Row(
      children: [
        _buildStepDot(1, 'Product', _currentStep >= 1, _currentStep == 1, isDark),
        Expanded(
          child: Container(
            height: 2,
            color: _currentStep >= 2
                ? const Color(0xFF4F46E5)
                : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
          ),
        ),
        _buildStepDot(2, 'Composition', _currentStep >= 2, _currentStep == 2, isDark),
        Expanded(
          child: Container(
            height: 2,
            color: _currentStep >= 3
                ? const Color(0xFF4F46E5)
                : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
          ),
        ),
        _buildStepDot(3, 'Requirements', _currentStep >= 3, _currentStep == 3, isDark),
      ],
    );
  }

  Widget _buildStepDot(int index, String title, bool isCompleted, bool isActive, bool isDark) {
    return Column(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: isActive
                ? const Color(0xFF4F46E5)
                : (isCompleted ? const Color(0xFF10B981) : const Color(0xFFE2E8F0)),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: isCompleted && !isActive
                ? const Icon(Icons.check, size: 14, color: Colors.white)
                : Text(
                    '$index',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isActive || isCompleted ? Colors.white : const Color(0xFF64748B),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: TextStyle(
            fontSize: 10,
            fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
            color: isActive ? const Color(0xFF4F46E5) : const Color(0xFF64748B),
          ),
        ),
      ],
    );
  }

  Widget _buildParameterField({
    required String label,
    required double value,
    required double min,
    required double max,
    required String unit,
    required IconData icon,
    required Color color,
    required ValueChanged<double> onChanged,
    String? helpText,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF1E293B),
                  ),
                ),
              ),
              Container(
                width: 74,
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    '${value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 1)} $unit',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF4F46E5),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (helpText != null) ...[
            const SizedBox(height: 4),
            Text(
              helpText,
              style: TextStyle(
                fontSize: 10,
                color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildShelfLifeSelector(bool isDark) {
    return Container(
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
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF4F46E5).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.calendar_month_rounded, color: Color(0xFF4F46E5), size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Expected Shelf Life',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF1E293B),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // Value display
              Container(
                width: 80,
                height: 44,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    '$_expectedShelfLife',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF4F46E5),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Unit dropdown
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: DropdownButton<String>(
                  value: _shelfLifeUnit,
                  underline: const SizedBox(),
                  isDense: true,
                  items: ['Days', 'Weeks', 'Months', 'Years'].map((u) {
                    return DropdownMenuItem(
                      value: u,
                      child: Text(u, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    );
                  }).toList(),
                  onChanged: (v) => setState(() => _shelfLifeUnit = v!),
                ),
              ),
              const SizedBox(width: 12),
              // Steppers
              _buildMiniStepper(
                value: _expectedShelfLife,
                min: 1,
                max: 3650,
                onDecrement: () => setState(() => _expectedShelfLife = (_expectedShelfLife - 1).clamp(1, 3650)),
                onIncrement: () => setState(() => _expectedShelfLife = (_expectedShelfLife + 1).clamp(1, 3650)),
                isDark: isDark,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTransportDistanceField(bool isDark) {
    return Container(
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
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.local_shipping_outlined, color: Color(0xFFF59E0B), size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Transportation Distance',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF1E293B),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                width: 80,
                height: 44,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    _transportDistance.toInt().toString(),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF4F46E5),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: DropdownButton<String>(
                  value: _transportUnit,
                  underline: const SizedBox(),
                  isDense: true,
                  items: ['km', 'miles'].map((u) {
                    return DropdownMenuItem(
                      value: u,
                      child: Text(u, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    );
                  }).toList(),
                  onChanged: (v) => setState(() => _transportUnit = v!),
                ),
              ),
              const SizedBox(width: 12),
              _buildMiniStepper(
                value: _transportDistance,
                min: 0,
                max: 5000,
                step: 10,
                onDecrement: () => setState(() => _transportDistance = (_transportDistance - 10).clamp(0, 5000)),
                onIncrement: () => setState(() => _transportDistance = (_transportDistance + 10).clamp(0, 5000)),
                isDark: isDark,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBudgetRangeField(bool isDark) {
    return Container(
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
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.attach_money, color: Color(0xFF10B981), size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Budget Range (₹)',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF1E293B),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // Min value
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Min',
                      style: TextStyle(
                        fontSize: 10,
                        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            formatInr(_budgetMin.toDouble(), decimals: 0),
                            // Indian digit grouping, e.g. ₹1,000.
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF4F46E5),
                            ),
                          ),
                          const SizedBox(width: 4),
                          InkWell(
                            onTap: () => setState(() => _budgetMin = (_budgetMin - 500).clamp(0, _budgetMax - 500)),
                            borderRadius: BorderRadius.circular(4),
                            child: const Icon(Icons.remove, size: 14, color: Color(0xFF4F46E5)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Max value
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Max',
                      style: TextStyle(
                        fontSize: 10,
                        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            formatInr(_budgetMax.toDouble(), decimals: 0),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF4F46E5),
                            ),
                          ),
                          const SizedBox(width: 4),
                          InkWell(
                            onTap: () => setState(() => _budgetMax = (_budgetMax + 500).clamp(_budgetMin + 500, 100000)),
                            borderRadius: BorderRadius.circular(4),
                            child: const Icon(Icons.add, size: 14, color: Color(0xFF4F46E5)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Per $_budgetUnit · AI will recommend options within your budget',
            style: TextStyle(
              fontSize: 10,
              color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStepper({
    required double value,
    required double min,
    required double max,
    double step = 1,
    required VoidCallback onDecrement,
    required VoidCallback onIncrement,
    required bool isDark,
  }) {
    return Row(
      children: [
        InkWell(
          onTap: onDecrement,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
            ),
            child: const Icon(Icons.remove, size: 16, color: Color(0xFF4F46E5)),
          ),
        ),
        const SizedBox(width: 8),
        InkWell(
          onTap: onIncrement,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
            ),
            child: const Icon(Icons.add, size: 16, color: Color(0xFF4F46E5)),
          ),
        ),
      ],
    );
  }
}
