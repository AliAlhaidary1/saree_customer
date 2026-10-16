import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

import 'core/app_controller.dart';
import 'core/app_theme.dart';
import 'core/json_util.dart';
import 'core/search_scope.dart';
import 'features/account/account_screens.dart';
import 'features/akhdimni/akhdimni_screens.dart';
import 'features/assistant/assistant_screen.dart';
import 'features/auth/auth_screens.dart';
import 'features/cart/cart_screens.dart';
import 'features/checkout_groups/checkout_groups_screens.dart';
import 'features/complaints/complaints_screen.dart';
import 'features/haraj/haraj_screens.dart';
import 'features/home/home_screen.dart';
import 'features/more/more_screens.dart';
import 'features/notifications/notifications_screen.dart';
import 'features/products/categories_screen.dart';
import 'features/products/products_screens.dart';
import 'widgets/ui_helpers.dart';

GoRouter buildRouter() {
  return GoRouter(
    initialLocation: '/',
    // Scoped refresh: auth/city/catalog-mode only. Cart steppers, shop
    // revalidation, and favorites no longer re-evaluate every redirect.
    refreshListenable: appController.navTick,
    routes: [
      GoRoute(
        path: '/login',
        pageBuilder: (_, state) => AppTheme.slidePage(
          key: state.pageKey,
          child: LoginScreen(next: state.uri.queryParameters['next']),
        ),
      ),
      GoRoute(
        path: '/change-password',
        pageBuilder: (_, state) => AppTheme.slidePage(
          key: state.pageKey,
          child: const ChangePasswordScreen(),
        ),
      ),
      GoRoute(
        path: '/register',
        pageBuilder: (_, state) => AppTheme.slidePage(
          key: state.pageKey,
          child: const RegisterScreen(),
        ),
      ),
      GoRoute(
        path: '/product/:slug',
        pageBuilder: (_, state) => AppTheme.slidePage(
          key: state.pageKey,
          child: ProductDetailsScreen(slug: state.pathParameters['slug']!),
        ),
      ),
      GoRoute(
        path: '/checkout',
        pageBuilder: (_, state) => AppTheme.slidePage(
          key: state.pageKey,
          child: const CheckoutScreen(),
        ),
      ),
      GoRoute(
        path: '/orders/:id',
        pageBuilder: (_, state) => AppTheme.slidePage(
          key: state.pageKey,
          child: OrderDetailsScreen(id: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/wishlist',
        pageBuilder: (_, state) => AppTheme.slidePage(
          key: state.pageKey,
          child: const WishlistScreen(),
        ),
      ),
      GoRoute(
        path: '/addresses',
        pageBuilder: (_, state) => AppTheme.slidePage(
          key: state.pageKey,
          child: const AddressesScreen(),
        ),
      ),
      GoRoute(
        path: '/profile',
        pageBuilder: (_, state) => AppTheme.slidePage(
          key: state.pageKey,
          child: const ProfileScreen(),
        ),
      ),
      GoRoute(
        path: '/notifications',
        pageBuilder: (_, state) => AppTheme.slidePage(
          key: state.pageKey,
          child: const NotificationsScreen(),
        ),
      ),
      GoRoute(
        path: '/wallet',
        pageBuilder: (_, state) => AppTheme.slidePage(
          key: state.pageKey,
          child: SimpleListScreen(
            title: appController.t('wallet'),
            snapshotName: 'wallet',
            loader: () async =>
                (await appController.api.transactions(type: 'wallet')).dataMaps,
            pageLoader: (limit, offset) async =>
                (await appController.api.transactions(
                  limit: limit,
                  offset: offset,
                  type: 'wallet',
                )).dataMaps,
            emptyMessage: appController.t('no_transaction'),
            header: const WalletSettingsHeader(),
          ),
        ),
      ),
      GoRoute(
        path: '/transactions',
        pageBuilder: (_, state) => AppTheme.slidePage(
          key: state.pageKey,
          child: SimpleListScreen(
            title: appController.t('transactions'),
            snapshotName: 'transactions',
            loader: () async =>
                (await appController.api.transactions()).dataMaps,
            pageLoader: (limit, offset) async =>
                (await appController.api.transactions(
                  limit: limit,
                  offset: offset,
                )).dataMaps,
            emptyMessage: appController.t('no_transaction'),
          ),
        ),
      ),
      GoRoute(
        path: '/sellers',
        pageBuilder: (_, state) => AppTheme.slidePage(
          key: state.pageKey,
          child: SellersScreen(
            typeId:
                state.uri.queryParameters['type'] ??
                state.uri.queryParameters['category'],
          ),
        ),
      ),
      GoRoute(
        path: '/seller/:id',
        pageBuilder: (_, state) => AppTheme.slidePage(
          key: state.pageKey,
          child: SellerPageScreen(id: state.pathParameters['id']),
        ),
      ),
      GoRoute(
        path: '/store/:slug',
        pageBuilder: (_, state) => AppTheme.slidePage(
          key: state.pageKey,
          child: SellerPageScreen(slug: state.pathParameters['slug']),
        ),
      ),
      GoRoute(
        path: '/offers',
        pageBuilder: (_, state) =>
            AppTheme.slidePage(key: state.pageKey, child: const OffersScreen()),
      ),
      GoRoute(
        path: '/search',
        pageBuilder: (_, state) =>
            AppTheme.slidePage(key: state.pageKey, child: const SearchScreen()),
      ),
      GoRoute(
        path: '/category/:slug',
        pageBuilder: (_, state) => AppTheme.slidePage(
          key: state.pageKey,
          child: CategoriesScreen(slug: state.pathParameters['slug'] ?? 'all'),
        ),
      ),
      GoRoute(
        path: '/akhdimni/orders/:id',
        pageBuilder: (_, state) => AppTheme.slidePage(
          key: state.pageKey,
          child: AkhdimniOrderDetailsScreen(id: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/haraj/mine',
        pageBuilder: (_, state) => AppTheme.slidePage(
          key: state.pageKey,
          child: const HarajListScreen(mine: true),
        ),
      ),
      GoRoute(
        path: '/haraj/create',
        pageBuilder: (_, state) => AppTheme.slidePage(
          key: state.pageKey,
          child: const HarajCreateScreen(),
        ),
      ),
      GoRoute(
        path: '/haraj/edit/:id',
        pageBuilder: (_, state) => AppTheme.slidePage(
          key: state.pageKey,
          child: HarajEditScreen(id: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/haraj/:id',
        pageBuilder: (_, state) => AppTheme.slidePage(
          key: state.pageKey,
          child: HarajDetailsScreen(id: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/checkout-groups',
        pageBuilder: (_, s) => AppTheme.slidePage(
          key: s.pageKey,
          child: const CheckoutGroupsScreen(),
        ),
      ),
      GoRoute(
        path: '/checkout-groups/:id',
        pageBuilder: (_, s) => AppTheme.slidePage(
          key: s.pageKey,
          child: CheckoutGroupDetailsScreen(id: s.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/akhdimni/create',
        pageBuilder: (_, state) => AppTheme.slidePage(
          key: state.pageKey,
          child: AkhdimniCreateScreen(
            categoryId: state.uri.queryParameters['category_id'],
            type: state.uri.queryParameters['type'],
          ),
        ),
      ),
      GoRoute(
        path: '/akhdimni/orders',
        pageBuilder: (_, state) => AppTheme.slidePage(
          key: state.pageKey,
          child: const AkhdimniOrdersScreen(),
        ),
      ),
      GoRoute(
        path: '/privacy',
        pageBuilder: (_, state) => AppTheme.slidePage(
          key: state.pageKey,
          child: CmsScreen(
            title: appController.t('privacy_policy'),
            settingKey: 'privacy_policy',
          ),
        ),
      ),
      GoRoute(
        path: '/terms',
        pageBuilder: (_, state) => AppTheme.slidePage(
          key: state.pageKey,
          child: CmsScreen(
            title: appController.t('terms_of_service'),
            settingKey: 'terms_conditions',
          ),
        ),
      ),
      GoRoute(
        path: '/about',
        pageBuilder: (_, state) => AppTheme.slidePage(
          key: state.pageKey,
          child: CmsScreen(
            title: appController.t('about_us'),
            settingKey: 'about_us',
          ),
        ),
      ),
      GoRoute(
        path: '/contact',
        pageBuilder: (_, state) => AppTheme.slidePage(
          key: state.pageKey,
          child: CmsScreen(
            title: appController.t('contact_us'),
            settingKey: 'contact_us',
          ),
        ),
      ),
      GoRoute(
        path: '/complaints',
        pageBuilder: (_, state) => AppTheme.slidePage(
          key: state.pageKey,
          child: const ComplaintsScreen(),
        ),
      ),
      GoRoute(
        path: '/assistant',
        pageBuilder: (_, state) => AppTheme.slidePage(
          key: state.pageKey,
          child: const AssistantScreen(),
        ),
      ),
      GoRoute(
        path: '/faq',
        pageBuilder: (_, state) =>
            AppTheme.slidePage(key: state.pageKey, child: const FaqScreen()),
      ),
      GoRoute(
        path: '/policy/:type',
        pageBuilder: (_, state) {
          final type = state.pathParameters['type'] ?? 'Privacy_Policy';
          const keys = {
            'Privacy_Policy': 'privacy_policy',
            'ReturnsAndExchangesPolicy': 'returns_and_exchanges_policy',
            'Shipping_Policy': 'shipping_policy',
            'Cancellation_Policy': 'cancellation_policy',
          };
          const titles = {
            'Privacy_Policy': 'privacy_policy',
            'ReturnsAndExchangesPolicy': 'recharge_and_exchange_policy',
            'Shipping_Policy': 'shipping_policy',
            'Cancellation_Policy': 'cancellation_policy',
          };
          return AppTheme.slidePage(
            key: state.pageKey,
            child: CmsScreen(
              title: appController.t(titles[type] ?? 'privacy_policy'),
              settingKey: keys[type] ?? 'privacy_policy',
            ),
          );
        },
      ),
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(
            path: '/',
            pageBuilder: (_, state) => AppTheme.slidePage(
              key: state.pageKey,
              child: const HomeScreen(),
            ),
          ),
          GoRoute(
            path: '/haraj',
            pageBuilder: (_, state) => AppTheme.slidePage(
              key: state.pageKey,
              child: const HarajListScreen(),
            ),
          ),
          GoRoute(
            path: '/products',
            // Web parity: in stores_only the catalog is hidden entirely.
            redirect: (_, _) => appController.isStoresOnly ? '/sellers' : null,
            pageBuilder: (_, state) {
              final q = state.uri.queryParameters;
              return AppTheme.slidePage(
                key: state.pageKey,
                child: ProductsScreen(
                  categoryId: q['category'],
                  search: q['search'],
                  hasOffer: q['offer'] == '1',
                  sectionId: q['section'],
                  sellerId: q['seller'],
                  sort: q['sort'],
                  minRating: q['rating'],
                  inStock: q['in_stock'] == '1',
                  priceMin: q['price_min'],
                  priceMax: q['price_max'],
                  canDeliver: q['deliver'] == '1',
                  isReturnable: q['returnable'] == '1',
                ),
              );
            },
          ),
          GoRoute(
            path: '/cart',
            pageBuilder: (_, state) => AppTheme.slidePage(
              key: state.pageKey,
              child: const CartScreen(),
            ),
          ),
          GoRoute(
            path: '/orders',
            pageBuilder: (_, state) => AppTheme.slidePage(
              key: state.pageKey,
              child: const OrdersScreen(),
            ),
          ),
          GoRoute(
            path: '/akhdimni',
            pageBuilder: (_, state) => AppTheme.slidePage(
              key: state.pageKey,
              child: const AkhdimniHomeScreen(),
            ),
          ),
          GoRoute(
            path: '/account',
            pageBuilder: (_, state) => AppTheme.slidePage(
              key: state.pageKey,
              child: const AccountScreen(),
            ),
          ),
        ],
      ),
    ],
  );
}

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child, required this.location});
  final Widget child;
  final String location;

  /// Bottom tabs: [الرئيسية, الحراج, اخدمني?, طلباتي]. Products & stores now
  /// live inside Home as a toggle (no separate tabs); Cart is reached from the
  /// header shortcut and orders replaced it in the bar.
  List<AppTab> get tabs {
    return [
      AppTab('home_tab', '/', Icons.home_outlined, Icons.home),
      AppTab('haraj', '/haraj', Icons.sell_outlined, Icons.sell),
      if (appController.akhdimniEnabled)
        AppTab(
          'akhdimni',
          '/akhdimni',
          Icons.delivery_dining_outlined,
          Icons.delivery_dining,
        ),
      AppTab(
        'my_orders',
        '/orders',
        Icons.receipt_long_outlined,
        Icons.receipt_long,
      ),
    ];
  }

  int get index {
    final ts = tabs;
    for (var i = 0; i < ts.length; i++) {
      if (ts[i].path == '/') {
        if (location == '/') return i;
      } else if (location.startsWith(ts[i].path)) {
        return i;
      }
    }
    return 0;
  }

  String _brandTitle() {
    final fromApi = J.str(appController.webSettings['site_title']);
    if (fromApi.isNotEmpty) return fromApi;
    return AppTheme.brandNameAr;
  }

  /// Orders renders its own AppBar (title + actions), so the brand header
  /// must not stack on top of it. Haraj now uses the shared brand header.
  bool get _hasOwnAppBar => location == '/orders';

  @override
  Widget build(BuildContext context) {
    final app = appController;
    if (app.maintenance) {
      return Scaffold(
        body: EmptyState(
          icon: Icons.cloud_off_outlined,
          message: app.t('maintenance_message'),
        ),
      );
    }
    return Scaffold(
      body: Column(
        children: [
          if (!_hasOwnAppBar)
            _BrandHeader(app: app, title: _brandTitle(), location: location),
          Expanded(child: child),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'assistant_fab',
        mini: true,
        backgroundColor: AppTheme.accentOrange,
        tooltip: app.t('assistant_title'),
        onPressed: () => context.push('/assistant'),
        child: const Icon(Icons.smart_toy_outlined, color: Colors.white),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => context.go(tabs[i].path),
        destinations: [
          for (final tab in tabs)
            NavigationDestination(
              icon: Icon(tab.icon),
              selectedIcon: Icon(tab.selectedIcon),
              label: app.t(tab.labelKey),
            ),
        ],
      ),
    );
  }
}

class AppTab {
  const AppTab(this.labelKey, this.path, this.icon, this.selectedIcon);
  final String labelKey;
  final String path;
  final IconData icon;
  final IconData selectedIcon;
}

/// The single page-aware search field (under the app header).
/// Visible only on home + products; searches the page you are on.
class _HeaderSearchBar extends StatefulWidget {
  const _HeaderSearchBar({required this.onProducts, this.onHaraj = false});
  final bool onProducts;
  final bool onHaraj;

  @override
  State<_HeaderSearchBar> createState() => _HeaderSearchBarState();
}

class _HeaderSearchBarState extends State<_HeaderSearchBar> {
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
      height: 44,
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
                hintStyle: TextStyle(
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

class _BrandHeader extends StatelessWidget {
  const _BrandHeader({
    required this.app,
    required this.title,
    required this.location,
  });
  final AppController app;
  final String title;
  final String location;

  /// Search exists only on searchable pages (home, products, haraj).
  /// Cart/account/orders never show it — like the web header.
  bool get _searchable =>
      location == '/' ||
      location.startsWith('/products') ||
      location == '/haraj';

  bool get _onProducts => location.startsWith('/products');

  bool get _onHaraj => location == '/haraj';

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.primaryNavy,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppTheme.backgroundWhite,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child:
                          app.brand.logoUrl != null &&
                              app.brand.logoUrl!.isNotEmpty
                          ? Image.network(
                              app.brand.logoUrl!,
                              width: 32,
                              height: 32,
                              fit: BoxFit.contain,
                              errorBuilder: (_, _, _) => Image.asset(
                                'assets/brand/sareemart-logo.png',
                                width: 32,
                                height: 32,
                                errorBuilder: (_, _, _) => const Icon(
                                  Icons.shopping_cart_rounded,
                                  color: AppTheme.accentOrange,
                                  size: 26,
                                ),
                              ),
                            )
                          : Image.asset(
                              'assets/brand/sareemart-logo.png',
                              width: 32,
                              height: 32,
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
                            ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: AppTheme.backgroundWhite,
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Notification bell with unread count (parity with front Header)
                  const NotificationBell(),
                  // Cart shortcut in the header. Wrapped in its own listener
                  // so the badge updates on every cart change.
                  ListenableBuilder(
                    listenable: app,
                    builder: (_, _) => IconButton(
                      onPressed: () => context.push('/cart'),
                      icon: Badge(
                        isLabelVisible: app.cartCount > 0,
                        backgroundColor: AppTheme.accentOrange,
                        label: Text(
                          '${app.cartCount}',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white,
                          ),
                        ),
                        child: const Icon(
                          Icons.shopping_cart_outlined,
                          color: AppTheme.backgroundWhite,
                        ),
                      ),
                      tooltip: app.t('cart'),
                    ),
                  ),
                  // My-account lives here now (bottom bar hosts Akhdimni).
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
              // Single page-aware search bar: only on home/products,
              // searching the page you are on.
              if (_searchable) const SizedBox(height: 10),
              if (_searchable)
                _HeaderSearchBar(onProducts: _onProducts, onHaraj: _onHaraj),
            ],
          ),
        ),
      ),
    );
  }
}

class SareemartCustomerApp extends StatelessWidget {
  const SareemartCustomerApp({super.key, required this.router});
  final GoRouter router;

  @override
  Widget build(BuildContext context) {
    // Chrome-only rebuilds (locale/brand/theme). Cart quantity changes,
    // shop revalidation, and badge ticks rebuild their own small scopes.
    return ListenableBuilder(
      listenable: Listenable.merge([
        appController.chromeTick,
        appController.i18n,
      ]),
      builder: (context, _) {
        final locale = appController.i18n.locale;
        return MaterialApp.router(
          title: J.str(
            appController.webSettings['site_title'],
            AppTheme.brandNameAr,
          ),
          debugShowCheckedModeBanner: false,
          locale: locale,
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          routerConfig: router,
          builder: (context, child) => Directionality(
            textDirection: appController.i18n.direction,
            child: child ?? const SizedBox.shrink(),
          ),
          theme: AppTheme.build(locale: locale, brand: appController.brand),
        );
      },
    );
  }
}
