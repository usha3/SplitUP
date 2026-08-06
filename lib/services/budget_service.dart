import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/group_budget_model.dart';

class BudgetService {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  BudgetService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore =
      firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  DocumentReference<Map<String, dynamic>> _budgetDocument(
      String groupId,
      ) {
    return _firestore
        .collection('groups')
        .doc(groupId)
        .collection('settings')
        .doc('budget');
  }

  Stream<GroupBudgetModel?> watchBudget(
      String groupId,
      ) {
    return _budgetDocument(groupId)
        .snapshots()
        .map((document) {
      if (!document.exists) {
        return null;
      }

      return GroupBudgetModel.fromFirestore(document);
    });
  }

  Future<GroupBudgetModel?> getBudget(
      String groupId,
      ) async {
    final document =
    await _budgetDocument(groupId).get();

    if (!document.exists) {
      return null;
    }

    return GroupBudgetModel.fromFirestore(document);
  }

  Future<void> saveBudget({
    required String groupId,
    required double monthlyLimit,
    required String currencyCode,
    bool alertsEnabled = true,
  }) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw StateError(
        'You must be logged in to update a budget.',
      );
    }

    if (monthlyLimit <= 0) {
      throw ArgumentError(
        'The monthly budget must be greater than zero.',
      );
    }

    final groupDocument = await _firestore
        .collection('groups')
        .doc(groupId)
        .get();

    if (!groupDocument.exists) {
      throw StateError('Group not found.');
    }

    final groupData = groupDocument.data() ?? {};

    final members = List<String>.from(
      groupData['members'] as List<dynamic>? ?? const [],
    );

    if (!members.contains(user.uid)) {
      throw StateError(
        'Only group members can update this budget.',
      );
    }

    await _budgetDocument(groupId).set(
      {
        'monthlyLimit': monthlyLimit,
        'currencyCode': currencyCode,
        'alertsEnabled': alertsEnabled,
        'updatedBy': user.uid,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> deleteBudget(String groupId) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw StateError(
        'You must be logged in to delete a budget.',
      );
    }

    await _budgetDocument(groupId).delete();
  }

  Future<double> calculateCurrentMonthSpending({
    required String groupId,
  }) async {
    final now = DateTime.now();

    final monthStart = DateTime(
      now.year,
      now.month,
      1,
    );

    final nextMonthStart = DateTime(
      now.year,
      now.month + 1,
      1,
    );

    final snapshot = await _firestore
        .collection('groups')
        .doc(groupId)
        .collection('expenses')
        .where(
      'createdAt',
      isGreaterThanOrEqualTo:
      Timestamp.fromDate(monthStart),
    )
        .where(
      'createdAt',
      isLessThan:
      Timestamp.fromDate(nextMonthStart),
    )
        .get();

    return snapshot.docs.fold<double>(
      0,
          (total, document) {
        final data = document.data();

        return total +
            ((data['amount'] as num?)?.toDouble() ?? 0);
      },
    );
  }
}