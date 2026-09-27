import 'package:flutter/material.dart';

class Package3DViewer extends StatefulWidget {
  final String productName;
  final String materialType; // 'standard', 'metallized', 'bio'
  final double filmThickness;
  final double packSizeGrams;
  final VoidCallback? onRotateLeft;
  final VoidCallback? onRotateRight;

  const Package3DViewer({
    super.key,
    this.productName = 'Potato Chips',
    this.materialType = 'metallized',
    this.filmThickness = 99.0,
    this.packSizeGrams = 50.0,
    this.onRotateLeft,
    this.onRotateRight,
  });

  @override
  State<Package3DViewer> createState() => _Package3DViewerState();
}

class _Package3DViewerState extends State<Package3DViewer>
    with SingleTickerProviderStateMixin {
  double _rotationY = 0.0;
  double _rotationX = 0.0;
  late AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  void _rotateBy(double delta) {
    setState(() {
      _rotationY += delta;
    });
  }

  void _resetRotation() {
    setState(() {
      _rotationY = 0.0;
      _rotationX = 0.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final sizeRatio = (widget.packSizeGrams / 100.0).clamp(0.80, 1.25);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Container(
        height: 300,
        width: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 0.85,
            colors: isDark
                ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
                : [const Color(0xFFF8FAFC), const Color(0xFFE2E8F0)],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.4)
                  : const Color(0x0C000000),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Soft Realistic Drop Floor Shadow (Centered)
            Positioned(
              bottom: 28,
              child: Container(
                width: 130 * sizeRatio,
                height: 20,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(100),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 22,
                      spreadRadius: 4,
                    ),
                  ],
                ),
              ),
            ),

            // Perfectly Centered 3D Interactive Mockup with Matrix Transformation
            GestureDetector(
              onPanUpdate: (details) {
                setState(() {
                  _rotationY += details.delta.dx * 0.012;
                  _rotationX -= details.delta.dy * 0.008;
                  _rotationX = _rotationX.clamp(-0.35, 0.35);
                });
              },
              child: AnimatedBuilder(
                animation: _shimmerController,
                builder: (context, child) {
                  return Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.0018) // 3D Perspective
                      ..rotateY(_rotationY)
                      ..rotateX(_rotationX),
                    child: _buildCenteredPouch(sizeRatio),
                  );
                },
              ),
            ),

            // Left Navigation Button
            Positioned(
              left: 12,
              child: Material(
                color: isDark
                    ? const Color(0xFF334155).withValues(alpha: 0.85)
                    : Colors.white.withValues(alpha: 0.9),
                shape: const CircleBorder(),
                elevation: 3,
                child: IconButton(
                  icon: const Icon(Icons.chevron_left_rounded, size: 22),
                  color: isDark ? Colors.white : const Color(0xFF1E293B),
                  onPressed: () {
                    _rotateBy(-0.45);
                    widget.onRotateLeft?.call();
                  },
                ),
              ),
            ),

            // Right Navigation Button
            Positioned(
              right: 12,
              child: Material(
                color: isDark
                    ? const Color(0xFF334155).withValues(alpha: 0.85)
                    : Colors.white.withValues(alpha: 0.9),
                shape: const CircleBorder(),
                elevation: 3,
                child: IconButton(
                  icon: const Icon(Icons.chevron_right_rounded, size: 22),
                  color: isDark ? Colors.white : const Color(0xFF1E293B),
                  onPressed: () {
                    _rotateBy(0.45);
                    widget.onRotateRight?.call();
                  },
                ),
              ),
            ),

            // Top Left Reset Orientation Button
            Positioned(
              top: 12,
              left: 14,
              child: InkWell(
                onTap: _resetRotation,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF334155).withValues(alpha: 0.6)
                        : Colors.white.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isDark
                          ? const Color(0xFF475569)
                          : const Color(0xFFCBD5E1),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.threed_rotation_rounded,
                          size: 14,
                          color: isDark ? Colors.white70 : const Color(0xFF475569)),
                      const SizedBox(width: 4),
                      Text(
                        'Reset 3D',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white70 : const Color(0xFF475569),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Top Right Live Spec Floating Pill
            Positioned(
              top: 12,
              right: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF4F46E5),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF4F46E5).withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.layers_rounded,
                        color: Colors.white, size: 12),
                    const SizedBox(width: 4),
                    Text(
                      '${widget.filmThickness.toInt()} µm | ${widget.packSizeGrams.toInt()}g',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Bottom Drag Helper Pill
            Positioned(
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.black.withValues(alpha: 0.4)
                      : Colors.white.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.touch_app_outlined,
                        size: 12,
                        color: isDark ? Colors.white70 : Colors.black54),
                    const SizedBox(width: 4),
                    Text(
                      'Drag to rotate 360°',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: isDark ? Colors.white70 : Colors.black54,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCenteredPouch(double sizeRatio) {
    final width = 150.0 * sizeRatio;
    final height = 195.0 * sizeRatio;

    List<Color> baseColors;
    String materialBadge;
    Color accentBadgeColor;

    if (widget.materialType == 'bio') {
      baseColors = [
        const Color(0xFFD4A373),
        const Color(0xFFCCD5AE),
        const Color(0xFFE9EDC9),
        const Color(0xFFD4A373),
      ];
      materialBadge = '🌿 Eco Bio-PLA';
      accentBadgeColor = const Color(0xFF10B981);
    } else if (widget.materialType == 'standard') {
      baseColors = [
        const Color(0xFF3B82F6),
        const Color(0xFF60A5FA),
        const Color(0xFF93C5FD),
        const Color(0xFF2563EB),
      ];
      materialBadge = 'Standard PE';
      accentBadgeColor = const Color(0xFF3B82F6);
    } else {
      baseColors = [
        const Color(0xFFD97706),
        const Color(0xFFFBBF24),
        const Color(0xFFFEF08A),
        const Color(0xFFF59E0B),
      ];
      materialBadge = '✨ MET-PET Barrier';
      accentBadgeColor = const Color(0xFFD97706);
    }

    final shimmerValue = _shimmerController.value;

    return Center(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: baseColors,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 18,
              offset: const Offset(2, 6),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Top Heat-Seal Ribs
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 14,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.15),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(
                    14,
                    (index) => Container(
                      width: 1.8,
                      height: 9,
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
                  ),
                ),
              ),
            ),

            // Bottom Seal Ribs
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 14,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.15),
                  borderRadius:
                      const BorderRadius.vertical(bottom: Radius.circular(16)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(
                    14,
                    (index) => Container(
                      width: 1.8,
                      height: 9,
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
                  ),
                ),
              ),
            ),

            // Shimmer Foil Light Reflection
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Transform.translate(
                  offset: Offset((shimmerValue * 2 - 1) * (width + 80), 0),
                  child: Transform.rotate(
                    angle: 0.4,
                    child: Container(
                      width: 40,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withValues(alpha: 0.0),
                            Colors.white.withValues(alpha: 0.35),
                            Colors.white.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Pouch Artwork Content (Centered)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDC2626),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white, width: 1.2),
                    ),
                    child: const Text(
                      'PackIT',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.productName,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF1E293B),
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                      shadows: [
                        Shadow(
                          color: Colors.white,
                          blurRadius: 3,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                  const Text(
                    'AI FORMULATED',
                    style: TextStyle(
                      color: Color(0xFF7C2D12),
                      fontSize: 8.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 46,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.fastfood_rounded,
                      color: Color(0xFFD97706),
                      size: 22,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: accentBadgeColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      materialBadge,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
