import 'package:sqlite3/sqlite3.dart';

/// How a database open failure must be handled by [CatalogDatabase.openFile].
enum OpenFailureKind {
  /// Reliable evidence of corruption or an invalid SQLite database.
  /// Only this kind may trigger quarantine + recreation.
  corruption,

  /// Transient or operational failure (locking, permissions, resources,
  /// unknown errors). The original file must be preserved and the error
  /// surfaced to the caller. Never quarantine on this kind.
  transient,
}

/// Classifies an open/probe failure. Conservative by design: only confirmed
/// SQLite corruption signatures quarantine; everything else (including
/// unknown exceptions and migration-time operational failures such as
/// disk-full) preserves the file.
///
/// Primary result codes (SQLite `rescode.html`):
/// * 11 `SQLITE_CORRUPT`, 26 `SQLITE_NOTADB` → [OpenFailureKind.corruption].
/// * 3 PERM, 5 BUSY, 6 LOCKED, 7 NOMEM, 8 READONLY, 10 IOERR, 13 FULL,
///   14 CANTOPEN, anything else, non-SQLite errors → transient.
OpenFailureKind classifyOpenFailure(Object error) {
  if (error is SqliteException) {
    switch (error.resultCode) {
      case 11: // SQLITE_CORRUPT
      case 26: // SQLITE_NOTADB
        return OpenFailureKind.corruption;
    }
  }
  return OpenFailureKind.transient;
}
