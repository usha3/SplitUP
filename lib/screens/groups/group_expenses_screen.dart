import 'package:flutter/material.dart';

import '../../models/expense_model.dart';
import '../../models/group_model.dart';
import '../../services/expense_service.dart';
import '../../utils/currency_formatter.dart';
import 'add_expense_screen.dart';
import 'edit_expense_screen.dart';
import 'receipt_viewer_screen.dart';

class GroupExpensesScreen extends StatelessWidget {
  final GroupModel group;

  const GroupExpensesScreen({
    super.key,
    required this.group,
  });

  IconData _categoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'food':
        return Icons.restaurant_rounded;

      case 'groceries':
        return Icons.shopping_cart_rounded;

      case 'rent':
        return Icons.home_rounded;

      case 'utilities':
        return Icons.electric_bolt_rounded;

      case 'travel':
        return Icons.flight_rounded;

      case 'entertainment':
        return Icons.movie_rounded;

      default:
        return Icons.receipt_long_rounded;
    }
  }

  Future<void> _confirmDeleteExpense({
    required BuildContext context,
    required ExpenseModel expense,
    required ExpenseService expenseService,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete expense?'),
          content: Text(
            'Delete "${expense.title}"? This will immediately '
                'recalculate the group totals and balances.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await expenseService.deleteExpense(
        groupId: group.id,
        expenseId: expense.id,
      );

      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Expense deleted.'),
        ),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unable to delete expense: $error',
          ),
        ),
      );
    }
  }

  void _viewReceipt(
      BuildContext context,
      String url,
      ) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReceiptViewerScreen(
          receiptUrl: url,
        ),
      ),
    );
  }

  static String _formatDate(DateTime date) {
    const months = [
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

    return '${months[date.month - 1]} '
        '${date.day}, ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final expenseService = ExpenseService();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expenses'),
      ),

      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => AddExpenseScreen(
                group: group,
              ),
            ),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('Add Expense'),
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
                  'Unable to load expenses: '
                      '${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final expenses = snapshot.data ?? [];

          final total = expenses.fold<double>(
            0,
                (sum, expense) =>
            sum + expense.amount,
          );

          return ListView(
            padding: const EdgeInsets.fromLTRB(
              16,
              16,
              16,
              100,
            ),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    children: [
                      const Text(
                        'Total group spending',
                      ),
                      const SizedBox(height: 6),
                      Text(
                        formatCurrency(
                          total,
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

              const SizedBox(height: 24),

              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Expenses',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(
                        fontWeight:
                        FontWeight.bold,
                      ),
                    ),
                  ),
                  Text(
                    '${expenses.length}',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium,
                  ),
                ],
              ),

              const SizedBox(height: 10),

              if (expenses.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        'No expenses yet.\n'
                            'Tap Add Expense to get started.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                )
              else
                ...expenses.map(
                      (expense) {
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Icon(
                            _categoryIcon(
                              expense.category,
                            ),
                          ),
                        ),

                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                expense.title,
                                style:
                                const TextStyle(
                                  fontWeight:
                                  FontWeight.w600,
                                ),
                              ),
                            ),

                            if (expense
                                .generatedFromRecurring)
                              Container(
                                padding:
                                const EdgeInsets
                                    .symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration:
                                BoxDecoration(
                                  color: Colors.blue
                                      .withValues(
                                    alpha: 0.12,
                                  ),
                                  borderRadius:
                                  BorderRadius
                                      .circular(20),
                                ),
                                child: const Row(
                                  mainAxisSize:
                                  MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons
                                          .repeat_rounded,
                                      size: 14,
                                      color:
                                      Colors.blue,
                                    ),
                                    SizedBox(
                                      width: 4,
                                    ),
                                    Text(
                                      'Recurring',
                                      style:
                                      TextStyle(
                                        color:
                                        Colors.blue,
                                        fontSize: 11,
                                        fontWeight:
                                        FontWeight
                                            .bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),

                        subtitle: Text(
                          '${expense.category} • '
                              '${formatCurrency(
                            expense.amountPerPerson,
                            group.currencyCode,
                          )} each\n'
                              'Total: ${formatCurrency(
                            expense.amount,
                            group.currencyCode,
                          )}'
                              '${expense.createdAt != null
                              ? '\nDate: ${_formatDate(
                            expense.createdAt!,
                          )}'
                              : ''}',
                        ),

                        trailing: Row(
                          mainAxisSize:
                          MainAxisSize.min,
                          children: [
                            if (expense.receiptUrl !=
                                null &&
                                expense.receiptUrl!
                                    .isNotEmpty)
                              IconButton(
                                tooltip:
                                'View Receipt',
                                icon: const Icon(
                                  Icons
                                      .receipt_long_rounded,
                                ),
                                onPressed: () {
                                  _viewReceipt(
                                    context,
                                    expense
                                        .receiptUrl!,
                                  );
                                },
                              ),

                            PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value ==
                                    'edit') {
                                  Navigator.of(
                                    context,
                                  ).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          EditExpenseScreen(
                                            group:
                                            group,
                                            expense:
                                            expense,
                                          ),
                                    ),
                                  );
                                }

                                if (value ==
                                    'delete') {
                                  _confirmDeleteExpense(
                                    context:
                                    context,
                                    expense:
                                    expense,
                                    expenseService:
                                    expenseService,
                                  );
                                }
                              },
                              itemBuilder: (_) =>
                              const [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons
                                            .edit_outlined,
                                      ),
                                      SizedBox(
                                          width: 10),
                                      Text('Edit'),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons
                                            .delete_outline,
                                      ),
                                      SizedBox(
                                          width: 10),
                                      Text('Delete'),
                                    ],
                                  ),
                                ),
                              ],
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