/// Constants for the Drift-backed offline catalog.
///
/// The database backs local browsing/search behind [catalogDbEnabled]
/// (rollback = set false, restart). JSON account storage is untouched, and
/// every catalog read falls back to JSON/network when the database is
/// unavailable, so disabling the flag restores the pre-cutover behavior.
class CatalogDbConfig {
  const CatalogDbConfig._();

  /// Kill-switch / cutover flag. Rollback = set false, restart.
  static const bool catalogDbEnabled = true;

  /// Test-only override for hermetic tests (flag stays authoritative in
  /// production). Allows unit tests to exercise the DB path without edits.
  static bool _testOverride = false;

  /// Effective gate used by [AppController.ensureCatalogDb]: the shipped
  /// flag OR the test override.
  static bool get enabledForUse => catalogDbEnabled || _testOverride;

  /// Test seam only. Never called from production code.
  static void setTestOverride(bool value) {
    _testOverride = value;
  }

  static const int schemaVersion = 3;
  static const String dbFileName = 'sareemart_catalog.db';

  /// Thumbnail disk budget (enforced from actual file bytes, Phase 4).
  static const int imageBudgetBytes = 150 * 1024 * 1024;

  /// Combined DB + images ceiling with pre-flight free-space check.
  static const int combinedCeilingBytes = 250 * 1024 * 1024;

  /// Client-side downscale target for prefetched thumbnails (Phase 4).
  static const int thumbnailMaxDimension = 512;

  /// Backend page cap for product listings, verified against the real
  /// `DiscoveryQueryBuilder::productContext` (clamps to 48) and live
  /// pagination probes: requesting more returns at most 48 rows, so the
  /// request size matches the cap — a full page never looks short.
  static const int syncPageSize = 48;
}
