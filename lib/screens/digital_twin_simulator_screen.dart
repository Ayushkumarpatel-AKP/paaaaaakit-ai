import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/app_session.dart';
import '../widgets/live_results_panel.dart';

class DigitalTwinSimulatorScreen extends StatefulWidget {
  final VoidCallback onBack;

  const DigitalTwinSimulatorScreen({super.key, required this.onBack});

  @override
  State<DigitalTwinSimulatorScreen> createState() =>
      _DigitalTwinSimulatorScreenState();
}

class _DigitalTwinSimulatorScreenState extends State<DigitalTwinSimulatorScreen>
    with SingleTickerProviderStateMixin {
  // Materials definition with physical barrier properties
  // WVTR: g/(m²·day) at 38°C, 90% RH; OTR: cc/(m²·day) at 23°C, 0% RH; Ea: Activation energy in kJ/mol
  final Map<String, Map<String, dynamic>> _materialSpecs = {
    'LDPE (Standard 40µm)': {
      'wvtr': 18.5,
      'otr': 3500.0,
      'ea': 42.0,
      'color': const Color(0xFFEF4444),
      'type': 'Monolayer Polyethylene',
      'barrier': 'Low Barrier',
      'recyclable': '100% Recyclable',
    },
    'Metallized PET + LDPE': {
      'wvtr': 0.8,
      'otr': 1.2,
      'ea': 68.0,
      'color': const Color(0xFF10B981),
      'type': 'Multi-layer Foil Barrier',
      'barrier': 'High Barrier',
      'recyclable': 'Specialized Stream',
    },
    'Bio-PLA Laminate': {
      'wvtr': 12.0,
      'otr': 650.0,
      'ea': 48.0,
      'color': const Color(0xFF06B6D4),
      'type': '100% Compostable Bio-Polymer',
      'barrier': 'Medium Barrier',
      'recyclable': 'Industrial Compost',
    },
    'Mono-PE EVOH Recyclable': {
      'wvtr': 2.1,
      'otr': 4.5,
      'ea': 60.0,
      'color': const Color(0xFF8B5CF6),
      'type': 'Circular High-Barrier Mono-Material',
      'barrier': 'High Barrier',
      'recyclable': '100% Circular PE',
    },
    'ALU Triplex (PET/ALU/PE)': {
      'wvtr': 0.05,
      'otr': 0.05,
      'ea': 85.0,
      'color': const Color(0xFFF59E0B),
      'type': 'Ultra Ultra Barrier Triplex',
      'barrier': 'Aseptic Barrier',
      'recyclable': 'Chemical Pyrolysis',
    },
  };

  late String _materialA;
  late String _materialB;

  double _simulatedDay = 60.0;
  double _ambientTemp = 25.0; // °C
  double _relativeHumidity = 60.0; // % RH
  double _filmThickness = 65.0; // µm
  String _activePreset = 'ambient';

  late AnimationController _pulseController;

  // Backend digital-twin result (real Arrhenius + permeation engine).
  Map<String, dynamic>? _backendSim;
  bool _backendLoading = false;
  bool _backendLive = false;
  String? _backendError;

  @override
  void initState() {
    super.initState();
    _materialA = 'LDPE (Standard 40µm)';
    _materialB = 'Metallized PET + LDPE';
    _runBackendSimulation();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  static const Map<String, String> _presetToBackend = {
    'ambient': 'Standard',
    'tropical': 'Tropical',
    'cold': 'Cold Chain',
    'arid': 'Arid',
  };

  /// Creates a demo product if the wizard has not produced one yet, so the
  /// backend physics panel works when opened directly from the dashboard.
  Future<String?> _ensureProductId() async {
    final session = AppSession.instance;
    if (session.productId != null) return session.productId;
    try {
      final created = await session.api.createProduct({
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
      session.rememberProduct('${created['id']}');
      return session.productId;
    } catch (_) {
      return null;
    }
  }

  /// Runs the same physics engine the backend uses and stores the real series.
  Future<void> _runBackendSimulation() async {
    setState(() {
      _backendLoading = true;
      _backendError = null;
    });
    try {
      final productId = await _ensureProductId();
      if (productId == null) {
        if (!mounted) return;
        setState(() {
          _backendLoading = false;
          _backendLive = false;
          _backendError = 'backend unreachable';
        });
        return;
      }

      final result = await AppSession.instance.api.simulateDigitalTwin({
        'productId': productId,
        'chamberPreset': _presetToBackend[_activePreset] ?? 'Standard',
        'temperatureC': _ambientTemp,
        'humidityRH': _relativeHumidity,
        'barrierThicknessUm': _filmThickness,
        'durationDays': 180,
      });

      if (!mounted) return;
      AppSession.instance.rememberSimulation('${result['simId']}');
      setState(() {
        _backendSim = result;
        _backendLive = true;
        _backendLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _backendLoading = false;
        _backendLive = false;
        _backendError = '$error';
      });
    }
  }

  List<double> _backendSeries(String key) {
    final series = _backendSim?['resultTimeSeries'];
    if (series is! Map) return const [];
    final raw = series[key];
    if (raw is! List) return const [];
    return raw.map((value) => (value as num).toDouble()).toList();
  }

  Widget _buildBackendPanel(bool isDark) {
    final sim = _backendSim;
    final rows = <MapEntry<String, String>>[];
    if (sim != null) {
      rows.addAll([
        MapEntry('Status', '${sim['status'] ?? '—'}'),
        MapEntry('Final quality', '${sim['finalQuality'] ?? '—'} %'),
        MapEntry('Predicted shelf life',
            '${sim['predictedShelfLifeDays'] ?? '—'} days'),
        MapEntry('Series OTR', '${sim['otr'] ?? '—'} cc/m²/day'),
        MapEntry('Series MVTR', '${sim['mvtr'] ?? '—'} g/m²/day'),
      ]);
    }

    return LiveResultsPanel(
      title: 'Backend Digital Twin (authoritative model)',
      subtitle: _backendLive
          ? '${_presetToBackend[_activePreset]} chamber · ${_ambientTemp.toInt()}°C / '
              '${_relativeHumidity.toInt()}% RH · ${_filmThickness.toInt()} µm'
          : (_backendError == null
              ? 'Backend physics unavailable'
              : 'Offline — $_backendError'),
      isLive: _backendLive,
      loading: _backendLoading,
      rows: rows,
      series: _backendSeries('quality'),
      seriesLabel: 'Quality decay (solve_ivp)',
      seriesUnit: '%',
      seriesColor: const Color(0xFF10B981),
      footnote: _backendLive
          ? 'Arrhenius kinetics calibrated at 25°C; permeabilities are typical '
              'published ranges.'
          : null,
      onRun: _runBackendSimulation,
    );
  }

  // --- Real ODE Kinetic Kinetics (Arrhenius & Fick\'s 1st Law of Diffusion) ---
  double _calculateDecayRate(String materialKey) {
    final spec = _materialSpecs[materialKey] ?? _materialSpecs.values.first;
    final double wvtr = spec['wvtr'] as double;
    final double otr = spec['otr'] as double;
    final double ea = spec['ea'] as double;

    // Arrhenius Temperature dependency: k = k0 * exp(-Ea / (R * T))
    // Standard R = 8.314 J/(mol*K)
    const double rConst = 8.314;
    final double tKelvin = _ambientTemp + 273.15;
    const double tRefKelvin = 298.15; // 25°C

    // Arrhenius multiplier relative to 25°C
    final double arrheniusFactor = math.exp((ea * 1000 / rConst) * (1 / tRefKelvin - 1 / tKelvin));

    // Humidity gradient factor (Fick's law: Flux proportional to delta RH)
    final double rhFactor = math.max(0.2, _relativeHumidity / 60.0);

    // Thickness factor (Flux inversely proportional to thickness L)
    final double thicknessFactor = 65.0 / math.max(20.0, _filmThickness);

    // Composite permeability penalty index
    final double permeabilityIndex = (math.sqrt(wvtr) * 0.008 + math.pow(otr, 0.35) * 0.004);

    return (permeabilityIndex * arrheniusFactor * rhFactor * thicknessFactor).clamp(0.0005, 0.25);
  }

  double _getQuality(String materialKey, double day) {
    final decayRate = _calculateDecayRate(materialKey);
    // ODE: dQ/dt = -k * Q  => Q(t) = Q0 * e^(-k * t)
    return (100.0 * math.exp(-decayRate * day)).clamp(0.0, 100.0);
  }

  int _getShelfLifeDays(String materialKey) {
    final decayRate = _calculateDecayRate(materialKey);
    // Threshold quality is 70% (AQL Failure point)
    // 70 = 100 * e^(-k * t) => t = -ln(0.70) / k
    if (decayRate <= 0.00001) return 365;
    final days = (-math.log(0.70) / decayRate).round();
    return days.clamp(3, 365);
  }

  double _getMoistureIngress(String materialKey, double day) {
    final spec = _materialSpecs[materialKey] ?? _materialSpecs.values.first;
    final double wvtr = spec['wvtr'] as double;
    final double rhRatio = _relativeHumidity / 100.0;
    final double thicknessFactor = 65.0 / _filmThickness;
    // grams of moisture ingress per package
    return (wvtr * 0.0035 * rhRatio * thicknessFactor * (day / 30.0)).clamp(0.01, 8.50);
  }

  double _getHeadspaceO2(String materialKey, double day) {
    final spec = _materialSpecs[materialKey] ?? _materialSpecs.values.first;
    final double otr = spec['otr'] as double;
    final double thicknessFactor = 65.0 / _filmThickness;
    // Starts at 0.5% after nitrogen flush, permeation increases it up to 21%
    final rate = (otr * 0.0003 * thicknessFactor).clamp(0.0001, 0.15);
    final o2 = 0.5 + 20.5 * (1.0 - math.exp(-rate * day));
    return o2.clamp(0.5, 20.9);
  }

  void _applyPreset(String presetKey) {
    // Run after setState so the request carries the new temperature/humidity.
    WidgetsBinding.instance.addPostFrameCallback((_) => _runBackendSimulation());
    setState(() {
      _activePreset = presetKey;
      switch (presetKey) {
        case 'ambient':
          _ambientTemp = 25.0;
          _relativeHumidity = 60.0;
          break;
        case 'tropical':
          _ambientTemp = 40.0;
          _relativeHumidity = 85.0;
          break;
        case 'cold':
          _ambientTemp = 4.0;
          _relativeHumidity = 45.0;
          break;
        case 'arid':
          _ambientTemp = 42.0;
          _relativeHumidity = 22.0;
          break;
      }
    });

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('⚡ Physics Preset: ${presetKey.toUpperCase()} conditions loaded.'),
        backgroundColor: const Color(0xFF4F46E5),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final qualityA = _getQuality(_materialA, _simulatedDay);
    final qualityB = _getQuality(_materialB, _simulatedDay);
    final shelfDaysA = _getShelfLifeDays(_materialA);
    final shelfDaysB = _getShelfLifeDays(_materialB);
    final moistureA = _getMoistureIngress(_materialA, _simulatedDay);
    final moistureB = _getMoistureIngress(_materialB, _simulatedDay);
    final o2A = _getHeadspaceO2(_materialA, _simulatedDay);
    final o2B = _getHeadspaceO2(_materialB, _simulatedDay);

    final shelfMultiplier = (shelfDaysB / math.max(1, shelfDaysA)).toStringAsFixed(1);
    final specA = _materialSpecs[_materialA]!;
    final specB = _materialSpecs[_materialB]!;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: widget.onBack,
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF4F46E5).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.hub_rounded, size: 18, color: Color(0xFF4F46E5)),
            ),
            const SizedBox(width: 8),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Packaging Digital Twin',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                Text(
                  'Arrhenius ODE & Permeation Physics',
                  style: TextStyle(fontSize: 10.5, color: Color(0xFF10B981), fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ),
        centerTitle: false,
        actions: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Container(
                margin: const EdgeInsets.only(right: 14),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15 + _pulseController.value * 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Color(0xFF10B981),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'LIVE ODE',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF059669),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Chamber Simulation Preset Bar
              _buildPresetBar(isDark),

              const SizedBox(height: 12),

              // Material Comparison Selector Card
              _buildMaterialComparisonCard(isDark, specA, specB),

              const SizedBox(height: 12),

              // Digital Twin Cross-Section Barrier Visualizer
              _buildTwinBarrierVisualizer(isDark, specB, o2B, moistureB, qualityB),

              const SizedBox(height: 12),

              // 4 High-Tech KPI Cards
              _buildKpiMetricsGrid(
                isDark: isDark,
                shelfDaysA: shelfDaysA,
                shelfDaysB: shelfDaysB,
                qualityA: qualityA,
                qualityB: qualityB,
                moistureA: moistureA,
                moistureB: moistureB,
                o2A: o2A,
                o2B: o2B,
              ),

              const SizedBox(height: 14),

              _buildBackendPanel(isDark),

              const SizedBox(height: 14),

              // ODE Degradation Dynamic Chart with Timeline Scrubber
              _buildArrheniusChartCard(isDark, qualityA, qualityB),

              const SizedBox(height: 14),

              // Environmental Physics Sliders
              _buildPhysicsControlsCard(isDark),

              const SizedBox(height: 14),

              // Scientific Insights & Summary Banner
              _buildSummaryBanner(shelfMultiplier, specA, specB),

              const SizedBox(height: 14),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('📄 Exporting Digital Twin Simulation Dossier (PDF)...'),
                            backgroundColor: Color(0xFF4F46E5),
                          ),
                        );
                      },
                      icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                      label: const Text('Export Report', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('✨ Applied $_materialB parameters to packaging production line!'),
                            backgroundColor: const Color(0xFF10B981),
                          ),
                        );
                      },
                      icon: const Icon(Icons.check_circle_outline_rounded, size: 16, color: Colors.white),
                      label: const Text('Adopt Optimized Spec', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4F46E5),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 2,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // --- WIDGET BUILDERS ---

  Widget _buildPresetBar(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          const Icon(Icons.tune_rounded, size: 14, color: Color(0xFF64748B)),
          const SizedBox(width: 6),
          const Text(
            'Chamber:',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  _buildPresetChip('ambient', '🌡️ 25°C / 60%'),
                  const SizedBox(width: 6),
                  _buildPresetChip('tropical', '🌴 40°C / 85%'),
                  const SizedBox(width: 6),
                  _buildPresetChip('cold', '❄️ 4°C / 45%'),
                  const SizedBox(width: 6),
                  _buildPresetChip('arid', '🏜️ 42°C / 22%'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetChip(String key, String label) {
    final isSelected = _activePreset == key;
    return GestureDetector(
      onTap: () => _applyPreset(key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF4F46E5) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFF4F46E5) : const Color(0xFF94A3B8).withValues(alpha: 0.4),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            color: isSelected ? Colors.white : const Color(0xFF64748B),
          ),
        ),
      ),
    );
  }

  Widget _buildMaterialComparisonCard(
    bool isDark,
    Map<String, dynamic> specA,
    Map<String, dynamic> specB,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Digital Twin Barrier Pair',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF4F46E5).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'ODE Matrix',
                  style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF4F46E5)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              // Material A Dropdown
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0F172A) : const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.4)),
                  ),
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _materialA,
                    underline: const SizedBox(),
                    icon: const Icon(Icons.arrow_drop_down, size: 18, color: Color(0xFFEF4444)),
                    items: _materialSpecs.keys.map((m) {
                      return DropdownMenuItem(
                        value: m,
                        child: Text(
                          m,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                      );
                    }).toList(),
                    onChanged: (v) => setState(() => _materialA = v!),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  '⚡ VS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF4F46E5),
                  ),
                ),
              ),
              // Material B Dropdown
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0F172A) : const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.6)),
                  ),
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _materialB,
                    underline: const SizedBox(),
                    icon: const Icon(Icons.arrow_drop_down, size: 18, color: Color(0xFF10B981)),
                    items: _materialSpecs.keys.map((m) {
                      return DropdownMenuItem(
                        value: m,
                        child: Text(
                          m,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF059669),
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: (v) => setState(() => _materialB = v!),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Sub-specs row
          Row(
            children: [
              Expanded(
                child: Text(
                  'WVTR: ${specA['wvtr']} | OTR: ${specA['otr']}',
                  style: const TextStyle(fontSize: 9.5, color: Color(0xFFEF4444), fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: Text(
                  'WVTR: ${specB['wvtr']} | OTR: ${specB['otr']}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 9.5, color: Color(0xFF059669), fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTwinBarrierVisualizer(
    bool isDark,
    Map<String, dynamic> specB,
    double o2B,
    double moistureB,
    double qualityB,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF0F172A), const Color(0xFF1E293B)]
              : [const Color(0xFFF8FAFC), const Color(0xFFEEF2FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF4F46E5).withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.layers_rounded, size: 16, color: Color(0xFF4F46E5)),
                  const SizedBox(width: 6),
                  Text(
                    'Micro-Barrier Internal Headspace Twin',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : const Color(0xFF1E293B),
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: qualityB >= 70 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  qualityB >= 70 ? 'STABLE AQL' : 'CRITICAL',
                  style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 3-Bar visual representation of Headspace & Barrier
          Row(
            children: [
              // Oxygen Level Gauge
              Expanded(
                child: _buildHUDGauge(
                  title: 'Headspace O₂',
                  value: '${o2B.toStringAsFixed(1)}%',
                  progress: (o2B / 21.0).clamp(0.0, 1.0),
                  color: o2B < 3.0 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                  sub: o2B < 3.0 ? 'MAP Flushing Active' : 'Oxygen Ingress High',
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 8),
              // Moisture Ingress Gauge
              Expanded(
                child: _buildHUDGauge(
                  title: 'Moisture (H₂O)',
                  value: '${moistureB.toStringAsFixed(2)}g',
                  progress: (moistureB / 1.5).clamp(0.0, 1.0),
                  color: moistureB < 0.1 ? const Color(0xFF10B981) : const Color(0xFF06B6D4),
                  sub: moistureB < 0.1 ? 'Dry Texture Retained' : 'Risk of Soggy Food',
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 8),
              // Crispness Index
              Expanded(
                child: _buildHUDGauge(
                  title: 'Freshness Index',
                  value: '${qualityB.toInt()}%',
                  progress: (qualityB / 100.0).clamp(0.0, 1.0),
                  color: qualityB >= 70 ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                  sub: 'At Day ${_simulatedDay.toInt()}',
                  isDark: isDark,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHUDGauge({
    required String title,
    required String value,
    required double progress,
    required Color color,
    required String sub,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A).withValues(alpha: 0.8) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: color),
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: color.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 3.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            sub,
            style: TextStyle(fontSize: 7.5, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B), fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildKpiMetricsGrid({
    required bool isDark,
    required int shelfDaysA,
    required int shelfDaysB,
    required double qualityA,
    required double qualityB,
    required double moistureA,
    required double moistureB,
    required double o2A,
    required double o2B,
  }) {
    final gainPercent = ((shelfDaysB - shelfDaysA) / math.max(1, shelfDaysA) * 100).toInt();

    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 1.35,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _buildKpiCard(
          title: 'Predicted Shelf Life',
          valA: '$shelfDaysA Days',
          valB: '$shelfDaysB Days',
          badge: '+$gainPercent%',
          badgeColor: const Color(0xFF10B981),
          icon: Icons.calendar_today_rounded,
          colorA: const Color(0xFFEF4444),
          colorB: const Color(0xFF10B981),
          isDark: isDark,
        ),
        _buildKpiCard(
          title: 'Quality @ Day ${_simulatedDay.toInt()}',
          valA: '${qualityA.toInt()}%',
          valB: '${qualityB.toInt()}%',
          badge: qualityB >= 70 ? 'Fresh' : 'Failed',
          badgeColor: qualityB >= 70 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
          icon: Icons.verified_outlined,
          colorA: qualityA >= 70 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
          colorB: qualityB >= 70 ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
          isDark: isDark,
        ),
        _buildKpiCard(
          title: 'Total Moisture Ingress',
          valA: '${moistureA.toStringAsFixed(2)}g',
          valB: '${moistureB.toStringAsFixed(2)}g',
          badge: moistureB < 0.1 ? 'Dry OK' : 'Soggy Risk',
          badgeColor: const Color(0xFF06B6D4),
          icon: Icons.water_drop_outlined,
          colorA: const Color(0xFFEF4444),
          colorB: const Color(0xFF06B6D4),
          isDark: isDark,
        ),
        _buildKpiCard(
          title: 'Headspace O₂ Oxidation',
          valA: '${o2A.toStringAsFixed(1)}% High',
          valB: '${o2B.toStringAsFixed(1)}% Safe',
          badge: o2B < 3.0 ? 'MAP Active' : 'Oxidized',
          badgeColor: const Color(0xFF8B5CF6),
          icon: Icons.shield_outlined,
          colorA: const Color(0xFFEF4444),
          colorB: const Color(0xFF8B5CF6),
          isDark: isDark,
        ),
      ],
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String valA,
    required String valB,
    required String badge,
    required Color badgeColor,
    required IconData icon,
    required Color colorA,
    required Color colorB,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 14, color: const Color(0xFF4F46E5)),
                  const SizedBox(width: 4),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  badge,
                  style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w900, color: badgeColor),
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Mat A', style: TextStyle(fontSize: 8, color: Color(0xFF94A3B8))),
                      Text(valA, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: colorA)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    color: colorB.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colorB.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Mat B', style: TextStyle(fontSize: 8, color: colorB, fontWeight: FontWeight.bold)),
                      Text(valB, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: colorB)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildArrheniusChartCard(bool isDark, double qualityA, double qualityB) {
    final rateA = _calculateDecayRate(_materialA);
    final rateB = _calculateDecayRate(_materialB);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
              : [Colors.white, const Color(0xFFF8FAFC)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Arrhenius ODE Degradation Curves',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Day ${_simulatedDay.toInt()}: ${qualityB.toInt()}% vs ${qualityA.toInt()}%',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF059669),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Legend
          Row(
            children: [
              Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFFEF4444), shape: BoxShape.circle)),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '$_materialA (A)',
                  style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle)),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '$_materialB (B)',
                  style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Container(width: 14, height: 1.5, color: const Color(0xFFEF4444).withValues(alpha: 0.6)),
              const SizedBox(width: 3),
              const Text('AQL 70%', style: TextStyle(fontSize: 9, color: Color(0xFF94A3B8), fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),

          // Custom Paint Graph
          SizedBox(
            height: 160,
            width: double.infinity,
            child: CustomPaint(
              painter: _InteractiveDigitalTwinPainter(
                isDark: isDark,
                simulatedDay: _simulatedDay,
                rateA: rateA,
                rateB: rateB,
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Interactive Timeline Scrubber Slider
          Row(
            children: [
              const Icon(Icons.touch_app_rounded, size: 16, color: Color(0xFF4F46E5)),
              const SizedBox(width: 6),
              Text(
                'Scrubber: ${_simulatedDay.toInt()}d',
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: Color(0xFF4F46E5)),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: const Color(0xFF4F46E5),
                    inactiveTrackColor: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                    thumbColor: const Color(0xFF4F46E5),
                    trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                  ),
                  child: Slider(
                    value: _simulatedDay,
                    min: 0,
                    max: 180,
                    divisions: 36,
                    onChanged: (val) => setState(() => _simulatedDay = val),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPhysicsControlsCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Environmental Physics & Thickness Tuning',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.refresh_rounded, size: 16, color: Color(0xFF64748B)),
                onPressed: () => _applyPreset('ambient'),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Temp Slider
          Row(
            children: [
              const Icon(Icons.thermostat_rounded, size: 16, color: Color(0xFFF59E0B)),
              const SizedBox(width: 6),
              SizedBox(
                width: 85,
                child: Text(
                  'Temp: ${_ambientTemp.toInt()}°C',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                ),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: const Color(0xFFF59E0B),
                    inactiveTrackColor: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                    thumbColor: const Color(0xFFF59E0B),
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                  ),
                  child: Slider(
                    value: _ambientTemp,
                    min: 4,
                    max: 50,
                    divisions: 46,
                    onChanged: (val) => setState(() => _ambientTemp = val),
                  ),
                ),
              ),
            ],
          ),

          // Humidity Slider
          Row(
            children: [
              const Icon(Icons.water_drop_rounded, size: 16, color: Color(0xFF06B6D4)),
              const SizedBox(width: 6),
              SizedBox(
                width: 85,
                child: Text(
                  'RH: ${_relativeHumidity.toInt()}%',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                ),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: const Color(0xFF06B6D4),
                    inactiveTrackColor: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                    thumbColor: const Color(0xFF06B6D4),
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                  ),
                  child: Slider(
                    value: _relativeHumidity,
                    min: 15,
                    max: 95,
                    divisions: 16,
                    onChanged: (val) => setState(() => _relativeHumidity = val),
                  ),
                ),
              ),
            ],
          ),

          // Film Thickness Slider
          Row(
            children: [
              const Icon(Icons.line_weight_rounded, size: 16, color: Color(0xFF8B5CF6)),
              const SizedBox(width: 6),
              SizedBox(
                width: 85,
                child: Text(
                  'Caliper: ${_filmThickness.toInt()}µm',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                ),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: const Color(0xFF8B5CF6),
                    inactiveTrackColor: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                    thumbColor: const Color(0xFF8B5CF6),
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                  ),
                  child: Slider(
                    value: _filmThickness,
                    min: 20,
                    max: 120,
                    divisions: 20,
                    onChanged: (val) => setState(() => _filmThickness = val),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryBanner(
    String multiplier,
    Map<String, dynamic> specA,
    Map<String, dynamic> specB,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFECFDF5), Color(0xFFD1FAE5)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF10B981).withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: Color(0xFF047857),
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '✨ Shelf life boosted by ${multiplier}x with $_materialB',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF047857),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Fick\'s diffusion analysis confirms ${specB['barrier']} minimizes rancidity and lipid peroxide formation under ${_ambientTemp.toInt()}°C & ${_relativeHumidity.toInt()}% RH.',
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: Color(0xFF065F46),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- ARRHENIUS ODE GRAPH CUSTOM PAINTER ---

class _InteractiveDigitalTwinPainter extends CustomPainter {
  final bool isDark;
  final double simulatedDay;
  final double rateA;
  final double rateB;

  _InteractiveDigitalTwinPainter({
    required this.isDark,
    required this.simulatedDay,
    required this.rateA,
    required this.rateB,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const double leftMargin = 30.0;
    const double bottomMargin = 20.0;
    const double topMargin = 8.0;
    const double rightMargin = 12.0;

    final double chartWidth = size.width - leftMargin - rightMargin;
    final double chartHeight = size.height - topMargin - bottomMargin;

    final gridPaint = Paint()
      ..color = isDark ? const Color(0xFF334155).withValues(alpha: 0.45) : const Color(0xFFE2E8F0)
      ..strokeWidth = 1;

    final textStyle = TextStyle(
      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
      fontSize: 9,
      fontWeight: FontWeight.w500,
    );

    // Y Axis Grid (0%, 25%, 50%, 75%, 100%)
    for (int i = 0; i <= 4; i++) {
      final y = topMargin + chartHeight * (1 - i / 4.0);
      canvas.drawLine(Offset(leftMargin, y), Offset(size.width - rightMargin, y), gridPaint);
      final tp = TextPainter(
        text: TextSpan(text: '${i * 25}%', style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(leftMargin - tp.width - 4, y - tp.height / 2));
    }

    // X Axis Days (0, 30, 60, 90, 120, 150, 180)
    final days = [0, 30, 60, 90, 120, 150, 180];
    for (int i = 0; i < days.length; i++) {
      final x = leftMargin + (i / (days.length - 1)) * chartWidth;
      canvas.drawLine(Offset(x, topMargin), Offset(x, topMargin + chartHeight), gridPaint);
      final tp = TextPainter(
        text: TextSpan(text: '${days[i]}d', style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, topMargin + chartHeight + 4));
    }

    // AQL Limit line at 70% Quality
    final aqlY = topMargin + chartHeight * (1 - 0.70);
    final aqlPaint = Paint()
      ..color = const Color(0xFFEF4444).withValues(alpha: 0.5)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(leftMargin, aqlY), Offset(size.width - rightMargin, aqlY), aqlPaint);

    // Curve 1: Material A
    final pathA = Path();
    final paintA = Paint()
      ..color = const Color(0xFFEF4444)
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke;

    pathA.moveTo(leftMargin, topMargin);
    for (double d = 0; d <= 180; d += 4) {
      final q = (100.0 * math.exp(-rateA * d)).clamp(0.0, 100.0);
      final x = leftMargin + (d / 180.0) * chartWidth;
      final y = topMargin + chartHeight * (1 - q / 100.0);
      pathA.lineTo(x, y);
    }
    canvas.drawPath(pathA, paintA);

    // Curve 2: Material B
    final pathB = Path();
    final paintB = Paint()
      ..color = const Color(0xFF10B981)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    pathB.moveTo(leftMargin, topMargin);
    for (double d = 0; d <= 180; d += 4) {
      final q = (100.0 * math.exp(-rateB * d)).clamp(0.0, 100.0);
      final x = leftMargin + (d / 180.0) * chartWidth;
      final y = topMargin + chartHeight * (1 - q / 100.0);
      pathB.lineTo(x, y);
    }

    // Shaded gradient fill under Curve B
    final fillPathB = Path.from(pathB)
      ..lineTo(size.width - rightMargin, topMargin + chartHeight)
      ..lineTo(leftMargin, topMargin + chartHeight)
      ..close();

    final fillPaintB = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF10B981).withValues(alpha: 0.22),
          const Color(0xFF10B981).withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(leftMargin, topMargin, chartWidth, chartHeight));
    canvas.drawPath(fillPathB, fillPaintB);
    canvas.drawPath(pathB, paintB);

    // Vertical Tracker Line on Scrubber Day
    final curX = leftMargin + (simulatedDay / 180.0) * chartWidth;
    final trackerPaint = Paint()
      ..color = const Color(0xFF4F46E5)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(curX, topMargin), Offset(curX, topMargin + chartHeight), trackerPaint);

    // Marker B
    final qCurB = (100.0 * math.exp(-rateB * simulatedDay)).clamp(0.0, 100.0);
    final yB = topMargin + chartHeight * (1 - qCurB / 100.0);
    canvas.drawCircle(Offset(curX, yB), 4, Paint()..color = const Color(0xFF10B981));
    canvas.drawCircle(Offset(curX, yB), 6, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.5);

    // Marker A
    final qCurA = (100.0 * math.exp(-rateA * simulatedDay)).clamp(0.0, 100.0);
    final yA = topMargin + chartHeight * (1 - qCurA / 100.0);
    canvas.drawCircle(Offset(curX, yA), 4, Paint()..color = const Color(0xFFEF4444));
    canvas.drawCircle(Offset(curX, yA), 6, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(covariant _InteractiveDigitalTwinPainter oldDelegate) =>
      oldDelegate.simulatedDay != simulatedDay ||
      oldDelegate.rateA != rateA ||
      oldDelegate.rateB != rateB ||
      oldDelegate.isDark != isDark;
}
