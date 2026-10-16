/// Typed coverage state for a synced catalog scope.
///
/// `bestEffort` is the only state Phase 1 code paths may write: paging over
/// offset-sorted listings cannot prove completeness (plan §3.2).
/// `verified` additionally requires [VerifiedEvidence.isSufficient], and no
/// production path in this phase can construct sufficient evidence — the
/// gate exists so Phase 2 must present it, not so tests can pretend to.
enum SyncCoverage { bestEffort, verified }

/// Strict string codec for the `sync_states.coverage` column.
/// Unknown values throw instead of mapping silently (fail loudly on
/// data errors rather than mislabeling catalog completeness).
class SyncCoverageCodec {
  const SyncCoverageCodec._();

  static String toDb(SyncCoverage coverage) => switch (coverage) {
        SyncCoverage.bestEffort => 'best_effort',
        SyncCoverage.verified => 'verified',
      };

  static SyncCoverage fromDb(String raw) => switch (raw) {
        'best_effort' => SyncCoverage.bestEffort,
        'verified' => SyncCoverage.verified,
        _ => throw ArgumentError.value(raw, 'coverage', 'unknown coverage'),
      };
}

/// Evidence bundle required before `verified` may be recorded:
/// a completed baseline, a completed composite-cursor walk (B1 contract),
/// and tombstone reconciliation (B2 feed). Cursor paging alone is NOT
/// sufficient: it captures inserts only, never updates or deletes, and says
/// nothing about backdated rows (plan §3.2–§3.3, §4.1).
class VerifiedEvidence {
  const VerifiedEvidence({
    required this.baselineComplete,
    required this.cursorComplete,
    required this.tombstonesReconciled,
  });

  final bool baselineComplete;
  final bool cursorComplete;
  final bool tombstonesReconciled;

  bool get isSufficient =>
      baselineComplete && cursorComplete && tombstonesReconciled;
}
