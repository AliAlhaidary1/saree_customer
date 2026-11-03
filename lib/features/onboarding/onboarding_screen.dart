import 'package:flutter/material.dart';

import '../../core/app_controller.dart';
import '../../core/app_theme.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onComplete});

  final Future<void> Function() onComplete;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _index = 0;
  bool _completing = false;

  static const _pages = [
    _OnboardingPageData(
      imagePath: 'assets/brand/onboarding-shopping-v2.png',
      titleKey: 'onboarding_1_title',
      bodyKey: 'onboarding_1_body',
    ),
    _OnboardingPageData(
      imagePath: 'assets/brand/onboarding-delivery-v2.png',
      titleKey: 'onboarding_2_title',
      bodyKey: 'onboarding_2_body',
    ),
    _OnboardingPageData(
      imagePath: 'assets/brand/onboarding-services-v2.png',
      titleKey: 'onboarding_3_title',
      bodyKey: 'onboarding_3_body',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (_completing) return;
    setState(() => _completing = true);
    try {
      await widget.onComplete();
    } finally {
      if (mounted) setState(() => _completing = false);
    }
  }

  void _next() {
    if (_index == _pages.length - 1) {
      _finish();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _index == _pages.length - 1;
    return Scaffold(
      backgroundColor: const Color(0xFFF8FBFE),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            children: [
              SizedBox(
                height: 52,
                child: Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              color: AppTheme.accentOrange,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 9),
                          const Flexible(
                            child: Text(
                              AppTheme.brandNameAr,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppTheme.primaryNavy,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      key: const Key('onboarding_skip'),
                      onPressed: _completing ? null : _finish,
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.textSecondary,
                      ),
                      child: Text(appController.t('onboarding_skip')),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: PageView.builder(
                  key: const Key('onboarding_pages'),
                  controller: _controller,
                  physics: const BouncingScrollPhysics(),
                  itemCount: _pages.length,
                  onPageChanged: (value) => setState(() => _index = value),
                  itemBuilder: (context, index) =>
                      _OnboardingPage(data: _pages[index]),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Text(
                    '${_index + 1} / ${_pages.length}',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  for (var i = 0; i < _pages.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      width: i == _index ? 26 : 7,
                      height: 7,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: i == _index
                            ? AppTheme.accentOrange
                            : AppTheme.primaryNavy.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  key: const Key('onboarding_next'),
                  onPressed: _completing ? null : _next,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.accentOrange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: _completing
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          appController.t(
                            isLast ? 'onboarding_start' : 'onboarding_next',
                          ),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
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

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({required this.data});

  final _OnboardingPageData data;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(32),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primaryNavy.withValues(alpha: 0.08),
                            blurRadius: 30,
                            offset: const Offset(0, 14),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(32),
                        child: Image.asset(
                          data.imagePath,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Container(
                  width: 38,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppTheme.accentOrange,
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                appController.t(data.titleKey),
                textAlign: TextAlign.start,
                style: const TextStyle(
                  color: AppTheme.primaryNavy,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Text(
                  appController.t(data.bodyKey),
                  textAlign: TextAlign.start,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 16,
                    height: 1.75,
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

class _OnboardingPageData {
  const _OnboardingPageData({
    required this.imagePath,
    required this.titleKey,
    required this.bodyKey,
  });

  final String imagePath;
  final String titleKey;
  final String bodyKey;
}
