import 'package:flutter/material.dart';

import '../core/app_theme.dart';

/// Branded launch splash with cart icon speed-line animation and brand fade-in.
class BrandSplashScreen extends StatefulWidget {
  const BrandSplashScreen({super.key, this.onComplete});

  final VoidCallback? onComplete;

  @override
  State<BrandSplashScreen> createState() => _BrandSplashScreenState();
}

class _BrandSplashScreenState extends State<BrandSplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _slideAnim;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _lineAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _slideAnim = Tween<double>(begin: -80, end: 0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOutCubic),
      ),
    );
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.35, 1.0, curve: Curves.easeOut),
      ),
    );
    _lineAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.55, curve: Curves.easeOut),
      ),
    );
    _controller.forward().then((_) {
      if (mounted) widget.onComplete?.call();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.primaryNavy,
      body: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 120,
                  height: 80,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Glowing orange speed lines
                      for (int i = 0; i < 3; i++)
                        Positioned(
                          left: 8 + i * 6,
                          child: Opacity(
                            opacity: _lineAnim.value * (0.4 + i * 0.2),
                            child: Transform.translate(
                              offset: Offset(
                                -40 + _lineAnim.value * (30 + i * 8),
                                0,
                              ),
                              child: Container(
                                width: 28 + i * 6,
                                height: 3,
                                decoration: BoxDecoration(
                                  color: AppTheme.accentOrange,
                                  borderRadius: BorderRadius.circular(2),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppTheme.accentOrange
                                          .withValues(alpha: 0.6),
                                      blurRadius: 8,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      // Brand icon sliding in
                      Transform.translate(
                        offset: Offset(_slideAnim.value, 0),
                        child: Image.asset(
                          'assets/brand/sreamart-mark.png',
                          width: 72,
                          height: 72,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Opacity(
                  opacity: _fadeAnim.value,
                  child: Column(
                    children: [
                      Text(
                        AppTheme.brandNameAr,
                        style: TextStyle(
                          color: AppTheme.backgroundWhite,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        AppTheme.brandNameEn,
                        style: TextStyle(
                          color: AppTheme.accentOrange,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
