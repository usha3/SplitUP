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

  const AnalyticsData({
    required this.totalSpending,
    required this.categoryTotals,
    required this.monthlyTotals,
  });

  const AnalyticsData.empty()
      : totalSpending = 0,
        categoryTotals = const {},
        monthlyTotals = const [];

  String get topCategory {
    if (categoryTotals.isEmpty) {
      return 'No data';
    }

    return categoryTotals.entries
        .reduce(
          (current, next) =>
      current.value >= next.value ? current : next,
    )
        .key;
  }
}