import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_notification_model.dart';

class InAppNotificationService {
  final FirebaseFirestore _firestore;

  InAppNotificationService({
    FirebaseFirestore? firestore,
  }) : _firestore =
      firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>>
  _notificationsRef(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('notifications');
  }

  Stream<List<AppNotificationModel>>
  getNotifications(String userId) {
    return _notificationsRef(userId)
        .orderBy(
      'createdAt',
      descending: true,
    )
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
          .map(
        AppNotificationModel.fromFirestore,
      )
          .toList(),
    );
  }

  Stream<int> getUnreadCount(String userId) {
    return _notificationsRef(userId)
        .where(
      'isRead',
      isEqualTo: false,
    )
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.length,
    );
  }

  Future<String> createNotification({
    required String userId,
    required String type,
    required String title,
    required String message,
    String? groupId,
    String? expenseId,
    String? settlementId,
  }) async {
    if (userId.trim().isEmpty) {
      throw ArgumentError(
        'Notification user ID is required.',
      );
    }

    final document =
    _notificationsRef(userId).doc();

    final notification =
    AppNotificationModel(
      id: document.id,
      userId: userId,
      type: type,
      title: title,
      message: message,
      groupId: groupId,
      expenseId: expenseId,
      settlementId: settlementId,
    );

    await document.set(
      notification.toFirestore(),
    );

    return document.id;
  }

  Future<void> markAsRead({
    required String userId,
    required String notificationId,
  }) async {
    await _notificationsRef(userId)
        .doc(notificationId)
        .update({
      'isRead': true,
    });
  }

  Future<void> markAllAsRead(
      String userId,
      ) async {
    final snapshot =
    await _notificationsRef(userId)
        .where(
      'isRead',
      isEqualTo: false,
    )
        .get();

    if (snapshot.docs.isEmpty) {
      return;
    }

    final batch = _firestore.batch();

    for (final document in snapshot.docs) {
      batch.update(
        document.reference,
        {
          'isRead': true,
        },
      );
    }

    await batch.commit();
  }
}