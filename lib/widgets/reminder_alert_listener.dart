import 'dart:async';
import 'package:flutter/material.dart';
import '../models/seller_reminder.dart';
import '../services/seller_reminder_service.dart';
import '../screens/sellers_screen.dart';

/// Listens for due/overdue reminders and shows real-time alerts.
/// Wraps child with overlay that displays alerts and navigates to Sellers when tapped.
class ReminderAlertListener extends StatefulWidget {
  final Widget child;

  const ReminderAlertListener({
    super.key,
    required this.child,
  });

  @override
  State<ReminderAlertListener> createState() => _ReminderAlertListenerState();
}

class _ReminderAlertListenerState extends State<ReminderAlertListener> {
  final SellerReminderService _reminderService = SellerReminderService();
  final Set<String> _alertedReminderIds = {};
  StreamSubscription<List<SellerReminder>>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscribeToOverdueReminders();
  }

  void _subscribeToOverdueReminders() {
    _subscription?.cancel();
    _subscription = _reminderService.getOverdueRemindersStream().listen((reminders) {
      if (!mounted) return;
      for (final r in reminders) {
        if (!_alertedReminderIds.contains(r.id)) {
          _alertedReminderIds.add(r.id);
          _showReminderAlert(r);
        }
      }
      setState(() {});
    });
  }

  void _showReminderAlert(SellerReminder reminder) {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.notifications_active, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Reminder due',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      reminder.message,
                      style: const TextStyle(fontSize: 13),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          backgroundColor: Colors.amber.shade800,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'View',
            textColor: Colors.white,
            onPressed: () => _navigateToSellers(),
          ),
        ),
      );
    });
  }

  void _navigateToSellers() {
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const SellersScreen(),
      ),
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<SellerReminder>>(
      stream: _reminderService.getOverdueRemindersStream(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return widget.child;
        }
        final overdue = snapshot.data!;
        return Stack(
          children: [
            widget.child,
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Material(
                  color: Colors.amber.shade700,
                  elevation: 4,
                  child: InkWell(
                    onTap: _navigateToSellers,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.notifications_active,
                            color: Colors.white,
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${overdue.length} reminder${overdue.length > 1 ? 's' : ''} due',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  overdue.map((r) => r.message).take(2).join(' • '),
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.95),
                                    fontSize: 13,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.arrow_forward,
                            color: Colors.white,
                            size: 24,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
