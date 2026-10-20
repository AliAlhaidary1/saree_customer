import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/app_controller.dart';
import '../core/app_theme.dart';
import 'skeleton_loader.dart';

class BusySpinner extends StatelessWidget {
  const BusySpinner({super.key, this.color = AppTheme.accentOrange});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      height: 22,
      child: CircularProgressIndicator(strokeWidth: 2.4, color: color),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: AppTheme.textSecondary),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textPrimary),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              BrandedButton(onPressed: onAction, label: actionLabel!),
            ],
          ],
        ),
      ),
    );
  }
}

Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  String? body,
}) async {
  final app = appController;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(title),
      content: body == null ? null : Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(app.t('cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(app.t('confirm')),
        ),
      ],
    ),
  );
  return ok == true;
}

class LoginRequired extends StatelessWidget {
  const LoginRequired({super.key, this.withScaffold = false});
  final bool withScaffold;

  @override
  Widget build(BuildContext context) {
    final app = appController;
    final body = EmptyState(
      icon: Icons.lock_outline,
      message: app.t('please_login_continue'),
      actionLabel: app.t('login'),
      onAction: () => context.push('/login'),
    );
    if (!withScaffold) return body;
    return Scaffold(
      appBar: AppBar(
        title: Text(app.t('login'), maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: body,
    );
  }
}

class BrandedLoading extends StatelessWidget {
  const BrandedLoading({super.key, this.skeleton = false});

  final bool skeleton;

  @override
  Widget build(BuildContext context) {
    if (skeleton) return const HomeLoadingSkeleton();
    return const Center(child: BusySpinner());
  }
}
