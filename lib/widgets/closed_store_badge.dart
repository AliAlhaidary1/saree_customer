import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/business_hours.dart';

class ClosedStoreBadge extends StatelessWidget {
  const ClosedStoreBadge({
    super.key,
    required this.product,
    this.compact = true,
  });

  final Map<String, dynamic> product;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final kind = productClosedKind(product, hours: appController.businessHours);
    final label = kind == ProductClosedKind.platform
        ? appController.t('platform_closed_badge')
        : kind == ProductClosedKind.seller
            ? appController.t('seller_closed_badge')
            : '';
    if (label.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 12,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: const Color(0xCC991B1B),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.storefront,
            size: compact ? 12 : 16,
            color: Colors.white,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 11 : 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

bool isProductStoreClosed(Map<String, dynamic> product) {
  return productClosedKind(product, hours: appController.businessHours) !=
      ProductClosedKind.none;
}
