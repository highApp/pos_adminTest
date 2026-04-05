import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../database/app_database.dart';
import '../services/seller_pos_checkout_replay.dart';
import 'sync_status.dart';

/// Example: push each pending queue row to Firestore, then mark the queue row synced.
///
/// - Call when [ConnectivityWatcher] reports online and on app resume.
/// - Use a single [syncPendingIfNeeded] flight at a time ([_running] guard).
/// - For higher throughput, group into [WriteBatch] (max 500 ops) after validating
///   all payloads; if any op fails, fall back to per-document writes.
class ExampleFirestoreSyncService {
  ExampleFirestoreSyncService({
    required AppDatabase db,
    FirebaseFirestore? firestore,
  })  : _db = db,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final AppDatabase _db;
  final FirebaseFirestore _firestore;

  bool _running = false;

  Future<void> syncPendingIfNeeded() async {
    if (_running) return;
    _running = true;
    try {
      final pending = await _db.pendingQueue(limit: 500);
      for (final row in pending) {
        try {
          final map = jsonDecode(row.dataJson) as Map<String, dynamic>;
          final docId = row.entityId ?? (map['id'] as String?);
          if (docId == null || docId.isEmpty) {
            debugPrint('Sync skip localId=${row.localId}: missing document id');
            continue;
          }
          final ref = _firestore.collection(row.dataTable).doc(docId);

          switch (row.actionType) {
            case 'create':
              if (row.dataTable == 'sales') {
                final sellerReplay =
                    SellerPosCheckoutReplay.decodeSellerReplayFromQueuedSale(map);
                final clean =
                    SellerPosCheckoutReplay.stripQueuedMetadataForFirestore(map);
                await ref.set(clean);
                if (sellerReplay != null && sellerReplay.isNotEmpty) {
                  final outcome =
                      await SellerPosCheckoutReplay.replayFromQueuePayload(
                    firestore: _firestore,
                    saleId: docId,
                    payload: sellerReplay,
                  );
                  if (outcome ==
                      SellerPostSaleReplayOutcome.saleDocumentMissing) {
                    throw StateError(
                      'Sale $docId missing immediately after create',
                    );
                  }
                }
              } else {
                await ref.set(map);
              }
              break;
            case 'update':
              await ref.set(map, SetOptions(merge: true));
              break;
            case 'delete':
              await ref.delete();
              break;
            case 'stock_delta':
              if (row.dataTable != 'products') {
                debugPrint('stock_delta expects products collection');
                await _db.markQueueSynced(row.localId);
                continue;
              }
              final delta = (map['delta'] as num?)?.toDouble();
              if (delta == null || delta == 0) {
                debugPrint('stock_delta skip localId=${row.localId}: bad delta');
                await _db.markQueueSynced(row.localId);
                continue;
              }
              final update = <String, dynamic>{
                'stock': FieldValue.increment(delta),
              };
              final u = map['updatedAt'];
              if (u is String) update['updatedAt'] = u;
              await ref.update(update);
              break;
            case 'seller_post_sale':
              if (row.dataTable != 'sales') {
                debugPrint('seller_post_sale expects sales collection');
                await _db.markQueueSynced(row.localId);
                continue;
              }
              final saleId = row.entityId;
              if (saleId == null || saleId.isEmpty) {
                debugPrint('seller_post_sale skip localId=${row.localId}: missing sale id');
                await _db.markQueueSynced(row.localId);
                continue;
              }
              final outcome = await SellerPosCheckoutReplay.replayFromQueuePayload(
                firestore: _firestore,
                saleId: saleId,
                payload: map,
              );
              if (outcome == SellerPostSaleReplayOutcome.saleDocumentMissing) {
                continue;
              }
              await _db.markQueueSynced(row.localId);
              continue;
            default:
              debugPrint('Unknown actionType=${row.actionType} localId=${row.localId}');
              continue;
          }

          await _db.markQueueSynced(row.localId);

          if (row.dataTable == 'sales' && row.actionType == 'create') {
            await (_db.update(_db.localSales)..where((t) => t.id.equals(docId))).write(
              LocalSalesCompanion(
                syncStatus: const Value(SyncStatus.synced),
                updatedAt: Value(DateTime.now().toUtc()),
              ),
            );
          }
        } catch (e, st) {
          debugPrint('Sync failed localId=${row.localId}: $e\n$st');
          if (row.dataTable == 'sales' && row.actionType == 'create') {
            final docId = row.entityId ?? _tryIdFromJson(row.dataJson);
            if (docId != null && docId.isNotEmpty) {
              await (_db.update(_db.localSales)..where((t) => t.id.equals(docId))).write(
                LocalSalesCompanion(
                  syncStatus: const Value(SyncStatus.failed),
                  updatedAt: Value(DateTime.now().toUtc()),
                ),
              );
            }
          }
        }
      }
    } finally {
      _running = false;
    }
  }

  String? _tryIdFromJson(String raw) {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map['id'] as String?;
    } catch (_) {
      return null;
    }
  }
}
