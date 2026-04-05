import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../database/offline_db.dart';
import '../offline/sync_coordinator.dart';

/// Shows connectivity + how many operations are waiting to upload. Tap for details.
class SyncStatusBanner extends StatelessWidget {
  const SyncStatusBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncCoordinator?>();
    if (sync == null || !OfflineDb.isSupported) {
      return const SizedBox.shrink();
    }

    final n = sync.pendingOutboundCount;
    final theme = Theme.of(context);
    Color bg;
    Color fg;
    IconData icon;
    String title;

    switch (sync.banner) {
      case SyncBannerState.offline:
        bg = Colors.orange.shade100;
        fg = Colors.orange.shade900;
        icon = Icons.cloud_off_outlined;
        title = n > 0
            ? 'Offline — $n upload${n == 1 ? '' : 's'} waiting to sync'
            : 'Offline — changes will sync when you are online';
        break;
      case SyncBannerState.syncing:
        bg = Colors.blue.shade50;
        fg = Colors.blue.shade900;
        icon = Icons.cloud_upload_outlined;
        title = n > 0 ? 'Syncing… ($n remaining)' : 'Syncing…';
        break;
      case SyncBannerState.syncFailed:
        bg = Colors.red.shade50;
        fg = Colors.red.shade900;
        icon = Icons.cloud_off_outlined;
        title =
            'Online but $n upload${n == 1 ? '' : 's'} failed — tap to retry';
        break;
      case SyncBannerState.synced:
        bg = Colors.green.shade50;
        fg = Colors.green.shade900;
        icon = Icons.cloud_done_outlined;
        title = 'Synced with server';
        break;
    }

    return Material(
      color: bg,
      child: InkWell(
        onTap: n > 0 || sync.banner == SyncBannerState.syncFailed
            ? () => showPendingUploadSheet(context, sync)
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              if (sync.banner == SyncBannerState.syncing)
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: fg,
                  ),
                )
              else
                Icon(icon, size: 22, color: fg),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (sync.banner == SyncBannerState.syncFailed)
                TextButton(
                  onPressed: () => sync.retrySyncNow(),
                  child: const Text('Retry'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Shared with [DashboardSyncStrip] and anywhere else that needs the queue list.
  static Future<void> showPendingUploadSheet(
    BuildContext context,
    SyncCoordinator sync,
  ) async {
    final rows = await OfflineDb.instance.pendingQueue(limit: 80);
    if (!context.mounted) return;

    final fmt = DateFormat('MMM d, h:mm a');
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final maxH = MediaQuery.of(ctx).size.height * 0.55;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: Text(
                    'Pending upload (${rows.length})',
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                ),
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxH),
                  child: rows.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('Nothing in the queue right now.'),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: rows.length,
                          itemBuilder: (_, i) {
                            final r = rows[i];
                            final label = labelForQueueRow(r.actionType, r.dataTable);
                            return ListTile(
                              dense: true,
                              leading: Icon(iconForQueueAction(r.actionType)),
                              title: Text(label),
                              subtitle: Text(
                                '${fmt.format(r.createdAt.toLocal())} · ${r.entityId ?? r.id}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      sync.retrySyncNow();
                    },
                    icon: const Icon(Icons.sync),
                    label: const Text('Sync now'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static String labelForQueueRow(String action, String table) {
    if (action == 'stock_delta' && table == 'products') {
      return 'Product stock update';
    }
    if (table == 'sales' && action == 'create') {
      return 'Sale (new bill)';
    }
    if (table == 'sales' && action == 'seller_post_sale') {
      return 'Seller payment & history';
    }
    return '$table · $action';
  }

  static IconData iconForQueueAction(String action) {
    switch (action) {
      case 'stock_delta':
        return Icons.inventory_2_outlined;
      case 'create':
        return Icons.receipt_long_outlined;
      case 'seller_post_sale':
        return Icons.person_outline;
      case 'update':
        return Icons.edit_outlined;
      case 'delete':
        return Icons.delete_outline;
      default:
        return Icons.cloud_upload_outlined;
    }
  }
}
