import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';

/// Full-screen in-app camera with Card Vault styling (burgundy accents, card frame guide).
class ScanCameraPage extends StatefulWidget {
  const ScanCameraPage({
    super.key,
    required this.accentColor,
    required this.sportLabel,
    required this.onCaptured,
    required this.onClose,
  });

  final Color accentColor;
  final String sportLabel;
  final void Function(Uint8List bytes) onCaptured;
  final VoidCallback onClose;

  @override
  State<ScanCameraPage> createState() => _ScanCameraPageState();
}

class _ScanCameraPageState extends State<ScanCameraPage> {
  CameraController? _controller;
  bool _initializing = true;
  String? _initError;
  bool _capturing = false;
  FlashMode _flash = FlashMode.auto;

  @override
  void initState() {
    super.initState();
    _setupCamera();
  }

  Future<void> _setupCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _initializing = false;
            _initError = 'No camera found on this device.';
          });
        }
        return;
      }

      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await controller.initialize();
      await controller.setFlashMode(_flash);
      await _enableAutofocus(controller);

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _initializing = false;
        _initError = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _initializing = false;
          _initError = 'Could not open camera: $e';
        });
      }
    }
  }

  /// Continuous AF/AE and a center AF/AE trigger so the first frame isn’t stuck soft.
  static Future<void> _enableAutofocus(CameraController c) async {
    if (!c.value.isInitialized) return;
    try {
      await c.setFocusMode(FocusMode.auto);
      await c.setExposureMode(ExposureMode.auto);
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!c.value.isInitialized) return;
    try {
      await c.setFocusPoint(const Offset(0.5, 0.52));
      await c.setExposurePoint(const Offset(0.5, 0.52));
    } catch (_) {}
  }

  Future<void> _cycleFlash() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final next = switch (_flash) {
      FlashMode.off => FlashMode.auto,
      FlashMode.auto => FlashMode.always,
      FlashMode.always => FlashMode.torch,
      FlashMode.torch => FlashMode.off,
    };
    try {
      await c.setFlashMode(next);
      if (mounted) setState(() => _flash = next);
    } catch (_) {
      try {
        await c.setFlashMode(FlashMode.off);
        if (mounted) setState(() => _flash = FlashMode.off);
      } catch (_) {}
    }
  }

  Future<void> _shutter() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _capturing) return;
    setState(() => _capturing = true);
    try {
      final shot = await c.takePicture();
      final bytes = await shot.readAsBytes();
      if (!mounted) return;
      widget.onCaptured(bytes);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Capture failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  IconData _flashIcon() {
    return switch (_flash) {
      FlashMode.off => Icons.flash_off_rounded,
      FlashMode.auto => Icons.flash_auto_rounded,
      FlashMode.always => Icons.flash_on_rounded,
      FlashMode.torch => Icons.highlight_rounded,
    };
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final bottom = MediaQuery.paddingOf(context).bottom;

    if (_initializing) {
      return ColoredBox(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                color: widget.accentColor,
                strokeWidth: 2,
              ),
              const SizedBox(height: 16),
              Text(
                'Preparing camera…',
                style: GoogleFonts.oswald(
                  fontSize: 15,
                  color: Colors.white70,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_initError != null) {
      return ColoredBox(
        color: Colors.black,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    onPressed: widget.onClose,
                    style: IconButton.styleFrom(foregroundColor: Colors.white),
                    icon: const Icon(Icons.close_rounded, size: 28),
                  ),
                ),
                const Spacer(),
                Text(
                  _initError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: widget.onClose,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Go back'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final c = _controller!;
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _CameraPreviewFill(controller: c),
          // Dimmed overlay + card cutout
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _ScanFramePainter(
                  cornerColor: Colors.white.withValues(alpha: 0.9),
                  dimColor: Colors.black.withValues(alpha: 0.55),
                ),
              ),
            ),
          ),
          // Top chrome
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: Padding(
              padding: EdgeInsets.fromLTRB(8, top + 4, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: widget.onClose,
                    style: IconButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.black38,
                    ),
                    icon: const Icon(Icons.close_rounded),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: widget.accentColor.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: widget.accentColor.withValues(alpha: 0.8),
                      ),
                    ),
                    child: Text(
                      widget.sportLabel,
                      style: GoogleFonts.oswald(
                        fontSize: 14,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: _cycleFlash,
                    style: IconButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.black38,
                    ),
                    icon: Icon(_flashIcon()),
                  ),
                ],
              ),
            ),
          ),
          // Hint
          Positioned(
            left: 24,
            right: 24,
            bottom: bottom + 168,
            child: Text(
              'Tap to refocus · Center the card in the frame — avoid glare and shadows.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 14,
                height: 1.35,
                shadows: const [
                  Shadow(color: Colors.black54, blurRadius: 8),
                ],
              ),
            ),
          ),
          // Bottom controls
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Padding(
              padding: EdgeInsets.fromLTRB(24, 16, 24, bottom + 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: _capturing ? null : _shutter,
                    child: Container(
                      width: 78,
                      height: 78,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primary.withValues(alpha: 0.45),
                            blurRadius: 18,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(5),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _capturing
                                ? Colors.white38
                                : AppTheme.primary,
                          ),
                          child: _capturing
                              ? const Padding(
                                  padding: EdgeInsets.all(20),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(
                                  Icons.camera_alt_rounded,
                                  color: Colors.white,
                                  size: 30,
                                ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraPreviewFill extends StatelessWidget {
  const _CameraPreviewFill({required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    if (!controller.value.isInitialized) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            var scale = size.aspectRatio * controller.value.aspectRatio;
            if (scale < 1) scale = 1 / scale;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) async {
                if (!controller.value.isInitialized) return;
                final x = (d.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
                final y = (d.localPosition.dy / constraints.maxHeight).clamp(0.0, 1.0);
                try {
                  await controller.setFocusMode(FocusMode.auto);
                  await controller.setFocusPoint(Offset(x, y));
                  await controller.setExposurePoint(Offset(x, y));
                } catch (_) {}
              },
              child: ClipRect(
                child: Transform.scale(
                  scale: scale,
                  alignment: Alignment.center,
                  child: Center(
                    child: CameraPreview(controller),
                  ),
                ),
              ),
            );
          },
        );
  }
}

/// Rounded-rect "viewfinder" with dimmed surroundings (trading-card aspect ~ 2.5:3.5).
class _ScanFramePainter extends CustomPainter {
  _ScanFramePainter({
    required this.cornerColor,
    required this.dimColor,
  });

  final Color cornerColor;
  final Color dimColor;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    const marginX = 28.0;
    final rectWidth = (w - marginX * 2).clamp(200.0, w - 40);
    final rectHeight = rectWidth * (3.5 / 2.5);
    final left = (w - rectWidth) / 2;
    final top = (h - rectHeight) / 2 - h * 0.04;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, rectWidth, rectHeight),
      const Radius.circular(14),
    );

    final dimPath = Path()..addRect(Rect.fromLTWH(0, 0, w, h));
    final hole = Path()..addRRect(rrect);
    final overlay = Path.combine(PathOperation.difference, dimPath, hole);

    canvas.drawPath(
      overlay,
      Paint()..color = dimColor,
    );

    final cornerLen = 28.0;
    final stroke = Paint()
      ..color = cornerColor
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    void corner(Offset o, bool flipH, bool flipV) {
      final dx = flipH ? -cornerLen : cornerLen;
      final dy = flipV ? -cornerLen : cornerLen;
      canvas.drawLine(o, o + Offset(dx, 0), stroke);
      canvas.drawLine(o, o + Offset(0, dy), stroke);
    }

    corner(Offset(left, top), false, false);
    corner(Offset(left + rectWidth, top), true, false);
    corner(Offset(left, top + rectHeight), false, true);
    corner(Offset(left + rectWidth, top + rectHeight), true, true);
  }

  @override
  bool shouldRepaint(covariant _ScanFramePainter oldDelegate) =>
      oldDelegate.cornerColor != cornerColor || oldDelegate.dimColor != dimColor;
}
