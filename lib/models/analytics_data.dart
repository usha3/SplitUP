class MonthlySpending {
  final DateTime month;
  final double amount;

  const MonthlySpending({
    required this.month,
    required this.amount,
  });
}

class AnalyticsData {
  final double totalSpending;
  final Map<String, double> categoryTotals;
  final List<MonthlySpending> monthlyTotals;

  final int expenseCount;
  final double averageExpense;

  final String largestExpenseTitle;
  final double largestExpenseAmount;

  final double currentMonthSpending;
  final double previousMonthSpending;
  final double projectedMonthEndSpending;

  final double weekendSpending;
  final double weekdaySpending;

  const AnalyticsData({
    required this.totalSpending,
    required this.categoryTotals,
    required this.monthlyTotals,
    required this.expenseCount,
    required this.averageExpense,
    required this.largestExpenseTitle,
    required this.largestExpenseAmount,
    required this.currentMonthSpending,
    required this.previousMonthSpending,
    required this.projectedMonthEndSpending,
    required this.weekendSpending,
    required this.weekdaySpending,
  });

  const AnalyticsData.empty()
      : totalSpending = 0,
        categoryTotals = const {},
        monthlyTotals = const [],
        expenseCount = 0,
        averageExpense = 0,
        largestExpenseTitle = '',
        largestExpenseAmount = 0,
        currentMonthSpending = 0,
        previousMonthSpending = 0,
        projectedMonthEndSpending = 0,
        weekendSpending = 0,
        weekdaySpending = 0;

  String get topCategory {
    if (categoryTotals.isEmpty) {
      return 'No data';
    }

    return categoryTotals.entries
        .reduce(
          (current, next) =>
      current.value >= next.value
          ? current
          : next,
    )
        .key;
  }

  double get topCategoryAmount {
    if (categoryTotals.isEmpty) {
      return 0;
    }

    return categoryTotals.entries
        .reduce(
          (current, next) =>
      current.value >= next.value
          ? current
          : next,
    )
        .value;
  }

  double get topCategoryPercentage {
    if (totalSpending <= 0) {
      return 0;
    }

    return topCategoryAmount / totalSpending * 100;
  }

  double get monthOverMonthDifference {
    return currentMonthSpending -
        previousMonthSpending;
  }

  double get monthOverMonthPercentage {
    if (previousMonthSpending <= 0) {
      return 0;
    }

    return monthOverMonthDifference.abs() /
        previousMonthSpending *
        100;
  }

  double get weekendToWeekdayRatio {
    if (weekdaySpending <= 0) {
      return weekendSpending > 0
          ? double.infinity
          : 0;
    }

    return weekendSpending / weekdaySpending;
  }
}