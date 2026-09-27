import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/food_item.dart';

class StorageConditionsScreen extends StatefulWidget {
  final Map<String, dynamic> productData;
  final VoidCallback onBack;
  final Function(Map<String, dynamic> completeData) onGetRecommendation;

  const StorageConditionsScreen({
    super.key,
    required this.productData,
    required this.onBack,
    required this.onGetRecommendation,
  });

  @override
  State<StorageConditionsScreen> createState() => _StorageConditionsScreenState();
}

class _StorageConditionsScreenState extends State<StorageConditionsScreen> {
  StorageType _selectedStorageType = StorageType.ambient;
  double _storageTemp = 25.0;
  String _tempUnit = '°C';
  double _relativeHumidity = 60.0;
  TransportCondition _selectedTransport = TransportCondition.normal;
  final TextEditingController _customStorageNotesController =
      TextEditingController(text: '');

  @override
  void dispose() {
    _customStorageNotesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final productName = widget.productData['name'] ?? 'Product';

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: widget.onBack,
        ),
        title: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFEEF2FF),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.inventory_2_outlined, size: 16, color: Color(0xFF4F46E5)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Storage & Distribution\n$productName',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF4F46E5),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.surfaceDark : Colors.white,
          border: Border(
            top: BorderSide(
              color: isDark ? AppTheme.cardBorderDark : AppTheme.cardBorderLight,
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: OutlinedButton(
                onPressed: widget.onBack,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  side: BorderSide(
                    color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
                  ),
                ),
                child: const Text(
                  'Back',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 4,
              child: Container(
                height: 50,
                decoration: AppTheme.gradientButtonDecoration(),
                child: ElevatedButton(
                  onPressed: () {
                    widget.onGetRecommendation({
                      ...widget.productData,
                      'storageType': _selectedStorageType,
                      'storageTemp': _storageTemp,
                      'tempUnit': _tempUnit,
                      'humidity': _relativeHumidity,
                      'transportCondition': _selectedTransport,
                      'customStorageNotes': _customStorageNotesController.text.trim(),
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Get AI Recommendation',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 16),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Storage Type Selection
              Text(
                'Storage Condition',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildStorageTypeCard(
                    StorageType.ambient,
                    'Ambient',
                    'Room Temperature',
                    Icons.wb_sunny_outlined,
                    const Color(0xFFF59E0B),
                    isDark,
                  ),
                  const SizedBox(width: 8),
                  _buildStorageTypeCard(
                    StorageType.chilled,
                    'Chilled',
                    'Refrigerated',
                    Icons.ac_unit_outlined,
                    const Color(0xFF06B6D4),
                    isDark,
                  ),
                  const SizedBox(width: 8),
                  _buildStorageTypeCard(
                    StorageType.frozen,
                    'Frozen',
                    '-18°C or below',
                    Icons.severe_cold_outlined,
                    const Color(0xFF3B82F6),
                    isDark,
                  ),
                ],
              ),

              const SizedBox(height: 18),

              // Temperature Control
              _buildParameterCard(
                title: 'Storage Temperature',
                icon: Icons.thermostat_rounded,
                accentColor: const Color(0xFFF59E0B),
                isDark: isDark,
                child: Row(
                  children: [
                    _buildStepper(
                      onTap: () => setState(() => _storageTemp = (_storageTemp - 1).clamp(-20, 60)),
                      icon: Icons.remove,
                      isDark: isDark,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        '${_storageTemp.toInt()}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF4F46E5),
                        ),
                      ),
                    ),
                    _buildStepper(
                      onTap: () => setState(() => _storageTemp = (_storageTemp + 1).clamp(-20, 60)),
                      icon: Icons.add,
                      isDark: isDark,
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButton<String>(
                        value: _tempUnit,
                        underline: const SizedBox(),
                        isDense: true,
                        items: ['°C', '°F'].map((u) {
                          return DropdownMenuItem(
                            value: u,
                            child: Text(u, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          );
                        }).toList(),
                        onChanged: (v) => setState(() => _tempUnit = v!),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Humidity Control
              _buildParameterCard(
                title: 'Relative Humidity',
                icon: Icons.water_drop_rounded,
                accentColor: const Color(0xFF06B6D4),
                isDark: isDark,
                child: Row(
                  children: [
                    _buildStepper(
                      onTap: () => setState(() => _relativeHumidity = (_relativeHumidity - 5).clamp(10, 100)),
                      icon: Icons.remove,
                      isDark: isDark,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text(
                        '${_relativeHumidity.toInt()}%',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF06B6D4),
                        ),
                      ),
                    ),
                    _buildStepper(
                      onTap: () => setState(() => _relativeHumidity = (_relativeHumidity + 5).clamp(10, 100)),
                      icon: Icons.add,
                      isDark: isDark,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Transportation Conditions
              Text(
                'Transportation Conditions',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: TransportCondition.values.map((cond) {
                  final isSelected = _selectedTransport == cond;
                  return ChoiceChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          cond.icon,
                          size: 14,
                          color: isSelected ? Colors.white : const Color(0xFF64748B),
                        ),
                        const SizedBox(width: 6),
                        Text(cond.label),
                      ],
                    ),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _selectedTransport = cond);
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

              // Custom Storage Notes
              Text(
                'Custom Storage Notes (Optional)',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _customStorageNotesController,
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText: 'e.g. Sensitive to light, needs nitrogen flush...',
                  border: OutlineInputBorder(),
                  filled: true,
                ),
              ),

              const SizedBox(height: 20),

              // AI Analysis Summary Card
              Container(
                padding: const EdgeInsets.all(16),
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
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFF4F46E5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'AI Analysis Preview',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1E1B4B),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Based on your product details and storage conditions, AI will recommend optimal packaging materials with cost analysis in ₹',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? const Color(0xFFC7D2FE) : const Color(0xFF4338CA),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF4F46E5)),
                  ],
                ),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStorageTypeCard(
    StorageType type,
    String title,
    String subtitle,
    IconData icon,
    Color color,
    bool isDark,
  ) {
    final isSelected = _selectedStorageType == type;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedStorageType = type),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(12),
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
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: isSelected ? color : const Color(0xFF64748B),
                  size: 20,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  color: isSelected ? color : (isDark ? Colors.white : const Color(0xFF1E293B)),
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 10,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildParameterCard({
    required String title,
    required IconData icon,
    required Color accentColor,
    required bool isDark,
    required Widget child,
  }) {
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
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accentColor, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
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
          child,
        ],
      ),
    );
  }

  Widget _buildStepper({required VoidCallback onTap, required IconData icon, required bool isDark}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
        ),
        child: Icon(icon, size: 18, color: const Color(0xFF4F46E5)),
      ),
    );
  }
}
