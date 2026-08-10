import 'package:cloud_firestore/cloud_firestore.dart';

enum RecurrenceFrequency {
  weekly,
  monthly,
  yearly,
}

class RecurringExpenseModel {
  final String id;
  final String groupId;
  final String title;
  final double amount;
  final String category;
  final String paidBy;
  final List<String> participants;
  final RecurrenceFrequency frequency;
  final int dayOfMonth;
  final DateTime nextDueDate;
  final DateTime? lastGeneratedAt;
  final bool isActive;
  final DateTime? createdAt;
  final String createdBy;

  const RecurringExpenseModel({
    required this.id,
    required this.groupId,
    required this.title,
    required this.amount,
    required this.category,
    required this.paidBy,
    required this.participants,
    required this.frequency,
    required this.dayOfMonth,
    required this.nextDueDate,
    required this.lastGeneratedAt,
    required this.isActive,
    required this.createdAt,
    required this.createdBy,
  });

  factory RecurringExpenseModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> document,
      ) {
    final data = document.data() ?? {};

    return RecurringExpenseModel(
      id: document.id,
      groupId: data['groupId']?.toString() ?? '',
      title: data['title']?.toString() ?? '',
      amount: (data['amount'] as num?)?.toDouble() ?? 0,
      category: data['category']?.toString() ?? 'Other',
      paidBy: data['paidBy']?.toString() ?? '',
      participants: List<String>.from(
        data['participants'] as List<dynamic>? ?? const [],
      ),
      frequency: _frequencyFromString(
        data['frequency']?.toString(),
      ),
      dayOfMonth:
      (data['dayOfMonth'] as num?)?.toInt() ?? 1,
      nextDueDate:
      _toDateTime(data['nextDueDate']) ?? DateTime.now(),
      lastGeneratedAt: _toDateTime(
        data['lastGeneratedAt'],
      ),
      isActive: data['isActive'] as bool? ?? true,
      createdAt: _toDateTime(data['createdAt']),
      createdBy: data['createdBy']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'groupId': groupId,
      'title': title,
      'amount': amount,
      'category': category,
      'paidBy': paidBy,
      'participants': participants,
      'frequency': frequency.name,
      'dayOfMonth': dayOfMonth,
      'nextDueDate': Timestamp.fromDate(nextDueDate),
      'lastGeneratedAt': lastGeneratedAt == null
          ? null
          : Timestamp.fromDate(lastGeneratedAt!),
      'isActive': isActive,
      'createdAt': createdAt == null
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(createdAt!),
      'createdBy': createdBy,
    };
  }

  RecurringExpenseModel copyWith({
    String? id,
    String? groupId,
    String? title,
    double? amount,
    String? category,
    String? paidBy,
    List<String>? participants,
    RecurrenceFrequency? frequency,
    int? dayOfMonth,
    DateTime? nextDueDate,
    DateTime? lastGeneratedAt,
    bool? isActive,
    DateTime? createdAt,
    String? createdBy,
  }) {
    return RecurringExpenseModel(
      id: id ?? this.id,
      groupId: groupId ?? this.groupId,
      title: title ?? this.title,
      amount: amount ?? this.amount,
      category: category ?? this.category,
      paidBy: paidBy ?? this.paidBy,
      participants: participants ?? this.participants,
      frequency: frequency ?? this.frequency,
      dayOfMonth: dayOfMonth ?? this.dayOfMonth,
      nextDueDate: nextDueDate ?? this.nextDueDate,
      lastGeneratedAt:
      lastGeneratedAt ?? this.lastGeneratedAt,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      createdBy: createdBy ?? this.createdBy,
    );
  }

  static RecurrenceFrequency _frequencyFromString(
      String? value,
      ) {
    switch (value) {
      case 'weekly':
        return RecurrenceFrequency.weekly;
      case 'yearly':
        return RecurrenceFrequency.yearly;
      case 'monthly':
      default:
        return RecurrenceFrequency.monthly;
    }
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