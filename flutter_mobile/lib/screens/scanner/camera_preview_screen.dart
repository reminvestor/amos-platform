import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:amos_mobile/screens/scanner/scanner_screen.dart';
import 'package:amos_mobile/config/theme.dart';

/// Camera preview screen with scanning overlay
class CameraPreviewScreen extends StatefulWidget {
  final ScanMode mode;

  const CameraPreviewScreen({super.key, required this.mode});

  @override
  State<CameraPreviewScreen> createState() => _CameraPreviewScreenState();
}

class _CameraPreviewScreenState extends State<CameraPreviewScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;
  bool _isCapturing = false;
  String? _error;
  File? _capturedImage; // Preview state

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      controller.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        setState(() => _error = 'No cameras available');
        return;
      }

      // Use the back camera
      final camera = _cameras!.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras!.first,
      );

      _controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _controller!.initialize();

      if (mounted) {
        setState(() => _isInitialized = true);
      }
    } catch (e) {
      setState(() => _error = 'Failed to initialize camera: $e');
    }
  }

  Future<void> _captureImage() async {
    if (_controller == null || !_controller!.value.isInitialized || _isCapturing) {
      return;
    }

    setState(() => _isCapturing = true);

    try {
      final image = await _controller!.takePicture();
      if (mounted) {
        setState(() {
          _capturedImage = File(image.path);
          _isCapturing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to capture: $e')),
        );
        setState(() => _isCapturing = false);
      }
    }
  }

  void _retakePhoto() {
    // Delete the captured image file
    _capturedImage?.delete();
    setState(() => _capturedImage = null);
  }

  void _usePhoto() {
    if (_capturedImage != null) {
      Navigator.pop(context, _capturedImage);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show preview if image is captured
    if (_capturedImage != null) {
      return _buildPreviewScreen();
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Camera preview
          if (_isInitialized && _controller != null)
            Center(
              child: CameraPreview(_controller!),
            )
          else if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),

          // Scanning overlay
          if (_isInitialized) _ScanOverlay(mode: widget.mode),

          // Top bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(LucideIcons.x, color: Colors.white, size: 28),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: widget.mode.color.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(widget.mode.icon, color: Colors.white, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            widget.mode.label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    const SizedBox(width: 48), // Balance the close button
                  ],
                ),
              ),
            ),
          ),

          // Bottom controls
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Hint text
                    Text(
                      _getHintText(),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    // Capture button
                    GestureDetector(
                      onTap: _isCapturing ? null : _captureImage,
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 4),
                        ),
                        child: Center(
                          child: _isCapturing
                              ? const SizedBox(
                                  width: 32,
                                  height: 32,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 3,
                                  ),
                                )
                              : Container(
                                  width: 56,
                                  height: 56,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Preview screen shown after capturing an image
  Widget _buildPreviewScreen() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Image preview
          Center(
            child: Image.file(
              _capturedImage!,
              fit: BoxFit.contain,
            ),
          ),

          // Top bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                color: Colors.black.withValues(alpha: 0.5),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(LucideIcons.x, color: Colors.white, size: 28),
                    ),
                    const Spacer(),
                    const Text(
                      'Review Photo',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 18,
                      ),
                    ),
                    const Spacer(),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
            ),
          ),

          // Bottom controls - Retake / Use Photo
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.8),
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    // Retake button
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _retakePhoto,
                        icon: const Icon(LucideIcons.refreshCw),
                        label: const Text('Retake'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Use Photo button
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: _usePhoto,
                        icon: const Icon(LucideIcons.check),
                        label: const Text('Use Photo'),
                        style: FilledButton.styleFrom(
                          backgroundColor: widget.mode.color,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getHintText() {
    switch (widget.mode) {
      case ScanMode.businessCard:
        return 'Position the business card within the frame';
      case ScanMode.receipt:
        return 'Capture the entire receipt';
      case ScanMode.document:
        return 'Align document edges with the frame';
      case ScanMode.whiteboard:
        return 'Include all whiteboard content';
    }
  }
}

/// Scanning overlay with animated border
class _ScanOverlay extends StatefulWidget {
  final ScanMode mode;

  const _ScanOverlay({required this.mode});

  @override
  State<_ScanOverlay> createState() => _ScanOverlayState();
}

class _ScanOverlayState extends State<_ScanOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate frame size based on mode
        final frameWidth = constraints.maxWidth * 0.85;
        final frameHeight = _getFrameHeight(frameWidth);

        return Stack(
          children: [
            // Dark overlay with cutout
            CustomPaint(
              size: Size(constraints.maxWidth, constraints.maxHeight),
              painter: _OverlayPainter(
                frameWidth: frameWidth,
                frameHeight: frameHeight,
                overlayColor: Colors.black.withValues(alpha: 0.6),
              ),
            ),
            // Animated frame border
            Center(
              child: AnimatedBuilder(
                animation: _animation,
                builder: (context, child) {
                  return Container(
                    width: frameWidth,
                    height: frameHeight,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Color.lerp(
                          widget.mode.color.withValues(alpha: 0.5),
                          widget.mode.color,
                          _animation.value,
                        )!,
                        width: 3,
                      ),
                    ),
                    child: Stack(
                      children: [
                        // Corner accents
                        ..._buildCornerAccents(frameWidth, frameHeight),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  double _getFrameHeight(double frameWidth) {
    switch (widget.mode) {
      case ScanMode.businessCard:
        // Business card aspect ratio (~1.75:1)
        return frameWidth / 1.75;
      case ScanMode.receipt:
        // Receipt is taller (~1:2)
        return frameWidth * 1.4;
      case ScanMode.document:
        // A4/Letter aspect ratio (~1:1.4)
        return frameWidth * 1.3;
      case ScanMode.whiteboard:
        // Landscape whiteboard (~1.5:1)
        return frameWidth / 1.3;
    }
  }

  List<Widget> _buildCornerAccents(double width, double height) {
    const cornerSize = 24.0;
    const cornerWidth = 4.0;
    final color = widget.mode.color;

    return [
      // Top-left
      Positioned(
        top: -2,
        left: -2,
        child: _CornerAccent(
          color: color,
          size: cornerSize,
          width: cornerWidth,
          corner: _Corner.topLeft,
        ),
      ),
      // Top-right
      Positioned(
        top: -2,
        right: -2,
        child: _CornerAccent(
          color: color,
          size: cornerSize,
          width: cornerWidth,
          corner: _Corner.topRight,
        ),
      ),
      // Bottom-left
      Positioned(
        bottom: -2,
        left: -2,
        child: _CornerAccent(
          color: color,
          size: cornerSize,
          width: cornerWidth,
          corner: _Corner.bottomLeft,
        ),
      ),
      // Bottom-right
      Positioned(
        bottom: -2,
        right: -2,
        child: _CornerAccent(
          color: color,
          size: cornerSize,
          width: cornerWidth,
          corner: _Corner.bottomRight,
        ),
      ),
    ];
  }
}

enum _Corner { topLeft, topRight, bottomLeft, bottomRight }

class _CornerAccent extends StatelessWidget {
  final Color color;
  final double size;
  final double width;
  final _Corner corner;

  const _CornerAccent({
    required this.color,
    required this.size,
    required this.width,
    required this.corner,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _CornerPainter(
          color: color,
          strokeWidth: width,
          corner: corner,
        ),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final _Corner corner;

  _CornerPainter({
    required this.color,
    required this.strokeWidth,
    required this.corner,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();

    switch (corner) {
      case _Corner.topLeft:
        path.moveTo(0, size.height);
        path.lineTo(0, 0);
        path.lineTo(size.width, 0);
        break;
      case _Corner.topRight:
        path.moveTo(0, 0);
        path.lineTo(size.width, 0);
        path.lineTo(size.width, size.height);
        break;
      case _Corner.bottomLeft:
        path.moveTo(0, 0);
        path.lineTo(0, size.height);
        path.lineTo(size.width, size.height);
        break;
      case _Corner.bottomRight:
        path.moveTo(0, size.height);
        path.lineTo(size.width, size.height);
        path.lineTo(size.width, 0);
        break;
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _OverlayPainter extends CustomPainter {
  final double frameWidth;
  final double frameHeight;
  final Color overlayColor;

  _OverlayPainter({
    required this.frameWidth,
    required this.frameHeight,
    required this.overlayColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = overlayColor;

    // Calculate frame position (centered)
    final frameLeft = (size.width - frameWidth) / 2;
    final frameTop = (size.height - frameHeight) / 2;

    // Create path with cutout
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(frameLeft, frameTop, frameWidth, frameHeight),
        const Radius.circular(12),
      ))
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _OverlayPainter oldDelegate) {
    return oldDelegate.frameWidth != frameWidth ||
        oldDelegate.frameHeight != frameHeight;
  }
}
