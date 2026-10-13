import 'package:flutter/foundation.dart';

/// Header search bus.
///
/// The AppShell header owns the single search field. It is only visible on
/// searchable pages (home `/`, `/products` and `/haraj` — never
/// cart/account/orders).
/// - On home: submit navigates to `/products?search=…`.
/// - On `/products`: submit notifies listeners and ProductsScreen filters
///   in place (no route stacking, no rebuild hacks).
/// - On `/haraj`: submit notifies listeners and HarajListScreen filters in
///   place.
class HeaderSearch extends ChangeNotifier {
  String productQuery = '';
  String harajQuery = '';

  void submitProducts(String q) {
    productQuery = q.trim();
    notifyListeners();
  }

  void submitHaraj(String q) {
    harajQuery = q.trim();
    notifyListeners();
  }
}

final headerSearch = HeaderSearch();
