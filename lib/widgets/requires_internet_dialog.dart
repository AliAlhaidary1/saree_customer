import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/app_theme.dart';
import '../core/offline/operation_policy.dart';

Future<bool> showRequiresInternetDialog(BuildContext context) async {
  final app = appController;
  var checking = false;
  var failedAgain = false;
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.accentOrange.withValues(alpha: 0.12),
              ),
              child: const Icon(
                Icons.wifi_off_rounded,
                size: 32,
                color: AppTheme.accentOrange,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              app.t('internet_required_title'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              app.t('internet_required_message'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13.5,
                color: AppTheme.textSecondary,
              ),
            ),
            if (failedAgain) ...[
              const SizedBox(height: 8),
              Text(
                app.t('network_error'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: Colors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: checking ? null : () => Navigator.pop(ctx, false),
            child: Text(app.t('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.accentOrange,
              foregroundColor: Colors.white,
            ),
            onPressed: checking
                ? null
                : () async {
                    setS(() {
                      checking = true;
                      failedAgain = false;
                    });
                    final online = await app.hasInternetAccess();
                    if (!ctx.mounted) return;
                    if (online) {
                      Navigator.pop(ctx, true);
                    } else {
                      setS(() {
                        checking = false;
                        failedAgain = true;
                      });
                    }
                  },
            child: checking
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(app.t('retry')),
          ),
        ],
      ),
    ),
  );
  return result == true;
}

Future<void> showCartError(BuildContext context, String message) async {
  if (!context.mounted) return;
  if (message == kRequiresInternet) {
    await showRequiresInternetDialog(context);
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message)),
  );
}
