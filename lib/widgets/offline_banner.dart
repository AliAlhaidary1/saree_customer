import 'package:flutter/material.dart';

import '../core/app_controller.dart';

/// Thin status strip shown when local-first content is painted:
/// * pending/blocked outbox ops (favorites/cart-merge waiting for network),
/// * caller-declared staleness (cached paint while refreshing).
///
/// Never claims "offline" from interface state alone — reachability is proven
/// only by API results. The strip therefore describes *what the user sees*
/// (saved data / pending sync), not the network link.

class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, this.stale = false, this.staleLabel});

  final bool stale;
  final String? staleLabel;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appController.sync.status,
      builder: (_, _) {
        final s = appController.sync.status.value;
        final showSync = s.pending > 0 || s.blocked > 0;
        if (!showSync && !stale) return const SizedBox.shrink();
        final text = s.blocked > 0
            ? appController.t('sync_blocked')
            : s.pending > 0
                ? appController.t('sync_pending')
                : (staleLabel ?? appController.t('offline_banner'));
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.amber.shade100,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.amber.shade700),
          ),
          child: Row(
            children: [
              Icon(Icons.cloud_off_outlined,
                  size: 16, color: Colors.amber.shade900),
              const SizedBox(width: 8),
              Expanded(
                child: Text(text,
                    style: TextStyle(
                        fontSize: 12, color: Colors.amber.shade900)),
              ),
              if (s.blocked > 0 || s.pending > 0)
                TextButton(
                  onPressed: () => appController.kickSync(),
                  child: Text(appController.t('retry')),
                ),
            ],
          ),
        );
      },
    );
  }
}

class SavedStatusChip extends StatelessWidget {
  const SavedStatusChip({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        appController.t('saved_status_note'),
        style: const TextStyle(fontSize: 11, color: Colors.black54),
      ),
    );
  }
}

class StalePriceNote extends StatelessWidget {
  const StalePriceNote({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        appController.t('stale_price_note'),
        style: const TextStyle(fontSize: 11, color: Colors.black54),
      ),
    );
  }
}
