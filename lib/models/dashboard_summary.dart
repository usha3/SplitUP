class DashboardSummary {
  final double netBalance;
  final double youOwe;
  final double youAreOwed;
  final double monthlySpending;
  final int activeGroups;

  const DashboardSummary({
    required this.netBalance,
    required this.youOwe,
    required this.youAreOwed,
    required this.monthlySpending,
    required this.activeGroups,
  });

  const DashboardSummary.empty()
      : netBalance = 0,
        youOwe = 0,
        youAreOwed = 0,
        monthlySpending = 0,
        activeGroups = 0;
}