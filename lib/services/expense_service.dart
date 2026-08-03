import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/expense_model.dart';

class ExpenseService {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  ExpenseService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  Stream<List<ExpenseModel>> getGroupExpenses(String groupId) {
    return _firestore
        .collection('groups')
        .doc(groupId)
        .collection('expenses')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) =>
          snapshot.docs.map(ExpenseModel.fromFirestore).toList(),
    );
  }

  Future<String> addExpense({
    required String groupId,
    required String title,
    required double amount,
    required String category,
    required List<String> participants,
  }) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw StateError('You must be logged in to add an expense.');
    }

    if (participants.isEmpty) {
      throw ArgumentError('Select at least one participant.');
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
      paidBy: user.uid,
      groupId: groupId,
      participants: participants,
    );

    await document.set(expense.toFirestore());

    return document.id;
  }

  Future<void> updateExpense({
    required String groupId,
    required String expenseId,
    required String title,
    required double amount,
    required String category,
    required List<String> participants,
  }) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw StateError('You must be logged in.');
    }

    if (title.trim().isEmpty) {
      throw ArgumentError('Expense title is required.');
    }

    if (amount <= 0) {
      throw ArgumentError('Expense amount must be greater than zero.');
    }

    if (participants.isEmpty) {
      throw ArgumentError('Select at least one participant.');
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
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteExpense({
    required String groupId,
    required String expenseId,
  }) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw StateError('You must be logged in.');
    }

    await _firestore
        .collection('groups')
        .doc(groupId)
        .collection('expenses')
        .doc(expenseId)
        .delete();
  }
}