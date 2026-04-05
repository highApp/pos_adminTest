import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../database/offline_db.dart';
import '../offline/sync_coordinator.dart';
import 'sync_status_banner.dart';

/// Explains how offline / pending uploads affect each dashboard area (full scroll view).
class DashboardSyncStrip extends StatelessWidget {
  const DashboardSyncStrip({super.key});

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncCoordinator?>();
    if (sync == null || !OfflineDb.isSupported) {
      return const SizedBox.shrink();
    }

    final pending = sync.pendingOutboundCount;
    final needsAttention = sync.isOffline ||
        pending > 0 ||
        sync.banner == SyncBannerState.syncFailed;

    if (!needsAttention) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    Color borderColor;
    Color iconBg;
    IconData headerIcon;
    String headline;
    switch (sync.banner) {
      case SyncBannerState.offline:
        borderColor = Colors.orange.shade200;
        iconBg = Colors.orange.shade50;
        headerIcon = Icons.cloud_off_outlined;
        headline = pending > 0
            ? 'Offline — $pending upload${pending == 1 ? '' : 's'} will run when you are back online'
            : 'Offline — figures below are from the last Firestore sync on this device';
        break;
      case SyncBannerState.syncing:
        borderColor = Colors.blue.shade200;
        iconBg = Colors.blue.shade50;
        headerIcon = Icons.cloud_upload_outlined;
        headline = 'Syncing — dashboard will match the server as uploads finish';
        break;
      case SyncBannerState.syncFailed:
        borderColor = Colors.red.shade200;
        iconBg = Colors.red.shade50;
        headerIcon = Icons.error_outline;
        headline =
            'Some uploads failed — open the queue below or use Retry in the top bar';
        break;
      case SyncBannerState.synced:
        borderColor = Colors.grey.shade300;
        iconBg = Colors.grey.shade100;
        headerIcon = Icons.info_outline;
        headline = 'Waiting for background sync';
        break;
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(headerIcon, color: theme.colorScheme.primary, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sync and this screen',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      headline,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        height: 1.35,
                        color: Colors.grey.shade800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'How each section uses data:',
            style: theme.textTheme.labelLarge?.copyWith(
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          _Bullet(
            icon: Icons.analytics_outlined,
            title: 'Overview, revenue, profit, returns',
            detail:
                'Built from Firestore sales & expenses. New offline bills appear after the sale row uploads.',
          ),
          _Bullet(
            icon: Icons.inventory_2_outlined,
            title: 'Products & low stock',
            detail:
                'Counts and stock levels update after product stock changes sync to the server.',
          ),
          _Bullet(
            icon: Icons.account_balance_wallet_outlined,
            title: 'Borrow card & balance entries',
            detail:
                'Borrow totals follow the dashboard date filter (seller dues by bill date; borrow-book by entry date). Not an all-time total.',
          ),
          _Bullet(
            icon: Icons.groups_outlined,
            title: 'Seller reminders & seller-linked money',
            detail:
                'Credit, dues, and seller history update after sale + seller payment rows finish uploading.',
          ),
          _Bullet(
            icon: Icons.show_chart_outlined,
            title: 'Sales trend chart',
            detail: 'Follows the same sales stream as overview for the selected period.',
          ),
          if (pending > 0 || sync.banner == SyncBannerState.syncFailed) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => SyncStatusBanner.showPendingUploadSheet(context, sync),
                icon: const Icon(Icons.list_alt, size: 20),
                label: Text('View upload queue ($pending)'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.teal.shade700),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
