import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

import 'core/app_controller.dart';
import 'core/app_theme.dart';
import 'core/json_util.dart';
import 'features/account/account_screens.dart';
import 'features/akhdimni/akhdimni_screens.dart';
import 'features/assistant/assistant_screen.dart';
import 'features/auth/auth_screens.dart';
import 'features/cart/cart_screens.dart';
import 'features/checkout_groups/checkout_groups_screens.dart';
import 'features/haraj/haraj_screens.dart';
import 'features/home/home_screen.dart';
import 'features/more/more_screens.dart';
import 'features/notifications/notifications_screen.dart';
import 'features/products/categories_screen.dart';
import 'features/products/products_screens.dart';
import 'features/roles/roles_screens.dart';
import 'widgets/ui_helpers.dart';

GoRouter buildRouter() {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: appController,
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
        path: '/orders',
        pageBuilder: (_, state) => AppTheme.slidePage(
          key: state.pageKey,
          child: const OrdersScreen(),
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
            loader: () async =>
                (await appController.api.transactions(type: 'wallet')).dataMaps,
            pageLoader: (limit, offset) async => (await appController.api
                    .transactions(limit: limit, offset: offset, type: 'wallet'))
                .dataMaps,
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
            loader: () async => (await appController.api.transactions()).dataMaps,
            pageLoader: (limit, offset) async => (await appController.api
                    .transactions(limit: limit, offset: offset))
                .dataMaps,
            emptyMessage: appController.t('no_transaction'),
          ),
        ),
      ),
      GoRoute(
        path: '/sellers',
        pageBuilder: (_, state) => AppTheme.slidePage(
          key: state.pageKey,
          child: SellersScreen(
            typeId: state.uri.queryParameters['type'] ??
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
        pageBuilder: (_, state) => AppTheme.slidePage(
          key: state.pageKey,
          child: const OffersScreen(),
        ),
      ),
      GoRoute(
        path: '/search',
        pageBuilder: (_, state) => AppTheme.slidePage(
          key: state.pageKey,
          child: const SearchScreen(),
        ),
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
        path: '/haraj',
        pageBuilder: (_, state) => AppTheme.slidePage(
          key: state.pageKey,
          child: const HarajListScreen(),
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
      GoRoute(path: '/checkout-groups', pageBuilder: (_, s)=> AppTheme.slidePage(key: s.pageKey, child: const CheckoutGroupsScreen())),
      GoRoute(path: '/checkout-groups/:id', pageBuilder: (_, s)=> AppTheme.slidePage(key: s.pageKey, child: CheckoutGroupDetailsScreen(id: s.pathParameters['id']!))),
      GoRoute(path: '/seller/orders', pageBuilder: (_, s)=> AppTheme.slidePage(key: s.pageKey, child: const SellerOrdersScreen())),
      GoRoute(path: '/seller/orders/:id', pageBuilder: (_, s)=> AppTheme.slidePage(key: s.pageKey, child: SellerOrderDetailsScreen(id: s.pathParameters['id']!))),
      GoRoute(path: '/seller/settlement', pageBuilder: (_, s)=> AppTheme.slidePage(key: s.pageKey, child: const SellerSettlementScreen())),
      GoRoute(path: '/courier', pageBuilder: (_, s)=> AppTheme.slidePage(key: s.pageKey, child: const CourierDashboardScreen())),
      GoRoute(path: '/courier/assignments', pageBuilder: (_, s)=> AppTheme.slidePage(key: s.pageKey, child: const CourierAssignmentsScreen())),
      GoRoute(path: '/courier/assignments/:id', pageBuilder: (_, s)=> AppTheme.slidePage(key: s.pageKey, child: CourierAssignmentDetailsScreen(id: s.pathParameters['id']!))),
      GoRoute(path: '/courier/settlement', pageBuilder: (_, s)=> AppTheme.slidePage(key: s.pageKey, child: const CourierSettlementScreen())),
      GoRoute(path: '/admin/checkout-groups', pageBuilder: (_, s)=> AppTheme.slidePage(key: s.pageKey, child: const AdminCheckoutGroupsScreen())),
      GoRoute(path: '/admin/checkout-groups/:id', pageBuilder: (_, s)=> AppTheme.slidePage(key: s.pageKey, child: AdminCheckoutGroupDetailsScreen(id: s.pathParameters['id']!))),
      GoRoute(path: '/admin/dispatch', pageBuilder: (_, s)=> AppTheme.slidePage(key: s.pageKey, child: const AdminDispatchScreen())),
      GoRoute(path: '/admin/returns', pageBuilder: (_, s)=> AppTheme.slidePage(key: s.pageKey, child: const AdminReturnsScreen())),
      GoRoute(
        path: '/akhdimni',
        pageBuilder: (_, state) => AppTheme.slidePage(
          key: state.pageKey,
          child: const AkhdimniHomeScreen(),
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
        path: '/assistant',
        pageBuilder: (_, state) => AppTheme.slidePage(
          key: state.pageKey,
          child: const AssistantScreen(),
        ),
      ),
      GoRoute(
        path: '/faq',
        pageBuilder: (_, state) => AppTheme.slidePage(
          key: state.pageKey,
          child: const FaqScreen(),
        ),
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
              title: appController
                  .t(titles[type] ?? 'privacy_policy'),
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
            path: '/products',
            pageBuilder: (_, state) => AppTheme.slidePage(
              key: state.pageKey,
              child: ProductsScreen(
                categoryId: state.uri.queryParameters['category'],
                search: state.uri.queryParameters['search'],
                hasOffer: state.uri.queryParameters['offer'] == '1',
                sectionId: state.uri.queryParameters['section'],
                sellerId: state.uri.queryParameters['seller'],
              ),
            ),
          ),
          GoRoute(
            path: '/cart',
            pageBuilder: (_, state) => AppTheme.slidePage(
              key: state.pageKey,
              child: const CartScreen(),
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

  int get index {
    if (location.startsWith('/products')) return 1;
    if (location.startsWith('/cart')) return 2;
    if (location.startsWith('/account')) return 3;
    return 0;
  }

  String _brandTitle() {
    final fromApi = J.str(appController.webSettings['site_title']);
    if (fromApi.isNotEmpty) return fromApi;
    return AppTheme.brandNameAr;
  }

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
          _BrandHeader(app: app, title: _brandTitle()),
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
        onDestinationSelected: (i) {
          switch (i) {
            case 0:
              context.go('/');
            case 1:
              context.go('/products');
            case 2:
              context.go('/cart');
            case 3:
              context.go('/account');
          }
        },
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: app.t('home'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.grid_view_outlined),
            selectedIcon: const Icon(Icons.grid_view),
            label: app.t('products'),
          ),
          NavigationDestination(
            icon: _AnimatedCartBadge(count: app.cartCount, selected: false),
            selectedIcon: _AnimatedCartBadge(count: app.cartCount, selected: true),
            label: app.t('cart'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline),
            selectedIcon: const Icon(Icons.person),
            label: app.t('my_account'),
          ),
        ],
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader({required this.app, required this.title});
  final AppController app;
  final String title;

  @override
  Widget build(BuildContext context) {
    final categories = app.rootCategories.isNotEmpty
        ? app.rootCategories
        : J.maps(app.shop?['categories']);

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
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: app.brand.logoUrl != null && app.brand.logoUrl!.isNotEmpty
                        ? Image.network(
                            app.brand.logoUrl!,
                            width: 36,
                            height: 36,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => Image.asset(
                              'assets/brand/saree-market-logo.png',
                              width: 36,
                              height: 36,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.shopping_cart_rounded,
                                color: AppTheme.accentOrange,
                                size: 28,
                              ),
                            ),
                          )
                        : Image.asset(
                            'assets/brand/saree-market-logo.png',
                            width: 36,
                            height: 36,
                            errorBuilder: (_, __, ___) => Image.asset(
                              'assets/brand/saree-market-mark.png',
                              width: 36,
                              height: 36,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.shopping_cart_rounded,
                                color: AppTheme.accentOrange,
                                size: 28,
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
                  // Location pin
                  InkWell(
                    onTap: app.cities.isEmpty
                        ? null
                        : () => showModalBottomSheet(
                            context: context,
                            builder: (_) => const CityPickerSheet(),
                          ),
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.location_on,
                            color: AppTheme.accentOrange,
                            size: 18,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              J.str(app.city?['name'], app.t('city')),
                              style: const TextStyle(
                                color: AppTheme.backgroundWhite,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Notification bell with unread count (parity with front Header)
                  const NotificationBell(),
                  IconButton(
                    onPressed: () => context.push('/sellers'),
                    icon: const Icon(
                      Icons.storefront_outlined,
                      color: AppTheme.backgroundWhite,
                    ),
                    tooltip: app.t('sellers'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Search bar
              GestureDetector(
                onTap: () => context.push('/search'),
                child: Container(
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
                        child: Text(
                          app.t('i_am_looking_for'),
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      if (categories.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.accentOrange.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.filter_list,
                                size: 14,
                                color: AppTheme.accentOrange,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                app.t('categories') == 'categories'
                                    ? 'فئات'
                                    : app.t('categories'),
                                style: const TextStyle(
                                  color: AppTheme.accentOrange,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnimatedCartBadge extends StatefulWidget {
  const _AnimatedCartBadge({required this.count, required this.selected});
  final int count;
  final bool selected;

  @override
  State<_AnimatedCartBadge> createState() => _AnimatedCartBadgeState();
}

class _AnimatedCartBadgeState extends State<_AnimatedCartBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void didUpdateWidget(_AnimatedCartBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.count != oldWidget.count && widget.count > 0) {
      _pulse.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween<double>(begin: 1, end: 1.25).animate(
        CurvedAnimation(parent: _pulse, curve: Curves.elasticOut),
      ),
      child: Badge(
        isLabelVisible: widget.count > 0,
        backgroundColor: AppTheme.accentOrange,
        label: Text(
          '${widget.count}',
          style: const TextStyle(fontSize: 10, color: Colors.white),
        ),
        child: Icon(
          widget.selected
              ? Icons.shopping_cart
              : Icons.shopping_cart_outlined,
        ),
      ),
    );
  }
}

class SareeCustomerApp extends StatelessWidget {
  const SareeCustomerApp({super.key, required this.router});
  final GoRouter router;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appController,
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
