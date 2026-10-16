// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'catalog_database.dart';

// ignore_for_file: type=lint
class $CitiesTable extends Cities with TableInfo<$CitiesTable, City> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CitiesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _serverIdMeta = const VerificationMeta(
    'serverId',
  );
  @override
  late final GeneratedColumn<int> serverId = GeneratedColumn<int>(
    'server_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _refreshedAtMeta = const VerificationMeta(
    'refreshedAt',
  );
  @override
  late final GeneratedColumn<DateTime> refreshedAt = GeneratedColumn<DateTime>(
    'refreshed_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    serverId,
    name,
    payload,
    refreshedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cities';
  @override
  VerificationContext validateIntegrity(
    Insertable<City> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('server_id')) {
      context.handle(
        _serverIdMeta,
        serverId.isAcceptableOrUnknown(data['server_id']!, _serverIdMeta),
      );
    } else if (isInserting) {
      context.missing(_serverIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('refreshed_at')) {
      context.handle(
        _refreshedAtMeta,
        refreshedAt.isAcceptableOrUnknown(
          data['refreshed_at']!,
          _refreshedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_refreshedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  City map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return City(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      serverId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      refreshedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}refreshed_at'],
      )!,
    );
  }

  @override
  $CitiesTable createAlias(String alias) {
    return $CitiesTable(attachedDatabase, alias);
  }
}

class City extends DataClass implements Insertable<City> {
  final int id;
  final int serverId;
  final String name;
  final String payload;
  final DateTime refreshedAt;
  const City({
    required this.id,
    required this.serverId,
    required this.name,
    required this.payload,
    required this.refreshedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['server_id'] = Variable<int>(serverId);
    map['name'] = Variable<String>(name);
    map['payload'] = Variable<String>(payload);
    map['refreshed_at'] = Variable<DateTime>(refreshedAt);
    return map;
  }

  CitiesCompanion toCompanion(bool nullToAbsent) {
    return CitiesCompanion(
      id: Value(id),
      serverId: Value(serverId),
      name: Value(name),
      payload: Value(payload),
      refreshedAt: Value(refreshedAt),
    );
  }

  factory City.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return City(
      id: serializer.fromJson<int>(json['id']),
      serverId: serializer.fromJson<int>(json['serverId']),
      name: serializer.fromJson<String>(json['name']),
      payload: serializer.fromJson<String>(json['payload']),
      refreshedAt: serializer.fromJson<DateTime>(json['refreshedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'serverId': serializer.toJson<int>(serverId),
      'name': serializer.toJson<String>(name),
      'payload': serializer.toJson<String>(payload),
      'refreshedAt': serializer.toJson<DateTime>(refreshedAt),
    };
  }

  City copyWith({
    int? id,
    int? serverId,
    String? name,
    String? payload,
    DateTime? refreshedAt,
  }) => City(
    id: id ?? this.id,
    serverId: serverId ?? this.serverId,
    name: name ?? this.name,
    payload: payload ?? this.payload,
    refreshedAt: refreshedAt ?? this.refreshedAt,
  );
  City copyWithCompanion(CitiesCompanion data) {
    return City(
      id: data.id.present ? data.id.value : this.id,
      serverId: data.serverId.present ? data.serverId.value : this.serverId,
      name: data.name.present ? data.name.value : this.name,
      payload: data.payload.present ? data.payload.value : this.payload,
      refreshedAt: data.refreshedAt.present
          ? data.refreshedAt.value
          : this.refreshedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('City(')
          ..write('id: $id, ')
          ..write('serverId: $serverId, ')
          ..write('name: $name, ')
          ..write('payload: $payload, ')
          ..write('refreshedAt: $refreshedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, serverId, name, payload, refreshedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is City &&
          other.id == this.id &&
          other.serverId == this.serverId &&
          other.name == this.name &&
          other.payload == this.payload &&
          other.refreshedAt == this.refreshedAt);
}

class CitiesCompanion extends UpdateCompanion<City> {
  final Value<int> id;
  final Value<int> serverId;
  final Value<String> name;
  final Value<String> payload;
  final Value<DateTime> refreshedAt;
  const CitiesCompanion({
    this.id = const Value.absent(),
    this.serverId = const Value.absent(),
    this.name = const Value.absent(),
    this.payload = const Value.absent(),
    this.refreshedAt = const Value.absent(),
  });
  CitiesCompanion.insert({
    this.id = const Value.absent(),
    required int serverId,
    required String name,
    required String payload,
    required DateTime refreshedAt,
  }) : serverId = Value(serverId),
       name = Value(name),
       payload = Value(payload),
       refreshedAt = Value(refreshedAt);
  static Insertable<City> custom({
    Expression<int>? id,
    Expression<int>? serverId,
    Expression<String>? name,
    Expression<String>? payload,
    Expression<DateTime>? refreshedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (serverId != null) 'server_id': serverId,
      if (name != null) 'name': name,
      if (payload != null) 'payload': payload,
      if (refreshedAt != null) 'refreshed_at': refreshedAt,
    });
  }

  CitiesCompanion copyWith({
    Value<int>? id,
    Value<int>? serverId,
    Value<String>? name,
    Value<String>? payload,
    Value<DateTime>? refreshedAt,
  }) {
    return CitiesCompanion(
      id: id ?? this.id,
      serverId: serverId ?? this.serverId,
      name: name ?? this.name,
      payload: payload ?? this.payload,
      refreshedAt: refreshedAt ?? this.refreshedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (serverId.present) {
      map['server_id'] = Variable<int>(serverId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (refreshedAt.present) {
      map['refreshed_at'] = Variable<DateTime>(refreshedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CitiesCompanion(')
          ..write('id: $id, ')
          ..write('serverId: $serverId, ')
          ..write('name: $name, ')
          ..write('payload: $payload, ')
          ..write('refreshedAt: $refreshedAt')
          ..write(')'))
        .toString();
  }
}

class $CategoriesTable extends Categories
    with TableInfo<$CategoriesTable, Category> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CategoriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _scopeMeta = const VerificationMeta('scope');
  @override
  late final GeneratedColumn<String> scope = GeneratedColumn<String>(
    'scope',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _serverIdMeta = const VerificationMeta(
    'serverId',
  );
  @override
  late final GeneratedColumn<int> serverId = GeneratedColumn<int>(
    'server_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _parentIdMeta = const VerificationMeta(
    'parentId',
  );
  @override
  late final GeneratedColumn<int> parentId = GeneratedColumn<int>(
    'parent_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _slugMeta = const VerificationMeta('slug');
  @override
  late final GeneratedColumn<String> slug = GeneratedColumn<String>(
    'slug',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _imageUrlMeta = const VerificationMeta(
    'imageUrl',
  );
  @override
  late final GeneratedColumn<String> imageUrl = GeneratedColumn<String>(
    'image_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rowOrderMeta = const VerificationMeta(
    'rowOrder',
  );
  @override
  late final GeneratedColumn<int> rowOrder = GeneratedColumn<int>(
    'row_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _refreshedAtMeta = const VerificationMeta(
    'refreshedAt',
  );
  @override
  late final GeneratedColumn<DateTime> refreshedAt = GeneratedColumn<DateTime>(
    'refreshed_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    scope,
    serverId,
    parentId,
    name,
    slug,
    imageUrl,
    rowOrder,
    type,
    refreshedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'categories';
  @override
  VerificationContext validateIntegrity(
    Insertable<Category> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('scope')) {
      context.handle(
        _scopeMeta,
        scope.isAcceptableOrUnknown(data['scope']!, _scopeMeta),
      );
    } else if (isInserting) {
      context.missing(_scopeMeta);
    }
    if (data.containsKey('server_id')) {
      context.handle(
        _serverIdMeta,
        serverId.isAcceptableOrUnknown(data['server_id']!, _serverIdMeta),
      );
    } else if (isInserting) {
      context.missing(_serverIdMeta);
    }
    if (data.containsKey('parent_id')) {
      context.handle(
        _parentIdMeta,
        parentId.isAcceptableOrUnknown(data['parent_id']!, _parentIdMeta),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('slug')) {
      context.handle(
        _slugMeta,
        slug.isAcceptableOrUnknown(data['slug']!, _slugMeta),
      );
    }
    if (data.containsKey('image_url')) {
      context.handle(
        _imageUrlMeta,
        imageUrl.isAcceptableOrUnknown(data['image_url']!, _imageUrlMeta),
      );
    }
    if (data.containsKey('row_order')) {
      context.handle(
        _rowOrderMeta,
        rowOrder.isAcceptableOrUnknown(data['row_order']!, _rowOrderMeta),
      );
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    }
    if (data.containsKey('refreshed_at')) {
      context.handle(
        _refreshedAtMeta,
        refreshedAt.isAcceptableOrUnknown(
          data['refreshed_at']!,
          _refreshedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_refreshedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {scope, serverId};
  @override
  Category map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Category(
      scope: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scope'],
      )!,
      serverId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_id'],
      )!,
      parentId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}parent_id'],
      ),
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      slug: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}slug'],
      ),
      imageUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}image_url'],
      ),
      rowOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}row_order'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      ),
      refreshedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}refreshed_at'],
      )!,
    );
  }

  @override
  $CategoriesTable createAlias(String alias) {
    return $CategoriesTable(attachedDatabase, alias);
  }
}

class Category extends DataClass implements Insertable<Category> {
  final String scope;
  final int serverId;
  final int? parentId;
  final String name;
  final String? slug;
  final String? imageUrl;
  final int rowOrder;
  final String? type;
  final DateTime refreshedAt;
  const Category({
    required this.scope,
    required this.serverId,
    this.parentId,
    required this.name,
    this.slug,
    this.imageUrl,
    required this.rowOrder,
    this.type,
    required this.refreshedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['scope'] = Variable<String>(scope);
    map['server_id'] = Variable<int>(serverId);
    if (!nullToAbsent || parentId != null) {
      map['parent_id'] = Variable<int>(parentId);
    }
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || slug != null) {
      map['slug'] = Variable<String>(slug);
    }
    if (!nullToAbsent || imageUrl != null) {
      map['image_url'] = Variable<String>(imageUrl);
    }
    map['row_order'] = Variable<int>(rowOrder);
    if (!nullToAbsent || type != null) {
      map['type'] = Variable<String>(type);
    }
    map['refreshed_at'] = Variable<DateTime>(refreshedAt);
    return map;
  }

  CategoriesCompanion toCompanion(bool nullToAbsent) {
    return CategoriesCompanion(
      scope: Value(scope),
      serverId: Value(serverId),
      parentId: parentId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentId),
      name: Value(name),
      slug: slug == null && nullToAbsent ? const Value.absent() : Value(slug),
      imageUrl: imageUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(imageUrl),
      rowOrder: Value(rowOrder),
      type: type == null && nullToAbsent ? const Value.absent() : Value(type),
      refreshedAt: Value(refreshedAt),
    );
  }

  factory Category.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Category(
      scope: serializer.fromJson<String>(json['scope']),
      serverId: serializer.fromJson<int>(json['serverId']),
      parentId: serializer.fromJson<int?>(json['parentId']),
      name: serializer.fromJson<String>(json['name']),
      slug: serializer.fromJson<String?>(json['slug']),
      imageUrl: serializer.fromJson<String?>(json['imageUrl']),
      rowOrder: serializer.fromJson<int>(json['rowOrder']),
      type: serializer.fromJson<String?>(json['type']),
      refreshedAt: serializer.fromJson<DateTime>(json['refreshedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'scope': serializer.toJson<String>(scope),
      'serverId': serializer.toJson<int>(serverId),
      'parentId': serializer.toJson<int?>(parentId),
      'name': serializer.toJson<String>(name),
      'slug': serializer.toJson<String?>(slug),
      'imageUrl': serializer.toJson<String?>(imageUrl),
      'rowOrder': serializer.toJson<int>(rowOrder),
      'type': serializer.toJson<String?>(type),
      'refreshedAt': serializer.toJson<DateTime>(refreshedAt),
    };
  }

  Category copyWith({
    String? scope,
    int? serverId,
    Value<int?> parentId = const Value.absent(),
    String? name,
    Value<String?> slug = const Value.absent(),
    Value<String?> imageUrl = const Value.absent(),
    int? rowOrder,
    Value<String?> type = const Value.absent(),
    DateTime? refreshedAt,
  }) => Category(
    scope: scope ?? this.scope,
    serverId: serverId ?? this.serverId,
    parentId: parentId.present ? parentId.value : this.parentId,
    name: name ?? this.name,
    slug: slug.present ? slug.value : this.slug,
    imageUrl: imageUrl.present ? imageUrl.value : this.imageUrl,
    rowOrder: rowOrder ?? this.rowOrder,
    type: type.present ? type.value : this.type,
    refreshedAt: refreshedAt ?? this.refreshedAt,
  );
  Category copyWithCompanion(CategoriesCompanion data) {
    return Category(
      scope: data.scope.present ? data.scope.value : this.scope,
      serverId: data.serverId.present ? data.serverId.value : this.serverId,
      parentId: data.parentId.present ? data.parentId.value : this.parentId,
      name: data.name.present ? data.name.value : this.name,
      slug: data.slug.present ? data.slug.value : this.slug,
      imageUrl: data.imageUrl.present ? data.imageUrl.value : this.imageUrl,
      rowOrder: data.rowOrder.present ? data.rowOrder.value : this.rowOrder,
      type: data.type.present ? data.type.value : this.type,
      refreshedAt: data.refreshedAt.present
          ? data.refreshedAt.value
          : this.refreshedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Category(')
          ..write('scope: $scope, ')
          ..write('serverId: $serverId, ')
          ..write('parentId: $parentId, ')
          ..write('name: $name, ')
          ..write('slug: $slug, ')
          ..write('imageUrl: $imageUrl, ')
          ..write('rowOrder: $rowOrder, ')
          ..write('type: $type, ')
          ..write('refreshedAt: $refreshedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    scope,
    serverId,
    parentId,
    name,
    slug,
    imageUrl,
    rowOrder,
    type,
    refreshedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Category &&
          other.scope == this.scope &&
          other.serverId == this.serverId &&
          other.parentId == this.parentId &&
          other.name == this.name &&
          other.slug == this.slug &&
          other.imageUrl == this.imageUrl &&
          other.rowOrder == this.rowOrder &&
          other.type == this.type &&
          other.refreshedAt == this.refreshedAt);
}

class CategoriesCompanion extends UpdateCompanion<Category> {
  final Value<String> scope;
  final Value<int> serverId;
  final Value<int?> parentId;
  final Value<String> name;
  final Value<String?> slug;
  final Value<String?> imageUrl;
  final Value<int> rowOrder;
  final Value<String?> type;
  final Value<DateTime> refreshedAt;
  final Value<int> rowid;
  const CategoriesCompanion({
    this.scope = const Value.absent(),
    this.serverId = const Value.absent(),
    this.parentId = const Value.absent(),
    this.name = const Value.absent(),
    this.slug = const Value.absent(),
    this.imageUrl = const Value.absent(),
    this.rowOrder = const Value.absent(),
    this.type = const Value.absent(),
    this.refreshedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CategoriesCompanion.insert({
    required String scope,
    required int serverId,
    this.parentId = const Value.absent(),
    required String name,
    this.slug = const Value.absent(),
    this.imageUrl = const Value.absent(),
    this.rowOrder = const Value.absent(),
    this.type = const Value.absent(),
    required DateTime refreshedAt,
    this.rowid = const Value.absent(),
  }) : scope = Value(scope),
       serverId = Value(serverId),
       name = Value(name),
       refreshedAt = Value(refreshedAt);
  static Insertable<Category> custom({
    Expression<String>? scope,
    Expression<int>? serverId,
    Expression<int>? parentId,
    Expression<String>? name,
    Expression<String>? slug,
    Expression<String>? imageUrl,
    Expression<int>? rowOrder,
    Expression<String>? type,
    Expression<DateTime>? refreshedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (scope != null) 'scope': scope,
      if (serverId != null) 'server_id': serverId,
      if (parentId != null) 'parent_id': parentId,
      if (name != null) 'name': name,
      if (slug != null) 'slug': slug,
      if (imageUrl != null) 'image_url': imageUrl,
      if (rowOrder != null) 'row_order': rowOrder,
      if (type != null) 'type': type,
      if (refreshedAt != null) 'refreshed_at': refreshedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CategoriesCompanion copyWith({
    Value<String>? scope,
    Value<int>? serverId,
    Value<int?>? parentId,
    Value<String>? name,
    Value<String?>? slug,
    Value<String?>? imageUrl,
    Value<int>? rowOrder,
    Value<String?>? type,
    Value<DateTime>? refreshedAt,
    Value<int>? rowid,
  }) {
    return CategoriesCompanion(
      scope: scope ?? this.scope,
      serverId: serverId ?? this.serverId,
      parentId: parentId ?? this.parentId,
      name: name ?? this.name,
      slug: slug ?? this.slug,
      imageUrl: imageUrl ?? this.imageUrl,
      rowOrder: rowOrder ?? this.rowOrder,
      type: type ?? this.type,
      refreshedAt: refreshedAt ?? this.refreshedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (scope.present) {
      map['scope'] = Variable<String>(scope.value);
    }
    if (serverId.present) {
      map['server_id'] = Variable<int>(serverId.value);
    }
    if (parentId.present) {
      map['parent_id'] = Variable<int>(parentId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (slug.present) {
      map['slug'] = Variable<String>(slug.value);
    }
    if (imageUrl.present) {
      map['image_url'] = Variable<String>(imageUrl.value);
    }
    if (rowOrder.present) {
      map['row_order'] = Variable<int>(rowOrder.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (refreshedAt.present) {
      map['refreshed_at'] = Variable<DateTime>(refreshedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CategoriesCompanion(')
          ..write('scope: $scope, ')
          ..write('serverId: $serverId, ')
          ..write('parentId: $parentId, ')
          ..write('name: $name, ')
          ..write('slug: $slug, ')
          ..write('imageUrl: $imageUrl, ')
          ..write('rowOrder: $rowOrder, ')
          ..write('type: $type, ')
          ..write('refreshedAt: $refreshedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $StoresTable extends Stores with TableInfo<$StoresTable, Store> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StoresTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _scopeMeta = const VerificationMeta('scope');
  @override
  late final GeneratedColumn<String> scope = GeneratedColumn<String>(
    'scope',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _serverIdMeta = const VerificationMeta(
    'serverId',
  );
  @override
  late final GeneratedColumn<int> serverId = GeneratedColumn<int>(
    'server_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _slugMeta = const VerificationMeta('slug');
  @override
  late final GeneratedColumn<String> slug = GeneratedColumn<String>(
    'slug',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _latitudeMeta = const VerificationMeta(
    'latitude',
  );
  @override
  late final GeneratedColumn<double> latitude = GeneratedColumn<double>(
    'latitude',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _longitudeMeta = const VerificationMeta(
    'longitude',
  );
  @override
  late final GeneratedColumn<double> longitude = GeneratedColumn<double>(
    'longitude',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _ratingMeta = const VerificationMeta('rating');
  @override
  late final GeneratedColumn<double> rating = GeneratedColumn<double>(
    'rating',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<int> status = GeneratedColumn<int>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _refreshedAtMeta = const VerificationMeta(
    'refreshedAt',
  );
  @override
  late final GeneratedColumn<DateTime> refreshedAt = GeneratedColumn<DateTime>(
    'refreshed_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastSeenAtMeta = const VerificationMeta(
    'lastSeenAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastSeenAt = GeneratedColumn<DateTime>(
    'last_seen_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    scope,
    serverId,
    slug,
    name,
    latitude,
    longitude,
    rating,
    status,
    payload,
    refreshedAt,
    lastSeenAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'stores';
  @override
  VerificationContext validateIntegrity(
    Insertable<Store> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('scope')) {
      context.handle(
        _scopeMeta,
        scope.isAcceptableOrUnknown(data['scope']!, _scopeMeta),
      );
    } else if (isInserting) {
      context.missing(_scopeMeta);
    }
    if (data.containsKey('server_id')) {
      context.handle(
        _serverIdMeta,
        serverId.isAcceptableOrUnknown(data['server_id']!, _serverIdMeta),
      );
    } else if (isInserting) {
      context.missing(_serverIdMeta);
    }
    if (data.containsKey('slug')) {
      context.handle(
        _slugMeta,
        slug.isAcceptableOrUnknown(data['slug']!, _slugMeta),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('latitude')) {
      context.handle(
        _latitudeMeta,
        latitude.isAcceptableOrUnknown(data['latitude']!, _latitudeMeta),
      );
    }
    if (data.containsKey('longitude')) {
      context.handle(
        _longitudeMeta,
        longitude.isAcceptableOrUnknown(data['longitude']!, _longitudeMeta),
      );
    }
    if (data.containsKey('rating')) {
      context.handle(
        _ratingMeta,
        rating.isAcceptableOrUnknown(data['rating']!, _ratingMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('refreshed_at')) {
      context.handle(
        _refreshedAtMeta,
        refreshedAt.isAcceptableOrUnknown(
          data['refreshed_at']!,
          _refreshedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_refreshedAtMeta);
    }
    if (data.containsKey('last_seen_at')) {
      context.handle(
        _lastSeenAtMeta,
        lastSeenAt.isAcceptableOrUnknown(
          data['last_seen_at']!,
          _lastSeenAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastSeenAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {scope, serverId};
  @override
  Store map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Store(
      scope: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scope'],
      )!,
      serverId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_id'],
      )!,
      slug: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}slug'],
      ),
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      latitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}latitude'],
      ),
      longitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}longitude'],
      ),
      rating: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}rating'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}status'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      refreshedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}refreshed_at'],
      )!,
      lastSeenAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_seen_at'],
      )!,
    );
  }

  @override
  $StoresTable createAlias(String alias) {
    return $StoresTable(attachedDatabase, alias);
  }
}

class Store extends DataClass implements Insertable<Store> {
  final String scope;
  final int serverId;
  final String? slug;
  final String name;
  final double? latitude;
  final double? longitude;
  final double rating;
  final int status;
  final String payload;
  final DateTime refreshedAt;
  final DateTime lastSeenAt;
  const Store({
    required this.scope,
    required this.serverId,
    this.slug,
    required this.name,
    this.latitude,
    this.longitude,
    required this.rating,
    required this.status,
    required this.payload,
    required this.refreshedAt,
    required this.lastSeenAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['scope'] = Variable<String>(scope);
    map['server_id'] = Variable<int>(serverId);
    if (!nullToAbsent || slug != null) {
      map['slug'] = Variable<String>(slug);
    }
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || latitude != null) {
      map['latitude'] = Variable<double>(latitude);
    }
    if (!nullToAbsent || longitude != null) {
      map['longitude'] = Variable<double>(longitude);
    }
    map['rating'] = Variable<double>(rating);
    map['status'] = Variable<int>(status);
    map['payload'] = Variable<String>(payload);
    map['refreshed_at'] = Variable<DateTime>(refreshedAt);
    map['last_seen_at'] = Variable<DateTime>(lastSeenAt);
    return map;
  }

  StoresCompanion toCompanion(bool nullToAbsent) {
    return StoresCompanion(
      scope: Value(scope),
      serverId: Value(serverId),
      slug: slug == null && nullToAbsent ? const Value.absent() : Value(slug),
      name: Value(name),
      latitude: latitude == null && nullToAbsent
          ? const Value.absent()
          : Value(latitude),
      longitude: longitude == null && nullToAbsent
          ? const Value.absent()
          : Value(longitude),
      rating: Value(rating),
      status: Value(status),
      payload: Value(payload),
      refreshedAt: Value(refreshedAt),
      lastSeenAt: Value(lastSeenAt),
    );
  }

  factory Store.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Store(
      scope: serializer.fromJson<String>(json['scope']),
      serverId: serializer.fromJson<int>(json['serverId']),
      slug: serializer.fromJson<String?>(json['slug']),
      name: serializer.fromJson<String>(json['name']),
      latitude: serializer.fromJson<double?>(json['latitude']),
      longitude: serializer.fromJson<double?>(json['longitude']),
      rating: serializer.fromJson<double>(json['rating']),
      status: serializer.fromJson<int>(json['status']),
      payload: serializer.fromJson<String>(json['payload']),
      refreshedAt: serializer.fromJson<DateTime>(json['refreshedAt']),
      lastSeenAt: serializer.fromJson<DateTime>(json['lastSeenAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'scope': serializer.toJson<String>(scope),
      'serverId': serializer.toJson<int>(serverId),
      'slug': serializer.toJson<String?>(slug),
      'name': serializer.toJson<String>(name),
      'latitude': serializer.toJson<double?>(latitude),
      'longitude': serializer.toJson<double?>(longitude),
      'rating': serializer.toJson<double>(rating),
      'status': serializer.toJson<int>(status),
      'payload': serializer.toJson<String>(payload),
      'refreshedAt': serializer.toJson<DateTime>(refreshedAt),
      'lastSeenAt': serializer.toJson<DateTime>(lastSeenAt),
    };
  }

  Store copyWith({
    String? scope,
    int? serverId,
    Value<String?> slug = const Value.absent(),
    String? name,
    Value<double?> latitude = const Value.absent(),
    Value<double?> longitude = const Value.absent(),
    double? rating,
    int? status,
    String? payload,
    DateTime? refreshedAt,
    DateTime? lastSeenAt,
  }) => Store(
    scope: scope ?? this.scope,
    serverId: serverId ?? this.serverId,
    slug: slug.present ? slug.value : this.slug,
    name: name ?? this.name,
    latitude: latitude.present ? latitude.value : this.latitude,
    longitude: longitude.present ? longitude.value : this.longitude,
    rating: rating ?? this.rating,
    status: status ?? this.status,
    payload: payload ?? this.payload,
    refreshedAt: refreshedAt ?? this.refreshedAt,
    lastSeenAt: lastSeenAt ?? this.lastSeenAt,
  );
  Store copyWithCompanion(StoresCompanion data) {
    return Store(
      scope: data.scope.present ? data.scope.value : this.scope,
      serverId: data.serverId.present ? data.serverId.value : this.serverId,
      slug: data.slug.present ? data.slug.value : this.slug,
      name: data.name.present ? data.name.value : this.name,
      latitude: data.latitude.present ? data.latitude.value : this.latitude,
      longitude: data.longitude.present ? data.longitude.value : this.longitude,
      rating: data.rating.present ? data.rating.value : this.rating,
      status: data.status.present ? data.status.value : this.status,
      payload: data.payload.present ? data.payload.value : this.payload,
      refreshedAt: data.refreshedAt.present
          ? data.refreshedAt.value
          : this.refreshedAt,
      lastSeenAt: data.lastSeenAt.present
          ? data.lastSeenAt.value
          : this.lastSeenAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Store(')
          ..write('scope: $scope, ')
          ..write('serverId: $serverId, ')
          ..write('slug: $slug, ')
          ..write('name: $name, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('rating: $rating, ')
          ..write('status: $status, ')
          ..write('payload: $payload, ')
          ..write('refreshedAt: $refreshedAt, ')
          ..write('lastSeenAt: $lastSeenAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    scope,
    serverId,
    slug,
    name,
    latitude,
    longitude,
    rating,
    status,
    payload,
    refreshedAt,
    lastSeenAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Store &&
          other.scope == this.scope &&
          other.serverId == this.serverId &&
          other.slug == this.slug &&
          other.name == this.name &&
          other.latitude == this.latitude &&
          other.longitude == this.longitude &&
          other.rating == this.rating &&
          other.status == this.status &&
          other.payload == this.payload &&
          other.refreshedAt == this.refreshedAt &&
          other.lastSeenAt == this.lastSeenAt);
}

class StoresCompanion extends UpdateCompanion<Store> {
  final Value<String> scope;
  final Value<int> serverId;
  final Value<String?> slug;
  final Value<String> name;
  final Value<double?> latitude;
  final Value<double?> longitude;
  final Value<double> rating;
  final Value<int> status;
  final Value<String> payload;
  final Value<DateTime> refreshedAt;
  final Value<DateTime> lastSeenAt;
  final Value<int> rowid;
  const StoresCompanion({
    this.scope = const Value.absent(),
    this.serverId = const Value.absent(),
    this.slug = const Value.absent(),
    this.name = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.rating = const Value.absent(),
    this.status = const Value.absent(),
    this.payload = const Value.absent(),
    this.refreshedAt = const Value.absent(),
    this.lastSeenAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StoresCompanion.insert({
    required String scope,
    required int serverId,
    this.slug = const Value.absent(),
    required String name,
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.rating = const Value.absent(),
    this.status = const Value.absent(),
    required String payload,
    required DateTime refreshedAt,
    required DateTime lastSeenAt,
    this.rowid = const Value.absent(),
  }) : scope = Value(scope),
       serverId = Value(serverId),
       name = Value(name),
       payload = Value(payload),
       refreshedAt = Value(refreshedAt),
       lastSeenAt = Value(lastSeenAt);
  static Insertable<Store> custom({
    Expression<String>? scope,
    Expression<int>? serverId,
    Expression<String>? slug,
    Expression<String>? name,
    Expression<double>? latitude,
    Expression<double>? longitude,
    Expression<double>? rating,
    Expression<int>? status,
    Expression<String>? payload,
    Expression<DateTime>? refreshedAt,
    Expression<DateTime>? lastSeenAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (scope != null) 'scope': scope,
      if (serverId != null) 'server_id': serverId,
      if (slug != null) 'slug': slug,
      if (name != null) 'name': name,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (rating != null) 'rating': rating,
      if (status != null) 'status': status,
      if (payload != null) 'payload': payload,
      if (refreshedAt != null) 'refreshed_at': refreshedAt,
      if (lastSeenAt != null) 'last_seen_at': lastSeenAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StoresCompanion copyWith({
    Value<String>? scope,
    Value<int>? serverId,
    Value<String?>? slug,
    Value<String>? name,
    Value<double?>? latitude,
    Value<double?>? longitude,
    Value<double>? rating,
    Value<int>? status,
    Value<String>? payload,
    Value<DateTime>? refreshedAt,
    Value<DateTime>? lastSeenAt,
    Value<int>? rowid,
  }) {
    return StoresCompanion(
      scope: scope ?? this.scope,
      serverId: serverId ?? this.serverId,
      slug: slug ?? this.slug,
      name: name ?? this.name,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      rating: rating ?? this.rating,
      status: status ?? this.status,
      payload: payload ?? this.payload,
      refreshedAt: refreshedAt ?? this.refreshedAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (scope.present) {
      map['scope'] = Variable<String>(scope.value);
    }
    if (serverId.present) {
      map['server_id'] = Variable<int>(serverId.value);
    }
    if (slug.present) {
      map['slug'] = Variable<String>(slug.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (latitude.present) {
      map['latitude'] = Variable<double>(latitude.value);
    }
    if (longitude.present) {
      map['longitude'] = Variable<double>(longitude.value);
    }
    if (rating.present) {
      map['rating'] = Variable<double>(rating.value);
    }
    if (status.present) {
      map['status'] = Variable<int>(status.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (refreshedAt.present) {
      map['refreshed_at'] = Variable<DateTime>(refreshedAt.value);
    }
    if (lastSeenAt.present) {
      map['last_seen_at'] = Variable<DateTime>(lastSeenAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StoresCompanion(')
          ..write('scope: $scope, ')
          ..write('serverId: $serverId, ')
          ..write('slug: $slug, ')
          ..write('name: $name, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('rating: $rating, ')
          ..write('status: $status, ')
          ..write('payload: $payload, ')
          ..write('refreshedAt: $refreshedAt, ')
          ..write('lastSeenAt: $lastSeenAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProductsTable extends Products with TableInfo<$ProductsTable, Product> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProductsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _scopeMeta = const VerificationMeta('scope');
  @override
  late final GeneratedColumn<String> scope = GeneratedColumn<String>(
    'scope',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _serverIdMeta = const VerificationMeta(
    'serverId',
  );
  @override
  late final GeneratedColumn<int> serverId = GeneratedColumn<int>(
    'server_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _slugMeta = const VerificationMeta('slug');
  @override
  late final GeneratedColumn<String> slug = GeneratedColumn<String>(
    'slug',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _storeIdMeta = const VerificationMeta(
    'storeId',
  );
  @override
  late final GeneratedColumn<int> storeId = GeneratedColumn<int>(
    'store_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryIdMeta = const VerificationMeta(
    'categoryId',
  );
  @override
  late final GeneratedColumn<int> categoryId = GeneratedColumn<int>(
    'category_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _searchBlobMeta = const VerificationMeta(
    'searchBlob',
  );
  @override
  late final GeneratedColumn<String> searchBlob = GeneratedColumn<String>(
    'search_blob',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _priceSnapshotMeta = const VerificationMeta(
    'priceSnapshot',
  );
  @override
  late final GeneratedColumn<String> priceSnapshot = GeneratedColumn<String>(
    'price_snapshot',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _thumbnailUrlMeta = const VerificationMeta(
    'thumbnailUrl',
  );
  @override
  late final GeneratedColumn<String> thumbnailUrl = GeneratedColumn<String>(
    'thumbnail_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _localImagePathMeta = const VerificationMeta(
    'localImagePath',
  );
  @override
  late final GeneratedColumn<String> localImagePath = GeneratedColumn<String>(
    'local_image_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _ratingMeta = const VerificationMeta('rating');
  @override
  late final GeneratedColumn<double> rating = GeneratedColumn<double>(
    'rating',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<int> status = GeneratedColumn<int>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _isListedMeta = const VerificationMeta(
    'isListed',
  );
  @override
  late final GeneratedColumn<bool> isListed = GeneratedColumn<bool>(
    'is_listed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_listed" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _minPriceMeta = const VerificationMeta(
    'minPrice',
  );
  @override
  late final GeneratedColumn<double> minPrice = GeneratedColumn<double>(
    'min_price',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _inStockMeta = const VerificationMeta(
    'inStock',
  );
  @override
  late final GeneratedColumn<bool> inStock = GeneratedColumn<bool>(
    'in_stock',
    aliasedName,
    true,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("in_stock" IN (0, 1))',
    ),
  );
  static const VerificationMeta _hasOfferMeta = const VerificationMeta(
    'hasOffer',
  );
  @override
  late final GeneratedColumn<bool> hasOffer = GeneratedColumn<bool>(
    'has_offer',
    aliasedName,
    true,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("has_offer" IN (0, 1))',
    ),
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _refreshedAtMeta = const VerificationMeta(
    'refreshedAt',
  );
  @override
  late final GeneratedColumn<DateTime> refreshedAt = GeneratedColumn<DateTime>(
    'refreshed_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastSeenAtMeta = const VerificationMeta(
    'lastSeenAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastSeenAt = GeneratedColumn<DateTime>(
    'last_seen_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    scope,
    serverId,
    slug,
    name,
    storeId,
    categoryId,
    searchBlob,
    priceSnapshot,
    thumbnailUrl,
    localImagePath,
    rating,
    status,
    isListed,
    minPrice,
    inStock,
    hasOffer,
    payload,
    refreshedAt,
    lastSeenAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'products';
  @override
  VerificationContext validateIntegrity(
    Insertable<Product> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('scope')) {
      context.handle(
        _scopeMeta,
        scope.isAcceptableOrUnknown(data['scope']!, _scopeMeta),
      );
    } else if (isInserting) {
      context.missing(_scopeMeta);
    }
    if (data.containsKey('server_id')) {
      context.handle(
        _serverIdMeta,
        serverId.isAcceptableOrUnknown(data['server_id']!, _serverIdMeta),
      );
    } else if (isInserting) {
      context.missing(_serverIdMeta);
    }
    if (data.containsKey('slug')) {
      context.handle(
        _slugMeta,
        slug.isAcceptableOrUnknown(data['slug']!, _slugMeta),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('store_id')) {
      context.handle(
        _storeIdMeta,
        storeId.isAcceptableOrUnknown(data['store_id']!, _storeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_storeIdMeta);
    }
    if (data.containsKey('category_id')) {
      context.handle(
        _categoryIdMeta,
        categoryId.isAcceptableOrUnknown(data['category_id']!, _categoryIdMeta),
      );
    }
    if (data.containsKey('search_blob')) {
      context.handle(
        _searchBlobMeta,
        searchBlob.isAcceptableOrUnknown(data['search_blob']!, _searchBlobMeta),
      );
    } else if (isInserting) {
      context.missing(_searchBlobMeta);
    }
    if (data.containsKey('price_snapshot')) {
      context.handle(
        _priceSnapshotMeta,
        priceSnapshot.isAcceptableOrUnknown(
          data['price_snapshot']!,
          _priceSnapshotMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_priceSnapshotMeta);
    }
    if (data.containsKey('thumbnail_url')) {
      context.handle(
        _thumbnailUrlMeta,
        thumbnailUrl.isAcceptableOrUnknown(
          data['thumbnail_url']!,
          _thumbnailUrlMeta,
        ),
      );
    }
    if (data.containsKey('local_image_path')) {
      context.handle(
        _localImagePathMeta,
        localImagePath.isAcceptableOrUnknown(
          data['local_image_path']!,
          _localImagePathMeta,
        ),
      );
    }
    if (data.containsKey('rating')) {
      context.handle(
        _ratingMeta,
        rating.isAcceptableOrUnknown(data['rating']!, _ratingMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('is_listed')) {
      context.handle(
        _isListedMeta,
        isListed.isAcceptableOrUnknown(data['is_listed']!, _isListedMeta),
      );
    }
    if (data.containsKey('min_price')) {
      context.handle(
        _minPriceMeta,
        minPrice.isAcceptableOrUnknown(data['min_price']!, _minPriceMeta),
      );
    }
    if (data.containsKey('in_stock')) {
      context.handle(
        _inStockMeta,
        inStock.isAcceptableOrUnknown(data['in_stock']!, _inStockMeta),
      );
    }
    if (data.containsKey('has_offer')) {
      context.handle(
        _hasOfferMeta,
        hasOffer.isAcceptableOrUnknown(data['has_offer']!, _hasOfferMeta),
      );
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('refreshed_at')) {
      context.handle(
        _refreshedAtMeta,
        refreshedAt.isAcceptableOrUnknown(
          data['refreshed_at']!,
          _refreshedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_refreshedAtMeta);
    }
    if (data.containsKey('last_seen_at')) {
      context.handle(
        _lastSeenAtMeta,
        lastSeenAt.isAcceptableOrUnknown(
          data['last_seen_at']!,
          _lastSeenAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastSeenAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {scope, serverId};
  @override
  Product map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Product(
      scope: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scope'],
      )!,
      serverId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_id'],
      )!,
      slug: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}slug'],
      ),
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      storeId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}store_id'],
      )!,
      categoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}category_id'],
      ),
      searchBlob: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}search_blob'],
      )!,
      priceSnapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}price_snapshot'],
      )!,
      thumbnailUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}thumbnail_url'],
      ),
      localImagePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_image_path'],
      ),
      rating: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}rating'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}status'],
      )!,
      isListed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_listed'],
      )!,
      minPrice: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}min_price'],
      ),
      inStock: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}in_stock'],
      ),
      hasOffer: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}has_offer'],
      ),
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      refreshedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}refreshed_at'],
      )!,
      lastSeenAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_seen_at'],
      )!,
    );
  }

  @override
  $ProductsTable createAlias(String alias) {
    return $ProductsTable(attachedDatabase, alias);
  }
}

class Product extends DataClass implements Insertable<Product> {
  final String scope;
  final int serverId;
  final String? slug;
  final String name;
  final int storeId;
  final int? categoryId;
  final String searchBlob;
  final String priceSnapshot;
  final String? thumbnailUrl;

  /// Local image file path. NULL means "not available offline" — callers
  /// must show a placeholder and never claim offline availability otherwise.
  final String? localImagePath;
  final double rating;
  final int status;

  /// False only after a clean full-walk reconciliation proves the row is
  /// absent from the server listing (deleted, unapproved, disabled, or
  /// out of stock — the listing hard-filters all of these).
  final bool isListed;

  /// Minimum effective variant price (discounted when present), NULL when the
  /// payload carries no usable price. NULL sorts last and never filters out.
  final double? minPrice;

  /// Any variant in stock (or product-level unlimited flag), NULL = unknown.
  /// Unknown rows are never hidden by stock filters.
  final bool? inStock;

  /// Any variant-level or row-level offer signal, NULL = unknown.
  final bool? hasOffer;
  final String payload;
  final DateTime refreshedAt;
  final DateTime lastSeenAt;
  const Product({
    required this.scope,
    required this.serverId,
    this.slug,
    required this.name,
    required this.storeId,
    this.categoryId,
    required this.searchBlob,
    required this.priceSnapshot,
    this.thumbnailUrl,
    this.localImagePath,
    required this.rating,
    required this.status,
    required this.isListed,
    this.minPrice,
    this.inStock,
    this.hasOffer,
    required this.payload,
    required this.refreshedAt,
    required this.lastSeenAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['scope'] = Variable<String>(scope);
    map['server_id'] = Variable<int>(serverId);
    if (!nullToAbsent || slug != null) {
      map['slug'] = Variable<String>(slug);
    }
    map['name'] = Variable<String>(name);
    map['store_id'] = Variable<int>(storeId);
    if (!nullToAbsent || categoryId != null) {
      map['category_id'] = Variable<int>(categoryId);
    }
    map['search_blob'] = Variable<String>(searchBlob);
    map['price_snapshot'] = Variable<String>(priceSnapshot);
    if (!nullToAbsent || thumbnailUrl != null) {
      map['thumbnail_url'] = Variable<String>(thumbnailUrl);
    }
    if (!nullToAbsent || localImagePath != null) {
      map['local_image_path'] = Variable<String>(localImagePath);
    }
    map['rating'] = Variable<double>(rating);
    map['status'] = Variable<int>(status);
    map['is_listed'] = Variable<bool>(isListed);
    if (!nullToAbsent || minPrice != null) {
      map['min_price'] = Variable<double>(minPrice);
    }
    if (!nullToAbsent || inStock != null) {
      map['in_stock'] = Variable<bool>(inStock);
    }
    if (!nullToAbsent || hasOffer != null) {
      map['has_offer'] = Variable<bool>(hasOffer);
    }
    map['payload'] = Variable<String>(payload);
    map['refreshed_at'] = Variable<DateTime>(refreshedAt);
    map['last_seen_at'] = Variable<DateTime>(lastSeenAt);
    return map;
  }

  ProductsCompanion toCompanion(bool nullToAbsent) {
    return ProductsCompanion(
      scope: Value(scope),
      serverId: Value(serverId),
      slug: slug == null && nullToAbsent ? const Value.absent() : Value(slug),
      name: Value(name),
      storeId: Value(storeId),
      categoryId: categoryId == null && nullToAbsent
          ? const Value.absent()
          : Value(categoryId),
      searchBlob: Value(searchBlob),
      priceSnapshot: Value(priceSnapshot),
      thumbnailUrl: thumbnailUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(thumbnailUrl),
      localImagePath: localImagePath == null && nullToAbsent
          ? const Value.absent()
          : Value(localImagePath),
      rating: Value(rating),
      status: Value(status),
      isListed: Value(isListed),
      minPrice: minPrice == null && nullToAbsent
          ? const Value.absent()
          : Value(minPrice),
      inStock: inStock == null && nullToAbsent
          ? const Value.absent()
          : Value(inStock),
      hasOffer: hasOffer == null && nullToAbsent
          ? const Value.absent()
          : Value(hasOffer),
      payload: Value(payload),
      refreshedAt: Value(refreshedAt),
      lastSeenAt: Value(lastSeenAt),
    );
  }

  factory Product.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Product(
      scope: serializer.fromJson<String>(json['scope']),
      serverId: serializer.fromJson<int>(json['serverId']),
      slug: serializer.fromJson<String?>(json['slug']),
      name: serializer.fromJson<String>(json['name']),
      storeId: serializer.fromJson<int>(json['storeId']),
      categoryId: serializer.fromJson<int?>(json['categoryId']),
      searchBlob: serializer.fromJson<String>(json['searchBlob']),
      priceSnapshot: serializer.fromJson<String>(json['priceSnapshot']),
      thumbnailUrl: serializer.fromJson<String?>(json['thumbnailUrl']),
      localImagePath: serializer.fromJson<String?>(json['localImagePath']),
      rating: serializer.fromJson<double>(json['rating']),
      status: serializer.fromJson<int>(json['status']),
      isListed: serializer.fromJson<bool>(json['isListed']),
      minPrice: serializer.fromJson<double?>(json['minPrice']),
      inStock: serializer.fromJson<bool?>(json['inStock']),
      hasOffer: serializer.fromJson<bool?>(json['hasOffer']),
      payload: serializer.fromJson<String>(json['payload']),
      refreshedAt: serializer.fromJson<DateTime>(json['refreshedAt']),
      lastSeenAt: serializer.fromJson<DateTime>(json['lastSeenAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'scope': serializer.toJson<String>(scope),
      'serverId': serializer.toJson<int>(serverId),
      'slug': serializer.toJson<String?>(slug),
      'name': serializer.toJson<String>(name),
      'storeId': serializer.toJson<int>(storeId),
      'categoryId': serializer.toJson<int?>(categoryId),
      'searchBlob': serializer.toJson<String>(searchBlob),
      'priceSnapshot': serializer.toJson<String>(priceSnapshot),
      'thumbnailUrl': serializer.toJson<String?>(thumbnailUrl),
      'localImagePath': serializer.toJson<String?>(localImagePath),
      'rating': serializer.toJson<double>(rating),
      'status': serializer.toJson<int>(status),
      'isListed': serializer.toJson<bool>(isListed),
      'minPrice': serializer.toJson<double?>(minPrice),
      'inStock': serializer.toJson<bool?>(inStock),
      'hasOffer': serializer.toJson<bool?>(hasOffer),
      'payload': serializer.toJson<String>(payload),
      'refreshedAt': serializer.toJson<DateTime>(refreshedAt),
      'lastSeenAt': serializer.toJson<DateTime>(lastSeenAt),
    };
  }

  Product copyWith({
    String? scope,
    int? serverId,
    Value<String?> slug = const Value.absent(),
    String? name,
    int? storeId,
    Value<int?> categoryId = const Value.absent(),
    String? searchBlob,
    String? priceSnapshot,
    Value<String?> thumbnailUrl = const Value.absent(),
    Value<String?> localImagePath = const Value.absent(),
    double? rating,
    int? status,
    bool? isListed,
    Value<double?> minPrice = const Value.absent(),
    Value<bool?> inStock = const Value.absent(),
    Value<bool?> hasOffer = const Value.absent(),
    String? payload,
    DateTime? refreshedAt,
    DateTime? lastSeenAt,
  }) => Product(
    scope: scope ?? this.scope,
    serverId: serverId ?? this.serverId,
    slug: slug.present ? slug.value : this.slug,
    name: name ?? this.name,
    storeId: storeId ?? this.storeId,
    categoryId: categoryId.present ? categoryId.value : this.categoryId,
    searchBlob: searchBlob ?? this.searchBlob,
    priceSnapshot: priceSnapshot ?? this.priceSnapshot,
    thumbnailUrl: thumbnailUrl.present ? thumbnailUrl.value : this.thumbnailUrl,
    localImagePath: localImagePath.present
        ? localImagePath.value
        : this.localImagePath,
    rating: rating ?? this.rating,
    status: status ?? this.status,
    isListed: isListed ?? this.isListed,
    minPrice: minPrice.present ? minPrice.value : this.minPrice,
    inStock: inStock.present ? inStock.value : this.inStock,
    hasOffer: hasOffer.present ? hasOffer.value : this.hasOffer,
    payload: payload ?? this.payload,
    refreshedAt: refreshedAt ?? this.refreshedAt,
    lastSeenAt: lastSeenAt ?? this.lastSeenAt,
  );
  Product copyWithCompanion(ProductsCompanion data) {
    return Product(
      scope: data.scope.present ? data.scope.value : this.scope,
      serverId: data.serverId.present ? data.serverId.value : this.serverId,
      slug: data.slug.present ? data.slug.value : this.slug,
      name: data.name.present ? data.name.value : this.name,
      storeId: data.storeId.present ? data.storeId.value : this.storeId,
      categoryId: data.categoryId.present
          ? data.categoryId.value
          : this.categoryId,
      searchBlob: data.searchBlob.present
          ? data.searchBlob.value
          : this.searchBlob,
      priceSnapshot: data.priceSnapshot.present
          ? data.priceSnapshot.value
          : this.priceSnapshot,
      thumbnailUrl: data.thumbnailUrl.present
          ? data.thumbnailUrl.value
          : this.thumbnailUrl,
      localImagePath: data.localImagePath.present
          ? data.localImagePath.value
          : this.localImagePath,
      rating: data.rating.present ? data.rating.value : this.rating,
      status: data.status.present ? data.status.value : this.status,
      isListed: data.isListed.present ? data.isListed.value : this.isListed,
      minPrice: data.minPrice.present ? data.minPrice.value : this.minPrice,
      inStock: data.inStock.present ? data.inStock.value : this.inStock,
      hasOffer: data.hasOffer.present ? data.hasOffer.value : this.hasOffer,
      payload: data.payload.present ? data.payload.value : this.payload,
      refreshedAt: data.refreshedAt.present
          ? data.refreshedAt.value
          : this.refreshedAt,
      lastSeenAt: data.lastSeenAt.present
          ? data.lastSeenAt.value
          : this.lastSeenAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Product(')
          ..write('scope: $scope, ')
          ..write('serverId: $serverId, ')
          ..write('slug: $slug, ')
          ..write('name: $name, ')
          ..write('storeId: $storeId, ')
          ..write('categoryId: $categoryId, ')
          ..write('searchBlob: $searchBlob, ')
          ..write('priceSnapshot: $priceSnapshot, ')
          ..write('thumbnailUrl: $thumbnailUrl, ')
          ..write('localImagePath: $localImagePath, ')
          ..write('rating: $rating, ')
          ..write('status: $status, ')
          ..write('isListed: $isListed, ')
          ..write('minPrice: $minPrice, ')
          ..write('inStock: $inStock, ')
          ..write('hasOffer: $hasOffer, ')
          ..write('payload: $payload, ')
          ..write('refreshedAt: $refreshedAt, ')
          ..write('lastSeenAt: $lastSeenAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    scope,
    serverId,
    slug,
    name,
    storeId,
    categoryId,
    searchBlob,
    priceSnapshot,
    thumbnailUrl,
    localImagePath,
    rating,
    status,
    isListed,
    minPrice,
    inStock,
    hasOffer,
    payload,
    refreshedAt,
    lastSeenAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Product &&
          other.scope == this.scope &&
          other.serverId == this.serverId &&
          other.slug == this.slug &&
          other.name == this.name &&
          other.storeId == this.storeId &&
          other.categoryId == this.categoryId &&
          other.searchBlob == this.searchBlob &&
          other.priceSnapshot == this.priceSnapshot &&
          other.thumbnailUrl == this.thumbnailUrl &&
          other.localImagePath == this.localImagePath &&
          other.rating == this.rating &&
          other.status == this.status &&
          other.isListed == this.isListed &&
          other.minPrice == this.minPrice &&
          other.inStock == this.inStock &&
          other.hasOffer == this.hasOffer &&
          other.payload == this.payload &&
          other.refreshedAt == this.refreshedAt &&
          other.lastSeenAt == this.lastSeenAt);
}

class ProductsCompanion extends UpdateCompanion<Product> {
  final Value<String> scope;
  final Value<int> serverId;
  final Value<String?> slug;
  final Value<String> name;
  final Value<int> storeId;
  final Value<int?> categoryId;
  final Value<String> searchBlob;
  final Value<String> priceSnapshot;
  final Value<String?> thumbnailUrl;
  final Value<String?> localImagePath;
  final Value<double> rating;
  final Value<int> status;
  final Value<bool> isListed;
  final Value<double?> minPrice;
  final Value<bool?> inStock;
  final Value<bool?> hasOffer;
  final Value<String> payload;
  final Value<DateTime> refreshedAt;
  final Value<DateTime> lastSeenAt;
  final Value<int> rowid;
  const ProductsCompanion({
    this.scope = const Value.absent(),
    this.serverId = const Value.absent(),
    this.slug = const Value.absent(),
    this.name = const Value.absent(),
    this.storeId = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.searchBlob = const Value.absent(),
    this.priceSnapshot = const Value.absent(),
    this.thumbnailUrl = const Value.absent(),
    this.localImagePath = const Value.absent(),
    this.rating = const Value.absent(),
    this.status = const Value.absent(),
    this.isListed = const Value.absent(),
    this.minPrice = const Value.absent(),
    this.inStock = const Value.absent(),
    this.hasOffer = const Value.absent(),
    this.payload = const Value.absent(),
    this.refreshedAt = const Value.absent(),
    this.lastSeenAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProductsCompanion.insert({
    required String scope,
    required int serverId,
    this.slug = const Value.absent(),
    required String name,
    required int storeId,
    this.categoryId = const Value.absent(),
    required String searchBlob,
    required String priceSnapshot,
    this.thumbnailUrl = const Value.absent(),
    this.localImagePath = const Value.absent(),
    this.rating = const Value.absent(),
    this.status = const Value.absent(),
    this.isListed = const Value.absent(),
    this.minPrice = const Value.absent(),
    this.inStock = const Value.absent(),
    this.hasOffer = const Value.absent(),
    required String payload,
    required DateTime refreshedAt,
    required DateTime lastSeenAt,
    this.rowid = const Value.absent(),
  }) : scope = Value(scope),
       serverId = Value(serverId),
       name = Value(name),
       storeId = Value(storeId),
       searchBlob = Value(searchBlob),
       priceSnapshot = Value(priceSnapshot),
       payload = Value(payload),
       refreshedAt = Value(refreshedAt),
       lastSeenAt = Value(lastSeenAt);
  static Insertable<Product> custom({
    Expression<String>? scope,
    Expression<int>? serverId,
    Expression<String>? slug,
    Expression<String>? name,
    Expression<int>? storeId,
    Expression<int>? categoryId,
    Expression<String>? searchBlob,
    Expression<String>? priceSnapshot,
    Expression<String>? thumbnailUrl,
    Expression<String>? localImagePath,
    Expression<double>? rating,
    Expression<int>? status,
    Expression<bool>? isListed,
    Expression<double>? minPrice,
    Expression<bool>? inStock,
    Expression<bool>? hasOffer,
    Expression<String>? payload,
    Expression<DateTime>? refreshedAt,
    Expression<DateTime>? lastSeenAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (scope != null) 'scope': scope,
      if (serverId != null) 'server_id': serverId,
      if (slug != null) 'slug': slug,
      if (name != null) 'name': name,
      if (storeId != null) 'store_id': storeId,
      if (categoryId != null) 'category_id': categoryId,
      if (searchBlob != null) 'search_blob': searchBlob,
      if (priceSnapshot != null) 'price_snapshot': priceSnapshot,
      if (thumbnailUrl != null) 'thumbnail_url': thumbnailUrl,
      if (localImagePath != null) 'local_image_path': localImagePath,
      if (rating != null) 'rating': rating,
      if (status != null) 'status': status,
      if (isListed != null) 'is_listed': isListed,
      if (minPrice != null) 'min_price': minPrice,
      if (inStock != null) 'in_stock': inStock,
      if (hasOffer != null) 'has_offer': hasOffer,
      if (payload != null) 'payload': payload,
      if (refreshedAt != null) 'refreshed_at': refreshedAt,
      if (lastSeenAt != null) 'last_seen_at': lastSeenAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProductsCompanion copyWith({
    Value<String>? scope,
    Value<int>? serverId,
    Value<String?>? slug,
    Value<String>? name,
    Value<int>? storeId,
    Value<int?>? categoryId,
    Value<String>? searchBlob,
    Value<String>? priceSnapshot,
    Value<String?>? thumbnailUrl,
    Value<String?>? localImagePath,
    Value<double>? rating,
    Value<int>? status,
    Value<bool>? isListed,
    Value<double?>? minPrice,
    Value<bool?>? inStock,
    Value<bool?>? hasOffer,
    Value<String>? payload,
    Value<DateTime>? refreshedAt,
    Value<DateTime>? lastSeenAt,
    Value<int>? rowid,
  }) {
    return ProductsCompanion(
      scope: scope ?? this.scope,
      serverId: serverId ?? this.serverId,
      slug: slug ?? this.slug,
      name: name ?? this.name,
      storeId: storeId ?? this.storeId,
      categoryId: categoryId ?? this.categoryId,
      searchBlob: searchBlob ?? this.searchBlob,
      priceSnapshot: priceSnapshot ?? this.priceSnapshot,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      localImagePath: localImagePath ?? this.localImagePath,
      rating: rating ?? this.rating,
      status: status ?? this.status,
      isListed: isListed ?? this.isListed,
      minPrice: minPrice ?? this.minPrice,
      inStock: inStock ?? this.inStock,
      hasOffer: hasOffer ?? this.hasOffer,
      payload: payload ?? this.payload,
      refreshedAt: refreshedAt ?? this.refreshedAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (scope.present) {
      map['scope'] = Variable<String>(scope.value);
    }
    if (serverId.present) {
      map['server_id'] = Variable<int>(serverId.value);
    }
    if (slug.present) {
      map['slug'] = Variable<String>(slug.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (storeId.present) {
      map['store_id'] = Variable<int>(storeId.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<int>(categoryId.value);
    }
    if (searchBlob.present) {
      map['search_blob'] = Variable<String>(searchBlob.value);
    }
    if (priceSnapshot.present) {
      map['price_snapshot'] = Variable<String>(priceSnapshot.value);
    }
    if (thumbnailUrl.present) {
      map['thumbnail_url'] = Variable<String>(thumbnailUrl.value);
    }
    if (localImagePath.present) {
      map['local_image_path'] = Variable<String>(localImagePath.value);
    }
    if (rating.present) {
      map['rating'] = Variable<double>(rating.value);
    }
    if (status.present) {
      map['status'] = Variable<int>(status.value);
    }
    if (isListed.present) {
      map['is_listed'] = Variable<bool>(isListed.value);
    }
    if (minPrice.present) {
      map['min_price'] = Variable<double>(minPrice.value);
    }
    if (inStock.present) {
      map['in_stock'] = Variable<bool>(inStock.value);
    }
    if (hasOffer.present) {
      map['has_offer'] = Variable<bool>(hasOffer.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (refreshedAt.present) {
      map['refreshed_at'] = Variable<DateTime>(refreshedAt.value);
    }
    if (lastSeenAt.present) {
      map['last_seen_at'] = Variable<DateTime>(lastSeenAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProductsCompanion(')
          ..write('scope: $scope, ')
          ..write('serverId: $serverId, ')
          ..write('slug: $slug, ')
          ..write('name: $name, ')
          ..write('storeId: $storeId, ')
          ..write('categoryId: $categoryId, ')
          ..write('searchBlob: $searchBlob, ')
          ..write('priceSnapshot: $priceSnapshot, ')
          ..write('thumbnailUrl: $thumbnailUrl, ')
          ..write('localImagePath: $localImagePath, ')
          ..write('rating: $rating, ')
          ..write('status: $status, ')
          ..write('isListed: $isListed, ')
          ..write('minPrice: $minPrice, ')
          ..write('inStock: $inStock, ')
          ..write('hasOffer: $hasOffer, ')
          ..write('payload: $payload, ')
          ..write('refreshedAt: $refreshedAt, ')
          ..write('lastSeenAt: $lastSeenAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProductVariantsTable extends ProductVariants
    with TableInfo<$ProductVariantsTable, ProductVariant> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProductVariantsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _scopeMeta = const VerificationMeta('scope');
  @override
  late final GeneratedColumn<String> scope = GeneratedColumn<String>(
    'scope',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _serverIdMeta = const VerificationMeta(
    'serverId',
  );
  @override
  late final GeneratedColumn<int> serverId = GeneratedColumn<int>(
    'server_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _productIdMeta = const VerificationMeta(
    'productId',
  );
  @override
  late final GeneratedColumn<int> productId = GeneratedColumn<int>(
    'product_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _refreshedAtMeta = const VerificationMeta(
    'refreshedAt',
  );
  @override
  late final GeneratedColumn<DateTime> refreshedAt = GeneratedColumn<DateTime>(
    'refreshed_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    scope,
    serverId,
    productId,
    payload,
    refreshedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'product_variants';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProductVariant> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('scope')) {
      context.handle(
        _scopeMeta,
        scope.isAcceptableOrUnknown(data['scope']!, _scopeMeta),
      );
    } else if (isInserting) {
      context.missing(_scopeMeta);
    }
    if (data.containsKey('server_id')) {
      context.handle(
        _serverIdMeta,
        serverId.isAcceptableOrUnknown(data['server_id']!, _serverIdMeta),
      );
    } else if (isInserting) {
      context.missing(_serverIdMeta);
    }
    if (data.containsKey('product_id')) {
      context.handle(
        _productIdMeta,
        productId.isAcceptableOrUnknown(data['product_id']!, _productIdMeta),
      );
    } else if (isInserting) {
      context.missing(_productIdMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('refreshed_at')) {
      context.handle(
        _refreshedAtMeta,
        refreshedAt.isAcceptableOrUnknown(
          data['refreshed_at']!,
          _refreshedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_refreshedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {scope, serverId};
  @override
  ProductVariant map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProductVariant(
      scope: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scope'],
      )!,
      serverId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_id'],
      )!,
      productId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}product_id'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      refreshedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}refreshed_at'],
      )!,
    );
  }

  @override
  $ProductVariantsTable createAlias(String alias) {
    return $ProductVariantsTable(attachedDatabase, alias);
  }
}

class ProductVariant extends DataClass implements Insertable<ProductVariant> {
  final String scope;
  final int serverId;
  final int productId;
  final String payload;
  final DateTime refreshedAt;
  const ProductVariant({
    required this.scope,
    required this.serverId,
    required this.productId,
    required this.payload,
    required this.refreshedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['scope'] = Variable<String>(scope);
    map['server_id'] = Variable<int>(serverId);
    map['product_id'] = Variable<int>(productId);
    map['payload'] = Variable<String>(payload);
    map['refreshed_at'] = Variable<DateTime>(refreshedAt);
    return map;
  }

  ProductVariantsCompanion toCompanion(bool nullToAbsent) {
    return ProductVariantsCompanion(
      scope: Value(scope),
      serverId: Value(serverId),
      productId: Value(productId),
      payload: Value(payload),
      refreshedAt: Value(refreshedAt),
    );
  }

  factory ProductVariant.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProductVariant(
      scope: serializer.fromJson<String>(json['scope']),
      serverId: serializer.fromJson<int>(json['serverId']),
      productId: serializer.fromJson<int>(json['productId']),
      payload: serializer.fromJson<String>(json['payload']),
      refreshedAt: serializer.fromJson<DateTime>(json['refreshedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'scope': serializer.toJson<String>(scope),
      'serverId': serializer.toJson<int>(serverId),
      'productId': serializer.toJson<int>(productId),
      'payload': serializer.toJson<String>(payload),
      'refreshedAt': serializer.toJson<DateTime>(refreshedAt),
    };
  }

  ProductVariant copyWith({
    String? scope,
    int? serverId,
    int? productId,
    String? payload,
    DateTime? refreshedAt,
  }) => ProductVariant(
    scope: scope ?? this.scope,
    serverId: serverId ?? this.serverId,
    productId: productId ?? this.productId,
    payload: payload ?? this.payload,
    refreshedAt: refreshedAt ?? this.refreshedAt,
  );
  ProductVariant copyWithCompanion(ProductVariantsCompanion data) {
    return ProductVariant(
      scope: data.scope.present ? data.scope.value : this.scope,
      serverId: data.serverId.present ? data.serverId.value : this.serverId,
      productId: data.productId.present ? data.productId.value : this.productId,
      payload: data.payload.present ? data.payload.value : this.payload,
      refreshedAt: data.refreshedAt.present
          ? data.refreshedAt.value
          : this.refreshedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProductVariant(')
          ..write('scope: $scope, ')
          ..write('serverId: $serverId, ')
          ..write('productId: $productId, ')
          ..write('payload: $payload, ')
          ..write('refreshedAt: $refreshedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(scope, serverId, productId, payload, refreshedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProductVariant &&
          other.scope == this.scope &&
          other.serverId == this.serverId &&
          other.productId == this.productId &&
          other.payload == this.payload &&
          other.refreshedAt == this.refreshedAt);
}

class ProductVariantsCompanion extends UpdateCompanion<ProductVariant> {
  final Value<String> scope;
  final Value<int> serverId;
  final Value<int> productId;
  final Value<String> payload;
  final Value<DateTime> refreshedAt;
  final Value<int> rowid;
  const ProductVariantsCompanion({
    this.scope = const Value.absent(),
    this.serverId = const Value.absent(),
    this.productId = const Value.absent(),
    this.payload = const Value.absent(),
    this.refreshedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProductVariantsCompanion.insert({
    required String scope,
    required int serverId,
    required int productId,
    required String payload,
    required DateTime refreshedAt,
    this.rowid = const Value.absent(),
  }) : scope = Value(scope),
       serverId = Value(serverId),
       productId = Value(productId),
       payload = Value(payload),
       refreshedAt = Value(refreshedAt);
  static Insertable<ProductVariant> custom({
    Expression<String>? scope,
    Expression<int>? serverId,
    Expression<int>? productId,
    Expression<String>? payload,
    Expression<DateTime>? refreshedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (scope != null) 'scope': scope,
      if (serverId != null) 'server_id': serverId,
      if (productId != null) 'product_id': productId,
      if (payload != null) 'payload': payload,
      if (refreshedAt != null) 'refreshed_at': refreshedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProductVariantsCompanion copyWith({
    Value<String>? scope,
    Value<int>? serverId,
    Value<int>? productId,
    Value<String>? payload,
    Value<DateTime>? refreshedAt,
    Value<int>? rowid,
  }) {
    return ProductVariantsCompanion(
      scope: scope ?? this.scope,
      serverId: serverId ?? this.serverId,
      productId: productId ?? this.productId,
      payload: payload ?? this.payload,
      refreshedAt: refreshedAt ?? this.refreshedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (scope.present) {
      map['scope'] = Variable<String>(scope.value);
    }
    if (serverId.present) {
      map['server_id'] = Variable<int>(serverId.value);
    }
    if (productId.present) {
      map['product_id'] = Variable<int>(productId.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (refreshedAt.present) {
      map['refreshed_at'] = Variable<DateTime>(refreshedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProductVariantsCompanion(')
          ..write('scope: $scope, ')
          ..write('serverId: $serverId, ')
          ..write('productId: $productId, ')
          ..write('payload: $payload, ')
          ..write('refreshedAt: $refreshedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedImagesTable extends CachedImages
    with TableInfo<$CachedImagesTable, CachedImage> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedImagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _urlMeta = const VerificationMeta('url');
  @override
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
    'url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localPathMeta = const VerificationMeta(
    'localPath',
  );
  @override
  late final GeneratedColumn<String> localPath = GeneratedColumn<String>(
    'local_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bytesMeta = const VerificationMeta('bytes');
  @override
  late final GeneratedColumn<int> bytes = GeneratedColumn<int>(
    'bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastUsedAtMeta = const VerificationMeta(
    'lastUsedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastUsedAt = GeneratedColumn<DateTime>(
    'last_used_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [url, localPath, bytes, lastUsedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_images';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedImage> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('url')) {
      context.handle(
        _urlMeta,
        url.isAcceptableOrUnknown(data['url']!, _urlMeta),
      );
    } else if (isInserting) {
      context.missing(_urlMeta);
    }
    if (data.containsKey('local_path')) {
      context.handle(
        _localPathMeta,
        localPath.isAcceptableOrUnknown(data['local_path']!, _localPathMeta),
      );
    } else if (isInserting) {
      context.missing(_localPathMeta);
    }
    if (data.containsKey('bytes')) {
      context.handle(
        _bytesMeta,
        bytes.isAcceptableOrUnknown(data['bytes']!, _bytesMeta),
      );
    } else if (isInserting) {
      context.missing(_bytesMeta);
    }
    if (data.containsKey('last_used_at')) {
      context.handle(
        _lastUsedAtMeta,
        lastUsedAt.isAcceptableOrUnknown(
          data['last_used_at']!,
          _lastUsedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastUsedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {url};
  @override
  CachedImage map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedImage(
      url: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}url'],
      )!,
      localPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_path'],
      )!,
      bytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}bytes'],
      )!,
      lastUsedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_used_at'],
      )!,
    );
  }

  @override
  $CachedImagesTable createAlias(String alias) {
    return $CachedImagesTable(attachedDatabase, alias);
  }
}

class CachedImage extends DataClass implements Insertable<CachedImage> {
  final String url;
  final String localPath;
  final int bytes;
  final DateTime lastUsedAt;
  const CachedImage({
    required this.url,
    required this.localPath,
    required this.bytes,
    required this.lastUsedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['url'] = Variable<String>(url);
    map['local_path'] = Variable<String>(localPath);
    map['bytes'] = Variable<int>(bytes);
    map['last_used_at'] = Variable<DateTime>(lastUsedAt);
    return map;
  }

  CachedImagesCompanion toCompanion(bool nullToAbsent) {
    return CachedImagesCompanion(
      url: Value(url),
      localPath: Value(localPath),
      bytes: Value(bytes),
      lastUsedAt: Value(lastUsedAt),
    );
  }

  factory CachedImage.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedImage(
      url: serializer.fromJson<String>(json['url']),
      localPath: serializer.fromJson<String>(json['localPath']),
      bytes: serializer.fromJson<int>(json['bytes']),
      lastUsedAt: serializer.fromJson<DateTime>(json['lastUsedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'url': serializer.toJson<String>(url),
      'localPath': serializer.toJson<String>(localPath),
      'bytes': serializer.toJson<int>(bytes),
      'lastUsedAt': serializer.toJson<DateTime>(lastUsedAt),
    };
  }

  CachedImage copyWith({
    String? url,
    String? localPath,
    int? bytes,
    DateTime? lastUsedAt,
  }) => CachedImage(
    url: url ?? this.url,
    localPath: localPath ?? this.localPath,
    bytes: bytes ?? this.bytes,
    lastUsedAt: lastUsedAt ?? this.lastUsedAt,
  );
  CachedImage copyWithCompanion(CachedImagesCompanion data) {
    return CachedImage(
      url: data.url.present ? data.url.value : this.url,
      localPath: data.localPath.present ? data.localPath.value : this.localPath,
      bytes: data.bytes.present ? data.bytes.value : this.bytes,
      lastUsedAt: data.lastUsedAt.present
          ? data.lastUsedAt.value
          : this.lastUsedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedImage(')
          ..write('url: $url, ')
          ..write('localPath: $localPath, ')
          ..write('bytes: $bytes, ')
          ..write('lastUsedAt: $lastUsedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(url, localPath, bytes, lastUsedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedImage &&
          other.url == this.url &&
          other.localPath == this.localPath &&
          other.bytes == this.bytes &&
          other.lastUsedAt == this.lastUsedAt);
}

class CachedImagesCompanion extends UpdateCompanion<CachedImage> {
  final Value<String> url;
  final Value<String> localPath;
  final Value<int> bytes;
  final Value<DateTime> lastUsedAt;
  final Value<int> rowid;
  const CachedImagesCompanion({
    this.url = const Value.absent(),
    this.localPath = const Value.absent(),
    this.bytes = const Value.absent(),
    this.lastUsedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedImagesCompanion.insert({
    required String url,
    required String localPath,
    required int bytes,
    required DateTime lastUsedAt,
    this.rowid = const Value.absent(),
  }) : url = Value(url),
       localPath = Value(localPath),
       bytes = Value(bytes),
       lastUsedAt = Value(lastUsedAt);
  static Insertable<CachedImage> custom({
    Expression<String>? url,
    Expression<String>? localPath,
    Expression<int>? bytes,
    Expression<DateTime>? lastUsedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (url != null) 'url': url,
      if (localPath != null) 'local_path': localPath,
      if (bytes != null) 'bytes': bytes,
      if (lastUsedAt != null) 'last_used_at': lastUsedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedImagesCompanion copyWith({
    Value<String>? url,
    Value<String>? localPath,
    Value<int>? bytes,
    Value<DateTime>? lastUsedAt,
    Value<int>? rowid,
  }) {
    return CachedImagesCompanion(
      url: url ?? this.url,
      localPath: localPath ?? this.localPath,
      bytes: bytes ?? this.bytes,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (localPath.present) {
      map['local_path'] = Variable<String>(localPath.value);
    }
    if (bytes.present) {
      map['bytes'] = Variable<int>(bytes.value);
    }
    if (lastUsedAt.present) {
      map['last_used_at'] = Variable<DateTime>(lastUsedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedImagesCompanion(')
          ..write('url: $url, ')
          ..write('localPath: $localPath, ')
          ..write('bytes: $bytes, ')
          ..write('lastUsedAt: $lastUsedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncStatesTable extends SyncStates
    with TableInfo<$SyncStatesTable, SyncState> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncStatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _scopeMeta = const VerificationMeta('scope');
  @override
  late final GeneratedColumn<String> scope = GeneratedColumn<String>(
    'scope',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _phaseMeta = const VerificationMeta('phase');
  @override
  late final GeneratedColumn<String> phase = GeneratedColumn<String>(
    'phase',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _coverageMeta = const VerificationMeta(
    'coverage',
  );
  @override
  late final GeneratedColumn<String> coverage = GeneratedColumn<String>(
    'coverage',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('best_effort'),
  );
  static const VerificationMeta _lastOffsetMeta = const VerificationMeta(
    'lastOffset',
  );
  @override
  late final GeneratedColumn<int> lastOffset = GeneratedColumn<int>(
    'last_offset',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastCreatedAtMeta = const VerificationMeta(
    'lastCreatedAt',
  );
  @override
  late final GeneratedColumn<String> lastCreatedAt = GeneratedColumn<String>(
    'last_created_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastIdMeta = const VerificationMeta('lastId');
  @override
  late final GeneratedColumn<int> lastId = GeneratedColumn<int>(
    'last_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _serverTotalMeta = const VerificationMeta(
    'serverTotal',
  );
  @override
  late final GeneratedColumn<int> serverTotal = GeneratedColumn<int>(
    'server_total',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _storedCountMeta = const VerificationMeta(
    'storedCount',
  );
  @override
  late final GeneratedColumn<int> storedCount = GeneratedColumn<int>(
    'stored_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _checkpointMeta = const VerificationMeta(
    'checkpoint',
  );
  @override
  late final GeneratedColumn<String> checkpoint = GeneratedColumn<String>(
    'checkpoint',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    scope,
    phase,
    coverage,
    lastOffset,
    lastCreatedAt,
    lastId,
    serverTotal,
    storedCount,
    checkpoint,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_states';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncState> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('scope')) {
      context.handle(
        _scopeMeta,
        scope.isAcceptableOrUnknown(data['scope']!, _scopeMeta),
      );
    } else if (isInserting) {
      context.missing(_scopeMeta);
    }
    if (data.containsKey('phase')) {
      context.handle(
        _phaseMeta,
        phase.isAcceptableOrUnknown(data['phase']!, _phaseMeta),
      );
    } else if (isInserting) {
      context.missing(_phaseMeta);
    }
    if (data.containsKey('coverage')) {
      context.handle(
        _coverageMeta,
        coverage.isAcceptableOrUnknown(data['coverage']!, _coverageMeta),
      );
    }
    if (data.containsKey('last_offset')) {
      context.handle(
        _lastOffsetMeta,
        lastOffset.isAcceptableOrUnknown(data['last_offset']!, _lastOffsetMeta),
      );
    }
    if (data.containsKey('last_created_at')) {
      context.handle(
        _lastCreatedAtMeta,
        lastCreatedAt.isAcceptableOrUnknown(
          data['last_created_at']!,
          _lastCreatedAtMeta,
        ),
      );
    }
    if (data.containsKey('last_id')) {
      context.handle(
        _lastIdMeta,
        lastId.isAcceptableOrUnknown(data['last_id']!, _lastIdMeta),
      );
    }
    if (data.containsKey('server_total')) {
      context.handle(
        _serverTotalMeta,
        serverTotal.isAcceptableOrUnknown(
          data['server_total']!,
          _serverTotalMeta,
        ),
      );
    }
    if (data.containsKey('stored_count')) {
      context.handle(
        _storedCountMeta,
        storedCount.isAcceptableOrUnknown(
          data['stored_count']!,
          _storedCountMeta,
        ),
      );
    }
    if (data.containsKey('checkpoint')) {
      context.handle(
        _checkpointMeta,
        checkpoint.isAcceptableOrUnknown(data['checkpoint']!, _checkpointMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {scope};
  @override
  SyncState map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncState(
      scope: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scope'],
      )!,
      phase: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}phase'],
      )!,
      coverage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}coverage'],
      )!,
      lastOffset: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_offset'],
      )!,
      lastCreatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_created_at'],
      ),
      lastId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_id'],
      )!,
      serverTotal: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_total'],
      )!,
      storedCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}stored_count'],
      )!,
      checkpoint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}checkpoint'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $SyncStatesTable createAlias(String alias) {
    return $SyncStatesTable(attachedDatabase, alias);
  }
}

class SyncState extends DataClass implements Insertable<SyncState> {
  final String scope;
  final String phase;
  final String coverage;
  final int lastOffset;
  final String? lastCreatedAt;
  final int lastId;
  final int serverTotal;
  final int storedCount;
  final String? checkpoint;
  final DateTime updatedAt;
  const SyncState({
    required this.scope,
    required this.phase,
    required this.coverage,
    required this.lastOffset,
    this.lastCreatedAt,
    required this.lastId,
    required this.serverTotal,
    required this.storedCount,
    this.checkpoint,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['scope'] = Variable<String>(scope);
    map['phase'] = Variable<String>(phase);
    map['coverage'] = Variable<String>(coverage);
    map['last_offset'] = Variable<int>(lastOffset);
    if (!nullToAbsent || lastCreatedAt != null) {
      map['last_created_at'] = Variable<String>(lastCreatedAt);
    }
    map['last_id'] = Variable<int>(lastId);
    map['server_total'] = Variable<int>(serverTotal);
    map['stored_count'] = Variable<int>(storedCount);
    if (!nullToAbsent || checkpoint != null) {
      map['checkpoint'] = Variable<String>(checkpoint);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  SyncStatesCompanion toCompanion(bool nullToAbsent) {
    return SyncStatesCompanion(
      scope: Value(scope),
      phase: Value(phase),
      coverage: Value(coverage),
      lastOffset: Value(lastOffset),
      lastCreatedAt: lastCreatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastCreatedAt),
      lastId: Value(lastId),
      serverTotal: Value(serverTotal),
      storedCount: Value(storedCount),
      checkpoint: checkpoint == null && nullToAbsent
          ? const Value.absent()
          : Value(checkpoint),
      updatedAt: Value(updatedAt),
    );
  }

  factory SyncState.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncState(
      scope: serializer.fromJson<String>(json['scope']),
      phase: serializer.fromJson<String>(json['phase']),
      coverage: serializer.fromJson<String>(json['coverage']),
      lastOffset: serializer.fromJson<int>(json['lastOffset']),
      lastCreatedAt: serializer.fromJson<String?>(json['lastCreatedAt']),
      lastId: serializer.fromJson<int>(json['lastId']),
      serverTotal: serializer.fromJson<int>(json['serverTotal']),
      storedCount: serializer.fromJson<int>(json['storedCount']),
      checkpoint: serializer.fromJson<String?>(json['checkpoint']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'scope': serializer.toJson<String>(scope),
      'phase': serializer.toJson<String>(phase),
      'coverage': serializer.toJson<String>(coverage),
      'lastOffset': serializer.toJson<int>(lastOffset),
      'lastCreatedAt': serializer.toJson<String?>(lastCreatedAt),
      'lastId': serializer.toJson<int>(lastId),
      'serverTotal': serializer.toJson<int>(serverTotal),
      'storedCount': serializer.toJson<int>(storedCount),
      'checkpoint': serializer.toJson<String?>(checkpoint),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  SyncState copyWith({
    String? scope,
    String? phase,
    String? coverage,
    int? lastOffset,
    Value<String?> lastCreatedAt = const Value.absent(),
    int? lastId,
    int? serverTotal,
    int? storedCount,
    Value<String?> checkpoint = const Value.absent(),
    DateTime? updatedAt,
  }) => SyncState(
    scope: scope ?? this.scope,
    phase: phase ?? this.phase,
    coverage: coverage ?? this.coverage,
    lastOffset: lastOffset ?? this.lastOffset,
    lastCreatedAt: lastCreatedAt.present
        ? lastCreatedAt.value
        : this.lastCreatedAt,
    lastId: lastId ?? this.lastId,
    serverTotal: serverTotal ?? this.serverTotal,
    storedCount: storedCount ?? this.storedCount,
    checkpoint: checkpoint.present ? checkpoint.value : this.checkpoint,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  SyncState copyWithCompanion(SyncStatesCompanion data) {
    return SyncState(
      scope: data.scope.present ? data.scope.value : this.scope,
      phase: data.phase.present ? data.phase.value : this.phase,
      coverage: data.coverage.present ? data.coverage.value : this.coverage,
      lastOffset: data.lastOffset.present
          ? data.lastOffset.value
          : this.lastOffset,
      lastCreatedAt: data.lastCreatedAt.present
          ? data.lastCreatedAt.value
          : this.lastCreatedAt,
      lastId: data.lastId.present ? data.lastId.value : this.lastId,
      serverTotal: data.serverTotal.present
          ? data.serverTotal.value
          : this.serverTotal,
      storedCount: data.storedCount.present
          ? data.storedCount.value
          : this.storedCount,
      checkpoint: data.checkpoint.present
          ? data.checkpoint.value
          : this.checkpoint,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncState(')
          ..write('scope: $scope, ')
          ..write('phase: $phase, ')
          ..write('coverage: $coverage, ')
          ..write('lastOffset: $lastOffset, ')
          ..write('lastCreatedAt: $lastCreatedAt, ')
          ..write('lastId: $lastId, ')
          ..write('serverTotal: $serverTotal, ')
          ..write('storedCount: $storedCount, ')
          ..write('checkpoint: $checkpoint, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    scope,
    phase,
    coverage,
    lastOffset,
    lastCreatedAt,
    lastId,
    serverTotal,
    storedCount,
    checkpoint,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncState &&
          other.scope == this.scope &&
          other.phase == this.phase &&
          other.coverage == this.coverage &&
          other.lastOffset == this.lastOffset &&
          other.lastCreatedAt == this.lastCreatedAt &&
          other.lastId == this.lastId &&
          other.serverTotal == this.serverTotal &&
          other.storedCount == this.storedCount &&
          other.checkpoint == this.checkpoint &&
          other.updatedAt == this.updatedAt);
}

class SyncStatesCompanion extends UpdateCompanion<SyncState> {
  final Value<String> scope;
  final Value<String> phase;
  final Value<String> coverage;
  final Value<int> lastOffset;
  final Value<String?> lastCreatedAt;
  final Value<int> lastId;
  final Value<int> serverTotal;
  final Value<int> storedCount;
  final Value<String?> checkpoint;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const SyncStatesCompanion({
    this.scope = const Value.absent(),
    this.phase = const Value.absent(),
    this.coverage = const Value.absent(),
    this.lastOffset = const Value.absent(),
    this.lastCreatedAt = const Value.absent(),
    this.lastId = const Value.absent(),
    this.serverTotal = const Value.absent(),
    this.storedCount = const Value.absent(),
    this.checkpoint = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncStatesCompanion.insert({
    required String scope,
    required String phase,
    this.coverage = const Value.absent(),
    this.lastOffset = const Value.absent(),
    this.lastCreatedAt = const Value.absent(),
    this.lastId = const Value.absent(),
    this.serverTotal = const Value.absent(),
    this.storedCount = const Value.absent(),
    this.checkpoint = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : scope = Value(scope),
       phase = Value(phase),
       updatedAt = Value(updatedAt);
  static Insertable<SyncState> custom({
    Expression<String>? scope,
    Expression<String>? phase,
    Expression<String>? coverage,
    Expression<int>? lastOffset,
    Expression<String>? lastCreatedAt,
    Expression<int>? lastId,
    Expression<int>? serverTotal,
    Expression<int>? storedCount,
    Expression<String>? checkpoint,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (scope != null) 'scope': scope,
      if (phase != null) 'phase': phase,
      if (coverage != null) 'coverage': coverage,
      if (lastOffset != null) 'last_offset': lastOffset,
      if (lastCreatedAt != null) 'last_created_at': lastCreatedAt,
      if (lastId != null) 'last_id': lastId,
      if (serverTotal != null) 'server_total': serverTotal,
      if (storedCount != null) 'stored_count': storedCount,
      if (checkpoint != null) 'checkpoint': checkpoint,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncStatesCompanion copyWith({
    Value<String>? scope,
    Value<String>? phase,
    Value<String>? coverage,
    Value<int>? lastOffset,
    Value<String?>? lastCreatedAt,
    Value<int>? lastId,
    Value<int>? serverTotal,
    Value<int>? storedCount,
    Value<String?>? checkpoint,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return SyncStatesCompanion(
      scope: scope ?? this.scope,
      phase: phase ?? this.phase,
      coverage: coverage ?? this.coverage,
      lastOffset: lastOffset ?? this.lastOffset,
      lastCreatedAt: lastCreatedAt ?? this.lastCreatedAt,
      lastId: lastId ?? this.lastId,
      serverTotal: serverTotal ?? this.serverTotal,
      storedCount: storedCount ?? this.storedCount,
      checkpoint: checkpoint ?? this.checkpoint,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (scope.present) {
      map['scope'] = Variable<String>(scope.value);
    }
    if (phase.present) {
      map['phase'] = Variable<String>(phase.value);
    }
    if (coverage.present) {
      map['coverage'] = Variable<String>(coverage.value);
    }
    if (lastOffset.present) {
      map['last_offset'] = Variable<int>(lastOffset.value);
    }
    if (lastCreatedAt.present) {
      map['last_created_at'] = Variable<String>(lastCreatedAt.value);
    }
    if (lastId.present) {
      map['last_id'] = Variable<int>(lastId.value);
    }
    if (serverTotal.present) {
      map['server_total'] = Variable<int>(serverTotal.value);
    }
    if (storedCount.present) {
      map['stored_count'] = Variable<int>(storedCount.value);
    }
    if (checkpoint.present) {
      map['checkpoint'] = Variable<String>(checkpoint.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncStatesCompanion(')
          ..write('scope: $scope, ')
          ..write('phase: $phase, ')
          ..write('coverage: $coverage, ')
          ..write('lastOffset: $lastOffset, ')
          ..write('lastCreatedAt: $lastCreatedAt, ')
          ..write('lastId: $lastId, ')
          ..write('serverTotal: $serverTotal, ')
          ..write('storedCount: $storedCount, ')
          ..write('checkpoint: $checkpoint, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CartItemsTable extends CartItems
    with TableInfo<$CartItemsTable, CartItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CartItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _productIdMeta = const VerificationMeta(
    'productId',
  );
  @override
  late final GeneratedColumn<int> productId = GeneratedColumn<int>(
    'product_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _variantIdMeta = const VerificationMeta(
    'variantId',
  );
  @override
  late final GeneratedColumn<int> variantId = GeneratedColumn<int>(
    'variant_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _qtyMeta = const VerificationMeta('qty');
  @override
  late final GeneratedColumn<int> qty = GeneratedColumn<int>(
    'qty',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _sellerIdMeta = const VerificationMeta(
    'sellerId',
  );
  @override
  late final GeneratedColumn<int> sellerId = GeneratedColumn<int>(
    'seller_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _imageUrlMeta = const VerificationMeta(
    'imageUrl',
  );
  @override
  late final GeneratedColumn<String> imageUrl = GeneratedColumn<String>(
    'image_url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _priceMeta = const VerificationMeta('price');
  @override
  late final GeneratedColumn<double> price = GeneratedColumn<double>(
    'price',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _variantLabelMeta = const VerificationMeta(
    'variantLabel',
  );
  @override
  late final GeneratedColumn<String> variantLabel = GeneratedColumn<String>(
    'variant_label',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _slugMeta = const VerificationMeta('slug');
  @override
  late final GeneratedColumn<String> slug = GeneratedColumn<String>(
    'slug',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _stockMeta = const VerificationMeta('stock');
  @override
  late final GeneratedColumn<int> stock = GeneratedColumn<int>(
    'stock',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _totalStockMeta = const VerificationMeta(
    'totalStock',
  );
  @override
  late final GeneratedColumn<int> totalStock = GeneratedColumn<int>(
    'total_stock',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isUnlimitedStockMeta = const VerificationMeta(
    'isUnlimitedStock',
  );
  @override
  late final GeneratedColumn<int> isUnlimitedStock = GeneratedColumn<int>(
    'is_unlimited_stock',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _stockStatusMeta = const VerificationMeta(
    'stockStatus',
  );
  @override
  late final GeneratedColumn<String> stockStatus = GeneratedColumn<String>(
    'stock_status',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _totalAllowedQuantityMeta =
      const VerificationMeta('totalAllowedQuantity');
  @override
  late final GeneratedColumn<int> totalAllowedQuantity = GeneratedColumn<int>(
    'total_allowed_quantity',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _savedAmountMeta = const VerificationMeta(
    'savedAmount',
  );
  @override
  late final GeneratedColumn<double> savedAmount = GeneratedColumn<double>(
    'saved_amount',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  @override
  late final GeneratedColumn<int> addedAt = GeneratedColumn<int>(
    'added_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    productId,
    variantId,
    qty,
    sellerId,
    name,
    imageUrl,
    price,
    variantLabel,
    slug,
    stock,
    totalStock,
    isUnlimitedStock,
    stockStatus,
    totalAllowedQuantity,
    savedAmount,
    addedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cart_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<CartItem> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('product_id')) {
      context.handle(
        _productIdMeta,
        productId.isAcceptableOrUnknown(data['product_id']!, _productIdMeta),
      );
    } else if (isInserting) {
      context.missing(_productIdMeta);
    }
    if (data.containsKey('variant_id')) {
      context.handle(
        _variantIdMeta,
        variantId.isAcceptableOrUnknown(data['variant_id']!, _variantIdMeta),
      );
    } else if (isInserting) {
      context.missing(_variantIdMeta);
    }
    if (data.containsKey('qty')) {
      context.handle(
        _qtyMeta,
        qty.isAcceptableOrUnknown(data['qty']!, _qtyMeta),
      );
    }
    if (data.containsKey('seller_id')) {
      context.handle(
        _sellerIdMeta,
        sellerId.isAcceptableOrUnknown(data['seller_id']!, _sellerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sellerIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('image_url')) {
      context.handle(
        _imageUrlMeta,
        imageUrl.isAcceptableOrUnknown(data['image_url']!, _imageUrlMeta),
      );
    } else if (isInserting) {
      context.missing(_imageUrlMeta);
    }
    if (data.containsKey('price')) {
      context.handle(
        _priceMeta,
        price.isAcceptableOrUnknown(data['price']!, _priceMeta),
      );
    } else if (isInserting) {
      context.missing(_priceMeta);
    }
    if (data.containsKey('variant_label')) {
      context.handle(
        _variantLabelMeta,
        variantLabel.isAcceptableOrUnknown(
          data['variant_label']!,
          _variantLabelMeta,
        ),
      );
    }
    if (data.containsKey('slug')) {
      context.handle(
        _slugMeta,
        slug.isAcceptableOrUnknown(data['slug']!, _slugMeta),
      );
    }
    if (data.containsKey('stock')) {
      context.handle(
        _stockMeta,
        stock.isAcceptableOrUnknown(data['stock']!, _stockMeta),
      );
    }
    if (data.containsKey('total_stock')) {
      context.handle(
        _totalStockMeta,
        totalStock.isAcceptableOrUnknown(data['total_stock']!, _totalStockMeta),
      );
    }
    if (data.containsKey('is_unlimited_stock')) {
      context.handle(
        _isUnlimitedStockMeta,
        isUnlimitedStock.isAcceptableOrUnknown(
          data['is_unlimited_stock']!,
          _isUnlimitedStockMeta,
        ),
      );
    }
    if (data.containsKey('stock_status')) {
      context.handle(
        _stockStatusMeta,
        stockStatus.isAcceptableOrUnknown(
          data['stock_status']!,
          _stockStatusMeta,
        ),
      );
    }
    if (data.containsKey('total_allowed_quantity')) {
      context.handle(
        _totalAllowedQuantityMeta,
        totalAllowedQuantity.isAcceptableOrUnknown(
          data['total_allowed_quantity']!,
          _totalAllowedQuantityMeta,
        ),
      );
    }
    if (data.containsKey('saved_amount')) {
      context.handle(
        _savedAmountMeta,
        savedAmount.isAcceptableOrUnknown(
          data['saved_amount']!,
          _savedAmountMeta,
        ),
      );
    }
    if (data.containsKey('added_at')) {
      context.handle(
        _addedAtMeta,
        addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_addedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {productId, variantId};
  @override
  CartItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CartItem(
      productId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}product_id'],
      )!,
      variantId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}variant_id'],
      )!,
      qty: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}qty'],
      )!,
      sellerId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}seller_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      imageUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}image_url'],
      )!,
      price: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}price'],
      )!,
      variantLabel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}variant_label'],
      ),
      slug: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}slug'],
      ),
      stock: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}stock'],
      ),
      totalStock: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_stock'],
      ),
      isUnlimitedStock: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}is_unlimited_stock'],
      )!,
      stockStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}stock_status'],
      ),
      totalAllowedQuantity: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_allowed_quantity'],
      ),
      savedAmount: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}saved_amount'],
      ),
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}added_at'],
      )!,
    );
  }

  @override
  $CartItemsTable createAlias(String alias) {
    return $CartItemsTable(attachedDatabase, alias);
  }
}

class CartItem extends DataClass implements Insertable<CartItem> {
  final int productId;
  final int variantId;
  final int qty;
  final int sellerId;
  final String name;
  final String imageUrl;
  final double price;
  final String? variantLabel;
  final String? slug;
  final int? stock;
  final int? totalStock;
  final int isUnlimitedStock;
  final String? stockStatus;
  final int? totalAllowedQuantity;
  final double? savedAmount;
  final int addedAt;
  const CartItem({
    required this.productId,
    required this.variantId,
    required this.qty,
    required this.sellerId,
    required this.name,
    required this.imageUrl,
    required this.price,
    this.variantLabel,
    this.slug,
    this.stock,
    this.totalStock,
    required this.isUnlimitedStock,
    this.stockStatus,
    this.totalAllowedQuantity,
    this.savedAmount,
    required this.addedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['product_id'] = Variable<int>(productId);
    map['variant_id'] = Variable<int>(variantId);
    map['qty'] = Variable<int>(qty);
    map['seller_id'] = Variable<int>(sellerId);
    map['name'] = Variable<String>(name);
    map['image_url'] = Variable<String>(imageUrl);
    map['price'] = Variable<double>(price);
    if (!nullToAbsent || variantLabel != null) {
      map['variant_label'] = Variable<String>(variantLabel);
    }
    if (!nullToAbsent || slug != null) {
      map['slug'] = Variable<String>(slug);
    }
    if (!nullToAbsent || stock != null) {
      map['stock'] = Variable<int>(stock);
    }
    if (!nullToAbsent || totalStock != null) {
      map['total_stock'] = Variable<int>(totalStock);
    }
    map['is_unlimited_stock'] = Variable<int>(isUnlimitedStock);
    if (!nullToAbsent || stockStatus != null) {
      map['stock_status'] = Variable<String>(stockStatus);
    }
    if (!nullToAbsent || totalAllowedQuantity != null) {
      map['total_allowed_quantity'] = Variable<int>(totalAllowedQuantity);
    }
    if (!nullToAbsent || savedAmount != null) {
      map['saved_amount'] = Variable<double>(savedAmount);
    }
    map['added_at'] = Variable<int>(addedAt);
    return map;
  }

  CartItemsCompanion toCompanion(bool nullToAbsent) {
    return CartItemsCompanion(
      productId: Value(productId),
      variantId: Value(variantId),
      qty: Value(qty),
      sellerId: Value(sellerId),
      name: Value(name),
      imageUrl: Value(imageUrl),
      price: Value(price),
      variantLabel: variantLabel == null && nullToAbsent
          ? const Value.absent()
          : Value(variantLabel),
      slug: slug == null && nullToAbsent ? const Value.absent() : Value(slug),
      stock: stock == null && nullToAbsent
          ? const Value.absent()
          : Value(stock),
      totalStock: totalStock == null && nullToAbsent
          ? const Value.absent()
          : Value(totalStock),
      isUnlimitedStock: Value(isUnlimitedStock),
      stockStatus: stockStatus == null && nullToAbsent
          ? const Value.absent()
          : Value(stockStatus),
      totalAllowedQuantity: totalAllowedQuantity == null && nullToAbsent
          ? const Value.absent()
          : Value(totalAllowedQuantity),
      savedAmount: savedAmount == null && nullToAbsent
          ? const Value.absent()
          : Value(savedAmount),
      addedAt: Value(addedAt),
    );
  }

  factory CartItem.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CartItem(
      productId: serializer.fromJson<int>(json['productId']),
      variantId: serializer.fromJson<int>(json['variantId']),
      qty: serializer.fromJson<int>(json['qty']),
      sellerId: serializer.fromJson<int>(json['sellerId']),
      name: serializer.fromJson<String>(json['name']),
      imageUrl: serializer.fromJson<String>(json['imageUrl']),
      price: serializer.fromJson<double>(json['price']),
      variantLabel: serializer.fromJson<String?>(json['variantLabel']),
      slug: serializer.fromJson<String?>(json['slug']),
      stock: serializer.fromJson<int?>(json['stock']),
      totalStock: serializer.fromJson<int?>(json['totalStock']),
      isUnlimitedStock: serializer.fromJson<int>(json['isUnlimitedStock']),
      stockStatus: serializer.fromJson<String?>(json['stockStatus']),
      totalAllowedQuantity: serializer.fromJson<int?>(
        json['totalAllowedQuantity'],
      ),
      savedAmount: serializer.fromJson<double?>(json['savedAmount']),
      addedAt: serializer.fromJson<int>(json['addedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'productId': serializer.toJson<int>(productId),
      'variantId': serializer.toJson<int>(variantId),
      'qty': serializer.toJson<int>(qty),
      'sellerId': serializer.toJson<int>(sellerId),
      'name': serializer.toJson<String>(name),
      'imageUrl': serializer.toJson<String>(imageUrl),
      'price': serializer.toJson<double>(price),
      'variantLabel': serializer.toJson<String?>(variantLabel),
      'slug': serializer.toJson<String?>(slug),
      'stock': serializer.toJson<int?>(stock),
      'totalStock': serializer.toJson<int?>(totalStock),
      'isUnlimitedStock': serializer.toJson<int>(isUnlimitedStock),
      'stockStatus': serializer.toJson<String?>(stockStatus),
      'totalAllowedQuantity': serializer.toJson<int?>(totalAllowedQuantity),
      'savedAmount': serializer.toJson<double?>(savedAmount),
      'addedAt': serializer.toJson<int>(addedAt),
    };
  }

  CartItem copyWith({
    int? productId,
    int? variantId,
    int? qty,
    int? sellerId,
    String? name,
    String? imageUrl,
    double? price,
    Value<String?> variantLabel = const Value.absent(),
    Value<String?> slug = const Value.absent(),
    Value<int?> stock = const Value.absent(),
    Value<int?> totalStock = const Value.absent(),
    int? isUnlimitedStock,
    Value<String?> stockStatus = const Value.absent(),
    Value<int?> totalAllowedQuantity = const Value.absent(),
    Value<double?> savedAmount = const Value.absent(),
    int? addedAt,
  }) => CartItem(
    productId: productId ?? this.productId,
    variantId: variantId ?? this.variantId,
    qty: qty ?? this.qty,
    sellerId: sellerId ?? this.sellerId,
    name: name ?? this.name,
    imageUrl: imageUrl ?? this.imageUrl,
    price: price ?? this.price,
    variantLabel: variantLabel.present ? variantLabel.value : this.variantLabel,
    slug: slug.present ? slug.value : this.slug,
    stock: stock.present ? stock.value : this.stock,
    totalStock: totalStock.present ? totalStock.value : this.totalStock,
    isUnlimitedStock: isUnlimitedStock ?? this.isUnlimitedStock,
    stockStatus: stockStatus.present ? stockStatus.value : this.stockStatus,
    totalAllowedQuantity: totalAllowedQuantity.present
        ? totalAllowedQuantity.value
        : this.totalAllowedQuantity,
    savedAmount: savedAmount.present ? savedAmount.value : this.savedAmount,
    addedAt: addedAt ?? this.addedAt,
  );
  CartItem copyWithCompanion(CartItemsCompanion data) {
    return CartItem(
      productId: data.productId.present ? data.productId.value : this.productId,
      variantId: data.variantId.present ? data.variantId.value : this.variantId,
      qty: data.qty.present ? data.qty.value : this.qty,
      sellerId: data.sellerId.present ? data.sellerId.value : this.sellerId,
      name: data.name.present ? data.name.value : this.name,
      imageUrl: data.imageUrl.present ? data.imageUrl.value : this.imageUrl,
      price: data.price.present ? data.price.value : this.price,
      variantLabel: data.variantLabel.present
          ? data.variantLabel.value
          : this.variantLabel,
      slug: data.slug.present ? data.slug.value : this.slug,
      stock: data.stock.present ? data.stock.value : this.stock,
      totalStock: data.totalStock.present
          ? data.totalStock.value
          : this.totalStock,
      isUnlimitedStock: data.isUnlimitedStock.present
          ? data.isUnlimitedStock.value
          : this.isUnlimitedStock,
      stockStatus: data.stockStatus.present
          ? data.stockStatus.value
          : this.stockStatus,
      totalAllowedQuantity: data.totalAllowedQuantity.present
          ? data.totalAllowedQuantity.value
          : this.totalAllowedQuantity,
      savedAmount: data.savedAmount.present
          ? data.savedAmount.value
          : this.savedAmount,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CartItem(')
          ..write('productId: $productId, ')
          ..write('variantId: $variantId, ')
          ..write('qty: $qty, ')
          ..write('sellerId: $sellerId, ')
          ..write('name: $name, ')
          ..write('imageUrl: $imageUrl, ')
          ..write('price: $price, ')
          ..write('variantLabel: $variantLabel, ')
          ..write('slug: $slug, ')
          ..write('stock: $stock, ')
          ..write('totalStock: $totalStock, ')
          ..write('isUnlimitedStock: $isUnlimitedStock, ')
          ..write('stockStatus: $stockStatus, ')
          ..write('totalAllowedQuantity: $totalAllowedQuantity, ')
          ..write('savedAmount: $savedAmount, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    productId,
    variantId,
    qty,
    sellerId,
    name,
    imageUrl,
    price,
    variantLabel,
    slug,
    stock,
    totalStock,
    isUnlimitedStock,
    stockStatus,
    totalAllowedQuantity,
    savedAmount,
    addedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CartItem &&
          other.productId == this.productId &&
          other.variantId == this.variantId &&
          other.qty == this.qty &&
          other.sellerId == this.sellerId &&
          other.name == this.name &&
          other.imageUrl == this.imageUrl &&
          other.price == this.price &&
          other.variantLabel == this.variantLabel &&
          other.slug == this.slug &&
          other.stock == this.stock &&
          other.totalStock == this.totalStock &&
          other.isUnlimitedStock == this.isUnlimitedStock &&
          other.stockStatus == this.stockStatus &&
          other.totalAllowedQuantity == this.totalAllowedQuantity &&
          other.savedAmount == this.savedAmount &&
          other.addedAt == this.addedAt);
}

class CartItemsCompanion extends UpdateCompanion<CartItem> {
  final Value<int> productId;
  final Value<int> variantId;
  final Value<int> qty;
  final Value<int> sellerId;
  final Value<String> name;
  final Value<String> imageUrl;
  final Value<double> price;
  final Value<String?> variantLabel;
  final Value<String?> slug;
  final Value<int?> stock;
  final Value<int?> totalStock;
  final Value<int> isUnlimitedStock;
  final Value<String?> stockStatus;
  final Value<int?> totalAllowedQuantity;
  final Value<double?> savedAmount;
  final Value<int> addedAt;
  final Value<int> rowid;
  const CartItemsCompanion({
    this.productId = const Value.absent(),
    this.variantId = const Value.absent(),
    this.qty = const Value.absent(),
    this.sellerId = const Value.absent(),
    this.name = const Value.absent(),
    this.imageUrl = const Value.absent(),
    this.price = const Value.absent(),
    this.variantLabel = const Value.absent(),
    this.slug = const Value.absent(),
    this.stock = const Value.absent(),
    this.totalStock = const Value.absent(),
    this.isUnlimitedStock = const Value.absent(),
    this.stockStatus = const Value.absent(),
    this.totalAllowedQuantity = const Value.absent(),
    this.savedAmount = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CartItemsCompanion.insert({
    required int productId,
    required int variantId,
    this.qty = const Value.absent(),
    required int sellerId,
    required String name,
    required String imageUrl,
    required double price,
    this.variantLabel = const Value.absent(),
    this.slug = const Value.absent(),
    this.stock = const Value.absent(),
    this.totalStock = const Value.absent(),
    this.isUnlimitedStock = const Value.absent(),
    this.stockStatus = const Value.absent(),
    this.totalAllowedQuantity = const Value.absent(),
    this.savedAmount = const Value.absent(),
    required int addedAt,
    this.rowid = const Value.absent(),
  }) : productId = Value(productId),
       variantId = Value(variantId),
       sellerId = Value(sellerId),
       name = Value(name),
       imageUrl = Value(imageUrl),
       price = Value(price),
       addedAt = Value(addedAt);
  static Insertable<CartItem> custom({
    Expression<int>? productId,
    Expression<int>? variantId,
    Expression<int>? qty,
    Expression<int>? sellerId,
    Expression<String>? name,
    Expression<String>? imageUrl,
    Expression<double>? price,
    Expression<String>? variantLabel,
    Expression<String>? slug,
    Expression<int>? stock,
    Expression<int>? totalStock,
    Expression<int>? isUnlimitedStock,
    Expression<String>? stockStatus,
    Expression<int>? totalAllowedQuantity,
    Expression<double>? savedAmount,
    Expression<int>? addedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (productId != null) 'product_id': productId,
      if (variantId != null) 'variant_id': variantId,
      if (qty != null) 'qty': qty,
      if (sellerId != null) 'seller_id': sellerId,
      if (name != null) 'name': name,
      if (imageUrl != null) 'image_url': imageUrl,
      if (price != null) 'price': price,
      if (variantLabel != null) 'variant_label': variantLabel,
      if (slug != null) 'slug': slug,
      if (stock != null) 'stock': stock,
      if (totalStock != null) 'total_stock': totalStock,
      if (isUnlimitedStock != null) 'is_unlimited_stock': isUnlimitedStock,
      if (stockStatus != null) 'stock_status': stockStatus,
      if (totalAllowedQuantity != null)
        'total_allowed_quantity': totalAllowedQuantity,
      if (savedAmount != null) 'saved_amount': savedAmount,
      if (addedAt != null) 'added_at': addedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CartItemsCompanion copyWith({
    Value<int>? productId,
    Value<int>? variantId,
    Value<int>? qty,
    Value<int>? sellerId,
    Value<String>? name,
    Value<String>? imageUrl,
    Value<double>? price,
    Value<String?>? variantLabel,
    Value<String?>? slug,
    Value<int?>? stock,
    Value<int?>? totalStock,
    Value<int>? isUnlimitedStock,
    Value<String?>? stockStatus,
    Value<int?>? totalAllowedQuantity,
    Value<double?>? savedAmount,
    Value<int>? addedAt,
    Value<int>? rowid,
  }) {
    return CartItemsCompanion(
      productId: productId ?? this.productId,
      variantId: variantId ?? this.variantId,
      qty: qty ?? this.qty,
      sellerId: sellerId ?? this.sellerId,
      name: name ?? this.name,
      imageUrl: imageUrl ?? this.imageUrl,
      price: price ?? this.price,
      variantLabel: variantLabel ?? this.variantLabel,
      slug: slug ?? this.slug,
      stock: stock ?? this.stock,
      totalStock: totalStock ?? this.totalStock,
      isUnlimitedStock: isUnlimitedStock ?? this.isUnlimitedStock,
      stockStatus: stockStatus ?? this.stockStatus,
      totalAllowedQuantity: totalAllowedQuantity ?? this.totalAllowedQuantity,
      savedAmount: savedAmount ?? this.savedAmount,
      addedAt: addedAt ?? this.addedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (productId.present) {
      map['product_id'] = Variable<int>(productId.value);
    }
    if (variantId.present) {
      map['variant_id'] = Variable<int>(variantId.value);
    }
    if (qty.present) {
      map['qty'] = Variable<int>(qty.value);
    }
    if (sellerId.present) {
      map['seller_id'] = Variable<int>(sellerId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (imageUrl.present) {
      map['image_url'] = Variable<String>(imageUrl.value);
    }
    if (price.present) {
      map['price'] = Variable<double>(price.value);
    }
    if (variantLabel.present) {
      map['variant_label'] = Variable<String>(variantLabel.value);
    }
    if (slug.present) {
      map['slug'] = Variable<String>(slug.value);
    }
    if (stock.present) {
      map['stock'] = Variable<int>(stock.value);
    }
    if (totalStock.present) {
      map['total_stock'] = Variable<int>(totalStock.value);
    }
    if (isUnlimitedStock.present) {
      map['is_unlimited_stock'] = Variable<int>(isUnlimitedStock.value);
    }
    if (stockStatus.present) {
      map['stock_status'] = Variable<String>(stockStatus.value);
    }
    if (totalAllowedQuantity.present) {
      map['total_allowed_quantity'] = Variable<int>(totalAllowedQuantity.value);
    }
    if (savedAmount.present) {
      map['saved_amount'] = Variable<double>(savedAmount.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<int>(addedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CartItemsCompanion(')
          ..write('productId: $productId, ')
          ..write('variantId: $variantId, ')
          ..write('qty: $qty, ')
          ..write('sellerId: $sellerId, ')
          ..write('name: $name, ')
          ..write('imageUrl: $imageUrl, ')
          ..write('price: $price, ')
          ..write('variantLabel: $variantLabel, ')
          ..write('slug: $slug, ')
          ..write('stock: $stock, ')
          ..write('totalStock: $totalStock, ')
          ..write('isUnlimitedStock: $isUnlimitedStock, ')
          ..write('stockStatus: $stockStatus, ')
          ..write('totalAllowedQuantity: $totalAllowedQuantity, ')
          ..write('savedAmount: $savedAmount, ')
          ..write('addedAt: $addedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$CatalogDatabase extends GeneratedDatabase {
  _$CatalogDatabase(QueryExecutor e) : super(e);
  $CatalogDatabaseManager get managers => $CatalogDatabaseManager(this);
  late final $CitiesTable cities = $CitiesTable(this);
  late final $CategoriesTable categories = $CategoriesTable(this);
  late final $StoresTable stores = $StoresTable(this);
  late final $ProductsTable products = $ProductsTable(this);
  late final $ProductVariantsTable productVariants = $ProductVariantsTable(
    this,
  );
  late final $CachedImagesTable cachedImages = $CachedImagesTable(this);
  late final $SyncStatesTable syncStates = $SyncStatesTable(this);
  late final $CartItemsTable cartItems = $CartItemsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    cities,
    categories,
    stores,
    products,
    productVariants,
    cachedImages,
    syncStates,
    cartItems,
  ];
}

typedef $$CitiesTableCreateCompanionBuilder =
    CitiesCompanion Function({
      Value<int> id,
      required int serverId,
      required String name,
      required String payload,
      required DateTime refreshedAt,
    });
typedef $$CitiesTableUpdateCompanionBuilder =
    CitiesCompanion Function({
      Value<int> id,
      Value<int> serverId,
      Value<String> name,
      Value<String> payload,
      Value<DateTime> refreshedAt,
    });

class $$CitiesTableFilterComposer
    extends Composer<_$CatalogDatabase, $CitiesTable> {
  $$CitiesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get refreshedAt => $composableBuilder(
    column: $table.refreshedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CitiesTableOrderingComposer
    extends Composer<_$CatalogDatabase, $CitiesTable> {
  $$CitiesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get refreshedAt => $composableBuilder(
    column: $table.refreshedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CitiesTableAnnotationComposer
    extends Composer<_$CatalogDatabase, $CitiesTable> {
  $$CitiesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get serverId =>
      $composableBuilder(column: $table.serverId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<DateTime> get refreshedAt => $composableBuilder(
    column: $table.refreshedAt,
    builder: (column) => column,
  );
}

class $$CitiesTableTableManager
    extends
        RootTableManager<
          _$CatalogDatabase,
          $CitiesTable,
          City,
          $$CitiesTableFilterComposer,
          $$CitiesTableOrderingComposer,
          $$CitiesTableAnnotationComposer,
          $$CitiesTableCreateCompanionBuilder,
          $$CitiesTableUpdateCompanionBuilder,
          (City, BaseReferences<_$CatalogDatabase, $CitiesTable, City>),
          City,
          PrefetchHooks Function()
        > {
  $$CitiesTableTableManager(_$CatalogDatabase db, $CitiesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CitiesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CitiesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CitiesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> serverId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<DateTime> refreshedAt = const Value.absent(),
              }) => CitiesCompanion(
                id: id,
                serverId: serverId,
                name: name,
                payload: payload,
                refreshedAt: refreshedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int serverId,
                required String name,
                required String payload,
                required DateTime refreshedAt,
              }) => CitiesCompanion.insert(
                id: id,
                serverId: serverId,
                name: name,
                payload: payload,
                refreshedAt: refreshedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CitiesTable, City>(table),
                  BaseReferences<_$CatalogDatabase, $CitiesTable, City>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CitiesTableProcessedTableManager =
    ProcessedTableManager<
      _$CatalogDatabase,
      $CitiesTable,
      City,
      $$CitiesTableFilterComposer,
      $$CitiesTableOrderingComposer,
      $$CitiesTableAnnotationComposer,
      $$CitiesTableCreateCompanionBuilder,
      $$CitiesTableUpdateCompanionBuilder,
      (City, BaseReferences<_$CatalogDatabase, $CitiesTable, City>),
      City,
      PrefetchHooks Function()
    >;
typedef $$CategoriesTableCreateCompanionBuilder =
    CategoriesCompanion Function({
      required String scope,
      required int serverId,
      Value<int?> parentId,
      required String name,
      Value<String?> slug,
      Value<String?> imageUrl,
      Value<int> rowOrder,
      Value<String?> type,
      required DateTime refreshedAt,
      Value<int> rowid,
    });
typedef $$CategoriesTableUpdateCompanionBuilder =
    CategoriesCompanion Function({
      Value<String> scope,
      Value<int> serverId,
      Value<int?> parentId,
      Value<String> name,
      Value<String?> slug,
      Value<String?> imageUrl,
      Value<int> rowOrder,
      Value<String?> type,
      Value<DateTime> refreshedAt,
      Value<int> rowid,
    });

class $$CategoriesTableFilterComposer
    extends Composer<_$CatalogDatabase, $CategoriesTable> {
  $$CategoriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get parentId => $composableBuilder(
    column: $table.parentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get slug => $composableBuilder(
    column: $table.slug,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get imageUrl => $composableBuilder(
    column: $table.imageUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rowOrder => $composableBuilder(
    column: $table.rowOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get refreshedAt => $composableBuilder(
    column: $table.refreshedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CategoriesTableOrderingComposer
    extends Composer<_$CatalogDatabase, $CategoriesTable> {
  $$CategoriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get parentId => $composableBuilder(
    column: $table.parentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get slug => $composableBuilder(
    column: $table.slug,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get imageUrl => $composableBuilder(
    column: $table.imageUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rowOrder => $composableBuilder(
    column: $table.rowOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get refreshedAt => $composableBuilder(
    column: $table.refreshedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CategoriesTableAnnotationComposer
    extends Composer<_$CatalogDatabase, $CategoriesTable> {
  $$CategoriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get scope =>
      $composableBuilder(column: $table.scope, builder: (column) => column);

  GeneratedColumn<int> get serverId =>
      $composableBuilder(column: $table.serverId, builder: (column) => column);

  GeneratedColumn<int> get parentId =>
      $composableBuilder(column: $table.parentId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get slug =>
      $composableBuilder(column: $table.slug, builder: (column) => column);

  GeneratedColumn<String> get imageUrl =>
      $composableBuilder(column: $table.imageUrl, builder: (column) => column);

  GeneratedColumn<int> get rowOrder =>
      $composableBuilder(column: $table.rowOrder, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<DateTime> get refreshedAt => $composableBuilder(
    column: $table.refreshedAt,
    builder: (column) => column,
  );
}

class $$CategoriesTableTableManager
    extends
        RootTableManager<
          _$CatalogDatabase,
          $CategoriesTable,
          Category,
          $$CategoriesTableFilterComposer,
          $$CategoriesTableOrderingComposer,
          $$CategoriesTableAnnotationComposer,
          $$CategoriesTableCreateCompanionBuilder,
          $$CategoriesTableUpdateCompanionBuilder,
          (
            Category,
            BaseReferences<_$CatalogDatabase, $CategoriesTable, Category>,
          ),
          Category,
          PrefetchHooks Function()
        > {
  $$CategoriesTableTableManager(_$CatalogDatabase db, $CategoriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CategoriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CategoriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CategoriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> scope = const Value.absent(),
                Value<int> serverId = const Value.absent(),
                Value<int?> parentId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> slug = const Value.absent(),
                Value<String?> imageUrl = const Value.absent(),
                Value<int> rowOrder = const Value.absent(),
                Value<String?> type = const Value.absent(),
                Value<DateTime> refreshedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CategoriesCompanion(
                scope: scope,
                serverId: serverId,
                parentId: parentId,
                name: name,
                slug: slug,
                imageUrl: imageUrl,
                rowOrder: rowOrder,
                type: type,
                refreshedAt: refreshedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String scope,
                required int serverId,
                Value<int?> parentId = const Value.absent(),
                required String name,
                Value<String?> slug = const Value.absent(),
                Value<String?> imageUrl = const Value.absent(),
                Value<int> rowOrder = const Value.absent(),
                Value<String?> type = const Value.absent(),
                required DateTime refreshedAt,
                Value<int> rowid = const Value.absent(),
              }) => CategoriesCompanion.insert(
                scope: scope,
                serverId: serverId,
                parentId: parentId,
                name: name,
                slug: slug,
                imageUrl: imageUrl,
                rowOrder: rowOrder,
                type: type,
                refreshedAt: refreshedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CategoriesTable, Category>(table),
                  BaseReferences<_$CatalogDatabase, $CategoriesTable, Category>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CategoriesTableProcessedTableManager =
    ProcessedTableManager<
      _$CatalogDatabase,
      $CategoriesTable,
      Category,
      $$CategoriesTableFilterComposer,
      $$CategoriesTableOrderingComposer,
      $$CategoriesTableAnnotationComposer,
      $$CategoriesTableCreateCompanionBuilder,
      $$CategoriesTableUpdateCompanionBuilder,
      (Category, BaseReferences<_$CatalogDatabase, $CategoriesTable, Category>),
      Category,
      PrefetchHooks Function()
    >;
typedef $$StoresTableCreateCompanionBuilder =
    StoresCompanion Function({
      required String scope,
      required int serverId,
      Value<String?> slug,
      required String name,
      Value<double?> latitude,
      Value<double?> longitude,
      Value<double> rating,
      Value<int> status,
      required String payload,
      required DateTime refreshedAt,
      required DateTime lastSeenAt,
      Value<int> rowid,
    });
typedef $$StoresTableUpdateCompanionBuilder =
    StoresCompanion Function({
      Value<String> scope,
      Value<int> serverId,
      Value<String?> slug,
      Value<String> name,
      Value<double?> latitude,
      Value<double?> longitude,
      Value<double> rating,
      Value<int> status,
      Value<String> payload,
      Value<DateTime> refreshedAt,
      Value<DateTime> lastSeenAt,
      Value<int> rowid,
    });

class $$StoresTableFilterComposer
    extends Composer<_$CatalogDatabase, $StoresTable> {
  $$StoresTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get slug => $composableBuilder(
    column: $table.slug,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get rating => $composableBuilder(
    column: $table.rating,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get refreshedAt => $composableBuilder(
    column: $table.refreshedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$StoresTableOrderingComposer
    extends Composer<_$CatalogDatabase, $StoresTable> {
  $$StoresTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get slug => $composableBuilder(
    column: $table.slug,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get rating => $composableBuilder(
    column: $table.rating,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get refreshedAt => $composableBuilder(
    column: $table.refreshedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$StoresTableAnnotationComposer
    extends Composer<_$CatalogDatabase, $StoresTable> {
  $$StoresTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get scope =>
      $composableBuilder(column: $table.scope, builder: (column) => column);

  GeneratedColumn<int> get serverId =>
      $composableBuilder(column: $table.serverId, builder: (column) => column);

  GeneratedColumn<String> get slug =>
      $composableBuilder(column: $table.slug, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<double> get latitude =>
      $composableBuilder(column: $table.latitude, builder: (column) => column);

  GeneratedColumn<double> get longitude =>
      $composableBuilder(column: $table.longitude, builder: (column) => column);

  GeneratedColumn<double> get rating =>
      $composableBuilder(column: $table.rating, builder: (column) => column);

  GeneratedColumn<int> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<DateTime> get refreshedAt => $composableBuilder(
    column: $table.refreshedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => column,
  );
}

class $$StoresTableTableManager
    extends
        RootTableManager<
          _$CatalogDatabase,
          $StoresTable,
          Store,
          $$StoresTableFilterComposer,
          $$StoresTableOrderingComposer,
          $$StoresTableAnnotationComposer,
          $$StoresTableCreateCompanionBuilder,
          $$StoresTableUpdateCompanionBuilder,
          (Store, BaseReferences<_$CatalogDatabase, $StoresTable, Store>),
          Store,
          PrefetchHooks Function()
        > {
  $$StoresTableTableManager(_$CatalogDatabase db, $StoresTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StoresTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StoresTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StoresTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> scope = const Value.absent(),
                Value<int> serverId = const Value.absent(),
                Value<String?> slug = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<double?> latitude = const Value.absent(),
                Value<double?> longitude = const Value.absent(),
                Value<double> rating = const Value.absent(),
                Value<int> status = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<DateTime> refreshedAt = const Value.absent(),
                Value<DateTime> lastSeenAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StoresCompanion(
                scope: scope,
                serverId: serverId,
                slug: slug,
                name: name,
                latitude: latitude,
                longitude: longitude,
                rating: rating,
                status: status,
                payload: payload,
                refreshedAt: refreshedAt,
                lastSeenAt: lastSeenAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String scope,
                required int serverId,
                Value<String?> slug = const Value.absent(),
                required String name,
                Value<double?> latitude = const Value.absent(),
                Value<double?> longitude = const Value.absent(),
                Value<double> rating = const Value.absent(),
                Value<int> status = const Value.absent(),
                required String payload,
                required DateTime refreshedAt,
                required DateTime lastSeenAt,
                Value<int> rowid = const Value.absent(),
              }) => StoresCompanion.insert(
                scope: scope,
                serverId: serverId,
                slug: slug,
                name: name,
                latitude: latitude,
                longitude: longitude,
                rating: rating,
                status: status,
                payload: payload,
                refreshedAt: refreshedAt,
                lastSeenAt: lastSeenAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$StoresTable, Store>(table),
                  BaseReferences<_$CatalogDatabase, $StoresTable, Store>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$StoresTableProcessedTableManager =
    ProcessedTableManager<
      _$CatalogDatabase,
      $StoresTable,
      Store,
      $$StoresTableFilterComposer,
      $$StoresTableOrderingComposer,
      $$StoresTableAnnotationComposer,
      $$StoresTableCreateCompanionBuilder,
      $$StoresTableUpdateCompanionBuilder,
      (Store, BaseReferences<_$CatalogDatabase, $StoresTable, Store>),
      Store,
      PrefetchHooks Function()
    >;
typedef $$ProductsTableCreateCompanionBuilder =
    ProductsCompanion Function({
      required String scope,
      required int serverId,
      Value<String?> slug,
      required String name,
      required int storeId,
      Value<int?> categoryId,
      required String searchBlob,
      required String priceSnapshot,
      Value<String?> thumbnailUrl,
      Value<String?> localImagePath,
      Value<double> rating,
      Value<int> status,
      Value<bool> isListed,
      Value<double?> minPrice,
      Value<bool?> inStock,
      Value<bool?> hasOffer,
      required String payload,
      required DateTime refreshedAt,
      required DateTime lastSeenAt,
      Value<int> rowid,
    });
typedef $$ProductsTableUpdateCompanionBuilder =
    ProductsCompanion Function({
      Value<String> scope,
      Value<int> serverId,
      Value<String?> slug,
      Value<String> name,
      Value<int> storeId,
      Value<int?> categoryId,
      Value<String> searchBlob,
      Value<String> priceSnapshot,
      Value<String?> thumbnailUrl,
      Value<String?> localImagePath,
      Value<double> rating,
      Value<int> status,
      Value<bool> isListed,
      Value<double?> minPrice,
      Value<bool?> inStock,
      Value<bool?> hasOffer,
      Value<String> payload,
      Value<DateTime> refreshedAt,
      Value<DateTime> lastSeenAt,
      Value<int> rowid,
    });

class $$ProductsTableFilterComposer
    extends Composer<_$CatalogDatabase, $ProductsTable> {
  $$ProductsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get slug => $composableBuilder(
    column: $table.slug,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get storeId => $composableBuilder(
    column: $table.storeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get searchBlob => $composableBuilder(
    column: $table.searchBlob,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get priceSnapshot => $composableBuilder(
    column: $table.priceSnapshot,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get thumbnailUrl => $composableBuilder(
    column: $table.thumbnailUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localImagePath => $composableBuilder(
    column: $table.localImagePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get rating => $composableBuilder(
    column: $table.rating,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isListed => $composableBuilder(
    column: $table.isListed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get minPrice => $composableBuilder(
    column: $table.minPrice,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get inStock => $composableBuilder(
    column: $table.inStock,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get hasOffer => $composableBuilder(
    column: $table.hasOffer,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get refreshedAt => $composableBuilder(
    column: $table.refreshedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ProductsTableOrderingComposer
    extends Composer<_$CatalogDatabase, $ProductsTable> {
  $$ProductsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get slug => $composableBuilder(
    column: $table.slug,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get storeId => $composableBuilder(
    column: $table.storeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get searchBlob => $composableBuilder(
    column: $table.searchBlob,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get priceSnapshot => $composableBuilder(
    column: $table.priceSnapshot,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get thumbnailUrl => $composableBuilder(
    column: $table.thumbnailUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localImagePath => $composableBuilder(
    column: $table.localImagePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get rating => $composableBuilder(
    column: $table.rating,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isListed => $composableBuilder(
    column: $table.isListed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get minPrice => $composableBuilder(
    column: $table.minPrice,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get inStock => $composableBuilder(
    column: $table.inStock,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get hasOffer => $composableBuilder(
    column: $table.hasOffer,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get refreshedAt => $composableBuilder(
    column: $table.refreshedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProductsTableAnnotationComposer
    extends Composer<_$CatalogDatabase, $ProductsTable> {
  $$ProductsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get scope =>
      $composableBuilder(column: $table.scope, builder: (column) => column);

  GeneratedColumn<int> get serverId =>
      $composableBuilder(column: $table.serverId, builder: (column) => column);

  GeneratedColumn<String> get slug =>
      $composableBuilder(column: $table.slug, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get storeId =>
      $composableBuilder(column: $table.storeId, builder: (column) => column);

  GeneratedColumn<int> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get searchBlob => $composableBuilder(
    column: $table.searchBlob,
    builder: (column) => column,
  );

  GeneratedColumn<String> get priceSnapshot => $composableBuilder(
    column: $table.priceSnapshot,
    builder: (column) => column,
  );

  GeneratedColumn<String> get thumbnailUrl => $composableBuilder(
    column: $table.thumbnailUrl,
    builder: (column) => column,
  );

  GeneratedColumn<String> get localImagePath => $composableBuilder(
    column: $table.localImagePath,
    builder: (column) => column,
  );

  GeneratedColumn<double> get rating =>
      $composableBuilder(column: $table.rating, builder: (column) => column);

  GeneratedColumn<int> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<bool> get isListed =>
      $composableBuilder(column: $table.isListed, builder: (column) => column);

  GeneratedColumn<double> get minPrice =>
      $composableBuilder(column: $table.minPrice, builder: (column) => column);

  GeneratedColumn<bool> get inStock =>
      $composableBuilder(column: $table.inStock, builder: (column) => column);

  GeneratedColumn<bool> get hasOffer =>
      $composableBuilder(column: $table.hasOffer, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<DateTime> get refreshedAt => $composableBuilder(
    column: $table.refreshedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => column,
  );
}

class $$ProductsTableTableManager
    extends
        RootTableManager<
          _$CatalogDatabase,
          $ProductsTable,
          Product,
          $$ProductsTableFilterComposer,
          $$ProductsTableOrderingComposer,
          $$ProductsTableAnnotationComposer,
          $$ProductsTableCreateCompanionBuilder,
          $$ProductsTableUpdateCompanionBuilder,
          (Product, BaseReferences<_$CatalogDatabase, $ProductsTable, Product>),
          Product,
          PrefetchHooks Function()
        > {
  $$ProductsTableTableManager(_$CatalogDatabase db, $ProductsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProductsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProductsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProductsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> scope = const Value.absent(),
                Value<int> serverId = const Value.absent(),
                Value<String?> slug = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> storeId = const Value.absent(),
                Value<int?> categoryId = const Value.absent(),
                Value<String> searchBlob = const Value.absent(),
                Value<String> priceSnapshot = const Value.absent(),
                Value<String?> thumbnailUrl = const Value.absent(),
                Value<String?> localImagePath = const Value.absent(),
                Value<double> rating = const Value.absent(),
                Value<int> status = const Value.absent(),
                Value<bool> isListed = const Value.absent(),
                Value<double?> minPrice = const Value.absent(),
                Value<bool?> inStock = const Value.absent(),
                Value<bool?> hasOffer = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<DateTime> refreshedAt = const Value.absent(),
                Value<DateTime> lastSeenAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProductsCompanion(
                scope: scope,
                serverId: serverId,
                slug: slug,
                name: name,
                storeId: storeId,
                categoryId: categoryId,
                searchBlob: searchBlob,
                priceSnapshot: priceSnapshot,
                thumbnailUrl: thumbnailUrl,
                localImagePath: localImagePath,
                rating: rating,
                status: status,
                isListed: isListed,
                minPrice: minPrice,
                inStock: inStock,
                hasOffer: hasOffer,
                payload: payload,
                refreshedAt: refreshedAt,
                lastSeenAt: lastSeenAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String scope,
                required int serverId,
                Value<String?> slug = const Value.absent(),
                required String name,
                required int storeId,
                Value<int?> categoryId = const Value.absent(),
                required String searchBlob,
                required String priceSnapshot,
                Value<String?> thumbnailUrl = const Value.absent(),
                Value<String?> localImagePath = const Value.absent(),
                Value<double> rating = const Value.absent(),
                Value<int> status = const Value.absent(),
                Value<bool> isListed = const Value.absent(),
                Value<double?> minPrice = const Value.absent(),
                Value<bool?> inStock = const Value.absent(),
                Value<bool?> hasOffer = const Value.absent(),
                required String payload,
                required DateTime refreshedAt,
                required DateTime lastSeenAt,
                Value<int> rowid = const Value.absent(),
              }) => ProductsCompanion.insert(
                scope: scope,
                serverId: serverId,
                slug: slug,
                name: name,
                storeId: storeId,
                categoryId: categoryId,
                searchBlob: searchBlob,
                priceSnapshot: priceSnapshot,
                thumbnailUrl: thumbnailUrl,
                localImagePath: localImagePath,
                rating: rating,
                status: status,
                isListed: isListed,
                minPrice: minPrice,
                inStock: inStock,
                hasOffer: hasOffer,
                payload: payload,
                refreshedAt: refreshedAt,
                lastSeenAt: lastSeenAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ProductsTable, Product>(table),
                  BaseReferences<_$CatalogDatabase, $ProductsTable, Product>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ProductsTableProcessedTableManager =
    ProcessedTableManager<
      _$CatalogDatabase,
      $ProductsTable,
      Product,
      $$ProductsTableFilterComposer,
      $$ProductsTableOrderingComposer,
      $$ProductsTableAnnotationComposer,
      $$ProductsTableCreateCompanionBuilder,
      $$ProductsTableUpdateCompanionBuilder,
      (Product, BaseReferences<_$CatalogDatabase, $ProductsTable, Product>),
      Product,
      PrefetchHooks Function()
    >;
typedef $$ProductVariantsTableCreateCompanionBuilder =
    ProductVariantsCompanion Function({
      required String scope,
      required int serverId,
      required int productId,
      required String payload,
      required DateTime refreshedAt,
      Value<int> rowid,
    });
typedef $$ProductVariantsTableUpdateCompanionBuilder =
    ProductVariantsCompanion Function({
      Value<String> scope,
      Value<int> serverId,
      Value<int> productId,
      Value<String> payload,
      Value<DateTime> refreshedAt,
      Value<int> rowid,
    });

class $$ProductVariantsTableFilterComposer
    extends Composer<_$CatalogDatabase, $ProductVariantsTable> {
  $$ProductVariantsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get productId => $composableBuilder(
    column: $table.productId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get refreshedAt => $composableBuilder(
    column: $table.refreshedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ProductVariantsTableOrderingComposer
    extends Composer<_$CatalogDatabase, $ProductVariantsTable> {
  $$ProductVariantsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get productId => $composableBuilder(
    column: $table.productId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get refreshedAt => $composableBuilder(
    column: $table.refreshedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProductVariantsTableAnnotationComposer
    extends Composer<_$CatalogDatabase, $ProductVariantsTable> {
  $$ProductVariantsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get scope =>
      $composableBuilder(column: $table.scope, builder: (column) => column);

  GeneratedColumn<int> get serverId =>
      $composableBuilder(column: $table.serverId, builder: (column) => column);

  GeneratedColumn<int> get productId =>
      $composableBuilder(column: $table.productId, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<DateTime> get refreshedAt => $composableBuilder(
    column: $table.refreshedAt,
    builder: (column) => column,
  );
}

class $$ProductVariantsTableTableManager
    extends
        RootTableManager<
          _$CatalogDatabase,
          $ProductVariantsTable,
          ProductVariant,
          $$ProductVariantsTableFilterComposer,
          $$ProductVariantsTableOrderingComposer,
          $$ProductVariantsTableAnnotationComposer,
          $$ProductVariantsTableCreateCompanionBuilder,
          $$ProductVariantsTableUpdateCompanionBuilder,
          (
            ProductVariant,
            BaseReferences<
              _$CatalogDatabase,
              $ProductVariantsTable,
              ProductVariant
            >,
          ),
          ProductVariant,
          PrefetchHooks Function()
        > {
  $$ProductVariantsTableTableManager(
    _$CatalogDatabase db,
    $ProductVariantsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProductVariantsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProductVariantsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProductVariantsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> scope = const Value.absent(),
                Value<int> serverId = const Value.absent(),
                Value<int> productId = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<DateTime> refreshedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProductVariantsCompanion(
                scope: scope,
                serverId: serverId,
                productId: productId,
                payload: payload,
                refreshedAt: refreshedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String scope,
                required int serverId,
                required int productId,
                required String payload,
                required DateTime refreshedAt,
                Value<int> rowid = const Value.absent(),
              }) => ProductVariantsCompanion.insert(
                scope: scope,
                serverId: serverId,
                productId: productId,
                payload: payload,
                refreshedAt: refreshedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ProductVariantsTable, ProductVariant>(table),
                  BaseReferences<
                    _$CatalogDatabase,
                    $ProductVariantsTable,
                    ProductVariant
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ProductVariantsTableProcessedTableManager =
    ProcessedTableManager<
      _$CatalogDatabase,
      $ProductVariantsTable,
      ProductVariant,
      $$ProductVariantsTableFilterComposer,
      $$ProductVariantsTableOrderingComposer,
      $$ProductVariantsTableAnnotationComposer,
      $$ProductVariantsTableCreateCompanionBuilder,
      $$ProductVariantsTableUpdateCompanionBuilder,
      (
        ProductVariant,
        BaseReferences<
          _$CatalogDatabase,
          $ProductVariantsTable,
          ProductVariant
        >,
      ),
      ProductVariant,
      PrefetchHooks Function()
    >;
typedef $$CachedImagesTableCreateCompanionBuilder =
    CachedImagesCompanion Function({
      required String url,
      required String localPath,
      required int bytes,
      required DateTime lastUsedAt,
      Value<int> rowid,
    });
typedef $$CachedImagesTableUpdateCompanionBuilder =
    CachedImagesCompanion Function({
      Value<String> url,
      Value<String> localPath,
      Value<int> bytes,
      Value<DateTime> lastUsedAt,
      Value<int> rowid,
    });

class $$CachedImagesTableFilterComposer
    extends Composer<_$CatalogDatabase, $CachedImagesTable> {
  $$CachedImagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get bytes => $composableBuilder(
    column: $table.bytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastUsedAt => $composableBuilder(
    column: $table.lastUsedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedImagesTableOrderingComposer
    extends Composer<_$CatalogDatabase, $CachedImagesTable> {
  $$CachedImagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get bytes => $composableBuilder(
    column: $table.bytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastUsedAt => $composableBuilder(
    column: $table.lastUsedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedImagesTableAnnotationComposer
    extends Composer<_$CatalogDatabase, $CachedImagesTable> {
  $$CachedImagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get url =>
      $composableBuilder(column: $table.url, builder: (column) => column);

  GeneratedColumn<String> get localPath =>
      $composableBuilder(column: $table.localPath, builder: (column) => column);

  GeneratedColumn<int> get bytes =>
      $composableBuilder(column: $table.bytes, builder: (column) => column);

  GeneratedColumn<DateTime> get lastUsedAt => $composableBuilder(
    column: $table.lastUsedAt,
    builder: (column) => column,
  );
}

class $$CachedImagesTableTableManager
    extends
        RootTableManager<
          _$CatalogDatabase,
          $CachedImagesTable,
          CachedImage,
          $$CachedImagesTableFilterComposer,
          $$CachedImagesTableOrderingComposer,
          $$CachedImagesTableAnnotationComposer,
          $$CachedImagesTableCreateCompanionBuilder,
          $$CachedImagesTableUpdateCompanionBuilder,
          (
            CachedImage,
            BaseReferences<_$CatalogDatabase, $CachedImagesTable, CachedImage>,
          ),
          CachedImage,
          PrefetchHooks Function()
        > {
  $$CachedImagesTableTableManager(
    _$CatalogDatabase db,
    $CachedImagesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedImagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedImagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedImagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> url = const Value.absent(),
                Value<String> localPath = const Value.absent(),
                Value<int> bytes = const Value.absent(),
                Value<DateTime> lastUsedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedImagesCompanion(
                url: url,
                localPath: localPath,
                bytes: bytes,
                lastUsedAt: lastUsedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String url,
                required String localPath,
                required int bytes,
                required DateTime lastUsedAt,
                Value<int> rowid = const Value.absent(),
              }) => CachedImagesCompanion.insert(
                url: url,
                localPath: localPath,
                bytes: bytes,
                lastUsedAt: lastUsedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CachedImagesTable, CachedImage>(table),
                  BaseReferences<
                    _$CatalogDatabase,
                    $CachedImagesTable,
                    CachedImage
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedImagesTableProcessedTableManager =
    ProcessedTableManager<
      _$CatalogDatabase,
      $CachedImagesTable,
      CachedImage,
      $$CachedImagesTableFilterComposer,
      $$CachedImagesTableOrderingComposer,
      $$CachedImagesTableAnnotationComposer,
      $$CachedImagesTableCreateCompanionBuilder,
      $$CachedImagesTableUpdateCompanionBuilder,
      (
        CachedImage,
        BaseReferences<_$CatalogDatabase, $CachedImagesTable, CachedImage>,
      ),
      CachedImage,
      PrefetchHooks Function()
    >;
typedef $$SyncStatesTableCreateCompanionBuilder =
    SyncStatesCompanion Function({
      required String scope,
      required String phase,
      Value<String> coverage,
      Value<int> lastOffset,
      Value<String?> lastCreatedAt,
      Value<int> lastId,
      Value<int> serverTotal,
      Value<int> storedCount,
      Value<String?> checkpoint,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$SyncStatesTableUpdateCompanionBuilder =
    SyncStatesCompanion Function({
      Value<String> scope,
      Value<String> phase,
      Value<String> coverage,
      Value<int> lastOffset,
      Value<String?> lastCreatedAt,
      Value<int> lastId,
      Value<int> serverTotal,
      Value<int> storedCount,
      Value<String?> checkpoint,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$SyncStatesTableFilterComposer
    extends Composer<_$CatalogDatabase, $SyncStatesTable> {
  $$SyncStatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get phase => $composableBuilder(
    column: $table.phase,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coverage => $composableBuilder(
    column: $table.coverage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastOffset => $composableBuilder(
    column: $table.lastOffset,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastCreatedAt => $composableBuilder(
    column: $table.lastCreatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastId => $composableBuilder(
    column: $table.lastId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get serverTotal => $composableBuilder(
    column: $table.serverTotal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get storedCount => $composableBuilder(
    column: $table.storedCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get checkpoint => $composableBuilder(
    column: $table.checkpoint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncStatesTableOrderingComposer
    extends Composer<_$CatalogDatabase, $SyncStatesTable> {
  $$SyncStatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get phase => $composableBuilder(
    column: $table.phase,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coverage => $composableBuilder(
    column: $table.coverage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastOffset => $composableBuilder(
    column: $table.lastOffset,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastCreatedAt => $composableBuilder(
    column: $table.lastCreatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastId => $composableBuilder(
    column: $table.lastId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get serverTotal => $composableBuilder(
    column: $table.serverTotal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get storedCount => $composableBuilder(
    column: $table.storedCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get checkpoint => $composableBuilder(
    column: $table.checkpoint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncStatesTableAnnotationComposer
    extends Composer<_$CatalogDatabase, $SyncStatesTable> {
  $$SyncStatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get scope =>
      $composableBuilder(column: $table.scope, builder: (column) => column);

  GeneratedColumn<String> get phase =>
      $composableBuilder(column: $table.phase, builder: (column) => column);

  GeneratedColumn<String> get coverage =>
      $composableBuilder(column: $table.coverage, builder: (column) => column);

  GeneratedColumn<int> get lastOffset => $composableBuilder(
    column: $table.lastOffset,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastCreatedAt => $composableBuilder(
    column: $table.lastCreatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastId =>
      $composableBuilder(column: $table.lastId, builder: (column) => column);

  GeneratedColumn<int> get serverTotal => $composableBuilder(
    column: $table.serverTotal,
    builder: (column) => column,
  );

  GeneratedColumn<int> get storedCount => $composableBuilder(
    column: $table.storedCount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get checkpoint => $composableBuilder(
    column: $table.checkpoint,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$SyncStatesTableTableManager
    extends
        RootTableManager<
          _$CatalogDatabase,
          $SyncStatesTable,
          SyncState,
          $$SyncStatesTableFilterComposer,
          $$SyncStatesTableOrderingComposer,
          $$SyncStatesTableAnnotationComposer,
          $$SyncStatesTableCreateCompanionBuilder,
          $$SyncStatesTableUpdateCompanionBuilder,
          (
            SyncState,
            BaseReferences<_$CatalogDatabase, $SyncStatesTable, SyncState>,
          ),
          SyncState,
          PrefetchHooks Function()
        > {
  $$SyncStatesTableTableManager(_$CatalogDatabase db, $SyncStatesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncStatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncStatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncStatesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> scope = const Value.absent(),
                Value<String> phase = const Value.absent(),
                Value<String> coverage = const Value.absent(),
                Value<int> lastOffset = const Value.absent(),
                Value<String?> lastCreatedAt = const Value.absent(),
                Value<int> lastId = const Value.absent(),
                Value<int> serverTotal = const Value.absent(),
                Value<int> storedCount = const Value.absent(),
                Value<String?> checkpoint = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncStatesCompanion(
                scope: scope,
                phase: phase,
                coverage: coverage,
                lastOffset: lastOffset,
                lastCreatedAt: lastCreatedAt,
                lastId: lastId,
                serverTotal: serverTotal,
                storedCount: storedCount,
                checkpoint: checkpoint,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String scope,
                required String phase,
                Value<String> coverage = const Value.absent(),
                Value<int> lastOffset = const Value.absent(),
                Value<String?> lastCreatedAt = const Value.absent(),
                Value<int> lastId = const Value.absent(),
                Value<int> serverTotal = const Value.absent(),
                Value<int> storedCount = const Value.absent(),
                Value<String?> checkpoint = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => SyncStatesCompanion.insert(
                scope: scope,
                phase: phase,
                coverage: coverage,
                lastOffset: lastOffset,
                lastCreatedAt: lastCreatedAt,
                lastId: lastId,
                serverTotal: serverTotal,
                storedCount: storedCount,
                checkpoint: checkpoint,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SyncStatesTable, SyncState>(table),
                  BaseReferences<
                    _$CatalogDatabase,
                    $SyncStatesTable,
                    SyncState
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncStatesTableProcessedTableManager =
    ProcessedTableManager<
      _$CatalogDatabase,
      $SyncStatesTable,
      SyncState,
      $$SyncStatesTableFilterComposer,
      $$SyncStatesTableOrderingComposer,
      $$SyncStatesTableAnnotationComposer,
      $$SyncStatesTableCreateCompanionBuilder,
      $$SyncStatesTableUpdateCompanionBuilder,
      (
        SyncState,
        BaseReferences<_$CatalogDatabase, $SyncStatesTable, SyncState>,
      ),
      SyncState,
      PrefetchHooks Function()
    >;
typedef $$CartItemsTableCreateCompanionBuilder =
    CartItemsCompanion Function({
      required int productId,
      required int variantId,
      Value<int> qty,
      required int sellerId,
      required String name,
      required String imageUrl,
      required double price,
      Value<String?> variantLabel,
      Value<String?> slug,
      Value<int?> stock,
      Value<int?> totalStock,
      Value<int> isUnlimitedStock,
      Value<String?> stockStatus,
      Value<int?> totalAllowedQuantity,
      Value<double?> savedAmount,
      required int addedAt,
      Value<int> rowid,
    });
typedef $$CartItemsTableUpdateCompanionBuilder =
    CartItemsCompanion Function({
      Value<int> productId,
      Value<int> variantId,
      Value<int> qty,
      Value<int> sellerId,
      Value<String> name,
      Value<String> imageUrl,
      Value<double> price,
      Value<String?> variantLabel,
      Value<String?> slug,
      Value<int?> stock,
      Value<int?> totalStock,
      Value<int> isUnlimitedStock,
      Value<String?> stockStatus,
      Value<int?> totalAllowedQuantity,
      Value<double?> savedAmount,
      Value<int> addedAt,
      Value<int> rowid,
    });

class $$CartItemsTableFilterComposer
    extends Composer<_$CatalogDatabase, $CartItemsTable> {
  $$CartItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get productId => $composableBuilder(
    column: $table.productId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get variantId => $composableBuilder(
    column: $table.variantId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get qty => $composableBuilder(
    column: $table.qty,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sellerId => $composableBuilder(
    column: $table.sellerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get imageUrl => $composableBuilder(
    column: $table.imageUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get price => $composableBuilder(
    column: $table.price,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get variantLabel => $composableBuilder(
    column: $table.variantLabel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get slug => $composableBuilder(
    column: $table.slug,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get stock => $composableBuilder(
    column: $table.stock,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalStock => $composableBuilder(
    column: $table.totalStock,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get isUnlimitedStock => $composableBuilder(
    column: $table.isUnlimitedStock,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get stockStatus => $composableBuilder(
    column: $table.stockStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalAllowedQuantity => $composableBuilder(
    column: $table.totalAllowedQuantity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get savedAmount => $composableBuilder(
    column: $table.savedAmount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CartItemsTableOrderingComposer
    extends Composer<_$CatalogDatabase, $CartItemsTable> {
  $$CartItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get productId => $composableBuilder(
    column: $table.productId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get variantId => $composableBuilder(
    column: $table.variantId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get qty => $composableBuilder(
    column: $table.qty,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sellerId => $composableBuilder(
    column: $table.sellerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get imageUrl => $composableBuilder(
    column: $table.imageUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get price => $composableBuilder(
    column: $table.price,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get variantLabel => $composableBuilder(
    column: $table.variantLabel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get slug => $composableBuilder(
    column: $table.slug,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get stock => $composableBuilder(
    column: $table.stock,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalStock => $composableBuilder(
    column: $table.totalStock,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get isUnlimitedStock => $composableBuilder(
    column: $table.isUnlimitedStock,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get stockStatus => $composableBuilder(
    column: $table.stockStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalAllowedQuantity => $composableBuilder(
    column: $table.totalAllowedQuantity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get savedAmount => $composableBuilder(
    column: $table.savedAmount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CartItemsTableAnnotationComposer
    extends Composer<_$CatalogDatabase, $CartItemsTable> {
  $$CartItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get productId =>
      $composableBuilder(column: $table.productId, builder: (column) => column);

  GeneratedColumn<int> get variantId =>
      $composableBuilder(column: $table.variantId, builder: (column) => column);

  GeneratedColumn<int> get qty =>
      $composableBuilder(column: $table.qty, builder: (column) => column);

  GeneratedColumn<int> get sellerId =>
      $composableBuilder(column: $table.sellerId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get imageUrl =>
      $composableBuilder(column: $table.imageUrl, builder: (column) => column);

  GeneratedColumn<double> get price =>
      $composableBuilder(column: $table.price, builder: (column) => column);

  GeneratedColumn<String> get variantLabel => $composableBuilder(
    column: $table.variantLabel,
    builder: (column) => column,
  );

  GeneratedColumn<String> get slug =>
      $composableBuilder(column: $table.slug, builder: (column) => column);

  GeneratedColumn<int> get stock =>
      $composableBuilder(column: $table.stock, builder: (column) => column);

  GeneratedColumn<int> get totalStock => $composableBuilder(
    column: $table.totalStock,
    builder: (column) => column,
  );

  GeneratedColumn<int> get isUnlimitedStock => $composableBuilder(
    column: $table.isUnlimitedStock,
    builder: (column) => column,
  );

  GeneratedColumn<String> get stockStatus => $composableBuilder(
    column: $table.stockStatus,
    builder: (column) => column,
  );

  GeneratedColumn<int> get totalAllowedQuantity => $composableBuilder(
    column: $table.totalAllowedQuantity,
    builder: (column) => column,
  );

  GeneratedColumn<double> get savedAmount => $composableBuilder(
    column: $table.savedAmount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);
}

class $$CartItemsTableTableManager
    extends
        RootTableManager<
          _$CatalogDatabase,
          $CartItemsTable,
          CartItem,
          $$CartItemsTableFilterComposer,
          $$CartItemsTableOrderingComposer,
          $$CartItemsTableAnnotationComposer,
          $$CartItemsTableCreateCompanionBuilder,
          $$CartItemsTableUpdateCompanionBuilder,
          (
            CartItem,
            BaseReferences<_$CatalogDatabase, $CartItemsTable, CartItem>,
          ),
          CartItem,
          PrefetchHooks Function()
        > {
  $$CartItemsTableTableManager(_$CatalogDatabase db, $CartItemsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CartItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CartItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CartItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> productId = const Value.absent(),
                Value<int> variantId = const Value.absent(),
                Value<int> qty = const Value.absent(),
                Value<int> sellerId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> imageUrl = const Value.absent(),
                Value<double> price = const Value.absent(),
                Value<String?> variantLabel = const Value.absent(),
                Value<String?> slug = const Value.absent(),
                Value<int?> stock = const Value.absent(),
                Value<int?> totalStock = const Value.absent(),
                Value<int> isUnlimitedStock = const Value.absent(),
                Value<String?> stockStatus = const Value.absent(),
                Value<int?> totalAllowedQuantity = const Value.absent(),
                Value<double?> savedAmount = const Value.absent(),
                Value<int> addedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CartItemsCompanion(
                productId: productId,
                variantId: variantId,
                qty: qty,
                sellerId: sellerId,
                name: name,
                imageUrl: imageUrl,
                price: price,
                variantLabel: variantLabel,
                slug: slug,
                stock: stock,
                totalStock: totalStock,
                isUnlimitedStock: isUnlimitedStock,
                stockStatus: stockStatus,
                totalAllowedQuantity: totalAllowedQuantity,
                savedAmount: savedAmount,
                addedAt: addedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int productId,
                required int variantId,
                Value<int> qty = const Value.absent(),
                required int sellerId,
                required String name,
                required String imageUrl,
                required double price,
                Value<String?> variantLabel = const Value.absent(),
                Value<String?> slug = const Value.absent(),
                Value<int?> stock = const Value.absent(),
                Value<int?> totalStock = const Value.absent(),
                Value<int> isUnlimitedStock = const Value.absent(),
                Value<String?> stockStatus = const Value.absent(),
                Value<int?> totalAllowedQuantity = const Value.absent(),
                Value<double?> savedAmount = const Value.absent(),
                required int addedAt,
                Value<int> rowid = const Value.absent(),
              }) => CartItemsCompanion.insert(
                productId: productId,
                variantId: variantId,
                qty: qty,
                sellerId: sellerId,
                name: name,
                imageUrl: imageUrl,
                price: price,
                variantLabel: variantLabel,
                slug: slug,
                stock: stock,
                totalStock: totalStock,
                isUnlimitedStock: isUnlimitedStock,
                stockStatus: stockStatus,
                totalAllowedQuantity: totalAllowedQuantity,
                savedAmount: savedAmount,
                addedAt: addedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CartItemsTable, CartItem>(table),
                  BaseReferences<_$CatalogDatabase, $CartItemsTable, CartItem>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CartItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$CatalogDatabase,
      $CartItemsTable,
      CartItem,
      $$CartItemsTableFilterComposer,
      $$CartItemsTableOrderingComposer,
      $$CartItemsTableAnnotationComposer,
      $$CartItemsTableCreateCompanionBuilder,
      $$CartItemsTableUpdateCompanionBuilder,
      (CartItem, BaseReferences<_$CatalogDatabase, $CartItemsTable, CartItem>),
      CartItem,
      PrefetchHooks Function()
    >;

class $CatalogDatabaseManager {
  final _$CatalogDatabase _db;
  $CatalogDatabaseManager(this._db);
  $$CitiesTableTableManager get cities =>
      $$CitiesTableTableManager(_db, _db.cities);
  $$CategoriesTableTableManager get categories =>
      $$CategoriesTableTableManager(_db, _db.categories);
  $$StoresTableTableManager get stores =>
      $$StoresTableTableManager(_db, _db.stores);
  $$ProductsTableTableManager get products =>
      $$ProductsTableTableManager(_db, _db.products);
  $$ProductVariantsTableTableManager get productVariants =>
      $$ProductVariantsTableTableManager(_db, _db.productVariants);
  $$CachedImagesTableTableManager get cachedImages =>
      $$CachedImagesTableTableManager(_db, _db.cachedImages);
  $$SyncStatesTableTableManager get syncStates =>
      $$SyncStatesTableTableManager(_db, _db.syncStates);
  $$CartItemsTableTableManager get cartItems =>
      $$CartItemsTableTableManager(_db, _db.cartItems);
}
