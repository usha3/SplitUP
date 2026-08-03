import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../models/analytics_data.dart';
import '../../services/analytics_service.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() =>
      _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  final AnalyticsService _analyticsService =
  AnalyticsService();

  late Future<AnalyticsData> _analyticsFuture;

  @override
  void initState() {
    super.initState();
    _analyticsFuture = _analyticsService.loadAnalytics();
  }

  Future<void> _refresh() async {
    setState(() {
      _analyticsFuture =
          _analyticsService.loadAnalytics();
    });

    await _analyticsFuture;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics'),
      ),
      body: FutureBuilder<AnalyticsData>(
        future: _analyticsFuture,
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
                  'Unable to load analytics:\n'
                      '${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final data =
              snapshot.data ?? const AnalyticsData.empty();

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics:
              const AlwaysScrollableScrollPhysics(),
              padding:
              const EdgeInsets.fromLTRB(16, 16, 16, 40),
              children: [
                _OverviewCard(data: data),
                const SizedBox(height: 20),
                Text(
                  'Monthly spending',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                _MonthlyChart(
                  monthlyTotals: data.monthlyTotals,
                ),
                const SizedBox(height: 24),
                Text(
                  'Spending by category',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                _CategoryChart(
                  categoryTotals: data.categoryTotals,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _OverviewCard extends StatelessWidget {
  final AnalyticsData data;

  const _OverviewCard({
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Expanded(
              child: _OverviewItem(
                label: 'Your total',
                value:
                '\$${data.totalSpending.toStringAsFixed(2)}',
                icon: Icons.account_balance_wallet_outlined,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _OverviewItem(
                label: 'Top category',
                value: data.topCategory,
                icon: Icons.category_outlined,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OverviewItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _OverviewItem({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CircleAvatar(
          backgroundColor: Theme.of(context)
              .colorScheme
              .primaryContainer,
          child: Icon(icon),
        ),
        const SizedBox(height: 10),
        Text(
          value,
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _MonthlyChart extends StatelessWidget {
  final List<MonthlySpending> monthlyTotals;

  const _MonthlyChart({
    required this.monthlyTotals,
  });

  @override
  Widget build(BuildContext context) {
    if (monthlyTotals.isEmpty) {
      return const _EmptyChart(
        message: 'No monthly spending data yet.',
      );
    }

    final highest = monthlyTotals.fold<double>(
      0,
          (current, item) =>
          math.max(current, item.amount),
    );

    final maxY = highest <= 0 ? 100.0 : highest * 1.25;

    return Card(
      child: Padding(
        padding:
        const EdgeInsets.fromLTRB(12, 24, 18, 16),
        child: SizedBox(
          height: 260,
          child: BarChart(
            BarChartData(
              minY: 0,
              maxY: maxY,
              alignment:
              BarChartAlignment.spaceAround,
              borderData: FlBorderData(show: false),
              gridData: const FlGridData(
                drawVerticalLine: false,
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (
                      group,
                      groupIndex,
                      rod,
                      rodIndex,
                      ) {
                    return BarTooltipItem(
                      '\$${rod.toY.toStringAsFixed(2)}',
                      const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    );
                  },
                ),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles:
                  SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles:
                  SideTitles(showTitles: false),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 46,
                    getTitlesWidget: (value, meta) {
                      return Text(
                        '\$${value.toInt()}',
                        style:
                        const TextStyle(fontSize: 11),
                      );
                    },
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      final index = value.toInt();

                      if (index < 0 ||
                          index >= monthlyTotals.length) {
                        return const SizedBox.shrink();
                      }

                      return Padding(
                        padding:
                        const EdgeInsets.only(top: 8),
                        child: Text(
                          _monthLabel(
                            monthlyTotals[index].month,
                          ),
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
                monthlyTotals.length,
                    (index) {
                  return BarChartGroupData(
                    x: index,
                    barRods: [
                      BarChartRodData(
                        toY: monthlyTotals[index].amount,
                        width: 18,
                        borderRadius:
                        BorderRadius.circular(6),
                        color: Theme.of(context)
                            .colorScheme
                            .primary,
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _monthLabel(DateTime date) {
    const names = [
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

    return names[date.month - 1];
  }
}

class _CategoryChart extends StatelessWidget {
  final Map<String, double> categoryTotals;

  const _CategoryChart({
    required this.categoryTotals,
  });

  @override
  Widget build(BuildContext context) {
    final entries = categoryTotals.entries
        .where((entry) => entry.value > 0)
        .toList()
      ..sort(
            (a, b) => b.value.compareTo(a.value),
      );

    if (entries.isEmpty) {
      return const _EmptyChart(
        message: 'No category data yet.',
      );
    }

    final total = entries.fold<double>(
      0,
          (sum, entry) => sum + entry.value,
    );

    final colors = [
      Theme.of(context).colorScheme.primary,
      Theme.of(context).colorScheme.secondary,
      Theme.of(context).colorScheme.tertiary,
      Theme.of(context).colorScheme.error,
      Theme.of(context)
          .colorScheme
          .primaryContainer,
      Theme.of(context)
          .colorScheme
          .secondaryContainer,
      Theme.of(context)
          .colorScheme
          .tertiaryContainer,
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            SizedBox(
              height: 230,
              child: PieChart(
                PieChartData(
                  centerSpaceRadius: 50,
                  sectionsSpace: 3,
                  sections: List.generate(
                    entries.length,
                        (index) {
                      final entry = entries[index];
                      final percentage =
                          entry.value / total * 100;

                      return PieChartSectionData(
                        value: entry.value,
                        color:
                        colors[index % colors.length],
                        radius: 60,
                        title:
                        '${percentage.toStringAsFixed(0)}%',
                        titleStyle: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      );
                    },
                  ),
                ),
                duration:
                const Duration(milliseconds: 300),
              ),
            ),
            const SizedBox(height: 18),
            ...List.generate(entries.length, (index) {
              final entry = entries[index];

              return Padding(
                padding:
                const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: colors[
                        index % colors.length],
                        borderRadius:
                        BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(entry.key),
                    ),
                    Text(
                      '\$${entry.value.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _EmptyChart extends StatelessWidget {
  final String message;

  const _EmptyChart({
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(
              Icons.bar_chart_rounded,
              size: 54,
              color:
              Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}