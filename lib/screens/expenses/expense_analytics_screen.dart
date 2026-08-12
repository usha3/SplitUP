import 'package:flutter/material.dart';

import '../../models/expense_model.dart';
import '../../models/group_model.dart';
import '../../services/expense_service.dart';
import '../../utils/currency_formatter.dart';
import 'package:fl_chart/fl_chart.dart';

class ExpenseAnalyticsScreen extends StatelessWidget {
  final GroupModel group;

  const ExpenseAnalyticsScreen({
    super.key,
    required this.group,
  });

  @override
  Widget build(BuildContext context) {
    final expenseService = ExpenseService();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expense Analytics'),
      ),
      body: StreamBuilder<List<ExpenseModel>>(
        stream: expenseService.getGroupExpenses(
          group.id,
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState ==
              ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Unable to load analytics: '
                      '${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final expenses = snapshot.data ?? [];

          final totalSpending = expenses.fold<double>(
            0,
                (total, expense) =>
            total + expense.amount,
          );

          double equalSplitTotal = 0;
          double itemizedSplitTotal = 0;

          for (final expense in expenses) {
            if (expense.splitType == 'itemized') {
              itemizedSplitTotal += expense.amount;
            } else {
              equalSplitTotal += expense.amount;
            }
          }

          final categoryTotals = <String, double>{};

          for (final expense in expenses) {
            final category = expense.category.trim().isEmpty
                ? 'Other'
                : expense.category.trim();

            categoryTotals[category] =
                (categoryTotals[category] ?? 0) +
                    expense.amount;
          }

          final sortedCategories =
          categoryTotals.entries.toList()
            ..sort(
                  (a, b) => b.value.compareTo(a.value),
            );

          final monthlyTotals = <String, double>{};

          for (final expense in expenses) {
            final date = expense.createdAt;

            if (date == null) {
              continue;
            }

            final key =
                '${date.year}-${date.month.toString().padLeft(2, '0')}';

            monthlyTotals[key] =
                (monthlyTotals[key] ?? 0) + expense.amount;
          }

          final sortedMonths = monthlyTotals.entries.toList()
            ..sort(
                  (a, b) => b.key.compareTo(a.key),
            );

          final chartMonths = sortedMonths.take(6).toList().reversed.toList();

          final maxMonthlySpending = chartMonths.isEmpty
              ? 0.0
              : chartMonths
              .map((entry) => entry.value)
              .reduce((a, b) => a > b ? a : b);

          final topCategory = sortedCategories.isEmpty
              ? null
              : sortedCategories.first;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Overview',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 10),

              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    children: [
                      const Text(
                        'Total Spending',
                      ),
                      const SizedBox(height: 6),
                      Text(
                        formatCurrency(
                          totalSpending,
                          group.currencyCode,
                        ),
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(
                          fontWeight:
                          FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              if (topCategory != null)
                Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                      child: Icon(
                        Icons.trending_up_rounded,
                      ),
                    ),
                    title: const Text(
                      'Top Spending Category',
                    ),
                    subtitle: Text(
                      topCategory.key,
                    ),
                    trailing: Text(
                      formatCurrency(
                        topCategory.value,
                        group.currencyCode,
                      ),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            const Icon(
                              Icons.people_outline,
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Equal Split',
                            ),
                            const SizedBox(height: 4),
                            Text(
                              formatCurrency(
                                equalSplitTotal,
                                group.currencyCode,
                              ),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 17,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 12),

                  Expanded(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            const Icon(
                              Icons.receipt_long_outlined,
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'By Item',
                            ),
                            const SizedBox(height: 4),
                            Text(
                              formatCurrency(
                                itemizedSplitTotal,
                                group.currencyCode,
                              ),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 17,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              Text(
                'Monthly Spending',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 10),

// Monthly bar chart
              if (chartMonths.isNotEmpty) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      16,
                      24,
                      16,
                      16,
                    ),
                    child: SizedBox(
                      height: 260,
                      child: BarChart(
                        BarChartData(
                          maxY: maxMonthlySpending > 0
                              ? maxMonthlySpending * 1.2
                              : 100,

                          alignment: BarChartAlignment.spaceAround,

                          gridData: const FlGridData(
                            show: false,
                          ),

                          borderData: FlBorderData(
                            show: false,
                          ),

                          barTouchData: BarTouchData(
                            enabled: true,
                            touchTooltipData: BarTouchTooltipData(
                              getTooltipItem: (
                                  barGroup,
                                  groupIndex,
                                  rod,
                                  rodIndex,
                                  ) {
                                return BarTooltipItem(
                                  formatCurrency(
                                    rod.toY,
                                    group.currencyCode,
                                  ),
                                  const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                );
                              },
                            ),
                          ),

                          titlesData: FlTitlesData(
                            topTitles: const AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: false,
                              ),
                            ),
                            rightTitles: const AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: false,
                              ),
                            ),
                            leftTitles: const AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: false,
                              ),
                            ),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 36,
                                getTitlesWidget: (
                                    value,
                                    meta,
                                    ) {
                                  final index = value.toInt();

                                  if (index < 0 ||
                                      index >= chartMonths.length) {
                                    return const SizedBox.shrink();
                                  }

                                  final parts =
                                  chartMonths[index]
                                      .key
                                      .split('-');

                                  final month =
                                  int.parse(parts[1]);

                                  const monthNames = [
                                    '',
                                    'Jan',
                                    'Feb',
                                    'Mar',
                                    'Apr',
                                    'May',
                                    'Jun',
                                    'Jul',
                                    'Aug',
                                    'Sep',
                                    'Oct',
                                    'Nov',
                                    'Dec',
                                  ];

                                  return Padding(
                                    padding: const EdgeInsets.only(
                                      top: 8,
                                    ),
                                    child: Text(
                                      monthNames[month],
                                      style: const TextStyle(
                                        fontSize: 12,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),

                          barGroups: List.generate(
                            chartMonths.length,
                                (index) {
                              final entry = chartMonths[index];

                              return BarChartGroupData(
                                x: index,
                                barRods: [
                                  BarChartRodData(
                                    toY: entry.value,
                                    width: 20,
                                    borderRadius:
                                    BorderRadius.circular(6),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),
              ],

// Monthly spending list
              if (sortedMonths.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        'No monthly spending data available.',
                      ),
                    ),
                  ),
                )
              else
                ...sortedMonths.map(
                      (entry) {
                    final parts = entry.key.split('-');

                    final year = int.parse(parts[0]);
                    final month = int.parse(parts[1]);

                    const monthNames = [
                      '',
                      'Jan',
                      'Feb',
                      'Mar',
                      'Apr',
                      'May',
                      'Jun',
                      'Jul',
                      'Aug',
                      'Sep',
                      'Oct',
                      'Nov',
                      'Dec',
                    ];

                    final label =
                        '${monthNames[month]} $year';

                    return Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                          child: Icon(
                            Icons.calendar_month_outlined,
                          ),
                        ),
                        title: Text(label),
                        trailing: Text(
                          formatCurrency(
                            entry.value,
                            group.currencyCode,
                          ),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    );
                  },
                ),

              const SizedBox(height: 24),

              Text(
                'Spending by Category',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 10),

              if (sortedCategories.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        'No expense data available yet.',
                      ),
                    ),
                  ),
                )
              else
                ...sortedCategories.map(
                      (entry) {
                    final percentage =
                    totalSpending > 0
                        ? entry.value /
                        totalSpending
                        : 0.0;

                    return Card(
                      child: Padding(
                        padding:
                        const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment:
                          CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    entry.key,
                                    style:
                                    const TextStyle(
                                      fontWeight:
                                      FontWeight.bold,
                                    ),
                                  ),
                                ),
                                Text(
                                  formatCurrency(
                                    entry.value,
                                    group.currencyCode,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 10),

                            LinearProgressIndicator(
                              value: percentage,
                            ),

                            const SizedBox(height: 6),

                            Text(
                              '${(percentage * 100).toStringAsFixed(1)}% of total spending',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}