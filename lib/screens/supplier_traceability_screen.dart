import 'package:flutter/material.dart';
import '../data/sample_data.dart';
import '../models/food_item.dart';
import '../services/app_session.dart';

class SupplierTraceabilityScreen extends StatefulWidget {
  final VoidCallback onBack;

  const SupplierTraceabilityScreen({super.key, required this.onBack});

  @override
  State<SupplierTraceabilityScreen> createState() =>
      _SupplierTraceabilityScreenState();
}

class _SupplierTraceabilityScreenState
    extends State<SupplierTraceabilityScreen> {
  int _selectedTab = 0; // 0: Suppliers, 1: Traceability, 2: QR Code

  static const String _placeholderLogo =
      'https://images.unsplash.com/photo-1486406146926-c627a92ad1ab?w=300&auto=format&fit=crop&q=80';

  List<SupplierItem> _suppliers = SampleData.suppliers;
  Map<String, Map<String, dynamic>> _backendSuppliers = {};
  bool _isLive = false;
  bool _loading = false;
  String? _materialFilter;

  static const List<String> _materialChips = [
    'met_pet',
    'evoh',
    'pla',
    'ldpe',
    'alu_foil',
    'paperboard',
  ];

  @override
  void initState() {
    super.initState();
    _loadSuppliers();
  }

  Future<void> _loadSuppliers({String? material}) async {
    setState(() => _loading = true);
    try {
      final payload = await AppSession.instance.api.suppliers(
        material: material,
        massKg: 1000,
      );
      final raw = (payload['suppliers'] as List?) ?? const [];
      final mapped = <SupplierItem>[];
      final byId = <String, Map<String, dynamic>>{};

      for (final entry in raw) {
        final map = Map<String, dynamic>.from(entry as Map);
        final id = '${map['id']}';
        byId[id] = map;
        final materials =
            (map['materialTypes'] as List?)?.join(', ') ?? 'Flexible packaging';
        final certs = (map['certifications'] as List?) ?? const [];
        final distance = map['distanceKm'];
        mapped.add(
          SupplierItem(
            id: id,
            name: '${map['name']}',
            logoUrl: _placeholderLogo,
            specialties: materials,
            location: distance == null
                ? '${map['locationLabel']}'
                : '${map['locationLabel']} · $distance km',
            badge: certs.isEmpty ? 'Verified' : '${certs.first}',
            rating: (map['rating'] as num?)?.toDouble() ?? 4.5,
            minOrder: '${map['minOrderKg'] ?? 1000} kg',
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        if (mapped.isEmpty) {
          _suppliers = SampleData.suppliers;
          _isLive = false;
        } else {
          _suppliers = mapped;
          _backendSuppliers = byId;
          _isLive = true;
        }
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _suppliers = SampleData.suppliers;
        _isLive = false;
        _loading = false;
      });
    }
  }

  Future<void> _contactSupplier(SupplierItem supplier) async {
    final backendEntry = _backendSuppliers[supplier.id];
    if (backendEntry == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('📞 Connecting to ${supplier.name} Sales Rep...'),
          backgroundColor: const Color(0xFF4F46E5),
        ),
      );
      return;
    }

    try {
      final response = await AppSession.instance.api.sendRfq(supplier.id, {
        'message': 'RFQ for ${supplier.specialties}',
        'quantityKg': 1000,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${response['confirmation'] ?? 'Request sent'}'),
          backgroundColor: const Color(0xFF4F46E5),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not reach the backend')),
      );
    }
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
        title: const Text(
          'Suppliers & Traceability',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
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
              // Segment Tabs
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1E293B)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    _buildTabButton(0, 'Suppliers'),
                    _buildTabButton(1, 'Traceability'),
                    _buildTabButton(2, 'QR Code'),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              if (_selectedTab == 0 || _selectedTab == 1) ...[
                // Verified Supplier Cards
                Row(
                  children: [
                    Text(
                      'Verified Packaging Suppliers',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
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
                          color: _isLive
                              ? const Color(0xFF059669)
                              : const Color(0xFF94A3B8),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),

                SizedBox(
                  height: 30,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _buildMaterialChip('All', null),
                      ..._materialChips.map(
                        (material) => _buildMaterialChip(material, material),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                ..._suppliers.map((supplier) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: isDark
                            ? const Color(0xFF334155)
                            : const Color(0xFFE2E8F0),
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
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            supplier.logoUrl,
                            width: 50,
                            height: 50,
                            fit: BoxFit.cover,
                            errorBuilder: (c, e, s) => Container(
                              width: 50,
                              height: 50,
                              color: const Color(0xFFEEF2FF),
                              child: const Icon(Icons.business_rounded,
                                  color: Color(0xFF4F46E5)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      supplier.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.bold,
                                        color: isDark
                                            ? Colors.white
                                            : const Color(0xFF0F172A),
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFECFDF5),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.star_rounded,
                                            size: 11, color: Color(0xFF059669)),
                                        const SizedBox(width: 2),
                                        Text(
                                          '${supplier.rating}',
                                          style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF059669),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                supplier.specialties,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.location_on_outlined,
                                      size: 12, color: Color(0xFF94A3B8)),
                                  const SizedBox(width: 3),
                                  Text(
                                    supplier.location,
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      color: Color(0xFF94A3B8),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          onPressed: () => _contactSupplier(supplier),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4F46E5),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text(
                            'Contact',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),

                const SizedBox(height: 18),
              ],

              // QR-Based Product Traceability Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF334155)
                        : const Color(0xFFE2E8F0),
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
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFF4F46E5).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.qr_code_2_rounded,
                            color: Color(0xFF4F46E5),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'QR-Based Product Traceability',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'Blockchain Batch Verification',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF10B981),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Center QR Code Box Visual
                    Container(
                      width: 140,
                      height: 140,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: CustomPaint(
                        painter: _QrCodeSimPainter(),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Batch Details Table
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF0F172A)
                            : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        children: [
                          _buildTraceRow('Product', 'Potato Chips Classic'),
                          _buildTraceRow('Batch No', 'PC250812-IN-09'),
                          _buildTraceRow('Mfg Date', '12-08-2025'),
                          _buildTraceRow('Expiry Date', '12-02-2026'),
                          _buildTraceRow('Supplier', 'UFlex Limited',
                              isLast: true),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    const Text(
                      'Scan to verify product details and supply chain information',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF94A3B8),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMaterialChip(String label, String? material) {
    final selected = _materialFilter == material;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () {
          setState(() => _materialFilter = material);
          _loadSuppliers(material: material);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFF4F46E5)
                : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label.replaceAll('_', ' '),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : const Color(0xFF475569),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabButton(int index, String title) {
    final isSelected = _selectedTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF4F46E5) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
              color: isSelected ? Colors.white : const Color(0xFF64748B),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTraceRow(String label, String value, {bool isLast = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _QrCodeSimPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF0F172A)
      ..style = PaintingStyle.fill;

    // Corner QR squares
    _drawCornerSquare(canvas, 0, 0, 32, paint);
    _drawCornerSquare(canvas, size.width - 32, 0, 32, paint);
    _drawCornerSquare(canvas, 0, size.height - 32, 32, paint);

    // Random QR modules
    final grid = 12;
    final step = size.width / grid;
    for (int r = 0; r < grid; r++) {
      for (int c = 0; c < grid; c++) {
        // Skip corner areas
        if ((r < 4 && c < 4) || (r < 4 && c > 7) || (r > 7 && c < 4)) continue;
        if ((r * 7 + c * 11) % 3 == 0 || (r + c) % 2 == 0) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(c * step + 1, r * step + 1, step - 2, step - 2),
              const Radius.circular(2),
            ),
            paint,
          );
        }
      }
    }
  }

  void _drawCornerSquare(
      Canvas canvas, double x, double y, double size, Paint paint) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, size, size), const Radius.circular(6)),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(x + 5, y + 5, size - 10, size - 10),
          const Radius.circular(4)),
      Paint()..color = Colors.white,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(x + 10, y + 10, size - 20, size - 20),
          const Radius.circular(2)),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
