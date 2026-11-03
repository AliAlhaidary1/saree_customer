import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/app_controller.dart';
import '../core/app_navigation.dart';
import '../core/app_theme.dart';
import '../core/json_util.dart';
import '../core/promo_price.dart';
import '../core/search_scope.dart';
import '../features/notifications/notifications_screen.dart';
import 'app_image.dart';
import 'ui_helpers.dart';

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
    this.cartKey,
  });

  final AppController app;
  final String title;

  /// Optional second line under the title (e.g. "12 • Stores").
  final String? subtitle;

  /// When set, a back button is shown before the logo.
  final VoidCallback? onBack;

  /// Optional widget rendered below the top row (e.g. a search field).
  final Widget? searchChild;
  final Key? cartKey;

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
                    _CartButton(key: cartKey, app: app),
                    _AccountHeaderButton(app: app),
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
  const _CartButton({super.key, required this.app});
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

/// Account entry point in the header: a user avatar that opens a compact
/// account sheet instead of jumping straight to the full account page.
/// The avatar shows the profile photo, the first letter of the name, or a
/// person glyph for guests — never a bare generic icon when a profile exists.
class _AccountHeaderButton extends StatelessWidget {
  const _AccountHeaderButton({required this.app});

  final AppController app;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final name = J.str(app.user?['name']);
        final profileImg = J.str(app.user?['profile'] ?? app.user?['image']);
        return SizedBox(
          width: 42,
          height: 42,
          child: Tooltip(
            message: app.t('my_account'),
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => _AccountMenuSheet.show(context, app),
                child: Center(
                  child: _HeaderAvatar(
                    name: name,
                    profileImg: profileImg,
                    loggedIn: app.isLoggedIn,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Header-sized avatar: white ring + soft shadow, photo when the URL is
/// decodable, otherwise an accent gradient with the name's initial.
class _HeaderAvatar extends StatelessWidget {
  const _HeaderAvatar({
    required this.name,
    required this.profileImg,
    required this.loggedIn,
    this.size = 36,
  });

  final String name;
  final String profileImg;
  final bool loggedIn;
  final double size;

  String get _initial {
    final value = name.trim();
    return value.isEmpty
        ? ''
        : String.fromCharCode(value.runes.first).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final app = appController;
    final photo = AppImage.isDisplayable(profileImg);
    final inner = size - 5;
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white,
            Colors.white.withValues(alpha: loggedIn ? 0.55 : 0.75),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipOval(
        child: photo
            ? AppImage(profileImg, thumb: true, fit: BoxFit.cover)
            : DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: loggedIn
                        ? [
                            app.accentColor,
                            Color.lerp(
                              app.accentColor,
                              AppTheme.primaryNavy,
                              0.4,
                            )!,
                          ]
                        : [
                            Colors.white.withValues(alpha: 0.24),
                            Colors.white.withValues(alpha: 0.10),
                          ],
                  ),
                ),
                child: Center(
                  child: _initial.isEmpty
                      ? Icon(
                          Icons.person_outline_rounded,
                          color: AppTheme.backgroundWhite,
                          size: inner * 0.56,
                        )
                      : Text(
                          _initial,
                          style: TextStyle(
                            color: AppTheme.backgroundWhite,
                            fontWeight: FontWeight.w800,
                            fontSize: inner * 0.44,
                            height: 1,
                          ),
                        ),
                ),
              ),
      ),
    );
  }
}

/// Bottom-sheet account menu: profile summary + wallet + the pages customers
/// reach most often, with quick logout. Kept in the header so every screen
/// gets the same account experience.
class _AccountMenuSheet extends StatelessWidget {
  const _AccountMenuSheet({required this.app, required this.router});

  final AppController app;
  final GoRouter router;

  static Future<void> show(BuildContext context, AppController app) {
    final router = GoRouter.of(context);
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (_) => _AccountMenuSheet(app: app, router: router),
    );
  }

  void _go(BuildContext context, String path) {
    Navigator.of(context).pop();
    openRouterLocation(router, path);
  }

  Future<void> _toggleLanguage() async {
    await app.setLanguage(app.i18n.code == 'ar' ? 'en' : 'ar');
  }

  Future<void> _logout(BuildContext context) async {
    final ok = await confirmAction(
      context,
      title: app.t('logout'),
      body: app.t('logout_confirm'),
    );
    if (!ok) return;
    await app.logout();
    if (!context.mounted) return;
    Navigator.of(context).pop();
    router.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: media.size.height * 0.9),
      child: Material(
        color: AppTheme.backgroundWhite,
        clipBehavior: Clip.antiAlias,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: ListenableBuilder(
          listenable: app,
          builder: (context, _) {
            final loggedIn = app.isLoggedIn;
            final name = J.str(app.user?['name']);
            final mobile = J.str(app.user?['mobile'] ?? app.user?['email']);
            final profileImg = J.str(
              app.user?['profile'] ?? app.user?['image'],
            );
            final wallet = J.d(
              app.user?['balance'] ??
                  app.user?['wallet'] ??
                  app.settings['user_balance'],
            );
            return ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: [
                _header(context, loggedIn, name, mobile, profileImg, wallet),
                if (loggedIn) _quickActions(context),
                _menu(context, loggedIn),
                SizedBox(height: media.padding.bottom + 8),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _header(
    BuildContext context,
    bool loggedIn,
    String name,
    String mobile,
    String profileImg,
    double wallet,
  ) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [AppTheme.primaryNavy, Color(0xFF143C60)],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
          child: Column(
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _go(context, '/account'),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      children: [
                        _HeaderAvatar(
                          name: name,
                          profileImg: profileImg,
                          loggedIn: loggedIn,
                          size: 52,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                loggedIn
                                    ? (name.isEmpty ? app.t('profile') : name)
                                    : app.t('welcome'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppTheme.backgroundWhite,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                mobile.isNotEmpty
                                    ? mobile
                                    : app.t('please_login_continue'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: AppTheme.backgroundWhite.withValues(
                                    alpha: 0.72,
                                  ),
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (loggedIn)
                          Icon(
                            Icons.chevron_left_rounded,
                            color: AppTheme.backgroundWhite.withValues(
                              alpha: 0.75,
                            ),
                          )
                        else
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: app.accentColor,
                              foregroundColor: AppTheme.backgroundWhite,
                              minimumSize: const Size(0, 38),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            onPressed: () => _go(context, '/login'),
                            child: Text(app.t('login')),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              if (loggedIn) ...[
                const SizedBox(height: 16),
                Material(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _go(context, '/wallet'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.account_balance_wallet_outlined,
                              color: AppTheme.backgroundWhite,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  app.t('walletBalance'),
                                  style: TextStyle(
                                    color: AppTheme.backgroundWhite.withValues(
                                      alpha: 0.72,
                                    ),
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  money(wallet, app.currency, app.decimals),
                                  style: const TextStyle(
                                    color: AppTheme.backgroundWhite,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_left_rounded,
                            color: AppTheme.backgroundWhite.withValues(
                              alpha: 0.8,
                            ),
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _quickActions(BuildContext context) {
    final items = <({IconData icon, String label, String path})>[
      (
        icon: Icons.receipt_long_outlined,
        label: app.t('orders'),
        path: '/orders',
      ),
      (
        icon: Icons.favorite_border,
        label: app.t('wishlist'),
        path: '/wishlist',
      ),
      (
        icon: Icons.location_on_outlined,
        label: app.t('myAddress'),
        path: '/addresses',
      ),
      (
        icon: Icons.account_balance_wallet_outlined,
        label: app.t('wallet'),
        path: '/wallet',
      ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: _QuickActionCard(
                icon: items[i].icon,
                label: items[i].label,
                onTap: () => _go(context, items[i].path),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _menu(BuildContext context, bool loggedIn) {
    return Column(
      children: [
        if (loggedIn)
          _menuTile(
            context,
            Icons.person_outline_rounded,
            app.t('profile'),
            '/profile',
          ),
        _menuTile(
          context,
          Icons.notifications_none_rounded,
          app.t('notifications'),
          '/notifications',
        ),
        if (loggedIn)
          _menuTile(
            context,
            Icons.lock_outline_rounded,
            app.t('change_password'),
            '/change-password',
          ),
        _menuTile(context, Icons.help_outline_rounded, app.t('faq'), '/faq'),
        _menuTile(
          context,
          Icons.feedback_outlined,
          app.t('complaints_suggestions'),
          '/complaints',
        ),
        _menuTile(
          context,
          Icons.info_outline_rounded,
          app.t('about_us'),
          '/about',
        ),
        ListTile(
          leading: const _MenuIcon(icon: Icons.language_rounded),
          title: Text(
            app.i18n.code == 'ar' ? 'English' : 'العربية',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          trailing: const Icon(
            Icons.swap_horiz_rounded,
            size: 20,
            color: AppTheme.textSecondary,
          ),
          onTap: _toggleLanguage,
        ),
        if (loggedIn) ...[
          const Divider(height: 20, indent: 16, endIndent: 16),
          ListTile(
            leading: const _MenuIcon(
              icon: Icons.logout_rounded,
              color: Color(0xFFDC2626),
              background: Color(0xFFFEE2E2),
            ),
            title: Text(
              app.t('logout'),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xFFDC2626),
              ),
            ),
            onTap: () => _logout(context),
          ),
        ],
      ],
    );
  }

  Widget _menuTile(
    BuildContext context,
    IconData icon,
    String title,
    String path,
  ) {
    return ListTile(
      leading: _MenuIcon(icon: icon),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppTheme.textPrimary,
        ),
      ),
      trailing: const Icon(
        Icons.chevron_left_rounded,
        size: 20,
        color: AppTheme.textSecondary,
      ),
      onTap: () => _go(context, path),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surfaceGrey,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 4),
          child: Column(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: appController.accentColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 20, color: appController.accentColor),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuIcon extends StatelessWidget {
  const _MenuIcon({
    required this.icon,
    this.color = AppTheme.primaryNavy,
    this.background = const Color(0x0F0A2540),
  });

  final IconData icon;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(icon, size: 20, color: color),
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
