import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/app_theme.dart';
import '../core/offline/operation_policy.dart';

Future<bool> showRequiresInternetDialog(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => const _RequiresInternetDialog(),
  );
  return result == true;
}

class _RequiresInternetDialog extends StatefulWidget {
  const _RequiresInternetDialog();

  @override
  State<_RequiresInternetDialog> createState() =>
      _RequiresInternetDialogState();
}

class _RequiresInternetDialogState extends State<_RequiresInternetDialog>
    with WidgetsBindingObserver {
  Timer? _pollTimer;
  bool _checking = false;
  bool _showProgress = false;
  bool _failedAgain = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // A network interface can take a moment to become usable after Wi-Fi or
    // mobile data is enabled. Poll the real backend while this dialog is open
    // so the customer does not have to close/restart the application.
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _checkConnectivity(showFailure: false);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkConnectivity(showFailure: false);
    }
  }

  Future<void> _checkConnectivity({required bool showFailure}) async {
    if (_checking || !mounted) return;
    setState(() {
      _checking = true;
      if (showFailure) {
        _showProgress = true;
        _failedAgain = false;
      }
    });
    final online = await appController.hasInternetAccess();
    if (!mounted) return;
    if (online) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _checking = false;
      _showProgress = false;
      if (showFailure) _failedAgain = true;
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = appController;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
          if (_failedAgain) ...[
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
          onPressed: _showProgress ? null : () => Navigator.pop(context, false),
          child: Text(app.t('cancel')),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.accentOrange,
            foregroundColor: Colors.white,
          ),
          onPressed: _checking
              ? null
              : () => _checkConnectivity(showFailure: true),
          child: _checking
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
    );
  }
}

Future<void> showCartError(BuildContext context, String message) async {
  if (!context.mounted) return;
  if (message == kRequiresInternet) {
    await showRequiresInternetDialog(context);
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
