import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/app_notification_model.dart';
import '../../services/in_app_notification_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/group_model.dart';
import '../groups/balances_screen.dart';
import '../expenses/expense_details_screen.dart';
import '../../models/expense_model.dart';

class NotificationsScreen
    extends StatelessWidget {
  const NotificationsScreen({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final user =
        FirebaseAuth.instance.currentUser;

    final notificationService =
    InAppNotificationService();

    if (user == null) {
      return const Scaffold(
        body: Center(
          child: Text(
            'You must be logged in.',
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton(
            onPressed: () {
              notificationService
                  .markAllAsRead(user.uid);
            },
            child: const Text(
              'Mark all read',
            ),
          ),
        ],
      ),
      body: StreamBuilder<
          List<AppNotificationModel>>(
        stream:
        notificationService
            .getNotifications(
          user.uid,
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState ==
              ConnectionState.waiting) {
            return const Center(
              child:
              CircularProgressIndicator(),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Unable to load notifications: '
                    '${snapshot.error}',
              ),
            );
          }

          final notifications =
              snapshot.data ?? [];

          if (notifications.isEmpty) {
            return const Center(
              child: Text(
                'No notifications yet.',
              ),
            );
          }

          return ListView.separated(
            padding:
            const EdgeInsets.all(16),
            itemCount:
            notifications.length,
            separatorBuilder:
                (_, _) =>
            const SizedBox(
              height: 8,
            ),
            itemBuilder:
                (context, index) {
              final notification =
              notifications[index];

              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    child: Icon(
                      _iconForType(
                        notification.type,
                      ),
                    ),
                  ),
                  title: Text(
                    notification.title,
                    style: TextStyle(
                      fontWeight:
                      notification.isRead
                          ? FontWeight
                          .normal
                          : FontWeight
                          .bold,
                    ),
                  ),
                  subtitle: Text(
                    notification.message,
                  ),
                  trailing:
                  notification.isRead
                      ? null
                      : const Icon(
                    Icons
                        .circle,
                    size: 10,
                  ),
                  onTap: () async {
                    if (!notification.isRead) {
                      await notificationService
                          .markAsRead(
                        userId: user.uid,
                        notificationId:
                        notification.id,
                      );
                    }

                    if (!context.mounted) {
                      return;
                    }

                    await _openNotificationTarget(
                      context: context,
                      notification: notification,
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }

  static Future<void> _openNotificationTarget({
    required BuildContext context,
    required AppNotificationModel notification,
  }) async {
    final groupId = notification.groupId;

    if (groupId == null || groupId.trim().isEmpty) {
      return;
    }

    final groupDocument = await FirebaseFirestore.instance
        .collection('groups')
        .doc(groupId)
        .get();

    if (!groupDocument.exists) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The related group could not be found.',
          ),
        ),
      );

      return;
    }

    final group = GroupModel.fromFirestore(
      groupDocument,
    );

    if (!context.mounted) return;

    switch (notification.type) {
      case 'expense_added':
        final expenseId =
            notification.expenseId;

        if (expenseId == null ||
            expenseId.trim().isEmpty) {
          return;
        }

        final expenseDocument =
        await FirebaseFirestore.instance
            .collection('groups')
            .doc(groupId)
            .collection('expenses')
            .doc(expenseId)
            .get();

        if (!expenseDocument.exists) {
          if (!context.mounted) return;

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'The related expense could not be found.',
              ),
            ),
          );

          return;
        }

        final expense =
        ExpenseModel.fromFirestore(
          expenseDocument,
        );

        if (!context.mounted) return;

        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                ExpenseDetailsScreen(
                  group: group,
                  expense: expense,
                ),
          ),
        );
        break;

      case 'settlement_recorded':
      case 'balance_reminder':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                BalancesScreen(
                  group: group,
                ),
          ),
        );
        break;

      case 'recurring_expense':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                BalancesScreen(
                  group: group,
                ),
          ),
        );
        break;

      default:
        break;
    }
  }

  static IconData _iconForType(
      String type,
      ) {
    switch (type) {
      case 'expense_added':
        return Icons.receipt_long_outlined;

      case 'settlement_recorded':
        return Icons.payments_outlined;

      case 'balance_reminder':
        return Icons.notifications_active_outlined;

      case 'recurring_expense':
        return Icons.repeat_rounded;

      default:
        return Icons.notifications_none;
    }
  }
}