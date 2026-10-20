import 'package:flutter/material.dart';

import '../core/app_controller.dart';

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
