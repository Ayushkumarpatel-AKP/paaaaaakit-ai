import 'package:flutter/material.dart';
import '../services/app_session.dart';
import '../widgets/live_results_panel.dart';

class ShelfLifePredictionScreen extends StatefulWidget {
  final VoidCallback onBack;

  const ShelfLifePredictionScreen({super.key, required this.onBack});

  @override
  State<ShelfLifePredictionScreen> createState() =>
      _ShelfLifePredictionScreenState();
}

class _ShelfLifePredictionScreenState extends State<ShelfLifePredictionScreen> {
  Map<String, dynamic>? _shelfLife;
  bool _loading = false;
  bool _isLive = false;

  @override
  void initState() {
    super.initState();
    _loadPrediction();
  }

  /// Runs the four-failure-mode model on the backend (quality / moisture /
  /// oxidation / microbial) and reports whichever fails first.
  Future<void> _loadPrediction() async {
    setState(() => _loading = true);
    try {
      final productId = await AppSession.instance.ensureProduct();
      if (productId == null) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _isLive = false;
        });
        return;
      }
      final result = await AppSession.instance.api.simulateShelfLife({
        'productId': productId,
        'chamberPreset': 'Standard',
        'temperatureC': 25,
        'humidityRH': 60,
        'durationDays': 180,
      });
      if (!mounted) return;
      setState(() {
        _shelfLife = result;
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

  List<double> _curve(String key) {
    final raw = _shelfLife?[key];
    if (raw is! List) return const [];
    return raw.map((value) => (value as num).toDouble()).toList();
  }

  Widget _buildBackendPanel(bool isDark) {
    final result = _shelfLife;
    final thresholds = (result?['thresholds'] as Map?) ?? const {};

    final rows = <MapEntry<String, String>>[];
    if (result != null) {
      rows.addAll([
        MapEntry('Predicted shelf life',
            '${result['predictedShelfLifeDays']} days'),
        MapEntry('Limiting factor', '${result['limitingFactor']}'),
        MapEntry('Moisture critical day',
            '${result['moistureCriticalDay'] ?? 'not within window'}'),
        MapEntry('Quality threshold', '${thresholds['qualityPct']} %'),
        MapEntry('PV limit', '${thresholds['peroxideValue']} meq O₂/kg'),
        MapEntry('Microbial limit', '${thresholds['microbialLogCfu']} log CFU/g'),
      ]);
    }

    return LiveResultsPanel(
      title: 'Backend shelf-life model',
      subtitle: _isLive
          ? 'Standard chamber · 25°C / 60% RH · earliest failure mode wins'
          : 'Backend physics unavailable',
      isLive: _isLive,
      loading: _loading,
      rows: rows,
      series: _curve('qualityCurve'),
      seriesLabel: 'Quality decay',
      seriesUnit: '%',
      seriesColor: const Color(0xFF8B5CF6),
      footnote: _isLive ? '${_shelfLife!['disclaimer']}' : null,
      onRun: _loadPrediction,
    );
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
        title: const Column(
          children: [
            Text(
              'Shelf Life Prediction',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            Text(
              'AI Model based on Food & Environmental Factors',
              style: TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
            ),
          ],
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildBackendPanel(isDark),

              const SizedBox(height: 14),

              // Hero Predicted Shelf Life Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? [const Color(0xFF1E1B4B), const Color(0xFF312E81)]
                        : [const Color(0xFFEEF2FF), const Color(0xFFE0E7FF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: const Color(0xFF818CF8).withValues(alpha: 0.5),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF4F46E5).withValues(alpha: 0.1),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: const Color(0xFF4F46E5),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.calendar_month_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Predicted Shelf Life',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? const Color(0xFFC7D2FE)
                                  : const Color(0xFF4338CA),
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            '6.2 Months',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF1E1B4B),
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            '(± 0.5 Months Confidence Interval)',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // Quality Degradation Curve Graph
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF334155)
                        : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Quality Degradation Curve',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color:
                            isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Legend
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildDot(const Color(0xFF10B981)),
                            const SizedBox(width: 4),
                            const Text(
                              'Predicted Quality',
                              style: TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildDot(const Color(0xFFEF4444)),
                            const SizedBox(width: 4),
                            const Text(
                              'AQL Limit (70%)',
                              style: TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Canvas Curve
                    SizedBox(
                      height: 160,
                      width: double.infinity,
                      child: CustomPaint(
                        painter: _DegradationPainter(isDark: isDark),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // Quality at Different Conditions Table
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF334155)
                        : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Quality at Different Conditions',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color:
                            isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildConditionRow(
                      icon: Icons.wb_sunny_outlined,
                      condition: 'Ambient (25°C)',
                      shelfLife: '6.2 months',
                      statusColor: const Color(0xFF10B981),
                      isDark: isDark,
                    ),
                    const Divider(height: 16),
                    _buildConditionRow(
                      icon: Icons.ac_unit_outlined,
                      condition: 'Chilled (4°C)',
                      shelfLife: '8.5 months',
                      statusColor: const Color(0xFF06B6D4),
                      isDark: isDark,
                    ),
                    const Divider(height: 16),
                    _buildConditionRow(
                      icon: Icons.water_outlined,
                      condition: 'High Humidity (80% RH)',
                      shelfLife: '4.1 months',
                      statusColor: const Color(0xFFF59E0B),
                      isDark: isDark,
                    ),
                    const Divider(height: 16),
                    _buildConditionRow(
                      icon: Icons.thermostat_outlined,
                      condition: 'High Temperature (40°C)',
                      shelfLife: '2.3 months',
                      statusColor: const Color(0xFFEF4444),
                      isDark: isDark,
                    ),
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

  Widget _buildDot(Color color) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  Widget _buildConditionRow({
    required IconData icon,
    required String condition,
    required String shelfLife,
    required Color statusColor,
    required bool isDark,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: statusColor, size: 16),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            condition,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : const Color(0xFF1E293B),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            shelfLife,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: statusColor,
            ),
          ),
        ),
      ],
    );
  }
}

class _DegradationPainter extends CustomPainter {
  final bool isDark;
  _DegradationPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    const double leftMargin = 32.0;
    const double bottomMargin = 22.0;
    const double topMargin = 8.0;
    const double rightMargin = 12.0;

    final double chartWidth = size.width - leftMargin - rightMargin;
    final double chartHeight = size.height - topMargin - bottomMargin;

    final gridPaint = Paint()
      ..color = isDark
          ? const Color(0xFF334155).withValues(alpha: 0.6)
          : const Color(0xFFE2E8F0)
      ..strokeWidth = 1;

    final textStyle = TextStyle(
      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
      fontSize: 9.5,
      fontWeight: FontWeight.w500,
    );

    // Draw horizontal grid lines (0%, 25%, 50%, 75%, 100%)
    for (int i = 0; i <= 4; i++) {
      final y = topMargin + chartHeight * (1 - i / 4.0);
      canvas.drawLine(
        Offset(leftMargin, y),
        Offset(size.width - rightMargin, y),
        gridPaint,
      );

      final textSpan = TextSpan(text: '${i * 25}%', style: textStyle);
      final tp = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(leftMargin - tp.width - 6, y - tp.height / 2));
    }

    // Draw months (0, 2, 4, 6, 8 Months)
    final months = [0, 2, 4, 6, 8];
    for (int i = 0; i < months.length; i++) {
      final x = leftMargin + (i / (months.length - 1)) * chartWidth;
      canvas.drawLine(
        Offset(x, topMargin),
        Offset(x, topMargin + chartHeight),
        gridPaint,
      );

      final textSpan = TextSpan(text: '${months[i]} Mo', style: textStyle);
      final tp = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, topMargin + chartHeight + 6));
    }

    // Acceptable Quality Limit (70% - Red dashed line)
    final limitY = topMargin + chartHeight * (1 - 0.70);
    final limitPaint = Paint()
      ..color = const Color(0xFFEF4444)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(leftMargin, limitY),
      Offset(size.width - rightMargin, limitY),
      limitPaint,
    );

    // Predicted Curve (Green smooth decay)
    final curvePath = Path();
    curvePath.moveTo(leftMargin, topMargin + chartHeight * 0.04); // 96% at 0
    curvePath.cubicTo(
      leftMargin + chartWidth * 0.35,
      topMargin + chartHeight * 0.10,
      leftMargin + chartWidth * 0.70,
      topMargin + chartHeight * 0.26,
      size.width - rightMargin,
      topMargin + chartHeight * 0.55,
    );

    final curvePaint = Paint()
      ..color = const Color(0xFF10B981)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    canvas.drawPath(curvePath, curvePaint);

    // Crossing point at 6.2 months (70%)
    final pX = leftMargin + (6.2 / 8) * chartWidth;
    final pY = limitY;
    canvas.drawCircle(Offset(pX, pY), 4.5, Paint()..color = const Color(0xFF10B981));
    canvas.drawCircle(
      Offset(pX, pY),
      7,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
