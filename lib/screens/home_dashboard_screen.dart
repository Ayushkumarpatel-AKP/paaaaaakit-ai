import 'package:flutter/material.dart';
import '../data/sample_data.dart';
import '../services/app_session.dart';

class HomeDashboardScreen extends StatefulWidget {
  final VoidCallback onToggleTheme;
  final Function(int) onNavigateTab;
  final Function(String route, {dynamic arguments}) onNavigate;

  const HomeDashboardScreen({
    super.key,
    required this.onToggleTheme,
    required this.onNavigateTab,
    required this.onNavigate,
  });

  @override
  State<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends State<HomeDashboardScreen> {
  Map<String, dynamic>? _summary;
  List<Map<String, dynamic>> _recentFeed = const [];
  bool _isLive = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  /// Pulls the real aggregate from `project_summary`; falls back to placeholders
  /// when the backend is not running.
  Future<void> _loadDashboard() async {
    setState(() => _loading = true);
    try {
      final summary = await AppSession.instance.api.dashboardSummary();
      final feed = await AppSession.instance.api.recentFeed(limit: 10);
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _recentFeed = feed.map((e) => Map<String, dynamic>.from(e as Map)).toList();
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

  Widget _buildKpiStrip(bool isDark) {
    final summary = _summary;
    final carbon = summary?['carbonReductionPercent'] as num?;
    final shelf = summary?['avgShelfLifeExtensionDays'] as num?;
    final projects = summary?['activeProjectCount'] as num?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Impact Overview',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
            const Spacer(),
            if (_loading)
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Text(
                _isLive ? 'live · backend' : 'sample data',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: _isLive ? const Color(0xFF059669) : const Color(0xFF94A3B8),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _buildKpiTile(
              isDark: isDark,
              label: 'Carbon cut',
              value: carbon == null ? '—' : '${carbon.toStringAsFixed(1)}%',
              icon: Icons.eco_outlined,
              color: const Color(0xFF10B981),
            ),
            const SizedBox(width: 10),
            _buildKpiTile(
              isDark: isDark,
              label: 'Shelf-life gain',
              value: shelf == null ? '—' : '${shelf.toStringAsFixed(0)} d',
              icon: Icons.hourglass_top_rounded,
              color: const Color(0xFF8B5CF6),
            ),
            const SizedBox(width: 10),
            _buildKpiTile(
              isDark: isDark,
              label: 'Projects',
              value: projects == null ? '—' : '${projects.toInt()}',
              icon: Icons.folder_open_outlined,
              color: const Color(0xFF3B82F6),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRecentActivity(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recent Simulations',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 10),
        ..._recentFeed.take(3).map(
          (item) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${item['productName'] ?? 'Untitled'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${item['chamberPreset'] ?? '—'} · final quality '
                        '${item['finalQuality'] ?? '—'}% · '
                        '${item['predictedShelfLifeDays'] ?? '—'} d',
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: (item['status'] == 'Optimal'
                            ? const Color(0xFF10B981)
                            : item['status'] == 'Warning'
                                ? const Color(0xFFF59E0B)
                                : const Color(0xFFEF4444))
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${item['status'] ?? '—'}',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w900,
                      color: item['status'] == 'Optimal'
                          ? const Color(0xFF059669)
                          : item['status'] == 'Warning'
                              ? const Color(0xFFB45309)
                              : const Color(0xFFB91C1C),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildKpiTile({
    required bool isDark,
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
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
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF10B981), Color(0xFF4F46E5)],
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.eco_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'PackIT AI',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color:
                              isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      IconButton(
                        onPressed: widget.onToggleTheme,
                        icon: Icon(
                          isDark
                              ? Icons.light_mode_outlined
                              : Icons.dark_mode_outlined,
                          color: isDark
                              ? const Color(0xFFFBBF24)
                              : const Color(0xFF475569),
                        ),
                      ),
                      Stack(
                        children: [
                          IconButton(
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      '🔔 3 Packaging Audits completed successfully!'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            },
                            icon: Icon(
                              Icons.notifications_outlined,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF475569),
                            ),
                          ),
                          Positioned(
                            top: 10,
                            right: 12,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Color(0xFFEF4444),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 18),

              // AI Expert Prompt / Search Card
              InkWell(
                onTap: () => widget.onNavigate('ai_chat'),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isDark
                          ? [
                              const Color(0xFF1E1B4B),
                              const Color(0xFF312E81),
                            ]
                          : [
                              const Color(0xFFEEF2FF),
                              const Color(0xFFE0E7FF),
                            ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFF818CF8).withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFF4F46E5),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.auto_awesome_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Ask our AI Packaging Expert...',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF1E1B4B),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '"Suggest packaging for my mango chips for 6 months shelf life"',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontStyle: FontStyle.italic,
                                color: isDark
                                    ? const Color(0xFFC7D2FE)
                                    : const Color(0xFF4338CA),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 14,
                        color: Color(0xFF4F46E5),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 22),

              _buildKpiStrip(isDark),

              if (_recentFeed.isNotEmpty) ...[
                const SizedBox(height: 18),
                _buildRecentActivity(isDark),
              ],

              const SizedBox(height: 22),

              // Grid of Modules
              GridView.count(
                crossAxisCount: 3,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.82,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildModuleCard(
                    context: context,
                    icon: Icons.inventory_2_outlined,
                    label: 'Packaging\nRecommendation',
                    badgeColor: const Color(0xFF3B82F6),
                    onTap: () => widget.onNavigate('product_input'),
                  ),
                  _buildModuleCard(
                    context: context,
                    icon: Icons.hourglass_top_rounded,
                    label: 'Shelf Life\nPrediction',
                    badgeColor: const Color(0xFF8B5CF6),
                    onTap: () => widget.onNavigate('shelf_life'),
                  ),
                  _buildModuleCard(
                    context: context,
                    icon: Icons.flip_camera_android_rounded,
                    label: 'Packaging\nSimulator (Digital Twin)',
                    badgeColor: const Color(0xFF10B981),
                    onTap: () => widget.onNavigate('digital_twin'),
                  ),
                  _buildModuleCard(
                    context: context,
                    icon: Icons.qr_code_scanner_rounded,
                    label: 'Camera Scan\nIdentify Packaging',
                    badgeColor: const Color(0xFFEF4444),
                    onTap: () => widget.onNavigate('packaging_auditor'),
                  ),
                  _buildModuleCard(
                    context: context,
                    icon: Icons.storefront_rounded,
                    label: 'Supplier &\nMarketplace',
                    badgeColor: const Color(0xFFF97316),
                    onTap: () => widget.onNavigate('suppliers'),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Popular Products Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Popular Products',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  TextButton(
                    onPressed: () => widget.onNavigate('product_input'),
                    child: const Text(
                      'View All',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF4F46E5),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              SizedBox(
                height: 105,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  children: [
                    _buildProductPill(
                      context: context,
                      name: 'Chips',
                      icon: Icons.cookie_outlined,
                      imageUrl:
                          'https://images.unsplash.com/photo-1566478989037-eec170784d0b?w=200&auto=format&fit=crop&q=80',
                      onTap: () => widget.onNavigate(
                        'recommendation_result',
                        arguments: SampleData.products[0],
                      ),
                    ),
                    _buildProductPill(
                      context: context,
                      name: 'Milk',
                      icon: Icons.local_drink_outlined,
                      imageUrl:
                          'https://images.unsplash.com/photo-1550583724-b2692b85b150?w=200&auto=format&fit=crop&q=80',
                      onTap: () => widget.onNavigate(
                        'recommendation_result',
                        arguments: SampleData.products[2],
                      ),
                    ),
                    _buildProductPill(
                      context: context,
                      name: 'Fruits',
                      icon: Icons.apple_outlined,
                      imageUrl:
                          'https://images.unsplash.com/photo-1619566636858-adf3ef46400b?w=200&auto=format&fit=crop&q=80',
                      onTap: () => widget.onNavigate(
                        'recommendation_result',
                        arguments: SampleData.products[1],
                      ),
                    ),
                    _buildProductPill(
                      context: context,
                      name: 'Vegetables',
                      icon: Icons.eco_outlined,
                      imageUrl:
                          'https://images.unsplash.com/photo-1592924357228-91a4daadcfea?w=200&auto=format&fit=crop&q=80',
                      onTap: () => widget.onNavigate(
                        'recommendation_result',
                        arguments: SampleData.products[3],
                      ),
                    ),
                    _buildProductPill(
                      context: context,
                      name: 'Meat',
                      icon: Icons.restaurant_outlined,
                      imageUrl:
                          'https://images.unsplash.com/photo-1603048588665-791ca8aea617?w=200&auto=format&fit=crop&q=80',
                      onTap: () => widget.onNavigate(
                        'recommendation_result',
                        arguments: SampleData.products[4],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Quick Action Card: Launch 3D Customizer USP
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: const Color(0xFF818CF8),
                          width: 1,
                        ),
                      ),
                      child: const Icon(
                        Icons.view_in_ar_rounded,
                        color: Color(0xFF818CF8),
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '3D Packaging Customizer',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Interactive 360° Material & Thickness Simulator',
                            style: TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () => widget.onNavigate('customizer_3d'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4F46E5),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Launch',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModuleCard({
    required BuildContext context,
    required IconData icon,
    required String label,
    required Color badgeColor,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.2)
                  : const Color(0x06000000),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: badgeColor, size: 22),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                height: 1.15,
                color: isDark ? Colors.white : const Color(0xFF1E293B),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductPill({
    required BuildContext context,
    required String name,
    required IconData icon,
    required String imageUrl,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 74,
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                imageUrl,
                width: 44,
                height: 44,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  width: 44,
                  height: 44,
                  color: const Color(0xFFEEF2FF),
                  child: Icon(icon, color: const Color(0xFF4F46E5), size: 22),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF1E293B),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
