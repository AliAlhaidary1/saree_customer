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
    return ColoredBox(
      color: AppTheme.primaryNavy,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 48,
                child: Row(
                  children: [
                    if (onBack != null) ...[
                      HeaderIconButton(
                        icon: Icons.arrow_back,
                        tooltip: MaterialLocalizations.of(
                          context,
                        ).backButtonTooltip,
                        onPressed: onBack!,
                      ),
                      const SizedBox(width: 2),
                    ],
                    BrandLogo(url: app.brand.logoUrl),
                    const SizedBox(width: 10),
                    Expanded(child: _titleBlock()),
                    const NotificationBell(),
                    _CartButton(app: app),
                    HeaderIconButton(
                      icon: Icons.person_outline,
                      tooltip: app.t('my_account'),
                      onPressed: () => context.push('/account'),
                    ),
                  ],
                ),
              ),
              if (searchChild != null) ...[
                const SizedBox(height: 8),
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
      fontSize: 15,
      height: 1.2,
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
            color: AppTheme.backgroundWhite.withValues(alpha: 0.72),
            fontSize: 11.5,
            height: 1.2,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

/// Compact 42dp header action. Regular [IconButton]s reserve 48dp each, which
/// squeezes the title to a few characters once the back button is also shown.
class HeaderIconButton extends StatelessWidget {
  const HeaderIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.iconSize = 22,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, color: AppTheme.backgroundWhite, size: iconSize),
      style: IconButton.styleFrom(
        minimumSize: const Size(42, 42),
        maximumSize: const Size(42, 42),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
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
        borderRadius: BorderRadius.circular(9),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Builder(
          builder: (_) {
            final logo = url;
            if (logo != null && logo.isNotEmpty && displayableLogo(logo)) {
              return CachedNetworkImage(
                imageUrl: logo,
                width: 24,
                height: 24,
                fit: BoxFit.contain,
                memCacheWidth: 72,
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
      width: 24,
      height: 24,
      errorBuilder: (_, _, _) => Image.asset(
        'assets/brand/sareemart-mark.png',
        width: 24,
        height: 24,
        errorBuilder: (_, _, _) => const Icon(
          Icons.shopping_cart_rounded,
          color: AppTheme.accentOrange,
          size: 24,
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
        tooltip: app.t('cart'),
        style: IconButton.styleFrom(
          minimumSize: const Size(42, 42),
          maximumSize: const Size(42, 42),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: Badge(
          isLabelVisible: app.cartCount > 0,
          label: Text(
            '${app.cartCount}',
            style: const TextStyle(fontSize: 10, color: Colors.white),
          ),
          child: const Icon(
            Icons.shopping_cart_outlined,
            color: AppTheme.backgroundWhite,
            size: 22,
          ),
        ),
      ),
    );
  }
}

/// The single page-aware search bar (under the brand header).
/// Visible only on searchable pages (home, products, haraj):
/// - Home shows a read-only bar that opens `/search`.
/// - Products / haraj filter their own list in place (debounced).
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
  void initState() {
    super.initState();
    _syncFromScope();
  }

  @override
  void didUpdateWidget(HeaderSearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The shell reuses this State across tabs, so mirror the query that
    // belongs to the page we just moved to instead of carrying stale text.
    if (widget.onProducts != oldWidget.onProducts ||
        widget.onHaraj != oldWidget.onHaraj) {
      _deb?.cancel();
      _syncFromScope();
    }
  }

  void _syncFromScope() {
    _ctrl.text = widget.onProducts
        ? headerSearch.productQuery
        : widget.onHaraj
        ? headerSearch.harajQuery
        : '';
    _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
  }

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
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = appController;
    // Home: the bar is a shortcut into the dedicated search page (recent
    // searches + suggestions). Editing in place only makes sense on pages
    // that can filter their own list (products / haraj).
    if (!widget.onProducts && !widget.onHaraj) {
      return Material(
        color: AppTheme.backgroundWhite,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/search'),
          child: SizedBox(
            height: 42,
            child: Row(
              children: [
                const SizedBox(width: 12),
                Icon(
                  Icons.search,
                  color: AppTheme.primaryNavy.withValues(alpha: 0.45),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    app.t('i_am_looking_for'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13.5,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
            ),
          ),
        ),
      );
    }
    final hasText = _ctrl.text.isNotEmpty;
    return Container(
      height: 42,
      padding: EdgeInsetsDirectional.only(start: 12, end: hasText ? 4 : 12),
      decoration: BoxDecoration(
        color: AppTheme.backgroundWhite,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.search,
            color: AppTheme.primaryNavy.withValues(alpha: 0.45),
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _ctrl,
              textInputAction: TextInputAction.search,
              textAlignVertical: TextAlignVertical.center,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
              onSubmitted: (value) {
                _deb?.cancel();
                _submit(value);
                FocusScope.of(context).unfocus();
              },
              onChanged: (_) {
                _deb?.cancel();
                _deb = Timer(
                  const Duration(milliseconds: 450),
                  () => _submit(_ctrl.text),
                );
                setState(() {});
              },
              decoration: InputDecoration(
                hintText: widget.onHaraj
                    ? app.t('search_in_haraj')
                    : app.t('i_am_looking_for'),
                hintStyle: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13.5,
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
          if (hasText)
            IconButton(
              onPressed: () {
                _deb?.cancel();
                _ctrl.clear();
                _submit('');
                setState(() {});
              },
              tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
              icon: const Icon(
                Icons.close_rounded,
                size: 18,
                color: AppTheme.textSecondary,
              ),
              style: IconButton.styleFrom(
                minimumSize: const Size(32, 32),
                maximumSize: const Size(32, 32),
                padding: EdgeInsets.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
