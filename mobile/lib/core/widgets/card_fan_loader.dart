import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class CardFanLoader extends StatefulWidget {
  const CardFanLoader({super.key, this.size = 56.0});
  final double size;

  @override
  State<CardFanLoader> createState() => _CardFanLoaderState();
}

class _CardFanLoaderState extends State<CardFanLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fanAnimation;
  late final Animation<double> _collapseAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();

    _fanAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0, 0.6, curve: Curves.easeOut)),
    );

    _collapseAnimation = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.6, 1, curve: Curves.easeIn)),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cardWidth = widget.size * 0.5;
    final cardHeight = widget.size * 0.7;

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final fanProgress = _fanAnimation.value;
            final collapseProgress = _collapseAnimation.value;
            final progress = fanProgress > 0 ? fanProgress : collapseProgress;

            return SizedBox(
              width: widget.size * 1.2,
              height: widget.size,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Card 1 (Back) - fans left
                  Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.001)
                      ..rotateZ(-0.436 * progress) // ~-25 degrees
                      ..translate(-18.0 * progress, 0.0, 0.0),
                    child: Container(
                      width: cardWidth,
                      height: cardHeight,
                      decoration: BoxDecoration(
                        color: const Color(0xFF4A0012),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Card 2 (Middle) - stays centered, grows slightly
                  Transform.scale(
                    scale: 1 + (0.08 * progress),
                    child: Container(
                      width: cardWidth,
                      height: cardHeight,
                      decoration: BoxDecoration(
                        color: const Color(0xFF9D0028),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 1),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 6,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Card 3 (Front) - fans right
                  Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.001)
                      ..rotateZ(0.436 * progress) // ~+25 degrees
                      ..translate(18 * progress, 0),
                    child: Container(
                      width: cardWidth,
                      height: cardHeight,
                      decoration: BoxDecoration(
                        color: AppTheme.primary,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 1),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
