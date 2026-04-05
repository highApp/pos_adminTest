import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:uuid/uuid.dart';

import '../offline/sync_status.dart';

part 'app_database.g.dart';

/// Outbound sync queue: every mutation is appended here after the local row is committed.
class SyncQueueEntries extends Table {
  /// Monotonic primary key (ordering for FIFO sync).
  IntColumn get localId => integer().autoIncrement()();

  /// Stable idempotency key (e.g. UUID) — use the same id when retrying a logical operation.
  TextColumn get id => text().unique()();

  TextColumn get actionType => text()();

  /// Firestore collection name (SQL column `table_name`). Not named [tableName]
  /// because that conflicts with Drift's [Table.tableName].
  TextColumn get dataTable => text().named('table_name')();

  /// Server / Firestore document id when known (nullable for creates before assign).
  TextColumn get entityId => text().nullable()();

  TextColumn get dataJson => text()();

  /// Queue-level completion flag (distinct from row [SyncStatus] on domain tables).
  BoolColumn get synced =>
      boolean().withDefault(const Constant(false))();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
}

/// Local authoritative copy of a sale until Firestore acknowledges it.
class LocalSales extends Table {
  TextColumn get id => text()();

  /// Full document payload matching Firestore shape (include `updatedAt` for LWW).
  TextColumn get dataJson => text()();

  IntColumn get syncStatus =>
      integer().withDefault(const Constant(SyncStatus.pending))();

  DateTimeColumn get updatedAt => dateTime()();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [SyncQueueEntries, LocalSales])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? e]) : super(e ?? _openConnection());

  @override
  int get schemaVersion => 1;

  /// Pending queue rows, oldest first.
  Future<List<SyncQueueEntry>> pendingQueue({int limit = 100}) {
    return (select(syncQueueEntries)
          ..where((q) => q.synced.equals(false))
          ..orderBy([(q) => OrderingTerm.asc(q.createdAt)])
          ..limit(limit))
        .get();
  }

  Future<int> pendingOutboundCount() async {
    final q = await (select(syncQueueEntries)
          ..where((t) => t.synced.equals(false)))
        .get();
    return q.length;
  }

  Future<void> markQueueSynced(int localId) {
    return (update(syncQueueEntries)..where((q) => q.localId.equals(localId)))
        .write(SyncQueueEntriesCompanion(synced: Value(true)));
  }

  /// Append after the corresponding domain row is committed locally.
  /// Returns [localId] for marking the row synced after a successful remote write.
  Future<int> enqueueSyncOperation({
    required String operationId,
    required String actionType,
    required String tableName,
    required String dataJson,
    String? entityId,
  }) {
    return into(syncQueueEntries).insert(
      SyncQueueEntriesCompanion.insert(
        id: operationId,
        actionType: actionType,
        dataTable: tableName,
        dataJson: dataJson,
        entityId: Value(entityId),
      ),
    );
  }

  Future<void> markLocalSaleRemoteSynced(String saleId) {
    return (update(localSales)..where((t) => t.id.equals(saleId))).write(
      LocalSalesCompanion(
        syncStatus: const Value(SyncStatus.synced),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  Future<void> upsertLocalSale({
    required String id,
    required String dataJson,
    required DateTime updatedAt,
    int syncStatus = SyncStatus.pending,
  }) {
    return into(localSales).insertOnConflictUpdate(
      LocalSalesCompanion.insert(
        id: id,
        dataJson: dataJson,
        syncStatus: Value(syncStatus),
        updatedAt: updatedAt,
      ),
    );
  }

  /// Queue Firestore `stock` field increments (negative = sold qty) for offline sales.
  Future<void> enqueueStockDecrements(Map<String, double> quantitiesByProductId) async {
    if (quantitiesByProductId.isEmpty) return;
    final now = DateTime.now().toUtc().toIso8601String();
    await transaction(() async {
      for (final e in quantitiesByProductId.entries) {
        if (e.value <= 0) continue;
        final payload = jsonEncode({
          'delta': -e.value,
          'updatedAt': now,
        });
        await enqueueSyncOperation(
          operationId: const Uuid().v4(),
          actionType: 'stock_delta',
          tableName: 'products',
          dataJson: payload,
          entityId: e.key,
        );
      }
    });
  }

  /// After the sale row is queued, enqueue seller credit / dues / history replay (offline POS only).
  /// Processed only once [sellerSideEffectsSynced] is false and `sales/{saleId}` exists on Firestore.
  Future<int> enqueueSellerPostSaleReplay({
    required String saleId,
    required Map<String, dynamic> payload,
  }) {
    return enqueueSyncOperation(
      operationId: const Uuid().v4(),
      actionType: 'seller_post_sale',
      tableName: 'sales',
      dataJson: jsonEncode(payload),
      entityId: saleId,
    );
  }
}

QueryExecutor _openConnection() => driftDatabase(name: 'pos_offline');
