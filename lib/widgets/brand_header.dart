import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/app_controller.dart';
import '../core/app_theme.dart';
import '../core/search_scope.dart';
import '../features/notifications/notifications_screen.dart';

/// Single reusable navy brand header used everywhere the shell or a
/// standalone page needs the app chrome (logo, title, notifications, cart,
/// account, platform status) with an optional search field underneath.
///
/// Both the shell ([AppShell]) and standalone pages (e.g. the stores list)
/// render this widget so the header never drifts between screens.
class BrandHeader extends StatelessWidget {
  const BrandHeader({
    super.key,
    required this.app,
    required this.title,
    this.subtitle,
    this.onBack,
    this.searchChild,
  });

  final AppController app;
  final String title;

  /// Optional second line under the title (e.g. "12 • Stores").
  final String? subtitle;

  /// When set, a back button is shown before the logo.
  final VoidCallback? onBack;

  /// Optional widget rendered below the top row (e.g. a search field).
  final Widget? searchChild;


  @override
  Widget build(BuildContext context) {
    return Container(
       decoration: const BoxDecoration(
         color: AppTheme.primaryNavy,
       ),
       child: SafeArea(
         bottom: false,
         child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 4),
           child: Column(
             children: [
                Row(
                  children: [
                    if (onBack != null)
                    IconButton(
                      onPressed: onBack,
                      icon: const Icon(
                        Icons.arrow_back,
                        color: AppTheme.backgroundWhite,
                      ),
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).backButtonTooltip,
                    ),
                  BrandLogo(url: app.brand.logoUrl),
                  const SizedBox(width: 8),
                  Expanded(child: _titleBlock()),
                  const NotificationBell(),
                  _CartButton(app: app),
                  IconButton(
                    onPressed: () => context.push('/account'),
                    icon: const Icon(
                      Icons.person_outline,
                      color: AppTheme.backgroundWhite,
                    ),
                    tooltip: app.t('my_account'),
                  ),
                 ],
               ),
                if (searchChild != null) ...[
                 const SizedBox(height: 10),
                 searchChild!,
               ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _titleBlock() {
    const titleStyle = TextStyle(
      color: AppTheme.backgroundWhite,
      fontWeight: FontWeight.w700,
      fontSize: 13,
    );
    if (subtitle == null || subtitle!.isEmpty) {
      return Text(
        title,
        style: titleStyle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: titleStyle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          subtitle!,
          style: TextStyle(
            color: AppTheme.backgroundWhite.withValues(alpha: 0.7),
            fontSize: 12,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

/// Bundled/cached logo with raster-only guard (SVG/HEIC/AVIF uploads must
/// fall back to the asset instead of Android's ImageDecoder).
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, required this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.backgroundWhite,
        borderRadius: BorderRadius.circular(10),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Builder(
          builder: (_) {
            final logo = url;
            if (logo != null && logo.isNotEmpty && displayableLogo(logo)) {
              return CachedNetworkImage(
                imageUrl: logo,
                width: 22,
                height: 22,
                fit: BoxFit.contain,
                memCacheWidth: 64,
                fadeInDuration: Duration.zero,
                fadeOutDuration: Duration.zero,
                errorWidget: (_, _, _) => _assetLogo(),
              );
            }
            return _assetLogo();
          },
        ),
      ),
    );
  }

  Widget _assetLogo() {
    return Image.asset(
      'assets/brand/sareemart-logo.png',
                width: 22,
                height: 22,
      errorBuilder: (_, _, _) => Image.asset(
        'assets/brand/sareemart-mark.png',
        width: 32,
        height: 32,
        errorBuilder: (_, _, _) => const Icon(
          Icons.shopping_cart_rounded,
          color: AppTheme.accentOrange,
          size: 26,
        ),
      ),
    );
  }
}

class _CartButton extends StatelessWidget {
  const _CartButton({required this.app});
  final AppController app;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (_, _) => IconButton(
        onPressed: () => context.push('/cart'),
        icon: Badge(
          isLabelVisible: app.cartCount > 0,
          label: Text(
            '${app.cartCount}',
            style: const TextStyle(fontSize: 10, color: Colors.white),
          ),
          child: const Icon(
            Icons.shopping_cart_outlined,
            color: AppTheme.backgroundWhite,
          ),
        ),
        tooltip: app.t('cart'),
      ),
    );
  }
}

/// The single page-aware search field (under the brand header).
/// Visible only on searchable pages (home, products, haraj); searches the
/// page you are on.
class HeaderSearchBar extends StatefulWidget {
  const HeaderSearchBar({
    super.key,
    this.onProducts = false,
    this.onHaraj = false,
  });
  final bool onProducts;
  final bool onHaraj;

  @override
  State<HeaderSearchBar> createState() => _HeaderSearchBarState();
}

class _HeaderSearchBarState extends State<HeaderSearchBar> {
  final _ctrl = TextEditingController();
  Timer? _deb;

  @override
  void dispose() {
    _deb?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _submit(String raw) {
    final q = raw.trim();
    if (widget.onProducts) {
      headerSearch.submitProducts(q);
    } else if (widget.onHaraj) {
      headerSearch.submitHaraj(q);
    } else if (q.isNotEmpty) {
      context.push('/products?search=${Uri.encodeComponent(q)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = appController;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      height: 36,
      decoration: BoxDecoration(
        color: AppTheme.backgroundWhite,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.search,
            color: AppTheme.primaryNavy.withValues(alpha: 0.5),
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _ctrl,
              textInputAction: TextInputAction.search,
              onSubmitted: _submit,
              onChanged: (_) {
                // Debounced live search while on the products/haraj page.
                if (!widget.onProducts && !widget.onHaraj) return;
                _deb?.cancel();
                _deb = Timer(
                  const Duration(milliseconds: 450),
                  () => _submit(_ctrl.text),
                );
              },
              decoration: InputDecoration(
                hintText: widget.onHaraj
                    ? app.t('search_in_haraj')
                    : app.t('i_am_looking_for'),
                hintStyle: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 14,
                ),
                filled: false,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
              ),
            ),
          ),
          InkWell(
            onTap: () => context.push('/search'),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.accentOrange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.search_outlined,
                    size: 14,
                    color: AppTheme.accentOrange,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    app.t('search'),
                    style: const TextStyle(
                      color: AppTheme.accentOrange,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Raster-only guard for the header logo: SVG/HEIC/AVIF uploads from the
/// brand API must use the bundled asset instead of Android's ImageDecoder
/// (which rejects them with 'unimplemented' on old devices).
bool displayableLogo(String url) {
  final lower = url.toLowerCase();
  if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
    return false;
  }
  try {
    final path = Uri.parse(url).path.toLowerCase();
    for (final ext in const [
      '.svg',
      '.svgz',
      '.heic',
      '.heif',
      '.avif',
      '.tif',
      '.tiff',
    ]) {
      if (path.endsWith(ext)) return false;
    }
  } catch (_) {
    return false;
  }
  return true;
}
