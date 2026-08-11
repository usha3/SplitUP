import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/expense_model.dart';

class ExpenseService {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  ExpenseService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore =
      firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  Stream<List<ExpenseModel>> getGroupExpenses(
      String groupId,
      ) {
    return _firestore
        .collection('groups')
        .doc(groupId)
        .collection('expenses')
        .orderBy(
      'createdAt',
      descending: true,
    )
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
          .map(ExpenseModel.fromFirestore)
          .toList(),
    );
  }

  Future<String> addExpense({
    required String groupId,
    required String title,
    required double amount,
    required String category,
    required String paidBy,
    required List<String> participants,
    String? receiptUrl,

    // NEW
    String splitType = 'equal',

    // NEW
    List<ExpenseItem> items = const [],

    // NEW
    Map<String, double> shares = const {},
  }) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw StateError(
        'You must be logged in to add an expense.',
      );
    }

    if (title.trim().isEmpty) {
      throw ArgumentError(
        'Expense title is required.',
      );
    }

    if (amount <= 0) {
      throw ArgumentError(
        'Expense amount must be greater than zero.',
      );
    }

    if (participants.isEmpty) {
      throw ArgumentError(
        'Select at least one participant.',
      );
    }

    if (paidBy.trim().isEmpty) {
      throw ArgumentError(
        'Select who paid for this expense.',
      );
    }

    if (splitType == 'itemized') {
      if (items.isEmpty) {
        throw ArgumentError(
          'Add at least one item.',
        );
      }

      for (final item in items) {
        if (item.name.trim().isEmpty) {
          throw ArgumentError(
            'Every item needs a name.',
          );
        }

        if (item.amount <= 0) {
          throw ArgumentError(
            'Every item must have a valid amount.',
          );
        }

        if (item.participants.isEmpty) {
          throw ArgumentError(
            '${item.name} must have at least one participant.',
          );
        }
      }

      final itemTotal = items.fold<double>(
        0,
            (total, item) => total + item.amount,
      );

      if ((itemTotal - amount).abs() > 0.01) {
        throw ArgumentError(
          'Item total does not match expense total.',
        );
      }
    }

    final document = _firestore
        .collection('groups')
        .doc(groupId)
        .collection('expenses')
        .doc();

    final expense = ExpenseModel(
      id: document.id,
      title: title.trim(),
      amount: amount,
      category: category,
      paidBy: paidBy,
      groupId: groupId,
      participants: participants,
      receiptUrl: receiptUrl,
      splitType: splitType,
      items: items,
      shares: shares,
    );

    await document.set(
      expense.toFirestore(),
    );

    return document.id;
  }

  Future<void> updateExpense({
    required String groupId,
    required String expenseId,
    required String title,
    required double amount,
    required String category,
    required List<String> participants,
    String? receiptUrl,

    String splitType = 'equal',
    List<ExpenseItem> items = const [],
    Map<String, double> shares = const {},
  }) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw StateError(
        'You must be logged in.',
      );
    }

    if (title.trim().isEmpty) {
      throw ArgumentError(
        'Expense title is required.',
      );
    }

    if (amount <= 0) {
      throw ArgumentError(
        'Expense amount must be greater than zero.',
      );
    }

    if (participants.isEmpty) {
      throw ArgumentError(
        'Select at least one participant.',
      );
    }

    await _firestore
        .collection('groups')
        .doc(groupId)
        .collection('expenses')
        .doc(expenseId)
        .update({
      'title': title.trim(),
      'amount': amount,
      'category': category,
      'participants': participants,
      'receiptUrl': receiptUrl,

      // NEW
      'splitType': splitType,
      'items':
      items.map((item) => item.toMap()).toList(),
      'shares': shares,

      'updatedAt':
      FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteExpense({
    required String groupId,
    required String expenseId,
  }) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw StateError(
        'You must be logged in.',
      );
    }

    await _firestore
        .collection('groups')
        .doc(groupId)
        .collection('expenses')
        .doc(expenseId)
        .delete();
  }
}