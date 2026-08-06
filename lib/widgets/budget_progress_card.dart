import 'package:flutter/material.dart';

import '../models/group_budget_model.dart';
import '../models/group_model.dart';
import '../services/budget_service.dart';
import '../utils/currency_formatter.dart';

class BudgetProgressCard extends StatelessWidget {
  final GroupModel group;
  final VoidCallback onEditBudget;

  const BudgetProgressCard({
    super.key,
    required this.group,
    required this.onEditBudget,
  });

  @override
  Widget build(BuildContext context) {
    final budgetService = BudgetService();

    return StreamBuilder<GroupBudgetModel?>(
      stream: budgetService.watchBudget(group.id),
      builder: (context, budgetSnapshot) {
        if (budgetSnapshot.connectionState == ConnectionState.waiting) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: CircularProgressIndicator(),
              ),
            ),
          );
        }

        if (budgetSnapshot.hasError) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Unable to load budget: ${budgetSnapshot.error}',
              ),
            ),
          );
        }

        final budget = budgetSnapshot.data;

        if (budget == null || budget.monthlyLimit <= 0) {
          return Card(
            child: ListTile(
              leading: const CircleAvatar(
                child: Icon(Icons.savings_outlined),
              ),
              title: const Text(
                'Set a monthly budget',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: const Text(
                'Set a monthly limit to track spending and receive alerts.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: onEditBudget,
            ),
          );
        }

        return FutureBuilder<double>(
          future: budgetService.calculateCurrentMonthSpending(
            groupId: group.id,
          ),
          builder: (context, spendingSnapshot) {
            if (spendingSnapshot.connectionState ==
                ConnectionState.waiting) {
              return const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: CircularProgressIndicator(),
                  ),
                ),
              );
            }

            if (spendingSnapshot.hasError) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Unable to calculate monthly spending: '
                        '${spendingSnapshot.error}',
                  ),
                ),
              );
            }

            final spent = spendingSnapshot.data ?? 0;
            final limit = budget.monthlyLimit;

            final rawProgress = limit <= 0 ? 0.0 : spent / limit;
            final progress = rawProgress.clamp(0.0, 1.0);
            final percentage = rawProgress * 100;
            final remaining = limit - spent;

            final progressColor = percentage >= 100
                ? Theme.of(context).colorScheme.error
                : percentage >= 80
                ? Colors.orange
                : Colors.green;

            final statusText = percentage >= 100
                ? 'Budget exceeded'
                : percentage >= 80
                ? 'Close to budget limit'
                : 'Budget on track';

            return Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onEditBudget,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: progressColor.withValues(
                              alpha: 0.12,
                            ),
                            child: Icon(
                              Icons.savings_outlined,
                              color: progressColor,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Monthly budget',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: progressColor.withValues(
                                      alpha: 0.12,
                                    ),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    statusText,
                                    style: TextStyle(
                                      color: progressColor,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Edit budget',
                            onPressed: onEditBudget,
                            icon: const Icon(Icons.edit_outlined),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      TweenAnimationBuilder<double>(
                        tween: Tween<double>(
                          begin: 0,
                          end: progress,
                        ),
                        duration: const Duration(milliseconds: 700),
                        curve: Curves.easeOutCubic,
                        builder: (context, value, child) {
                          return LinearProgressIndicator(
                            value: value,
                            minHeight: 12,
                            borderRadius: BorderRadius.circular(12),
                            color: progressColor,
                            backgroundColor: progressColor.withValues(
                              alpha: 0.12,
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Spent this month',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${formatCurrency(spent, group.currencyCode)} '
                                      '/ ${formatCurrency(limit, group.currencyCode)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '${percentage.toStringAsFixed(0)}%',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: progressColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            remaining >= 0
                                ? Icons.account_balance_wallet_outlined
                                : Icons.warning_amber_rounded,
                            size: 18,
                            color: progressColor,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              remaining >= 0
                                  ? '${formatCurrency(remaining, group.currencyCode)} remaining'
                                  : '${formatCurrency(remaining.abs(), group.currencyCode)} over budget',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: progressColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}