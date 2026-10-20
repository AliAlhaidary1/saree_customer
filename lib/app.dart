import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'features/complaints/complaints_screen.dart';
import 'features/haraj/haraj_screens.dart';
import 'features/home/home_screen.dart';
import 'features/more/more_screens.dart';
import 'features/notifications/notifications_screen.dart';
import 'features/products/categories_screen.dart';
import 'features/products/products_screens.dart';
import 'widgets/brand_header.dart';
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
        // Kept outside the ShellRoute: pushing a ShellRoute branch from a
        // top-level page (product details) created a second match for the same
        // shell route, whose page key is the route hash and therefore
        // duplicated ("!keyReservation.contains(key)").
        path: '/cart',
        pageBuilder: (_, state) => AppTheme.slidePage(
          key: state.pageKey,
          child: AppShell(location: state.uri.path, child: const CartScreen()),
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
            // The legacy standalone catalog page is gone: every browse entry
            // point lands on the unified home design.
            redirect: (_, _) => '/',
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

  /// Pages named in the header itself instead of carrying the brand name.
  String _headerTitle() {
    if (location == '/orders') return appController.t('my_orders');
    return _brandTitle();
  }

  /// Search exists only on searchable pages (home, products, haraj).
  Widget? _headerSearchFor(String location) {
    if (location == '/') return const HeaderSearchBar();
    if (location == '/haraj') return const HeaderSearchBar(onHaraj: true);
    return null;
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
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: AppTheme.primaryNavy,
        body: Column(
          children: [
            BrandHeader(
              app: app,
              title: _headerTitle(),
              searchChild: _headerSearchFor(location),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(32),
                  ),
                  // Material (not Container): ListTile paints background/ink
                  // on the nearest Material ancestor; a bare ColoredBox would
                  // hide those and trips a framework assertion.
                  child: Material(color: AppTheme.surfaceGrey, child: child),
                ),
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          // Unique per shell instance: /cart is now rendered in its own
          // AppShell above the tab shell, and two visible FABs sharing one
          // hero tag trip the Hero duplicate-tag assertion.
          heroTag: 'assistant_fab_$location',
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

class SareemartCustomerApp extends StatefulWidget {
  const SareemartCustomerApp({super.key, required this.router});
  final GoRouter router;

  @override
  State<SareemartCustomerApp> createState() => _SareemartCustomerAppState();
}

class _SareemartCustomerAppState extends State<SareemartCustomerApp> {
  late final AppBackButtonDispatcher _backDispatcher = AppBackButtonDispatcher(
    widget.router,
  );

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
    );
    final router = widget.router;
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
          routeInformationProvider: router.routeInformationProvider,
          routeInformationParser: router.routeInformationParser,
          routerDelegate: router.routerDelegate,
          backButtonDispatcher: _backDispatcher,
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

/// Root back-button dispatcher that keeps the Android/system back button
/// inside the app.
///
/// go_router only consults a [ShellRoute]'s nested navigator when it can pop
/// (`_findCurrentNavigator`), so on a single-page tab like `/haraj` the back
/// press falls through to the root navigator, returns "not handled", and
/// Android closes the app. When nothing could be popped, this returns to the
/// home tab instead. From home, exiting requires explicit confirmation.
class AppBackButtonDispatcher extends RootBackButtonDispatcher {
  AppBackButtonDispatcher(this.router);

  final GoRouter router;
  bool _askingExit = false;

  @override
  Future<bool> didPopRoute() async {
    final handled = await super.didPopRoute();
    if (handled) return true;
    final location = router.routerDelegate.currentConfiguration.uri.path;
    if (location != '/') {
      router.go('/');
      return true;
    }
    // On the home tab: ask before actually leaving the app.
    if (_askingExit) return true;
    final context = router.routerDelegate.navigatorKey.currentContext;
    if (context == null || !context.mounted) return false;
    _askingExit = true;
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(appController.t('exit_app')),
          content: Text(appController.t('exit_confirm')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(appController.t('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(appController.t('exit_app')),
            ),
          ],
        ),
      );
      return confirmed != true;
    } finally {
      _askingExit = false;
    }
  }
}
