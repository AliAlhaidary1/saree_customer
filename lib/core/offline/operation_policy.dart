/// Central offline-eligibility policy for customer-app operations.
///
/// Two classes only — there is no "maybe offline" middle ground:
///
/// * [OfflineEligibility.offlineCapable]: safe to perform/edit locally and
///   reconcile later (browsing cached catalog, favorite toggles via the
///   idempotent outbox). Local money/price displays from this class
///   are ESTIMATES until the server revalidates them.
/// * [OfflineEligibility.onlineOnly]: requires a live backend state
///   transition. These must never complete, be queued for auto-execution, or
///   be reported successful while the backend is unreachable.
///
/// Service-layer enforcement lives with each operation (the API result is the
/// guard); UI pre-checks via [CustomerApi.likelyOffline] are fast feedback
/// only and never authoritative. Hiding a button is not a guard.
enum OfflineEligibility { offlineCapable, onlineOnly }

/// Operations subject to this policy.
enum CustomerOp {
  browseCatalog,
  viewProductDetails,
  searchLocal,
  editCart,
  toggleFavorite,
  manageAddressesLocal,
  checkout,
  createOrder,
  initiatePayment,
  verifyPayment,
  cancelOrder,
  modifyOrder,
  requestRefund,
  walletTransfer,
}

class OperationPolicy {
  const OperationPolicy._();

  static OfflineEligibility eligibilityOf(CustomerOp op) {
    switch (op) {
      case CustomerOp.browseCatalog:
      case CustomerOp.viewProductDetails:
      case CustomerOp.searchLocal:
      case CustomerOp.toggleFavorite:
      case CustomerOp.manageAddressesLocal:
      case CustomerOp.editCart:
        return OfflineEligibility.offlineCapable;
      case CustomerOp.checkout:
      case CustomerOp.createOrder:
      case CustomerOp.initiatePayment:
      case CustomerOp.verifyPayment:
      case CustomerOp.cancelOrder:
      case CustomerOp.modifyOrder:
      case CustomerOp.requestRefund:
      case CustomerOp.walletTransfer:
        return OfflineEligibility.onlineOnly;
    }
  }

  static bool isOnlineOnly(CustomerOp op) =>
      eligibilityOf(op) == OfflineEligibility.onlineOnly;
}

/// Sentinel error code returned by cart mutations when the backend is
/// unreachable. UI shows the shared offline dialog for this code instead of
/// a snackbar (see `showCartError`).
const kRequiresInternet = 'requires_internet';
