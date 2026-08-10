import 'package:cloud_firestore/cloud_firestore.dart';

class ExpenseModel {
  final String id;
  final String title;
  final double amount;
  final String category;
  final String paidBy;
  final String groupId;
  final List<String> participants;
  final DateTime? createdAt;
  final bool generatedFromRecurring;
  final String? recurringExpenseId;
  final String? receiptUrl;

  const ExpenseModel({
    required this.id,
    required this.title,
    required this.amount,
    required this.category,
    required this.paidBy,
    required this.groupId,
    required this.participants,
    this.createdAt,
    this.generatedFromRecurring = false,
    this.recurringExpenseId,
    this.receiptUrl,
  });

  factory ExpenseModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> document,
      ) {
    final data = document.data() ?? {};

    return ExpenseModel(
      id: document.id,
      title: data['title'] as String? ?? '',
      amount: _toDouble(data['amount']),
      category: data['category'] as String? ?? 'Other',
      paidBy: data['paidBy'] as String? ?? '',
      groupId: data['groupId'] as String? ?? '',
      participants: List<String>.from(
        data['participants'] as List<dynamic>? ?? const [],
      ),
      createdAt: _toDateTime(data['createdAt']),
      generatedFromRecurring:
      data['generatedFromRecurring'] == true,

      recurringExpenseId:
      data['recurringExpenseId']?.toString(),
      receiptUrl: data['receiptUrl']?.toString(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      'amount': amount,
      'category': category,
      'paidBy': paidBy,
      'groupId': groupId,
      'participants': participants,
      'createdAt': createdAt ?? FieldValue.serverTimestamp(),
      'generatedFromRecurring': generatedFromRecurring,
      'recurringExpenseId': recurringExpenseId,
      'receiptUrl': receiptUrl,
    };
  }

  double get amountPerPerson {
    if (participants.isEmpty) {
      return amount;
    }

    return amount / participants.length;
  }

  ExpenseModel copyWith({
    String? id,
    String? title,
    double? amount,
    String? category,
    String? paidBy,
    String? groupId,
    List<String>? participants,
    DateTime? createdAt,
    String? receiptUrl,
  }) {
    return ExpenseModel(
      id: id ?? this.id,
      title: title ?? this.title,
      amount: amount ?? this.amount,
      category: category ?? this.category,
      paidBy: paidBy ?? this.paidBy,
      groupId: groupId ?? this.groupId,
      participants:
      participants ?? this.participants,
      createdAt: createdAt ?? this.createdAt,
      generatedFromRecurring:
      generatedFromRecurring,
      recurringExpenseId:
      recurringExpenseId,
      receiptUrl:
      receiptUrl ?? this.receiptUrl,
    );
  }

  static double _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '') ?? 0;
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