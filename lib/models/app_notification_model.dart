import 'package:cloud_firestore/cloud_firestore.dart';

class AppNotificationModel {
  final String id;
  final String userId;
  final String type;
  final String title;
  final String message;
  final String? groupId;
  final String? expenseId;
  final String? settlementId;
  final bool isRead;
  final DateTime? createdAt;

  const AppNotificationModel({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    required this.message,
    this.groupId,
    this.expenseId,
    this.settlementId,
    this.isRead = false,
    this.createdAt,
  });

  factory AppNotificationModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> document,
      ) {
    final data = document.data() ?? {};

    return AppNotificationModel(
      id: document.id,
      userId: data['userId']?.toString() ?? '',
      type: data['type']?.toString() ?? '',
      title: data['title']?.toString() ?? '',
      message: data['message']?.toString() ?? '',
      groupId: data['groupId']?.toString(),
      expenseId: data['expenseId']?.toString(),
      settlementId: data['settlementId']?.toString(),
      isRead: data['isRead'] == true,
      createdAt: _toDateTime(data['createdAt']),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'type': type,
      'title': title,
      'message': message,
      'groupId': groupId,
      'expenseId': expenseId,
      'settlementId': settlementId,
      'isRead': isRead,
      'createdAt':
      createdAt ?? FieldValue.serverTimestamp(),
    };
  }

  static DateTime? _toDateTime(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(
        value,
      );
    }

    return null;
  }
}