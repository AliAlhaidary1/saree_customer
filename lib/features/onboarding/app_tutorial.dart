import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

import '../../core/app_controller.dart';
import '../../core/app_theme.dart';

abstract final class AppTutorialKeys {
  static final search = GlobalKey(debugLabel: 'tutorial_search');
  static final cart = GlobalKey(debugLabel: 'tutorial_cart');
  static final assistant = GlobalKey(debugLabel: 'tutorial_assistant');
  static final haraj = GlobalKey(debugLabel: 'tutorial_haraj');
  static final akhdimni = GlobalKey(debugLabel: 'tutorial_akhdimni');
  static final orders = GlobalKey(debugLabel: 'tutorial_orders');

  static GlobalKey? forTab(String path) => switch (path) {
    '/haraj' => haraj,
    '/akhdimni' => akhdimni,
    '/orders' => orders,
    _ => null,
  };
}

class AppTutorial extends StatefulWidget {
  const AppTutorial({super.key, required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  @override
  State<AppTutorial> createState() => _AppTutorialState();
}

class _AppTutorialState extends State<AppTutorial> {
  TutorialCoachMark? _tutorial;
  bool _scheduled = false;
  bool _shown = false;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(covariant AppTutorial oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && !oldWidget.enabled) _schedule();
  }

  @override
  void dispose() {
    if (_tutorial?.isShowing ?? false) _tutorial!.finish();
    super.dispose();
  }

  void _schedule() {
    if (_scheduled || _shown || _completed || !widget.enabled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      _scheduled = false;
      if (!mounted || _shown || _completed || !widget.enabled) return;
      _shown = true;
      _show();
    });
  }

  void _complete() {
    if (_completed) return;
    _completed = true;
    unawaited(appController.completeAppTutorial());
  }

  void _show() {
    final steps = [
      _TutorialStep(
        key: AppTutorialKeys.search,
        titleKey: 'tutorial_search_title',
        bodyKey: 'tutorial_search_body',
        align: ContentAlign.bottom,
      ),
      _TutorialStep(
        key: AppTutorialKeys.cart,
        titleKey: 'tutorial_cart_title',
        bodyKey: 'tutorial_cart_body',
        align: ContentAlign.bottom,
      ),
      _TutorialStep(
        key: AppTutorialKeys.assistant,
        titleKey: 'tutorial_assistant_title',
        bodyKey: 'tutorial_assistant_body',
        align: ContentAlign.top,
      ),
      _TutorialStep(
        key: AppTutorialKeys.haraj,
        titleKey: 'tutorial_haraj_title',
        bodyKey: 'tutorial_haraj_body',
        align: ContentAlign.top,
      ),
      _TutorialStep(
        key: AppTutorialKeys.akhdimni,
        titleKey: 'tutorial_akhdimni_title',
        bodyKey: 'tutorial_akhdimni_body',
        align: ContentAlign.top,
      ),
      _TutorialStep(
        key: AppTutorialKeys.orders,
        titleKey: 'tutorial_orders_title',
        bodyKey: 'tutorial_orders_body',
        align: ContentAlign.top,
      ),
    ].where((step) => step.key.currentContext != null).toList();
    if (steps.isEmpty) return;

    final targets = <TargetFocus>[
      for (var i = 0; i < steps.length; i++)
        TargetFocus(
          identify: steps[i].titleKey,
          keyTarget: steps[i].key,
          shape: ShapeLightFocus.RRect,
          radius: 14,
          paddingFocus: 7,
          enableOverlayTab: true,
          contents: [
            TargetContent(
              align: steps[i].align,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              builder: (context, controller) => _TutorialCard(
                title: appController.t(steps[i].titleKey),
                body: appController.t(steps[i].bodyKey),
                step: i + 1,
                total: steps.length,
                isLast: i == steps.length - 1,
                onNext: controller.next,
              ),
            ),
          ],
        ),
    ];

    _tutorial = TutorialCoachMark(
      targets: targets,
      colorShadow: AppTheme.primaryNavy,
      opacityShadow: 0.86,
      textSkip: appController.t('tutorial_skip'),
      textStyleSkip: const TextStyle(
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
      alignSkip: AlignmentDirectional.topStart,
      paddingFocus: 6,
      pulseEnable: false,
      onFinish: _complete,
      onSkip: () {
        _complete();
        return true;
      },
    )..show(context: context, rootOverlay: true);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _TutorialCard extends StatelessWidget {
  const _TutorialCard({
    required this.title,
    required this.body,
    required this.step,
    required this.total,
    required this.isLast,
    required this.onNext,
  });

  final String title;
  final String body;
  final int step;
  final int total;
  final bool isLast;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$step / $total',
            style: const TextStyle(
              color: AppTheme.accentOrange,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              color: AppTheme.primaryNavy,
              fontSize: 21,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 15,
              height: 1.65,
            ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton(
              key: const Key('tutorial_next'),
              onPressed: onNext,
              child: Text(
                appController.t(isLast ? 'tutorial_done' : 'tutorial_next'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TutorialStep {
  const _TutorialStep({
    required this.key,
    required this.titleKey,
    required this.bodyKey,
    required this.align,
  });

  final GlobalKey key;
  final String titleKey;
  final String bodyKey;
  final ContentAlign align;
}
