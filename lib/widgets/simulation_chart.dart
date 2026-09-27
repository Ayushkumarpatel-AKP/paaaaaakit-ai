import 'package:flutter/material.dart';

class SimulationLineChart extends StatelessWidget {
  final String title;
  final bool showComparison;
  final double currentScrubDay;

  const SimulationLineChart({
    super.key,
    this.title = 'Shelf Life Simulation (Days)',
    this.showComparison = true,
    this.currentScrubDay = 90.0,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.2)
                : const Color(0x06000000),
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
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'Live ODE Model',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF059669),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Legend
          Wrap(
            spacing: 14,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _buildLegendItem(
                color: const Color(0xFFEF4444),
                label: 'LDPE (Standard)',
              ),
              _buildLegendItem(
                color: const Color(0xFF10B981),
                label: 'Metallized PET + LDPE',
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Custom Paint Line Chart with exact padding
          SizedBox(
            height: 175,
            width: double.infinity,
            child: CustomPaint(
              painter: _SimulationChartPainter(
                isDark: isDark,
                showComparison: showComparison,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem({required Color color, required String label}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 4,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _SimulationChartPainter extends CustomPainter {
  final bool isDark;
  final bool showComparison;

  _SimulationChartPainter({
    required this.isDark,
    required this.showComparison,
  });

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

    // Draw horizontal grid lines & Y-axis labels (Quality %: 0%, 25%, 50%, 75%, 100%)
    for (int i = 0; i <= 4; i++) {
      final y = topMargin + chartHeight * (1 - i / 4.0);
      canvas.drawLine(
        Offset(leftMargin, y),
        Offset(size.width - rightMargin, y),
        gridPaint,
      );

      final textSpan = TextSpan(
        text: '${i * 25}%',
        style: textStyle,
      );
      final tp = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(leftMargin - tp.width - 6, y - tp.height / 2));
    }

    // Draw vertical day grid lines & X-axis labels (0, 30, 60, 90, 120, 150, 180 Days)
    final days = [0, 30, 60, 90, 120, 150, 180];
    for (int i = 0; i < days.length; i++) {
      final x = leftMargin + (i / (days.length - 1)) * chartWidth;
      canvas.drawLine(
        Offset(x, topMargin),
        Offset(x, topMargin + chartHeight),
        gridPaint,
      );

      final textSpan = TextSpan(
        text: '${days[i]}',
        style: textStyle,
      );
      final tp = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, topMargin + chartHeight + 6));
    }

    // Draw Acceptable Quality Limit (AQL = 70% threshold)
    final aqlY = topMargin + chartHeight * (1 - 0.70);
    final aqlPaint = Paint()
      ..color = const Color(0xFFF59E0B).withValues(alpha: 0.7)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(leftMargin, aqlY),
      Offset(size.width - rightMargin, aqlY),
      aqlPaint,
    );

    // Curve 1: LDPE Standard (Degrades quickly below 70% within 35 days)
    final ldpePath = Path();
    final ldpePaint = Paint()
      ..color = const Color(0xFFEF4444)
      ..strokeWidth = 2.8
      ..style = PaintingStyle.stroke;

    ldpePath.moveTo(leftMargin, topMargin); // Day 0 = 100%
    ldpePath.cubicTo(
      leftMargin + chartWidth * 0.12,
      topMargin + chartHeight * 0.20,
      leftMargin + chartWidth * 0.22,
      topMargin + chartHeight * 0.65, // Drops below AQL fast
      leftMargin + chartWidth * 0.35,
      topMargin + chartHeight * 0.85,
    );
    ldpePath.quadraticBezierTo(
      leftMargin + chartWidth * 0.6,
      topMargin + chartHeight * 0.95,
      size.width - rightMargin,
      topMargin + chartHeight * 0.98,
    );
    canvas.drawPath(ldpePath, ldpePaint);

    // Curve 2: Metallized PET + LDPE (Maintains high quality >85% for 180 days)
    if (showComparison) {
      final metPath = Path();
      final metPaint = Paint()
        ..color = const Color(0xFF10B981)
        ..strokeWidth = 3.0
        ..style = PaintingStyle.stroke;

      metPath.moveTo(leftMargin, topMargin); // Day 0 = 100%
      metPath.cubicTo(
        leftMargin + chartWidth * 0.35,
        topMargin + chartHeight * 0.03,
        leftMargin + chartWidth * 0.70,
        topMargin + chartHeight * 0.08,
        size.width - rightMargin,
        topMargin + chartHeight * 0.18, // Day 180 = 82%
      );

      // Fill Gradient under Metallized curve
      final fillPath = Path.from(metPath)
        ..lineTo(size.width - rightMargin, topMargin + chartHeight)
        ..lineTo(leftMargin, topMargin + chartHeight)
        ..close();

      final fillPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF10B981).withValues(alpha: 0.25),
            const Color(0xFF10B981).withValues(alpha: 0.0),
          ],
        ).createShader(
          Rect.fromLTWH(
              leftMargin, topMargin, chartWidth, chartHeight),
        );
      canvas.drawPath(fillPath, fillPaint);
      canvas.drawPath(metPath, metPaint);

      // Highlight Data Point on Day 90
      final p90X = leftMargin + (3 / 6) * chartWidth;
      final p90Y = topMargin + chartHeight * 0.055;
      final pointPaint = Paint()..color = const Color(0xFF10B981);
      canvas.drawCircle(Offset(p90X, p90Y), 4.5, pointPaint);
      canvas.drawCircle(
        Offset(p90X, p90Y),
        7,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class CostSustainabilityBarChart extends StatelessWidget {
  const CostSustainabilityBarChart({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.2)
                : const Color(0x06000000),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cost vs Shelf Life vs Sustainability',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 12),
          // Legend
          Wrap(
            spacing: 12,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _buildLegendDot(const Color(0xFF3B82F6), 'Cost (₹)'),
              _buildLegendDot(const Color(0xFF8B5CF6), 'Shelf Life (Mo)'),
              _buildLegendDot(const Color(0xFF10B981), 'Sustainability Score'),
            ],
          ),
          const SizedBox(height: 20),

          // 3-Bar Groups for Option 1, Option 2, Option 3
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _buildBarGroup(
                title: 'Option 1\nStandard',
                costHeight: 44,
                costVal: '₹1.2',
                shelfHeight: 64,
                shelfVal: '4 Mo',
                sustHeight: 78,
                sustVal: '60',
              ),
              _buildBarGroup(
                title: 'Option 2\nRecom. (Met)',
                costHeight: 60,
                costVal: '₹1.8',
                shelfHeight: 98,
                shelfVal: '6 Mo',
                sustHeight: 78,
                sustVal: '60',
                isRecommended: true,
              ),
              _buildBarGroup(
                title: 'Option 3\nEco-Bio',
                costHeight: 76,
                costVal: '₹2.1',
                shelfHeight: 84,
                shelfVal: '5 Mo',
                sustHeight: 114,
                sustVal: '75',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegendDot(Color color, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          text,
          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildBarGroup({
    required String title,
    required double costHeight,
    required String costVal,
    required double shelfHeight,
    required String shelfVal,
    required double sustHeight,
    required String sustVal,
    bool isRecommended = false,
  }) {
    return Column(
      children: [
        if (isRecommended)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            margin: const EdgeInsets.only(bottom: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              'BEST VALUE',
              style: TextStyle(
                color: Colors.white,
                fontSize: 8,
                fontWeight: FontWeight.bold,
              ),
            ),
          )
        else
          const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _buildSingleBar(
              height: costHeight,
              color: const Color(0xFF3B82F6),
              val: costVal,
            ),
            const SizedBox(width: 4),
            _buildSingleBar(
              height: shelfHeight,
              color: const Color(0xFF8B5CF6),
              val: shelfVal,
            ),
            const SizedBox(width: 4),
            _buildSingleBar(
              height: sustHeight,
              color: const Color(0xFF10B981),
              val: sustVal,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildSingleBar({
    required double height,
    required Color color,
    required String val,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          val,
          style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 2),
        Container(
          width: 17,
          height: height,
          decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          ),
        ),
      ],
    );
  }
}
