import 'package:flutter/material.dart';
import '../models/food_item.dart';

class LayerStackWidget extends StatelessWidget {
  final List<PackagingLayer> layers;

  const LayerStackWidget({
    super.key,
    required this.layers,
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
                'Recommended Packaging Structure',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '3-Ply Laminate',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF4F46E5),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Isometric 3D Layer Stack Visual Representation
          Container(
            height: 140,
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Layer 3 (Bottom Sealant - e.g. LDPE 75um)
                Positioned(
                  top: 60,
                  left: 20,
                  right: 20,
                  child: _buildIsometricLayer(
                    color: const Color(0xFF38BDF8),
                    shadowColor: const Color(0xFF0284C7),
                    height: 28,
                    label: 'Sealant Layer (75 µm LDPE)',
                  ),
                ),

                // Layer 2 (Middle Barrier - e.g. Metallized PET 12um)
                Positioned(
                  top: 32,
                  left: 30,
                  right: 30,
                  child: _buildIsometricLayer(
                    color: const Color(0xFFCBD5E1),
                    shadowColor: const Color(0xFF94A3B8),
                    height: 22,
                    label: 'Barrier Layer (12 µm MET-PET)',
                  ),
                ),

                // Layer 1 (Top Print - e.g. PET 12um)
                Positioned(
                  top: 4,
                  left: 40,
                  right: 40,
                  child: _buildIsometricLayer(
                    color: const Color(0xFFF59E0B),
                    shadowColor: const Color(0xFFD97706),
                    height: 22,
                    label: 'Print Layer (12 µm PET)',
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),

          // Layer Breakdown Cards
          ...layers.asMap().entries.map((entry) {
            final index = entry.key;
            final layer = entry.value;

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: layer.layerColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: layer.layerColor.withValues(alpha: 0.4),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 6,
                          children: [
                            Text(
                              layer.name,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF1E293B),
                              ),
                            ),
                            Text(
                              '• ${layer.role}',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                                color: isDark
                                    ? const Color(0xFF94A3B8)
                                    : const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          layer.materialDescription,
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark
                                ? const Color(0xFF64748B)
                                : const Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildIsometricLayer({
    required Color color,
    required Color shadowColor,
    required double height,
    required String label,
  }) {
    return Transform(
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.002)
        ..rotateX(0.75)
        ..rotateZ(-0.15),
      alignment: Alignment.center,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: shadowColor.withValues(alpha: 0.6),
              offset: const Offset(0, 4),
              blurRadius: 2,
            ),
          ],
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.6),
            width: 1,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
        ),
      ),
    );
  }
}
