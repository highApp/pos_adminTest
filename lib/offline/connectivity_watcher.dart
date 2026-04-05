import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:internet_connection_checker/internet_connection_checker.dart';

/// Emits when the device likely has usable internet (not just Wi‑Fi association).
///
/// For a shop POS, foreground + connectivity changes are usually enough; iOS
/// background execution is limited, so also trigger sync on app resume.
class ConnectivityWatcher {
  ConnectivityWatcher({
    Connectivity? connectivity,
    InternetConnectionChecker? internetChecker,
  })  : _connectivity = connectivity ?? Connectivity(),
        _internetChecker = internetChecker ?? InternetConnectionChecker.instance;

  final Connectivity _connectivity;
  final InternetConnectionChecker _internetChecker;

  final _controller = StreamController<bool>.broadcast();
  Stream<bool> get onlineStream => _controller.stream;

  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _lastOnline = false;

  Future<void> start() async {
    await _emitCurrent();
    await _sub?.cancel();
    _sub = _connectivity.onConnectivityChanged.listen((_) => _emitCurrent());
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    await _controller.close();
  }

  /// Call from [WidgetsBindingObserver.didChangeAppLifecycleState] when resumed.
  Future<void> refresh() => _emitCurrent();

  Future<void> _emitCurrent() async {
    try {
      final results = await _connectivity.checkConnectivity();
      final hasLink = results.any((r) =>
          r == ConnectivityResult.mobile ||
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.ethernet);
      if (!hasLink) {
        _push(false);
        return;
      }
      final reachable = await _internetChecker.hasConnection;
      _push(reachable);
    } catch (e, st) {
      debugPrint('ConnectivityWatcher: $e\n$st');
      _push(false);
    }
  }

  void _push(bool online) {
    if (online == _lastOnline && _controller.hasListener) return;
    _lastOnline = online;
    if (!_controller.isClosed) _controller.add(online);
  }

  bool get lastKnownOnline => _lastOnline;
}
