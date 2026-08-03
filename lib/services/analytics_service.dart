import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/analytics_data.dart';
import '../models/expense_model.dart';
import '../models/group_model.dart';

class AnalyticsService {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  AnalyticsService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  Future<AnalyticsData> loadAnalytics() async {
    final user = _auth.currentUser;

    if (user == null) {
      return const AnalyticsData.empty();
    }

    final groupSnapshot = await _firestore
        .collection('groups')
        .where(
      'members',
      arrayContains: user.uid,
    )
        .get();

    final groups = groupSnapshot.docs
        .map(GroupModel.fromFirestore)
        .toList();

    final expenses = <ExpenseModel>[];

    for (final group in groups) {
      final expenseSnapshot = await _firestore
          .collection('groups')
          .doc(group.id)
          .collection('expenses')
          .get();

      expenses.addAll(
        expenseSnapshot.docs.map(
          ExpenseModel.fromFirestore,
        ),
      );
    }

    final categoryTotals = <String, double>{};
    final monthlyMap = <String, double>{};

    final now = DateTime.now();

    final sixMonths = List.generate(6, (index) {
      return DateTime(
        now.year,
        now.month - (5 - index),
      );
    });

    for (final month in sixMonths) {
      monthlyMap[_monthKey(month)] = 0;
    }

    double totalSpending = 0;

    for (final expense in expenses) {
      if (!expense.participants.contains(user.uid)) {
        continue;
      }

      final personalShare = expense.amountPerPerson;

      totalSpending += personalShare;

      final category = expense.category.trim().isEmpty
          ? 'Other'
          : expense.category.trim();

      categoryTotals[category] =
          (categoryTotals[category] ?? 0) + personalShare;

      final createdAt = expense.createdAt;

      if (createdAt != null) {
        final key = _monthKey(createdAt);

        if (monthlyMap.containsKey(key)) {
          monthlyMap[key] =
              (monthlyMap[key] ?? 0) + personalShare;
        }
      }
    }

    final monthlyTotals = sixMonths
        .map(
          (month) => MonthlySpending(
        month: month,
        amount: monthlyMap[_monthKey(month)] ?? 0,
      ),
    )
        .toList();

    return AnalyticsData(
      totalSpending: totalSpending,
      categoryTotals: categoryTotals,
      monthlyTotals: monthlyTotals,
    );
  }

  static String _monthKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}';
  }
}