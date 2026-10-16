import 'package:drift/drift.dart';

/// Drift schema v1 for the offline catalog (Phase 1 foundation).
///
/// Identity rule (plan §2.2): every entity whose membership or display data
/// can vary by location scope is keyed by the composite natural key
/// (`scope`, `server_id`). Rows from different scopes therefore never
/// collide. Only global reference data (`cities`) and content-addressed
/// images (`cached_images`, keyed by URL) use global keys.
///
/// Account data (favorites, cart, orders, outbox, sessions, tokens,
/// addresses) NEVER lives in these tables — see the existing JSON stores.

/// Global reference data: cities do not vary by sync scope.
class Cities extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get serverId => integer().unique()();
  TextColumn get name => text()();
  TextColumn get payload => text()();
  DateTimeColumn get refreshedAt => dateTime()();
}

/// Store listing is city/GPS-scoped; availability context may differ.
class Stores extends Table {
  TextColumn get scope => text()();
  IntColumn get serverId => integer()();
  TextColumn get slug => text().nullable()();
  TextColumn get name => text()();
  RealColumn get latitude => real().nullable()();
  RealColumn get longitude => real().nullable()();
  RealColumn get rating => real().withDefault(const Constant(0))();
  IntColumn get status => integer().withDefault(const Constant(1))();
  TextColumn get payload => text()();
  DateTimeColumn get refreshedAt => dateTime()();
  DateTimeColumn get lastSeenAt => dateTime()();

  @override
  Set<Column> get primaryKey => {scope, serverId};
}

/// Category listing is city-scoped (`row_order` may vary by scope).
class Categories extends Table {
  TextColumn get scope => text()();
  IntColumn get serverId => integer()();
  IntColumn get parentId => integer().nullable()();
  TextColumn get name => text()();
  TextColumn get slug => text().nullable()();
  TextColumn get imageUrl => text().nullable()();
  IntColumn get rowOrder => integer().withDefault(const Constant(0))();
  TextColumn get type => text().nullable()(); // 'category' | 'section' | 'haraj'
  DateTimeColumn get refreshedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {scope, serverId};
}

/// Product display snapshots. Prices/stock are server-authoritative estimates
/// here (plan §2.1): this table is for offline display, never for checkout.
///
/// Reconciliation columns (schema v3): the sync walks the full server listing
/// and then reconciles membership instead of trusting offset checkpoints.
/// `isListed` marks rows present in the last clean full walk — browse, search,
/// counts and FTS read listed rows only, while detail lookups still resolve
/// unlisted rows (stale, server revalidates). `minPrice`/`inStock`/`hasOffer`
/// are computed from the row payload at upsert time (NULL = unknown, and
/// unknown rows are never hidden by that filter); all are refreshed on every
/// re-upsert, so updates propagate without a change feed.
class Products extends Table {
  TextColumn get scope => text()();
  IntColumn get serverId => integer()();
  TextColumn get slug => text().nullable()();
  TextColumn get name => text()();
  IntColumn get storeId => integer()();
  IntColumn get categoryId => integer().nullable()();
  TextColumn get searchBlob => text()();
  TextColumn get priceSnapshot => text()();
  TextColumn get thumbnailUrl => text().nullable()();

  /// Local image file path. NULL means "not available offline" — callers
  /// must show a placeholder and never claim offline availability otherwise.
  TextColumn get localImagePath => text().nullable()();

  RealColumn get rating => real().withDefault(const Constant(0))();
  IntColumn get status => integer().withDefault(const Constant(1))();

  /// False only after a clean full-walk reconciliation proves the row is
  /// absent from the server listing (deleted, unapproved, disabled, or
  /// out of stock — the listing hard-filters all of these).
  BoolColumn get isListed => boolean().withDefault(const Constant(true))();

  /// Minimum effective variant price (discounted when present), NULL when the
  /// payload carries no usable price. NULL sorts last and never filters out.
  RealColumn get minPrice => real().nullable()();

  /// Any variant in stock (or product-level unlimited flag), NULL = unknown.
  /// Unknown rows are never hidden by stock filters.
  BoolColumn get inStock => boolean().nullable()();

  /// Any variant-level or row-level offer signal, NULL = unknown.
  BoolColumn get hasOffer => boolean().nullable()();

  TextColumn get payload => text()();
  DateTimeColumn get refreshedAt => dateTime()();
  DateTimeColumn get lastSeenAt => dateTime()();

  @override
  Set<Column> get primaryKey => {scope, serverId};
}

class ProductVariants extends Table {
  TextColumn get scope => text()();
  IntColumn get serverId => integer()();
  IntColumn get productId => integer()();
  TextColumn get payload => text()();
  DateTimeColumn get refreshedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {scope, serverId};

  /// Composite foreign key (SQLite fully supports multi-column FKs):
  /// a variant row cannot exist without its scoped product. Enforced only
  /// when connections run `PRAGMA foreign_keys = ON` (see
  /// [CatalogDatabase] `beforeOpen`, schema v2+). Cascades keep explicit
  /// DAO deletes consistent; FTS rows are maintained explicitly (FTS5
  /// tables cannot participate in foreign keys).
  @override
  List<String> get customConstraints => [
        'FOREIGN KEY (scope, product_id) REFERENCES products (scope, server_id) '
            'ON DELETE CASCADE',
      ];
}

/// Image manifest. Files live in the app-private images directory; this table
/// tracks actual bytes for budget enforcement (Phase 4 pipeline).
class CachedImages extends Table {
  TextColumn get url => text()();
  TextColumn get localPath => text()();
  IntColumn get bytes => integer()();
  DateTimeColumn get lastUsedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {url};
}

class SyncStates extends Table {
  TextColumn get scope => text()();
  TextColumn get phase => text()();
  TextColumn get coverage => text().withDefault(const Constant('best_effort'))();
  IntColumn get lastOffset => integer().withDefault(const Constant(0))();
  TextColumn get lastCreatedAt => text().nullable()();
  IntColumn get lastId => integer().withDefault(const Constant(0))();
  IntColumn get serverTotal => integer().withDefault(const Constant(0))();
  IntColumn get storedCount => integer().withDefault(const Constant(0))();
  TextColumn get checkpoint => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {scope};
}

class CartItems extends Table {
  IntColumn get productId => integer()();
  IntColumn get variantId => integer()();
  IntColumn get qty => integer().withDefault(const Constant(1))();
  IntColumn get sellerId => integer()();
  TextColumn get name => text()();
  TextColumn get imageUrl => text()();
  RealColumn get price => real()();
  TextColumn get variantLabel => text().nullable()();
  TextColumn get slug => text().nullable()();
  IntColumn get stock => integer().nullable()();
  IntColumn get totalStock => integer().nullable()();
  IntColumn get isUnlimitedStock => integer().withDefault(const Constant(0))();
  TextColumn get stockStatus => text().nullable()();
  IntColumn get totalAllowedQuantity => integer().nullable()();
  RealColumn get savedAmount => real().nullable()();
  IntColumn get addedAt => integer()();

  @override
  Set<Column> get primaryKey => {productId, variantId};
}
