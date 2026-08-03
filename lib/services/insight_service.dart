import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/analytics_data.dart';
import '../models/spending_insight.dart';

class InsightService {
  List<SpendingInsight> generateInsights(
      AnalyticsData data,
      ) {
    final insights = <SpendingInsight>[];

    if (data.totalSpending <= 0) {
      return const [
        SpendingInsight(
          title: 'Start tracking',
          message:
          'Add expenses to receive personalized spending insights.',
          icon: Icons.auto_awesome_outlined,
          type: InsightType.information,
        ),
      ];
    }

    _addTopCategoryInsight(data, insights);
    _addMonthlyTrendInsight(data, insights);
    _addAverageMonthlyInsight(data, insights);
    _addHighestMonthInsight(data, insights);
    _addCategoryConcentrationInsight(data, insights);

    return insights.take(5).toList();
  }

  SpendingInsight generatePrimaryInsight(
      AnalyticsData data,
      ) {
    final insights = generateInsights(data);

    return insights.first;
  }

  void _addTopCategoryInsight(
      AnalyticsData data,
      List<SpendingInsight> insights,
      ) {
    if (data.categoryTotals.isEmpty) {
      return;
    }

    final topEntry = data.categoryTotals.entries.reduce(
          (current, next) =>
      current.value >= next.value ? current : next,
    );

    final percentage =
        topEntry.value / data.totalSpending * 100;

    insights.add(
      SpendingInsight(
        title: 'Top spending category',
        message:
        '${topEntry.key} represents '
            '${percentage.toStringAsFixed(0)}% of your total spending '
            '(\$${topEntry.value.toStringAsFixed(2)}).',
        icon: Icons.category_outlined,
        type: percentage >= 50
            ? InsightType.warning
            : InsightType.information,
      ),
    );
  }

  void _addMonthlyTrendInsight(
      AnalyticsData data,
      List<SpendingInsight> insights,
      ) {
    final monthly = data.monthlyTotals;

    if (monthly.length < 2) {
      return;
    }

    final current = monthly.last.amount;
    final previous = monthly[monthly.length - 2].amount;

    if (previous <= 0 && current <= 0) {
      return;
    }

    if (previous <= 0 && current > 0) {
      insights.add(
        SpendingInsight(
          title: 'New monthly activity',
          message:
          'You recorded \$${current.toStringAsFixed(2)} '
              'in spending this month.',
          icon: Icons.trending_up_rounded,
          type: InsightType.information,
        ),
      );

      return;
    }

    final difference = current - previous;
    final percentage = difference.abs() / previous * 100;

    if (difference > 0.01) {
      insights.add(
        SpendingInsight(
          title: 'Spending increased',
          message:
          'You spent ${percentage.toStringAsFixed(0)}% more '
              'than last month, an increase of '
              '\$${difference.toStringAsFixed(2)}.',
          icon: Icons.trending_up_rounded,
          type: InsightType.warning,
        ),
      );
    } else if (difference < -0.01) {
      insights.add(
        SpendingInsight(
          title: 'Spending decreased',
          message:
          'You spent ${percentage.toStringAsFixed(0)}% less '
              'than last month, saving '
              '\$${difference.abs().toStringAsFixed(2)}.',
          icon: Icons.trending_down_rounded,
          type: InsightType.positive,
        ),
      );
    } else {
      insights.add(
        const SpendingInsight(
          title: 'Stable spending',
          message:
          'Your spending is approximately the same as last month.',
          icon: Icons.horizontal_rule_rounded,
          type: InsightType.information,
        ),
      );
    }
  }

  void _addAverageMonthlyInsight(
      AnalyticsData data,
      List<SpendingInsight> insights,
      ) {
    final activeMonths = data.monthlyTotals
        .where((month) => month.amount > 0)
        .toList();

    if (activeMonths.isEmpty) {
      return;
    }

    final total = activeMonths.fold<double>(
      0,
          (sum, month) => sum + month.amount,
    );

    final average = total / activeMonths.length;

    insights.add(
      SpendingInsight(
        title: 'Monthly average',
        message:
        'Your average monthly shared spending is '
            '\$${average.toStringAsFixed(2)}.',
        icon: Icons.calculate_outlined,
        type: InsightType.information,
      ),
    );
  }

  void _addHighestMonthInsight(
      AnalyticsData data,
      List<SpendingInsight> insights,
      ) {
    final activeMonths = data.monthlyTotals
        .where((month) => month.amount > 0)
        .toList();

    if (activeMonths.length < 2) {
      return;
    }

    final highest = activeMonths.reduce(
          (current, next) =>
      current.amount >= next.amount ? current : next,
    );

    insights.add(
      SpendingInsight(
        title: 'Highest spending month',
        message:
        '${_monthName(highest.month)} had your highest spending '
            'at \$${highest.amount.toStringAsFixed(2)}.',
        icon: Icons.calendar_month_outlined,
        type: InsightType.information,
      ),
    );
  }

  void _addCategoryConcentrationInsight(
      AnalyticsData data,
      List<SpendingInsight> insights,
      ) {
    if (data.categoryTotals.length < 2) {
      return;
    }

    final amounts = data.categoryTotals.values.toList()
      ..sort((a, b) => b.compareTo(a));

    final topTwo = amounts
        .take(math.min(2, amounts.length))
        .fold<double>(0, (sum, value) => sum + value);

    final percentage = topTwo / data.totalSpending * 100;

    if (percentage >= 75) {
      insights.add(
        SpendingInsight(
          title: 'Spending is concentrated',
          message:
          'Your two largest categories account for '
              '${percentage.toStringAsFixed(0)}% of your spending.',
          icon: Icons.pie_chart_outline_rounded,
          type: InsightType.warning,
        ),
      );
    }
  }

  String _monthName(DateTime date) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    return months[date.month - 1];
  }
}