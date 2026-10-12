import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/app_theme.dart';
import '../core/json_util.dart';
import 'app_image.dart';

/// Compact store card used on the home "stores" view (web parity with
/// ShopBySellers store-card). Shows logo, name, rating, product count,
/// distance and an open/closed badge when the backend provides a flag.
class StoreCard extends StatelessWidget {
  const StoreCard({
    super.key,
    required this.seller,
    required this.onTap,
    this.distanceKm,
  });

  final Map<String, dynamic> seller;
  final VoidCallback onTap;
  final double? distanceKm;

  bool? _openFlag() {
    for (final key in [
      'is_open',
      'seller_is_open',
      'store_open',
      'open',
      'store_status',
    ]) {
      final v = seller[key];
      if (v == null) continue;
      if (v == true || v == 1 || v == '1' || v == 'open' || v == 'opened') {
        return true;
      }
      if (v == false || v == 0 || v == '0' || v == 'closed' || v == 'close') {
        return false;
      }
    }
    final status = '${seller['status'] ?? ''}'.trim().toLowerCase();
    if (status == 'open' || status == 'opened' || status == '1') return true;
    if (status == 'closed' || status == 'close' || status == '0') return false;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final app = appController;
    final name = J.str(seller['store_name'] ?? seller['name']);
    final rating =
        double.tryParse('${seller['average_rating'] ?? seller['rating'] ?? ''}');
    final productCount = J.i(
      seller['product_count'] ?? seller['products_count'],
    );
    final open = _openFlag();
    final hasDelivery = J.flag(seller['delivery']) ||
        J.str(seller['delivery_type']).isNotEmpty ||
        J.flag(seller['can_deliver']);

    return Material(
      color: AppTheme.backgroundWhite,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: AppTheme.primaryNavy.withValues(alpha: 0.06),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 58,
                  height: 58,
                  child: AppImage(
                    J.str(seller['logo_url']),
                    placeholder: app.placeholder,
                    thumb: true,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        if (open == false) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE5E7EB),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              app.t('closed'),
                              style: const TextStyle(
                                color: Color(0xFF374151),
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        if (rating != null && rating > 0) ...[
                          const Icon(
                            Icons.star_rounded,
                            size: 14,
                            color: Colors.amber,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            rating.toStringAsFixed(1),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (productCount > 0)
                          Text(
                            '$productCount ${app.t('products')}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        if (hasDelivery)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.accentOrange
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              app.t('delivery') == 'delivery'
                                  ? 'توصيل'
                                  : app.t('delivery'),
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppTheme.accentOrange,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        if (distanceKm != null) ...[
                          const SizedBox(width: 8),
                          Icon(
                            Icons.near_me,
                            size: 12,
                            color: AppTheme.textSecondary,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '${distanceKm!.toStringAsFixed(1)} كم',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: AppTheme.textSecondary.withValues(alpha: 0.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
