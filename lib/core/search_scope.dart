import 'package:flutter/foundation.dart';

/// Header search bus.
///
/// The AppShell header owns the single search field. It is only visible on
/// searchable pages (home `/` and `/products` — never cart/account/orders).
/// - On home: submit navigates to `/products?search=…`.
/// - On `/products`: submit notifies listeners and ProductsScreen filters
///   in place (no route stacking, no rebuild hacks).
class HeaderSearch extends ChangeNotifier {
  String productQuery = '';

  void submitProducts(String q) {
    productQuery = q.trim();
    notifyListeners();
  }
}

final headerSearch = HeaderSearch();
