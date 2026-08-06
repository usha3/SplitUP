import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/analytics_data.dart';
import '../models/spending_insight.dart';
import '../utils/currency_formatter.dart';

class InsightService {
  List<SpendingInsight> generateInsights(
      AnalyticsData data, {
        String currencyCode = 'USD',
      }) {
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

    final insights = <SpendingInsight>[];

    _addMonthlyTrendInsight(
      data,
      insights,
      currencyCode,
    );

    _addProjectedSpendingInsight(
      data,
      insights,
      currencyCode,
    );

    _addTopCategoryInsight(
      data,
      insights,
      currencyCode,
    );

    _addLargestExpenseInsight(
      data,
      insights,
      currencyCode,
    );

    _addAverageExpenseInsight(
      data,
      insights,
      currencyCode,
    );

    _addWeekendInsight(
      data,
      insights,
      currencyCode,
    );

    _addCategoryConcentrationInsight(
      data,
      insights,
    );

    _addRecommendationInsight(
      data,
      insights,
      currencyCode,
    );
    return insights.take(8).toList();
  }

  SpendingInsight generatePrimaryInsight(
      AnalyticsData data, {
        String currencyCode = 'USD',
      }) {
    return generateInsights(
      data,
      currencyCode: currencyCode,
    ).first;
  }

  void _addMonthlyTrendInsight(
      AnalyticsData data,
      List<SpendingInsight> insights,
      String currencyCode,
      ) {
    final current = data.currentMonthSpending;
    final previous = data.previousMonthSpending;

    if (previous <= 0 && current <= 0) {
      return;
    }

    if (previous <= 0 && current > 0) {
      insights.add(
        SpendingInsight(
          title: 'New monthly activity',
          message:
          'You have recorded ${formatCurrency(current, currencyCode)} '
              'in personal spending this month.',
          icon: Icons.trending_up_rounded,
          type: InsightType.information,
        ),
      );

      return;
    }

    final difference =
        data.monthOverMonthDifference;

    final percentage =
        data.monthOverMonthPercentage;

    if (difference > 0.01) {
      insights.add(
        SpendingInsight(
          title: 'Spending increased',
          message:
          'You have spent ${percentage.toStringAsFixed(0)}% more '
              'than last month, an increase of '
              '${formatCurrency(difference, currencyCode)}.',
          icon: Icons.trending_up_rounded,
          type: InsightType.warning,
        ),
      );
    } else if (difference < -0.01) {
      insights.add(
        SpendingInsight(
          title: 'Spending decreased',
          message:
          'You have spent ${percentage.toStringAsFixed(0)}% less '
              'than last month, a reduction of '
              '${formatCurrency(difference.abs(), currencyCode)}.',
          icon: Icons.savings_outlined,
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

  void _addProjectedSpendingInsight(
      AnalyticsData data,
      List<SpendingInsight> insights,
      String currencyCode,
      ) {
    final projection =
        data.projectedMonthEndSpending;

    if (projection <= 0) {
      return;
    }

    insights.add(
      SpendingInsight(
        title: 'Month-end projection',
        message:
        'Estimated month-end spending: '
            '${formatCurrency(projection, currencyCode)}. '
            'Based on your current spending trend.',
        icon: Icons.calendar_month_outlined,
        type: InsightType.information,
      ),
    );
  }

  void _addTopCategoryInsight(
      AnalyticsData data,
      List<SpendingInsight> insights,
      String currencyCode,
      ) {
    if (data.categoryTotals.isEmpty) {
      return;
    }

    final percentage =
        data.topCategoryPercentage;

    insights.add(
      SpendingInsight(
        title: 'Top spending category',
        message:
        '${data.topCategory} represents '
            '${percentage.toStringAsFixed(0)}% of your spending '
            '(${formatCurrency(data.topCategoryAmount, currencyCode)}).',
        icon: Icons.pie_chart_outline_rounded,
        type: percentage >= 50
            ? InsightType.warning
            : InsightType.information,
      ),
    );
  }

  void _addLargestExpenseInsight(
      AnalyticsData data,
      List<SpendingInsight> insights,
      String currencyCode,
      ) {
    if (data.largestExpenseAmount <= 0) {
      return;
    }

    insights.add(
      SpendingInsight(
        title: 'Largest personal expense',
        message:
        '${data.largestExpenseTitle} was your largest share at '
            '${formatCurrency(data.largestExpenseAmount, currencyCode)}.',
        icon: Icons.receipt_long_outlined,
        type: InsightType.information,
      ),
    );
  }

  void _addAverageExpenseInsight(
      AnalyticsData data,
      List<SpendingInsight> insights,
      String currencyCode,
      ) {
    if (data.expenseCount <= 0) {
      return;
    }

    insights.add(
      SpendingInsight(
        title: 'Average expense',
        message:
        'Your average personal share across '
            '${data.expenseCount} expense'
            '${data.expenseCount == 1 ? '' : 's'} is '
            '${formatCurrency(data.averageExpense, currencyCode)}.',
        icon: Icons.calculate_outlined,
        type: InsightType.information,
      ),
    );
  }

  void _addWeekendInsight(
      AnalyticsData data,
      List<SpendingInsight> insights,
      String currencyCode,
      ) {
    final weekend = data.weekendSpending;
    final weekday = data.weekdaySpending;

    if (weekend <= 0 && weekday <= 0) {
      return;
    }

    if (weekend > weekday && weekday > 0) {
      final ratio = data.weekendToWeekdayRatio;

      insights.add(
        SpendingInsight(
          title: 'Weekend spending is higher',
          message:
          'Weekend spending is ${ratio.toStringAsFixed(1)}× '
              'your weekday spending: '
              '${formatCurrency(weekend, currencyCode)} versus '
              '${formatCurrency(weekday, currencyCode)}.',
          icon: Icons.weekend_outlined,
          type: ratio >= 1.5
              ? InsightType.warning
              : InsightType.information,
        ),
      );
    } else {
      insights.add(
        SpendingInsight(
          title: 'Weekday spending leads',
          message:
          'You spent ${formatCurrency(weekday, currencyCode)} '
              'on weekdays and '
              '${formatCurrency(weekend, currencyCode)} '
              'on weekends.',
          icon: Icons.date_range_outlined,
          type: InsightType.information,
        ),
      );
    }
  }

  void _addCategoryConcentrationInsight(
      AnalyticsData data,
      List<SpendingInsight> insights,
      ) {
    if (data.categoryTotals.length < 2 ||
        data.totalSpending <= 0) {
      return;
    }

    final amounts =
    data.categoryTotals.values.toList()
      ..sort((a, b) => b.compareTo(a));

    final topTwo = amounts
        .take(math.min(2, amounts.length))
        .fold<double>(
      0,
          (sum, value) => sum + value,
    );

    final percentage =
        topTwo / data.totalSpending * 100;

    if (percentage >= 75) {
      insights.add(
        SpendingInsight(
          title: 'Spending is concentrated',
          message:
          'Your two largest categories account for '
              '${percentage.toStringAsFixed(0)}% of your total spending.',
          icon: Icons.donut_large_outlined,
          type: InsightType.warning,
        ),
      );
    }
  }
  void _addRecommendationInsight(
      AnalyticsData data,
      List<SpendingInsight> insights,
      String currencyCode,
      ) {
    if (data.totalSpending <= 0 ||
        data.categoryTotals.isEmpty) {
      return;
    }

    final suggestedReduction =
        data.topCategoryAmount * 0.15;

    if (suggestedReduction <= 0) {
      return;
    }

    insights.add(
      SpendingInsight(
        title: 'Save ${formatCurrency(
          suggestedReduction,
          currencyCode,
        )} next month',
        message:
        'Reduce ${data.topCategory} expenses by 15% '
            'to reach this saving.',
        icon: Icons.lightbulb_outline_rounded,
        type: InsightType.positive,
      ),
    );
  }
}