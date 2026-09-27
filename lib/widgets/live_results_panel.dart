import 'package:flutter/material.dart';

/// Compact chip showing whether a screen is displaying backend results or the
/// bundled sample data.
class LiveBadge extends StatelessWidget {
  const LiveBadge({
    super.key,
    required this.isLive,
    this.loading = false,
    this.liveLabel = 'live · backend',
    this.offlineLabel = 'sample data',
  });

  final bool isLive;
  final bool loading;
  final String liveLabel;
  final String offlineLabel;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 11,
            height: 11,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 6),
          Text(
            'computing…',
            style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: (isLive ? const Color(0xFF10B981) : const Color(0xFF94A3B8))
            .withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isLive ? liveLabel : offlineLabel,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          color: isLive ? const Color(0xFF059669) : const Color(0xFF64748B),
        ),
      ),
    );
  }
}

/// Data-driven sparkline (no chart dependency) for a backend time series.
class Sparkline extends StatelessWidget {
  const Sparkline({
    super.key,
    required this.values,
    this.color = const Color(0xFF4F46E5),
    this.height = 64,
    this.includeZero = true,
  });

  final List<double> values;
  final Color color;
  final double height;
  final bool includeZero;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _SparklinePainter(
          values: values,
          color: color,
          gridColor: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          includeZero: includeZero,
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({
    required this.values,
    required this.color,
    required this.gridColor,
    required this.includeZero,
  });

  final List<double> values;
  final Color color;
  final Color gridColor;
  final bool includeZero;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;

    var minValue = values.reduce((a, b) => a < b ? a : b);
    var maxValue = values.reduce((a, b) => a > b ? a : b);
    if (includeZero) minValue = 0;
    if (maxValue - minValue < 1e-9) maxValue = minValue + 1;

    double xFor(int i) => size.width * i / (values.length - 1);
    double yFor(double value) =>
        size.height * (1 - (value - minValue) / (maxValue - minValue));

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (int i = 0; i <= 2; i++) {
      final y = size.height * i / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final path = Path()..moveTo(xFor(0), yFor(values.first));
    for (int i = 1; i < values.length; i++) {
      path.lineTo(xFor(i), yFor(values[i]));
    }

    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0.0)],
        ).createShader(Offset.zero & size),
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2.4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}

/// Card that renders backend-computed results (with optional series + sparkline).
class LiveResultsPanel extends StatelessWidget {
  const LiveResultsPanel({
    super.key,
    required this.title,
    required this.isLive,
    this.loading = false,
    this.subtitle,
    this.rows = const [],
    this.series,
    this.seriesLabel,
    this.seriesUnit,
    this.seriesColor = const Color(0xFF4F46E5),
    this.footnote,
    this.onRun,
  });

  final String title;
  final bool isLive;
  final bool loading;
  final String? subtitle;
  final List<MapEntry<String, String>> rows;
  final List<double>? series;
  final String? seriesLabel;
  final String? seriesUnit;
  final Color seriesColor;
  final String? footnote;
  final VoidCallback? onRun;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final values = series;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              LiveBadge(isLive: isLive, loading: loading),
            ],
          ),
          if (values != null && values.length > 1) ...[
            const SizedBox(height: 12),
            if (seriesLabel != null)
              Text(
                seriesUnit == null
                    ? seriesLabel!
                    : '$seriesLabel  (${values.last.toStringAsFixed(1)} $seriesUnit)',
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF64748B),
                ),
              ),
            const SizedBox(height: 6),
            Sparkline(values: values, color: seriesColor),
          ],
          if (rows.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...rows.map(
              (row) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        row.key,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Text(
                      row.value,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (footnote != null) ...[
            const SizedBox(height: 2),
            Text(
              footnote!,
              style: const TextStyle(
                fontSize: 10,
                fontStyle: FontStyle.italic,
                color: Color(0xFF94A3B8),
              ),
            ),
          ],
          if (onRun != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onRun,
                icon: const Icon(Icons.play_arrow_rounded, size: 16),
                label: const Text(
                  'Run on backend',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
