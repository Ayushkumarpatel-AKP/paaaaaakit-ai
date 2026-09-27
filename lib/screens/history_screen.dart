import 'package:flutter/material.dart';
import '../data/sample_data.dart';
import '../services/app_session.dart';
import '../utils/currency.dart';

class HistoryScreen extends StatefulWidget {
  final Function(String route, {dynamic arguments}) onNavigate;

  const HistoryScreen({super.key, required this.onNavigate});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  int _selectedFilter = 0; // 0: All, 1: Recommendations, 2: Audits, 3: Simulations

  bool _isLive = false;
  bool _loading = false;

  List<Map<String, dynamic>> _historyItems = [
    {
      'id': 'h1',
      'title': 'Potato Chips Classic',
      'type': 'AI Recommendation',
      'date': 'Today, 01:15 AM',
      'status': 'Optimal Match',
      'statusColor': Color(0xFF10B981),
      'structure': 'PET 12µ + MET-PET 12µ + LDPE 75µ',
      'shelfLife': '6 Months',
      'cost': '₹1.80/pack',
      'imageUrl':
          'https://images.unsplash.com/photo-1566478989037-eec170784d0b?w=200&auto=format&fit=crop&q=80',
      'product': SampleData.products[0],
    },
    {
      'id': 'h2',
      'title': 'Bingo Original Pack Audit',
      'type': 'Camera Audit',
      'date': 'Yesterday, 04:30 PM',
      'status': 'Seal Passed QA (82%)',
      'statusColor': Color(0xFF10B981),
      'structure': 'MET-PET / LDPE Laminate',
      'shelfLife': '5.5 Months',
      'cost': 'Defects: None',
      'imageUrl':
          'https://images.unsplash.com/photo-1566478989037-eec170784d0b?w=200&auto=format&fit=crop&q=80',
    },
    {
      'id': 'h3',
      'title': 'Dried Mango Slices',
      'type': 'AI Recommendation',
      'date': '24 Sep 2026',
      'status': 'High Barrier (96%)',
      'statusColor': Color(0xFF4F46E5),
      'structure': 'BOPP Matte + ALU Foil 7µ + PE 60µ',
      'shelfLife': '8-10 Months',
      'cost': '₹2.10/pack',
      'imageUrl':
          'https://images.unsplash.com/photo-1601493700631-2b16ec4b4716?w=200&auto=format&fit=crop&q=80',
      'product': SampleData.products[1],
    },
    {
      'id': 'h4',
      'title': 'Whole Milk Aseptic Carton',
      'type': 'Digital Twin Sim',
      'date': '22 Sep 2026',
      'status': 'ODE Verified',
      'statusColor': Color(0xFF06B6D4),
      'structure': '6-Layer Paperboard + ALU Barrier',
      'shelfLife': '12 Months',
      'cost': '₹3.40/carton',
      'imageUrl':
          'https://images.unsplash.com/photo-1550583724-b2692b85b150?w=200&auto=format&fit=crop&q=80',
      'product': SampleData.products[2],
    },
    {
      'id': 'h5',
      'title': 'Seal Integrity Stress Test',
      'type': 'Camera Audit',
      'date': '20 Sep 2026',
      'status': 'Defect Detected (34%)',
      'statusColor': Color(0xFFEF4444),
      'structure': 'Standard BOPP / LDPE',
      'shelfLife': '18 Days',
      'cost': 'Top Crease Channeling',
      'imageUrl':
          'https://images.unsplash.com/photo-1527018607619-766bd329ff81?w=200&auto=format&fit=crop&q=80',
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  /// Reads the denormalized `project_summary` collection; keeps the bundled
  /// sample list when the backend is unavailable.
  Future<void> _loadHistory() async {
    setState(() => _loading = true);
    try {
      final payload = await AppSession.instance.api.history(limit: 50);
      final projects = (payload['projects'] as List?) ?? const [];
      if (projects.isEmpty) {
        if (!mounted) return;
        setState(() {
          _isLive = false;
          _loading = false;
        });
        return;
      }

      final mapped = projects.map((raw) {
        final project = Map<String, dynamic>.from(raw as Map);
        return _projectToItem(project);
      }).toList();

      if (!mounted) return;
      setState(() {
        _historyItems = mapped;
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

  Map<String, dynamic> _projectToItem(Map<String, dynamic> project) {
    final status = '${project['status'] ?? 'Draft'}';
    final hasSim = project['latestSimId'] != null;
    final gained = (project['shelfLifeGainedDays'] as num?)?.toDouble() ?? 0;
    final cost = (project['costPer1k'] as num?)?.toDouble() ?? 0;
    final eco = (project['ecoScore'] as num?)?.toDouble() ?? 0;

    return {
      'id': project['productId'],
      'productId': project['productId'],
      'title': '${project['productName'] ?? 'Untitled project'}',
      'type': hasSim ? 'Digital Twin Sim' : 'AI Recommendation',
      'date': '${project['updatedAt'] ?? project['createdAt'] ?? ''}'
          .replaceAll('T', ' ')
          .split('.')
          .first,
      'status': status,
      'statusColor': status == 'Optimal'
          ? const Color(0xFF10B981)
          : status == 'Warning'
              ? const Color(0xFFF59E0B)
              : status == 'Action Needed'
                  ? const Color(0xFFEF4444)
                  : const Color(0xFF4F46E5),
      'structure': eco > 0 ? 'Eco score ${eco.toStringAsFixed(0)}/100' : 'Spec saved',
      'shelfLife': gained == 0 ? '—' : '${gained.toStringAsFixed(1)} d vs target',
      'cost': cost <= 0 ? '—' : '${formatInr(cost)}/1k',
      'imageUrl':
          'https://images.unsplash.com/photo-1566478989037-eec170784d0b?w=200&auto=format&fit=crop&q=80',
      'product': null,
    };
  }

  Future<void> _exportReports() async {
    final first = _historyItems.isEmpty ? null : _historyItems.first;
    final projectId = first?['productId'] ?? AppSession.instance.productId;
    if (projectId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('📄 Create a project first to export a PDF report'),
          backgroundColor: Color(0xFFF59E0B),
        ),
      );
      return;
    }

    final url = AppSession.instance.api.reportExportUrl('$projectId');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('📄 PDF report ready: $url'),
        backgroundColor: const Color(0xFF10B981),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final filteredList = _historyItems.where((item) {
      if (_selectedFilter == 1) return item['type'] == 'AI Recommendation';
      if (_selectedFilter == 2) return item['type'] == 'Camera Audit';
      if (_selectedFilter == 3) return item['type'] == 'Digital Twin Sim';
      return true;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Analysis History & Reports',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        centerTitle: true,
        actions: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            onPressed: _exportReports,
          ),
        ],
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Filter Chips
            Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _buildFilterChip(
                      0, 'All (${_historyItems.length})${_isLive ? ' · live' : ''}'),
                  _buildFilterChip(1, 'Recommendations'),
                  _buildFilterChip(2, 'Audits'),
                  _buildFilterChip(3, 'Simulations'),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // History List
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: filteredList.length,
                itemBuilder: (context, index) {
                  final item = filteredList[index];
                  final statusColor = item['statusColor'] as Color;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: isDark ? Colors.black.withValues(alpha: 0.2) : const Color(0x06000000),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.network(
                                item['imageUrl'] as String,
                                width: 44,
                                height: 44,
                                fit: BoxFit.cover,
                                errorBuilder: (c, e, s) => Container(
                                  width: 44,
                                  height: 44,
                                  color: const Color(0xFFEEF2FF),
                                  child: const Icon(Icons.inventory_2, color: Color(0xFF4F46E5)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          item['title'] as String,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.bold,
                                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: statusColor.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          item['status'] as String,
                                          style: TextStyle(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.bold,
                                            color: statusColor,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${item['type']} • ${item['date']}',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(
                                child: Text(
                                  '🛡️ ${item['structure']}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                ),
                              ),
                              Text(
                                '⏳ ${item['shelfLife']}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF4F46E5),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              item['cost'] as String,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: isDark ? const Color(0xFFC7D2FE) : const Color(0xFF4338CA),
                              ),
                            ),
                            InkWell(
                              onTap: () {
                                if (item['product'] != null) {
                                  widget.onNavigate('recommendation_result', arguments: item['product']);
                                } else if (item['type'] == 'Camera Audit') {
                                  widget.onNavigate('packaging_auditor');
                                } else {
                                  widget.onNavigate('digital_twin');
                                }
                              },
                              child: const Row(
                                children: [
                                  Text(
                                    'Re-open Spec',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF4F46E5),
                                    ),
                                  ),
                                  SizedBox(width: 2),
                                  Icon(Icons.chevron_right_rounded, size: 14, color: Color(0xFF4F46E5)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(int index, String label) {
    final isSelected = _selectedFilter == index;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (val) => setState(() => _selectedFilter = index),
        selectedColor: const Color(0xFF4F46E5),
        labelStyle: TextStyle(
          fontSize: 11,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
          color: isSelected ? Colors.white : const Color(0xFF64748B),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isSelected ? const Color(0xFF4F46E5) : const Color(0xFFCBD5E1),
          ),
        ),
      ),
    );
  }
}
