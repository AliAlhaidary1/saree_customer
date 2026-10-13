import 'package:flutter/material.dart';

import '../core/app_theme.dart';

/// شاشة بداية واحدة فقط — خلفية كحلية سادة (نفس لون الـ Native)
/// أنيميشن بسيط وسريع: خطوط سرعة + ومضة برق + ظهور اسم سريع MART.
class BrandSplashScreen extends StatefulWidget {
  const BrandSplashScreen({super.key, this.onComplete});

  final VoidCallback? onComplete;

  @override
  State<BrandSplashScreen> createState() => _BrandSplashScreenState();
}

class _BrandSplashScreenState extends State<BrandSplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  late final Animation<double> _lines; // خطوط السرعة تنزلق من اليسار
  late final Animation<double> _brandFade; // الاسم يظهر
  late final Animation<double> _brandSlide; // الاسم ينزلق للأعلى قليلاً
  late final Animation<double> _lineGrow; // الخط البرتقالي يتمدد
  late final Animation<double> _bolt1; // ومضة البرق الأولى
  late final Animation<double> _bolt2; // ومضة البرق الثانية

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _lines = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _c,
        curve: const Interval(0.0, 0.30, curve: Curves.easeOutCubic),
      ),
    );
    _brandFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _c,
        curve: const Interval(0.15, 0.50, curve: Curves.easeOut),
      ),
    );
    _brandSlide = Tween<double>(begin: 18.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _c,
        curve: const Interval(0.15, 0.50, curve: Curves.easeOutCubic),
      ),
    );
    // البرق يومض مرتين: 0.35-0.50 و 0.60-0.75
    _bolt1 = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _c,
        curve: const Interval(0.35, 0.50, curve: Curves.easeInOut),
      ),
    );
    _bolt2 = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _c,
        curve: const Interval(0.60, 0.75, curve: Curves.easeInOut),
      ),
    );
    _lineGrow = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _c,
        curve: const Interval(0.45, 0.70, curve: Curves.easeOutCubic),
      ),
    );

    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.primaryNavy,
      body: Center(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            // شدة البرق = max الومضتين (يومض مرتين ثم يثبت)
            final bolt = (_bolt1.value > _bolt2.value
                    ? _bolt1.value
                    : _bolt2.value)
                .clamp(0.0, 1.0);
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // خطوط السرعة
                    Opacity(
                      opacity: _lines.value.clamp(0.0, 1.0),
                      child: Transform.translate(
                        offset: Offset(
                          -30 * (1 - _lines.value.clamp(0.0, 1.0)),
                          0,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _bar(30, 0.9),
                            const SizedBox(height: 5),
                            _bar(42, 1.0),
                            const SizedBox(height: 5),
                            _bar(24, 0.7),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // الاسم: سريع بالأبيض
                    Opacity(
                      opacity: _brandFade.value.clamp(0.0, 1.0),
                      child: Transform.translate(
                        offset: Offset(0, _brandSlide.value),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'سريع',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 46,
                                fontWeight: FontWeight.w800,
                                height: 1.1,
                              ),
                            ),
                            const SizedBox(width: 6),
                            // البرق بجانب الاسم يومض
                            Icon(
                              Icons.bolt_rounded,
                              size: 30,
                              color: Color(0xFFFF6B00).withValues(
                                alpha: 0.25 + 0.75 * bolt,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                // MART أسفل الاسم
                Opacity(
                  opacity: _brandFade.value.clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset(0, _brandSlide.value),
                    child: const Text(
                      'MART',
                      style: TextStyle(
                        color: Color(0xFFFF6B00),
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 6.0,
                        height: 1.1,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // الخط المتمدد تحت الاسم
                Opacity(
                  opacity: _brandFade.value.clamp(0.0, 1.0),
                  child: Transform.scale(
                    scaleX: _lineGrow.value.clamp(0.001, 1.0),
                    alignment: Alignment.center,
                    child: Container(
                      width: 200,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF6B00),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _bar(double width, double opacity) {
    return Container(
      width: width * _lines.value.clamp(0.0, 1.0),
      height: 5,
      decoration: BoxDecoration(
        color: const Color(0xFFFF6B00).withValues(alpha: opacity),
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}
