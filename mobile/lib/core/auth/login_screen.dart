import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../widgets/attr_tag.dart';
import '../widgets/serial_tag.dart';
import 'auth_service.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _AnimatedCardsBackground extends StatefulWidget {
  const _AnimatedCardsBackground();

  @override
  State<_AnimatedCardsBackground> createState() => _AnimatedCardsBackgroundState();
}

class _AnimatedCardsBackgroundState extends State<_AnimatedCardsBackground> with TickerProviderStateMixin {
  late AnimationController _cardController;
  late AnimationController _chipController;
  late List<Animation<Offset>> _cardSlides;
  late List<Animation<double>> _cardFades;
  late List<Animation<double>> _chipDrops;

  void _setupAnimations() {
    _cardController = AnimationController(duration: const Duration(milliseconds: 1200), vsync: this);
    _chipController = AnimationController(duration: const Duration(milliseconds: 1300), vsync: this);

    // Card animations: staggered slides and fades
    _cardSlides = List.generate(
      5,
      (i) => Tween<Offset>(begin: const Offset(0, 0.4), end: Offset.zero).animate(
        CurvedAnimation(
          parent: _cardController,
          curve: Interval(i * 0.15, i * 0.15 + 0.3, curve: Curves.easeOut),
        ),
      ),
    );

    _cardFades = List.generate(
      5,
      (i) => Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(
          parent: _cardController,
          curve: Interval(i * 0.15, i * 0.15 + 0.3, curve: Curves.easeOut),
        ),
      ),
    );

    // Chip animations: staggered drops with elastic bounce
    _chipDrops = List.generate(
      6,
      (i) => Tween<double>(begin: -30, end: 0).animate(
        CurvedAnimation(
          parent: _chipController,
          curve: Interval(i * 0.1, i * 0.1 + 0.4, curve: Curves.elasticOut),
        ),
      ),
    );

    _cardController.forward();
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) _chipController.forward();
    });
  }

  @override
  void initState() {
    super.initState();
    _setupAnimations();
  }

  @override
  void didUpdateWidget(covariant _AnimatedCardsBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reset animations on hot reload
    _cardController.dispose();
    _chipController.dispose();
    _setupAnimations();
  }

  @override
  void dispose() {
    _cardController.dispose();
    _chipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cardPositions = [
      (20.0, 180.0, -0.15),
      (60.0, 160.0, -0.05),
      (110.0, 170.0, 0.08),
      (155.0, 155.0, 0.18),
      (195.0, 185.0, 0.28),
    ];

    final chipData = [
      (-55.0, -45.0, 'RC', Colors.green),
      (-15.0, -65.0, 'AUTO', Colors.purple),
      (30.0, -50.0, 'PATCH', Colors.blue),
      (75.0, -60.0, 'SSP', Colors.amber),
      (115.0, -50.0, '/99', Colors.blue),
      (150.0, -42.0, '/25', Colors.orange),
    ];

    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Animated cards
          ...List.generate(5, (i) {
            final (x, y, rotation) = cardPositions[i];
            return AnimatedBuilder(
              animation: Listenable.merge([_cardSlides[i], _cardFades[i]]),
              builder: (context, child) {
                final slideOffset = _cardSlides[i].value * 60;
                return Transform.translate(
                  offset: Offset(x - 140, y + slideOffset.dy),
                  child: Transform.rotate(
                    angle: rotation,
                    child: Opacity(
                      opacity: _cardFades[i].value,
                      child: _CardWidget(),
                    ),
                  ),
                );
              },
            );
          }),

          // Animated chips
          ...List.generate(6, (i) {
            final (x, y, label, color) = chipData[i];
            return AnimatedBuilder(
              animation: _chipDrops[i],
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(x, y + _chipDrops[i].value),
                  child: label.startsWith('/')
                      ? SerialTag(serialNumber: label, serialMax: int.tryParse(label.substring(1)) ?? 99)
                      : AttrTag(label, color: color),
                );
              },
            );
          }),
        ],
      ),
    );
  }
}

class _CardWidget extends StatelessWidget {
  const _CardWidget();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 70,
      height: 95,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.grey[850]!,
            Colors.grey[950]!,
          ],
        ),
        border: Border.all(
          color: Colors.grey[700]!,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
          // Inset shadow for depth
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.08),
            blurRadius: 4,
            offset: const Offset(1, 1),
            spreadRadius: -1,
          ),
        ],
      ),
      child: Stack(
        children: [
          // Inner border/inset effect
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: Colors.grey[800]!.withValues(alpha: 0.5),
                  width: 1,
                ),
              ),
              margin: const EdgeInsets.all(2),
            ),
          ),

          // Shimmer/gloss overlay
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: 0.12),
                    Colors.white.withValues(alpha: 0.02),
                    Colors.transparent,
                  ],
                  stops: const [0, 0.3, 1],
                ),
              ),
            ),
          ),

          // Athlete icon/silhouette
          Center(
            child: Icon(
              Icons.sports_basketball,
              color: Colors.grey[600],
              size: 32,
            ),
          ),

          // Team color indicator (top-left corner)
          Positioned(
            left: 4,
            top: 4,
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),

          // Card number (bottom-right)
          Positioned(
            right: 4,
            bottom: 4,
            child: Text(
              '#42',
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.bold,
                color: Colors.grey[400],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LockedCardWidget extends StatelessWidget {
  const _LockedCardWidget();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      height: 320,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF424242).withValues(alpha: 0.4),
            const Color(0xFF1A1A1A).withValues(alpha: 0.5),
          ],
        ),
        border: Border.all(
          color: const Color(0xFF616161).withValues(alpha: 0.6),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
          // Outer glow
          BoxShadow(
            color: AppTheme.primary.withValues(alpha: 0.25),
            blurRadius: 24,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Stack(
        children: [
          // Shimmer overlay
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: 0.1),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // Lock icon
          Center(
            child: Icon(
              Icons.lock,
              color: Colors.grey[600],
              size: 80,
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureIcon extends StatelessWidget {
  const _FeatureIcon({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.1),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          child: Icon(
            icon,
            color: Colors.white.withValues(alpha: 0.7),
            size: 24,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _HoloShimmerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Base dark gradient
    final basePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFF0A0A0E),
          const Color(0xFF1A0F2E),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), basePaint);

    // Subtle rainbow sweep across (very low opacity)
    final rainbowPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFF00F5D4).withValues(alpha: 0.06),
          const Color(0xFF3B82F6).withValues(alpha: 0.05),
          const Color(0xFF8B5CF6).withValues(alpha: 0.06),
          const Color(0xFFEC4899).withValues(alpha: 0.05),
          const Color(0xFFF59E0B).withValues(alpha: 0.06),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), rainbowPaint);

    // Soft radial bloom (top-left)
    final bloomPaint1 = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.4, -0.5),
        radius: 1.2,
        colors: [
          const Color(0xFF00F5D4).withValues(alpha: 0.12),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bloomPaint1);

    // Soft radial bloom (bottom-right)
    final bloomPaint2 = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.3, 0.6),
        radius: 1.3,
        colors: [
          const Color(0xFF3B82F6).withValues(alpha: 0.08),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bloomPaint2);

    // Subtle vertical shimmer
    final shimmerPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFFEC4899).withValues(alpha: 0.04),
          Colors.transparent,
          const Color(0xFFF59E0B).withValues(alpha: 0.04),
          Colors.transparent,
        ],
        stops: const [0, 0.25, 0.75, 1],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), shimmerPaint);

    // Vignette: subtle darkening at edges
    final vignettePaint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 1.4,
        colors: [
          Colors.transparent,
          Colors.black.withValues(alpha: 0.1),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), vignettePaint);
  }

  @override
  bool shouldRepaint(_HoloShimmerPainter oldDelegate) => false;
}

class _HoloBackground extends StatelessWidget {
  const _HoloBackground({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Base dark color
        Container(color: const Color(0xFF0A0A0E)),

        // Holographic shimmer painter
        CustomPaint(
          painter: _HoloShimmerPainter(),
          size: Size.infinite,
        ),

        // Content on top
        child,
      ],
    );
  }
}

class _LoginScreenState extends ConsumerState<LoginScreen> with TickerProviderStateMixin {
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading    = false;
  bool _usePassword = false;
  String? _message;
  bool _isError = false;

  late AnimationController _brandController;
  late AnimationController _buttonController;
  late Animation<double> _eyebrowFade;
  late Animation<double> _headingFade;
  late Animation<double> _taglineFade;
  late Animation<double> _buttonGlow;

  @override
  void initState() {
    super.initState();
    _brandController = AnimationController(duration: const Duration(milliseconds: 1200), vsync: this);
    _buttonController = AnimationController(duration: const Duration(milliseconds: 1500), vsync: this)..repeat();

    _eyebrowFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _brandController, curve: const Interval(0, 0.3, curve: Curves.easeOut)),
    );
    _headingFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _brandController, curve: const Interval(0.15, 0.6, curve: Curves.easeOut)),
    );
    _taglineFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _brandController, curve: const Interval(0.35, 0.8, curve: Curves.easeOut)),
    );
    _buttonGlow = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _buttonController, curve: Curves.easeInOut),
    );

    _brandController.forward();
  }

  @override
  void dispose() {
    _brandController.dispose();
    _buttonController.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() { _loading = true; _message = null; });
    try {
      final auth = ref.read(authServiceProvider);
      if (_usePassword) {
        await auth.signInWithPassword(_emailCtrl.text.trim(), _passwordCtrl.text);
      } else {
        await auth.signInWithEmail(_emailCtrl.text.trim());
        setState(() { _message = 'Check your email for a magic link.'; _isError = false; });
      }
    } catch (e) {
      setState(() { _message = e.toString(); _isError = true; });
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black87,
      body: _HoloBackground(
        child: SafeArea(
          child: Column(
            children: [
              // Brand block with locked card
              Expanded(
                flex: 2,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Large locked card behind
                    Positioned(
                      top: 120,
                      child: _LockedCardWidget(),
                    ),
                    // Brand text on top
                    Center(
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                          // Eyebrow
                          AnimatedBuilder(
                            animation: _eyebrowFade,
                            builder: (context, child) => Opacity(opacity: _eyebrowFade.value, child: child),
                            child: Text(
                              'CARD VAULT',
                              style: GoogleFonts.oswald(
                                fontSize: 11,
                                fontWeight: FontWeight.w300,
                                letterSpacing: 2.5,
                                color: const Color(0xFF6B7280),
                                shadows: [
                                  Shadow(
                                    offset: const Offset(0, 0),
                                    blurRadius: 8,
                                    color: AppTheme.primary.withValues(alpha: 0.3),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          // Large logotype
                          AnimatedBuilder(
                            animation: _headingFade,
                            builder: (context, child) => Opacity(opacity: _headingFade.value, child: child),
                            child: Text(
                              'YOUR\nCOLLECTION',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.oswald(
                                fontSize: 48,
                                fontWeight: FontWeight.w700,
                                height: 1.1,
                                color: Colors.white,
                                shadows: [
                                  Shadow(
                                    offset: const Offset(0, 0),
                                    blurRadius: 12,
                                    color: AppTheme.primary.withValues(alpha: 0.4),
                                  ),
                                  Shadow(
                                    offset: const Offset(0, 0),
                                    blurRadius: 24,
                                    color: AppTheme.primary.withValues(alpha: 0.2),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          // Tagline
                          AnimatedBuilder(
                            animation: _taglineFade,
                            builder: (context, child) => Opacity(opacity: _taglineFade.value, child: child),
                            child: Text(
                              'Track. Value. Sell.',
                              style: GoogleFonts.oswald(
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
                                letterSpacing: 0.5,
                                color: Colors.white.withValues(alpha: 0.5),
                                shadows: [
                                  Shadow(
                                    offset: const Offset(0, 0),
                                    blurRadius: 8,
                                    color: AppTheme.primary.withValues(alpha: 0.25),
                                  ),
                                ],
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
              ),

              // Feature icons row
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _FeatureIcon(icon: Icons.search, label: 'Search'),
                    _FeatureIcon(icon: Icons.qr_code_2, label: 'Scan'),
                    _FeatureIcon(icon: Icons.trending_up, label: 'Invest'),
                    _FeatureIcon(icon: Icons.favorite_outline, label: 'Wishlist'),
                    _FeatureIcon(icon: Icons.analytics, label: 'Analyze'),
                  ],
                ),
              ),

              // Form section
              Expanded(
                flex: 1,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextField(
                                controller: _emailCtrl,
                                keyboardType: TextInputType.emailAddress,
                                autocorrect: false,
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  labelText: 'Email address',
                                  labelStyle: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.5),
                                    fontSize: 13,
                                  ),
                                  filled: false,
                                  fillColor: Colors.transparent,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide(color: AppTheme.primary, width: 1.5),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                ),
                              ),
                              if (_usePassword) ...[
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _passwordCtrl,
                                  obscureText: true,
                                  style: const TextStyle(color: Colors.white),
                                  decoration: InputDecoration(
                                    labelText: 'Password',
                                    labelStyle: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.5),
                                      fontSize: 13,
                                    ),
                                    filled: false,
                                    fillColor: Colors.transparent,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide(color: AppTheme.primary, width: 1.5),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 20),
                              AnimatedBuilder(
                                animation: _buttonGlow,
                                builder: (context, child) {
                                  final glowAlpha = (0.3 * (0.5 + 0.5 * (_buttonGlow.value - 0.5).abs() * 2)).clamp(0.1, 0.5);
                                  return Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppTheme.primary.withValues(alpha: glowAlpha),
                                          blurRadius: 12 + (8 * _buttonGlow.value),
                                          spreadRadius: 1 + (2 * _buttonGlow.value),
                                        ),
                                      ],
                                    ),
                                    child: child,
                                  );
                                },
                                child: SizedBox(
                                  height: 48,
                                  child: FilledButton(
                                    onPressed: _loading ? null : _signIn,
                                    style: FilledButton.styleFrom(
                                      backgroundColor: AppTheme.primary,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                    child: _loading
                                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                        : Text(
                                            _usePassword ? 'Sign In' : 'Send Magic Link',
                                            style: GoogleFonts.oswald(fontWeight: FontWeight.w600, fontSize: 15),
                                          ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextButton(
                                onPressed: () => setState(() { _usePassword = !_usePassword; _message = null; }),
                                child: Text(
                                  _usePassword ? 'Use magic link instead' : 'Sign in with password instead',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.6),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              if (_message != null) ...[
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: (_isError ? Colors.red : AppTheme.primary).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: (_isError ? Colors.red : AppTheme.primary).withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Text(
                                    _message!,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: _isError ? Colors.red.shade300 : AppTheme.primary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
