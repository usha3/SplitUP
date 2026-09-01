import 'package:cloud_firestore/cloud_firestore.dart';

class ExpenseItem {
  final String name;
  final double amount;
  final List<String> participants;

  const ExpenseItem({
    required this.name,
    required this.amount,
    required this.participants,
  });

  factory ExpenseItem.fromMap(Map<String, dynamic> data) {
    return ExpenseItem(
      name: data['name']?.toString() ?? '',
      amount: _toDouble(data['amount']),
      participants: List<String>.from(
        data['participants'] as List<dynamic>? ?? const [],
      ),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'amount': amount,
      'participants': participants,
    };
  }

  static double _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}

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

  final String splitType;
  final List<ExpenseItem> items;
  final Map<String, double> shares;

  final double receiptAdjustment;
  final String? receiptAdjustmentLabel;

  final double receiptTax;
  final double receiptTipAndFees;
  final double receiptDiscounts;
  final double receiptReconciliation;

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
    this.splitType = 'equal',
    this.items = const [],
    this.shares = const {},
    this.receiptAdjustment = 0,
    this.receiptAdjustmentLabel,
    this.receiptTax = 0,
    this.receiptTipAndFees = 0,
    this.receiptDiscounts = 0,
    this.receiptReconciliation = 0,
  });

  factory ExpenseModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> document,
      ) {
    final data = document.data() ?? {};

    final rawItems = data['items'];

    final items = rawItems is List
        ? rawItems
        .whereType<Map>()
        .map(
          (item) => ExpenseItem.fromMap(
        Map<String, dynamic>.from(item),
      ),
    )
        .toList()
        : <ExpenseItem>[];

    final rawShares = data['shares'];

    final shares = <String, double>{};

    if (rawShares is Map) {
      rawShares.forEach((key, value) {
        shares[key.toString()] = _toDouble(value);
      });
    }

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
      splitType:
      data['splitType']?.toString() ?? 'equal',
      items: items,
      shares: shares,
      receiptAdjustment:
      (data['receiptAdjustment'] as num?)
        ?.toDouble() ??
        0,

      receiptAdjustmentLabel:
       data['receiptAdjustmentLabel']
        ?.toString(),
      receiptTax: _toDouble(data['receiptTax']),
      receiptTipAndFees: _toDouble(data['receiptTipAndFees']),
      receiptDiscounts: _toDouble(data['receiptDiscounts']),
      receiptReconciliation: _toDouble(data['receiptReconciliation']),
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
      'createdAt':
      createdAt ?? FieldValue.serverTimestamp(),
      'generatedFromRecurring':
      generatedFromRecurring,
      'recurringExpenseId':
      recurringExpenseId,
      'receiptUrl': receiptUrl,

      // NEW
      'splitType': splitType,
      'items':
      items.map((item) => item.toMap()).toList(),
      'shares': shares,
      'receiptAdjustment': receiptAdjustment,
      'receiptAdjustmentLabel':
      receiptAdjustmentLabel,
      'receiptTax': receiptTax,
      'receiptTipAndFees': receiptTipAndFees,
      'receiptDiscounts': receiptDiscounts,
      'receiptReconciliation': receiptReconciliation,
    };
  }

  double get amountPerPerson {
    if (participants.isEmpty) {
      return amount;
    }

    return amount / participants.length;
  }

  double shareFor(String memberId) {
    if (shares.containsKey(memberId)) {
      return shares[memberId]!;
    }

    if (splitType == 'equal' &&
        participants.contains(memberId) &&
        participants.isNotEmpty) {
      return amount / participants.length;
    }

    return 0;
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
    String? splitType,
    List<ExpenseItem>? items,
    Map<String, double>? shares,
    double? receiptAdjustment,
    String? receiptAdjustmentLabel,
    double? receiptTax,
    double? receiptTipAndFees,
    double? receiptDiscounts,
    double? receiptReconciliation,
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
      createdAt:
      createdAt ?? this.createdAt,
      generatedFromRecurring:
      generatedFromRecurring,
      recurringExpenseId:
      recurringExpenseId,
      receiptUrl:
      receiptUrl ?? this.receiptUrl,
      splitType:
      splitType ?? this.splitType,
      items:
      items ?? this.items,
      shares:
      shares ?? this.shares,
    );
  }

  static double _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(
      value?.toString() ?? '',
    ) ??
        0;
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