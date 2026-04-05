import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../database/offline_db.dart';
import 'sync_coordinator.dart';

/// Starts connectivity listening and sync when the app runs (native platforms only).
class OfflineLifecycleWidget extends StatefulWidget {
  const OfflineLifecycleWidget({super.key, required this.child});

  final Widget child;

  @override
  State<OfflineLifecycleWidget> createState() => _OfflineLifecycleWidgetState();
}

class _OfflineLifecycleWidgetState extends State<OfflineLifecycleWidget>
    with WidgetsBindingObserver {
  SyncCoordinator? _coordinator;

  @override
  void initState() {
    super.initState();
    if (OfflineDb.isSupported) {
      WidgetsBinding.instance.addObserver(this);
      _coordinator = SyncCoordinator(db: OfflineDb.instance)..start();
    }
  }

  @override
  void dispose() {
    if (_coordinator != null) {
      WidgetsBinding.instance.removeObserver(this);
      _coordinator!.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _coordinator?.onAppResumed();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<SyncCoordinator?>.value(
      value: _coordinator,
      child: widget.child,
    );
  }
}
