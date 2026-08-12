import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/expense_model.dart';
import '../services/in_app_notification_service.dart';
import 'package:flutter/foundation.dart';

class ExpenseService {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final InAppNotificationService
  _inAppNotificationService;

  ExpenseService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    InAppNotificationService?
    inAppNotificationService,
  })  : _firestore =
      firestore ?? FirebaseFirestore.instance,
        _auth =
            auth ?? FirebaseAuth.instance,
        _inAppNotificationService =
            inAppNotificationService ??
                InAppNotificationService();

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

// Create notifications only after the expense
// has been successfully saved.
    await _createExpenseNotifications(
      groupId: groupId,
      expenseId: document.id,
      expenseTitle: title.trim(),
      amount: amount,
      participants: participants,
      shares: shares,
      createdByUserId: user.uid,
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

  Future<void> _createExpenseNotifications({
    required String groupId,
    required String expenseId,
    required String expenseTitle,
    required double amount,
    required List<String> participants,
    required Map<String, double> shares,
    required String createdByUserId,
  }) async {
    try {
      final groupDocument = await _firestore
          .collection('groups')
          .doc(groupId)
          .get();

      final groupData =
          groupDocument.data() ?? {};

      final groupName =
          groupData['name']
              ?.toString()
              .trim() ??
              'your group';

      for (final participantId in participants) {
        // Don't notify the person who created the expense.
        if (participantId == createdByUserId) {
          continue;
        }

        // Guest members don't have user accounts.
        if (participantId.startsWith('guest_')) {
          continue;
        }

        final participantShare =
            shares[participantId] ??
                (participants.isNotEmpty
                    ? amount / participants.length
                    : 0);

        await _inAppNotificationService
            .createNotification(
          userId: participantId,
          type: 'expense_added',
          title: 'New expense added',
          message:
          '$expenseTitle was added in $groupName. '
              'Your share is '
              '\$${participantShare.toStringAsFixed(2)}.',
          groupId: groupId,
          expenseId: expenseId,
        );
      }
    } catch (error) {
      // Expense creation must not fail just because
      // a notification could not be created.
      debugPrint(
        'Unable to create expense notifications: $error',
      );
    }
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