import 'dart:async';

import 'package:flutter/foundation.dart';

import '../database/app_database.dart';
import 'connectivity_watcher.dart';
import 'example_firestore_sync_service.dart';

/// Banner line for POS: offline / syncing / synced (and failed while online).
enum SyncBannerState {
  offline,
  syncing,
  synced,
  /// Still has unsynced queue rows after a sync attempt while online.
  syncFailed,
}

/// Wires connectivity to [ExampleFirestoreSyncService]. Use with [Provider] at app root.
class SyncCoordinator extends ChangeNotifier {
  SyncCoordinator({required AppDatabase db})
      : _db = db,
        _sync = ExampleFirestoreSyncService(db: db),
        _net = ConnectivityWatcher();

  final AppDatabase _db;
  final ExampleFirestoreSyncService _sync;
  final ConnectivityWatcher _net;

  StreamSubscription<bool>? _sub;

  bool _syncRunning = false;

  SyncBannerState _banner = SyncBannerState.synced;
  SyncBannerState get banner => _banner;

  /// Unsynced outbound queue rows (sales, stock, etc.).
  int _pendingOutbound = 0;
  int get pendingOutboundCount => _pendingOutbound;

  Future<void> _refreshPendingCount() async {
    _pendingOutbound = await _db.pendingOutboundCount();
  }

  /// Manual retry (e.g. user tapped the status banner after a failure).
  Future<void> retrySyncNow() => _runSync();

  /// Call after new rows are added to the local queue (sale saved offline, stock queued, etc.).
  /// Does not wait for Firestore sync so checkout can show the receipt immediately.
  Future<void> onLocalQueueChanged() async {
    await _refreshPendingCount();
    if (_net.lastKnownOnline) {
      notifyListeners();
      unawaited(_runSync());
    } else {
      _banner = SyncBannerState.offline;
      notifyListeners();
    }
  }

  /// `true` when Wi‑Fi/mobile/ethernet is up **and** a quick reachability check succeeds.
  /// Use this to tell **offline vs online** (not the same as “everything is synced”).
  bool get isLikelyOnline => _net.lastKnownOnline;

  /// Shorthand: no usable internet right now.
  bool get isOffline => !isLikelyOnline;

  Future<void> start() async {
    await _net.start();
    await _refreshPendingCount();
    await _recomputeBanner();
    _sub = _net.onlineStream.listen((online) async {
      if (!online) {
        await _refreshPendingCount();
        _banner = SyncBannerState.offline;
        notifyListeners();
        return;
      }
      await _runSync();
    });
  }

  /// Call from [WidgetsBindingObserver.didChangeAppLifecycleState] when [resumed].
  Future<void> onAppResumed() async {
    await _net.refresh();
    await _runSync();
  }

  Future<void> _runSync() async {
    if (_syncRunning) return;
    _syncRunning = true;
    try {
    await _refreshPendingCount();
    if (!_net.lastKnownOnline) {
      _banner = SyncBannerState.offline;
      notifyListeners();
      return;
    }
    if (_pendingOutbound == 0) {
      _banner = SyncBannerState.synced;
      notifyListeners();
      return;
    }
    _banner = SyncBannerState.syncing;
    notifyListeners();
    await _sync.syncPendingIfNeeded();
    await _refreshPendingCount();
    _banner =
        _pendingOutbound > 0 ? SyncBannerState.syncFailed : SyncBannerState.synced;
    notifyListeners();
    } finally {
      _syncRunning = false;
    }
  }

  Future<void> _recomputeBanner() async {
    await _refreshPendingCount();
    if (!_net.lastKnownOnline) {
      _banner = SyncBannerState.offline;
      notifyListeners();
      return;
    }
    if (_pendingOutbound == 0) {
      _banner = SyncBannerState.synced;
      notifyListeners();
      return;
    }
    _banner = SyncBannerState.syncing;
    notifyListeners();
    await _sync.syncPendingIfNeeded();
    await _refreshPendingCount();
    _banner =
        _pendingOutbound > 0 ? SyncBannerState.syncFailed : SyncBannerState.synced;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _net.dispose();
    super.dispose();
  }
}
