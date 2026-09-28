import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:image_picker/image_picker.dart';

import '../data/mockup_library.dart';

/// Interactive 3D mockup studio.
///
/// Renders a bundled `.glb` packaging mockup with `<model-viewer>` inside an
/// [InAppWebView] so the pack can be inspected from every angle, and lets the
/// user upload artwork, crop/rotate/scale it on a 2:3 artboard and stamp it onto
/// the mockup as a live texture.
///
/// The [mockups] list is supplied by the caller, so a product only ever sees the
/// mockup shapes that belong to its own family.
///
/// Both the mockup `.glb` files and the `model-viewer` library are bundled
/// assets, so the studio runs with no network connection at all.
class PackagingMockupStudio extends StatefulWidget {
  /// Name printed nowhere on the model but used for messaging.
  final String productName;

  /// Mockups offered for the current product (already filtered).
  final List<PackagingMockup> mockups;

  /// Selected packaging material id, shown in the spec pill.
  final String materialType;

  /// Current film gauge in microns, shown in the spec pill.
  final double filmThickness;

  /// Current pack size in grams, shown in the spec pill.
  final double packSizeGrams;

  const PackagingMockupStudio({
    super.key,
    required this.productName,
    required this.mockups,
    this.materialType = 'metallized',
    this.filmThickness = 99.0,
    this.packSizeGrams = 50.0,
  });

  @override
  State<PackagingMockupStudio> createState() => _PackagingMockupStudioState();
}

class _PackagingMockupStudioState extends State<PackagingMockupStudio> {
  final ImagePicker _picker = ImagePicker();

  PackagingMockup? _selectedMockup;
  InAppWebViewController? _webController;

  /// Bundled `<model-viewer>` library, inlined into the viewer document so the
  /// 3D preview never needs a network connection.
  static const String _viewerScriptAsset =
      'assets/model_viewer/model-viewer.min.js';
  String _viewerScript = '';

  String _modelDataUri = '';

  /// Set once the viewer document itself has loaded, so the 3D canvas is no
  /// longer covered by the spinner.
  bool _pageReady = false;

  /// Set by the model's own `load` event, which means it is safe to stamp a
  /// texture onto it.
  bool _modelLoaded = false;

  /// The plugin renders the viewer in a `data:` iframe on web, whose opaque
  /// origin blocks every Dart -> JS call. Only native builds can drive the
  /// viewer, so the browser preview is view/rotate only.
  bool get _canDriveViewer => !kIsWeb;

  String? _viewerError;

  File? _artwork;
  bool _artworkApplied = false;

  double _x = 0;
  double _y = 0;
  double _scale = 1;
  double _rotation = 0;
  double _light = 1;

  @override
  void initState() {
    super.initState();
    _loadViewerScript();
    _selectInitialMockup();
  }

  Future<void> _loadViewerScript() async {
    try {
      final script = await rootBundle.loadString(_viewerScriptAsset);
      if (!mounted) return;
      setState(() => _viewerScript = script);
    } catch (_) {
      if (!mounted) return;
      setState(() =>
          _viewerError = 'The bundled 3D library could not be read.');
    }
  }

  @override
  void didUpdateWidget(covariant PackagingMockupStudio oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A different product means a different mockup family — reset the picker.
    if (_mockupSignature(oldWidget.mockups) !=
        _mockupSignature(widget.mockups)) {
      _artworkApplied = false;
      _selectInitialMockup();
    }
  }

  String _mockupSignature(List<PackagingMockup> mockups) =>
      mockups.map((mockup) => mockup.id).join('|');

  void _selectInitialMockup() {
    if (widget.mockups.isEmpty) {
      _selectedMockup = null;
      _modelDataUri = '';
      return;
    }
    _loadMockup(widget.mockups.first);
  }

  Future<void> _loadMockup(PackagingMockup mockup) async {
    setState(() {
      _selectedMockup = mockup;
      _pageReady = false;
      _modelLoaded = false;
      _viewerError = null;
      _modelDataUri = '';
      _artworkApplied = false;
    });

    try {
      final bytes = await rootBundle.load(mockup.assetPath);
      if (!mounted || _selectedMockup?.id != mockup.id) return;
      setState(() {
        _modelDataUri = 'data:model/gltf-binary;base64,'
            '${base64Encode(bytes.buffer.asUint8List())}';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _viewerError = 'Mockup "${mockup.label}" could not be loaded.');
    }
  }

  Future<void> _pickArtwork() async {
    try {
      final result = await _picker.pickImage(source: ImageSource.gallery);
      if (result == null || !mounted) return;
      setState(() {
        _artwork = File(result.path);
        _artworkApplied = false;
      });
    } catch (_) {
      _showMessage('Could not open the gallery.');
    }
  }

  String get _artworkMimeType {
    final ext = _artwork?.path.split('.').last.toLowerCase();
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }

  Future<void> _applyArtwork() async {
    if (!_canDriveViewer) {
      _showMessage('Artwork editing needs the Android app.');
      return;
    }
    if (_artwork == null) {
      _showMessage('Pehle artwork upload karo.');
      return;
    }
    if (_webController == null || !_modelLoaded) {
      _showMessage('Mockup abhi load ho raha hai.');
      return;
    }

    try {
      final bytes = await _artwork!.readAsBytes();
      final dataUri = 'data:$_artworkMimeType;base64,${base64Encode(bytes)}';
      await _webController!.evaluateJavascript(
        source:
            'applyArtwork(${jsonEncode(dataUri)}, $_x, $_y, $_scale, $_rotation)',
      );
      if (!mounted) return;
      setState(() => _artworkApplied = true);
      _showMessage('Artwork mockup par apply ho gaya.');
    } catch (_) {
      _showMessage('Artwork apply nahi ho paya.');
    }
  }

  /// Re-stamps the artwork while the user drags a slider, but only once the
  /// artwork has been applied at least once.
  void _refreshAppliedArtwork() {
    if (!_artworkApplied) return;
    _applyArtwork();
  }

  void _fitToTemplate() {
    setState(() {
      _x = 0;
      _y = 0;
      _scale = 1;
      _rotation = 0;
    });
    _refreshAppliedArtwork();
  }

  void _resetView() {
    _webController?.evaluateJavascript(source: 'resetCamera()');
  }

  void _setLight(double value) {
    setState(() => _light = value);
    _webController?.evaluateJavascript(source: 'setExposure($value)');
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _viewerHtml() {
    final model = jsonEncode(_modelDataUri);
    return '''<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no"><script type="module">$_viewerScript</script><style>html,body,model-viewer{width:100%;height:100%;margin:0;background:transparent;overflow:hidden}model-viewer{--poster-color:transparent}</style></head><body><model-viewer id="model" src=$model camera-controls touch-action="pan-y" exposure="$_light" shadow-intensity="1"></model-viewer><script>const viewer=document.getElementById('model');const bridge=window.flutter_inappwebview;viewer.addEventListener('load',()=>{if(bridge&&bridge.callHandler)bridge.callHandler('modelLoaded');});window.resetCamera=()=>{if(viewer.resetTurntableRotation)viewer.resetTurntableRotation();};window.setExposure=(value)=>{viewer.exposure=value;};window.applyArtwork=async(dataUri,x,y,scale,rotation)=>{if(!viewer.model)return;const image=new Image();image.src=dataUri;await image.decode();const canvas=document.createElement('canvas');canvas.width=600;canvas.height=900;const ctx=canvas.getContext('2d');const ratio=image.width/image.height;let width=600,height=900;if(ratio>600/900)width=900*ratio;else height=600/ratio;ctx.translate(300,450);ctx.rotate(rotation*Math.PI/180);ctx.translate(-300,-450);ctx.drawImage(image,(600-width*scale)/2+x*6,(900-height*scale)/2+y*9,width*scale,height*scale);const texture=await viewer.createTexture(canvas.toDataURL('image/png'));let applied=0;viewer.model.materials.forEach(material=>{const pbr=material.pbrMetallicRoughness;if(!pbr)return;if(pbr.baseColorTexture&&pbr.baseColorTexture.setTexture){pbr.baseColorTexture.setTexture(texture);}else{pbr.baseColorTexture=texture;}applied+=1;});return applied;};</script></body></html>''';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
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
          _buildHeader(isDark),
          if (!_canDriveViewer) ...[
            const SizedBox(height: 10),
            _buildWebNotice(),
          ],
          const SizedBox(height: 12),
          _buildMockupPicker(isDark),
          const SizedBox(height: 12),
          _buildViewer(isDark),
          const SizedBox(height: 14),
          _buildArtworkEditor(isDark),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    return Row(
      children: [
        const Icon(Icons.threed_rotation_rounded, size: 18, color: Color(0xFF4F46E5)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '360° Mockup Studio',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              Text(
                widget.productName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
        TextButton.icon(
          onPressed: (_modelDataUri.isEmpty || !_canDriveViewer) ? null : _resetView,
          icon: const Icon(Icons.restart_alt_rounded, size: 16),
          label: const Text('Reset view', style: TextStyle(fontSize: 11)),
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF4F46E5),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: const Size(0, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ],
    );
  }

  /// The web build of the plugin cannot receive Dart -> JS calls, so say so
  /// plainly instead of offering artwork buttons that silently do nothing.
  Widget _buildWebNotice() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.35)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 15, color: Color(0xFFB45309)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Browser preview: you can rotate and zoom the mockup, but uploading artwork onto it '
              'only works in the Android app.',
              style: TextStyle(fontSize: 10.5, height: 1.35, color: Color(0xFF92400E)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMockupPicker(bool isDark) {
    if (widget.mockups.isEmpty) {
      return Text(
        'No 3D mockup available for this product.',
        style: TextStyle(
          fontSize: 12,
          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'CHOOSE MOCKUP',
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 1.1,
            fontWeight: FontWeight.w700,
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF94A3B8),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: widget.mockups.map((mockup) {
            final isSelected = _selectedMockup?.id == mockup.id;
            return ChoiceChip(
              avatar: Icon(
                Icons.inventory_2_outlined,
                size: 15,
                color: isSelected ? Colors.white : const Color(0xFF4F46E5),
              ),
              label: Text(mockup.label),
              selected: isSelected,
              showCheckmark: false,
              onSelected: (selected) {
                if (!selected || isSelected) return;
                _loadMockup(mockup);
              },
              selectedColor: const Color(0xFF4F46E5),
              backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
              labelStyle: TextStyle(
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
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
      ],
    );
  }

  Widget _buildViewer(bool isDark) {
    return Container(
      height: 320,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 0.9,
          colors: isDark
              ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
              : [const Color(0xFFF8FAFC), const Color(0xFFE2E8F0)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
        ),
      ),
      child: Stack(
        children: [
          if (_modelDataUri.isNotEmpty && _viewerScript.isNotEmpty)
            InAppWebView(
              key: ValueKey(_modelDataUri),
              initialData: InAppWebViewInitialData(data: _viewerHtml()),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                transparentBackground: true,
                disallowOverScroll: true,
                mediaPlaybackRequiresUserGesture: false,
              ),
              onWebViewCreated: (controller) {
                _webController = controller;
                controller.addJavaScriptHandler(
                  handlerName: 'modelLoaded',
                  callback: (_) {
                    if (!mounted) return;
                    setState(() {
                      _modelLoaded = true;
                      _viewerError = null;
                    });
                  },
                );
              },
              onLoadStop: (_, __) {
                if (!mounted) return;
                setState(() => _pageReady = true);
              },
              onReceivedError: (_, __, error) {
                if (!mounted) return;
                setState(() =>
                    _viewerError = '3D viewer error: ${error.description}');
              },
            ),

          // Spec pill
          Positioned(
            top: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF4F46E5),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${widget.filmThickness.toInt()} µm | ${widget.packSizeGrams.toInt()}g',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),

          // Loading / error overlay
          if (_viewerError != null)
            Positioned.fill(
              child: Container(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.55)
                    : Colors.white.withValues(alpha: 0.85),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline_rounded,
                            size: 26, color: Color(0xFFF43F5E)),
                        const SizedBox(height: 8),
                        Text(
                          _viewerError!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 11.5, color: Color(0xFFF43F5E)),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Try selecting another mockup.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: isDark
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          else if (!_pageReady)
            Positioned.fill(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'LOADING MOCKUP',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          if (_pageReady)
            Positioned(
              bottom: 10,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.black.withValues(alpha: 0.45)
                        : Colors.white.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'DRAG TO ROTATE  •  PINCH TO ZOOM',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildArtworkEditor(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.image_outlined, size: 16, color: Color(0xFF4F46E5)),
            const SizedBox(width: 8),
            Text(
              'Artwork',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
            const Spacer(),
            Text(
              'RECTANGULAR FORMAT / 2 : 3',
              style: TextStyle(
                fontSize: 9.5,
                letterSpacing: 0.6,
                color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Center(child: _buildArtworkPreview(isDark)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _pickArtwork,
                icon: const Icon(Icons.upload_file_rounded, size: 17),
                label: Text(
                  _artwork == null ? 'Upload artwork' : 'Change artwork',
                  style: const TextStyle(fontSize: 12.5),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF4F46E5),
                  minimumSize: const Size(0, 44),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: (_modelLoaded && _canDriveViewer) ? _applyArtwork : null,
                icon: const Icon(Icons.auto_fix_high_rounded, size: 17),
                label: const Text(
                  'Apply to mockup',
                  style: TextStyle(fontSize: 12.5),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF4F46E5),
                  minimumSize: const Size(0, 44),
                  side: const BorderSide(color: Color(0xFF818CF8)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
        if (_artworkApplied)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Icon(Icons.check_circle_rounded, size: 14, color: Color(0xFF10B981)),
                SizedBox(width: 6),
                Text(
                  'TEXTURE APPLIED TO MOCKUP',
                  style: TextStyle(
                    color: Color(0xFF10B981),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        _buildSectionLabel('EDIT / CROP ARTWORK', isDark),
        _buildSlider('Horizontal', _x, -100, 100, (v) => setState(() => _x = v)),
        _buildSlider('Vertical', _y, -100, 100, (v) => setState(() => _y = v)),
        _buildSlider('Scale', _scale, 0.5, 1.8, (v) => setState(() => _scale = v)),
        _buildSlider('Rotate', _rotation, -180, 180, (v) => setState(() => _rotation = v)),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: _artwork == null ? null : _fitToTemplate,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF4F46E5),
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('FIT TO TEMPLATE', style: TextStyle(fontSize: 11)),
          ),
        ),
        const SizedBox(height: 8),
        _buildSectionLabel('LIGHTING', isDark),
        Row(
          children: [
            const Icon(Icons.light_mode_outlined, size: 16, color: Color(0xFF94A3B8)),
            Expanded(
              child: Slider(
                value: _light,
                min: 0.4,
                max: 1.6,
                divisions: 12,
                activeColor: const Color(0xFF4F46E5),
                onChanged: _canDriveViewer ? _setLight : null,
              ),
            ),
            SizedBox(
              width: 38,
              child: Text(
                '${(_light * 100).round()}%',
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 10.5),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildArtworkPreview(bool isDark) {
    return Container(
      height: 210,
      width: 140,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
        ),
      ),
      child: _artwork == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.add_photo_alternate_outlined,
                      size: 26,
                      color: isDark
                          ? const Color(0xFF475569)
                          : const Color(0xFFCBD5E1),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No artwork yet',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: isDark
                            ? const Color(0xFF64748B)
                            : const Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final h = constraints.maxHeight;
                return ClipRect(
                  child: Transform.translate(
                    offset: Offset(_x / 100 * w, _y / 100 * h),
                    child: Transform.rotate(
                      angle: _rotation * math.pi / 180,
                      child: Transform.scale(
                        scale: _scale,
                        child: Image.file(
                          _artwork!,
                          width: w,
                          height: h,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildSectionLabel(String text, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          letterSpacing: 1.1,
          fontWeight: FontWeight.w700,
          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF94A3B8),
        ),
      ),
    );
  }

  Widget _buildSlider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(label, style: const TextStyle(fontSize: 11)),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            activeColor: const Color(0xFF4F46E5),
            onChanged: onChanged,
            // Re-stamp the texture once the drag settles, so the 3D mockup
            // tracks the editor without re-uploading on every frame.
            onChangeEnd: (_) => _refreshAppliedArtwork(),
          ),
        ),
        SizedBox(
          width: 42,
          child: Text(
            label == 'Scale' ? '${value.toStringAsFixed(2)}x' : value.toStringAsFixed(0),
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 10.5),
          ),
        ),
      ],
    );
  }
}
