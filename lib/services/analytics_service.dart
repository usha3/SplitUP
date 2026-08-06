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
  })  : _firestore =
      firestore ?? FirebaseFirestore.instance,
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
    double largestExpenseAmount = 0;
    String largestExpenseTitle = '';

    double weekendSpending = 0;
    double weekdaySpending = 0;

    int expenseCount = 0;

    for (final expense in expenses) {
      if (!expense.participants.contains(user.uid)) {
        continue;
      }

      final personalShare = expense.amountPerPerson;

      if (personalShare <= 0) {
        continue;
      }

      expenseCount++;
      totalSpending += personalShare;

      if (personalShare > largestExpenseAmount) {
        largestExpenseAmount = personalShare;
        largestExpenseTitle = expense.title.trim().isEmpty
            ? 'Untitled expense'
            : expense.title.trim();
      }

      final category = expense.category.trim().isEmpty
          ? 'Other'
          : expense.category.trim();

      categoryTotals[category] =
          (categoryTotals[category] ?? 0) +
              personalShare;

      final createdAt = expense.createdAt;

      if (createdAt == null) {
        continue;
      }

      final monthKey = _monthKey(createdAt);

      if (monthlyMap.containsKey(monthKey)) {
        monthlyMap[monthKey] =
            (monthlyMap[monthKey] ?? 0) +
                personalShare;
      }

      final isWeekend =
          createdAt.weekday == DateTime.saturday ||
              createdAt.weekday == DateTime.sunday;

      if (isWeekend) {
        weekendSpending += personalShare;
      } else {
        weekdaySpending += personalShare;
      }
    }

    final monthlyTotals = sixMonths
        .map(
          (month) => MonthlySpending(
        month: month,
        amount:
        monthlyMap[_monthKey(month)] ?? 0,
      ),
    )
        .toList();

    final currentMonthKey = _monthKey(now);

    final previousMonth = DateTime(
      now.year,
      now.month - 1,
    );

    final previousMonthKey =
    _monthKey(previousMonth);

    final currentMonthSpending =
        monthlyMap[currentMonthKey] ?? 0;

    final previousMonthSpending =
        monthlyMap[previousMonthKey] ?? 0;

    final projectedMonthEndSpending =
    _projectMonthEndSpending(
      currentSpending: currentMonthSpending,
      now: now,
    );

    final averageExpense = expenseCount == 0
        ? 0.0
        : totalSpending / expenseCount;

    return AnalyticsData(
      totalSpending: totalSpending,
      categoryTotals: categoryTotals,
      monthlyTotals: monthlyTotals,
      expenseCount: expenseCount,
      averageExpense: averageExpense,
      largestExpenseTitle: largestExpenseTitle,
      largestExpenseAmount: largestExpenseAmount,
      currentMonthSpending: currentMonthSpending,
      previousMonthSpending: previousMonthSpending,
      projectedMonthEndSpending:
      projectedMonthEndSpending,
      weekendSpending: weekendSpending,
      weekdaySpending: weekdaySpending,
    );
  }

  static double _projectMonthEndSpending({
    required double currentSpending,
    required DateTime now,
  }) {
    if (currentSpending <= 0 || now.day <= 0) {
      return 0;
    }

    final daysInMonth = DateTime(
      now.year,
      now.month + 1,
      0,
    ).day;

    final dailyAverage =
        currentSpending / now.day;

    return dailyAverage * daysInMonth;
  }

  static String _monthKey(DateTime date) {
    return '${date.year}-'
        '${date.month.toString().padLeft(2, '0')}';
  }
}