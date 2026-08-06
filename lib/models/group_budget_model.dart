import 'package:cloud_firestore/cloud_firestore.dart';

class GroupBudgetModel {
  final String groupId;
  final double monthlyLimit;
  final String currencyCode;
  final bool alertsEnabled;
  final DateTime? updatedAt;

  const GroupBudgetModel({
    required this.groupId,
    required this.monthlyLimit,
    required this.currencyCode,
    this.alertsEnabled = true,
    this.updatedAt,
  });

  factory GroupBudgetModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> document,
      ) {
    final data = document.data() ?? {};

    return GroupBudgetModel(
      groupId: document.id,
      monthlyLimit:
      (data['monthlyLimit'] as num?)?.toDouble() ?? 0,
      currencyCode:
      data['currencyCode']?.toString() ?? 'USD',
      alertsEnabled:
      data['alertsEnabled'] as bool? ?? true,
      updatedAt: _toDateTime(data['updatedAt']),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'monthlyLimit': monthlyLimit,
      'currencyCode': currencyCode,
      'alertsEnabled': alertsEnabled,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  GroupBudgetModel copyWith({
    String? groupId,
    double? monthlyLimit,
    String? currencyCode,
    bool? alertsEnabled,
    DateTime? updatedAt,
  }) {
    return GroupBudgetModel(
      groupId: groupId ?? this.groupId,
      monthlyLimit: monthlyLimit ?? this.monthlyLimit,
      currencyCode: currencyCode ?? this.currencyCode,
      alertsEnabled: alertsEnabled ?? this.alertsEnabled,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static DateTime? _toDateTime(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }

    return null;
  }
}