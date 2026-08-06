import 'package:flutter/material.dart';

import '../../models/debt_model.dart';
import '../../models/expense_model.dart';
import '../../models/group_model.dart';
import '../../models/settlement_model.dart';
import '../../models/user_model.dart';
import '../../services/balance_service.dart';
import '../../services/expense_service.dart';
import '../../services/settlement_service.dart';
import '../../services/user_service.dart';
import 'add_expense_screen.dart';
import 'edit_expense_screen.dart';
import 'manage_members_screen.dart';
import 'group_report_screen.dart';
import '../../utils/currency_formatter.dart';
import '../../widgets/budget_progress_card.dart';
import '../budget/set_budget_screen.dart';

class GroupDetailsScreen extends StatelessWidget {
  final GroupModel group;

  const GroupDetailsScreen({
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

  Future<void> _settleDebt({
    required BuildContext context,
    required DebtModel debt,
    required SettlementService settlementService,
  }) async {
    final amountController = TextEditingController(
      text: debt.amount.toStringAsFixed(2),
    );

    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Settle up'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Enter the amount that was paid toward this balance.',
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: amountController,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Payment amount',
                    prefixIcon: Icon(Icons.attach_money),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final amount = double.tryParse(
                      value?.trim() ?? '',
                    );

                    if (amount == null || amount <= 0) {
                      return 'Enter a valid payment amount';
                    }

                    if (amount > debt.amount + 0.01) {
                      return 'Amount cannot exceed the current debt';
                    }

                    return null;
                  },
                ),
              ],
            ),
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
                if (formKey.currentState?.validate() ?? false) {
                  Navigator.of(dialogContext).pop(true);
                }
              },
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      amountController.dispose();
      return;
    }

    final amount = double.parse(
      amountController.text.trim(),
    );

    amountController.dispose();

    try {
      await settlementService.recordSettlement(
        groupId: group.id,
        fromUserId: debt.fromUserId,
        toUserId: debt.toUserId,
        amount: amount,
      );

      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Payment recorded successfully.'),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unable to record payment: $error',
          ),
        ),
      );
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

      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Expense deleted.'),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unable to delete expense: $error',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final expenseService = ExpenseService();
    final balanceService = BalanceService();
    final userService = UserService();
    final settlementService = SettlementService();

    return Scaffold(
      appBar: AppBar(
        title: Text(group.name),
        actions: [
          IconButton(
            tooltip: 'Reports',
            icon: const Icon(Icons.assessment_outlined),
            onPressed: () async {
              final expenseService = ExpenseService();
              final settlementService = SettlementService();
              final userService = UserService();

              final expenses = await expenseService
                  .getGroupExpenses(group.id)
                  .first;

              final settlements = await settlementService
                  .getGroupSettlements(group.id)
                  .first;

              final users =
              await userService.getUsersByIds(group.members);

              final memberNames = <String, String>{};

              users.forEach((id, user) {
                memberNames[id] = user.name;
              });

              if (!context.mounted) return;

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => GroupReportScreen(
                    group: group,
                    expenses: expenses,
                    settlements: settlements,
                    memberNames: memberNames,
                  ),
                ),
              );
            },
          ),
        ],
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
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          Card(
            child: ListTile(
              leading: const CircleAvatar(
                child: Icon(Icons.groups),
              ),
              title: Text(
                group.name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                group.description.isEmpty
                    ? 'No description'
                    : group.description,
              ),
            ),
          ),
          const SizedBox(height: 20),

          Text(
            'Members',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),

          Card(
            child: ListTile(
              leading: const Icon(Icons.people_outline),
              title: const Text('Members'),
              subtitle: Text(
                '${group.members.length} member(s)',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ManageMembersScreen(
                      group: group,
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 24),

          Text(
            'Monthly budget',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 10),

          BudgetProgressCard(
            group: group,
            onEditBudget: () async {
              await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => SetBudgetScreen(
                    group: group,
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 24),

          Text(
            'Expenses and balances',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),

          StreamBuilder<List<ExpenseModel>>(
            stream: expenseService.getGroupExpenses(group.id),
            builder: (context, expenseSnapshot) {
              if (expenseSnapshot.connectionState ==
                  ConnectionState.waiting) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(),
                  ),
                );
              }

              if (expenseSnapshot.hasError) {
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Unable to load expenses: '
                          '${expenseSnapshot.error}',
                    ),
                  ),
                );
              }

              final expenses = expenseSnapshot.data ?? [];

              return StreamBuilder<List<SettlementModel>>(
                stream: settlementService.getGroupSettlements(
                  group.id,
                ),
                builder: (context, settlementSnapshot) {
                  if (settlementSnapshot.connectionState ==
                      ConnectionState.waiting) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }

                  if (settlementSnapshot.hasError) {
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Unable to load settlements: '
                              '${settlementSnapshot.error}',
                        ),
                      ),
                    );
                  }

                  final settlements =
                      settlementSnapshot.data ?? [];

                  final debts = balanceService.simplifyDebts(
                    memberIds: group.members,
                    expenses: expenses,
                    settlements: settlements,
                  );

                  final total = expenses.fold<double>(
                    0,
                        (sum, expense) => sum + expense.amount,
                  );

                  return Column(
                    crossAxisAlignment:
                    CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Balances',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),

                      if (debts.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(20),
                            child: Center(
                              child: Text(
                                'Everyone is settled up.',
                              ),
                            ),
                          ),
                        )
                      else
                        FutureBuilder<Map<String, UserModel>>(
                          future: userService.getUsersByIds(
                            group.members,
                          ),
                          builder: (
                              context,
                              userSnapshot,
                              ) {
                            if (userSnapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(16),
                                  child:
                                  CircularProgressIndicator(),
                                ),
                              );
                            }

                            if (userSnapshot.hasError) {
                              return Card(
                                child: Padding(
                                  padding:
                                  const EdgeInsets.all(16),
                                  child: Text(
                                    'Unable to load member names: '
                                        '${userSnapshot.error}',
                                  ),
                                ),
                              );
                            }

                            final users =
                                userSnapshot.data ?? {};

                            return Column(
                              children: debts
                                  .map(
                                    (debt) => _DebtCard(
                                      debt: debt,
                                      users: users,
                                      currencyCode: group.currencyCode,
                                      onSettle: ()  {
                                    _settleDebt(
                                      context: context,
                                      debt: debt,
                                      settlementService:
                                      settlementService,
                                    );
                                  },
                                ),
                              )
                                  .toList(),
                            );
                          },
                        ),

                      const SizedBox(height: 20),

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

                      const SizedBox(height: 20),

                      Text(
                        'Expenses',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
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
                              (expense) => Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                child: Icon(
                                  _categoryIcon(
                                    expense.category,
                                  ),
                                ),
                              ),
                              title: Text(
                                expense.title,
                                style: const TextStyle(
                                  fontWeight:
                                  FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                '${expense.category} • '
                                    '${formatCurrency(expense.amountPerPerson, group.currencyCode)} each\n'
                                    'Total: ${formatCurrency(expense.amount, group.currencyCode)}',
                              ),
                              isThreeLine: true,
                              trailing:
                              PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'edit') {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            EditExpenseScreen(
                                              group: group,
                                              expense: expense,
                                            ),
                                      ),
                                    );
                                  }

                                  if (value == 'delete') {
                                    _confirmDeleteExpense(
                                      context: context,
                                      expense: expense,
                                      expenseService:
                                      expenseService,
                                    );
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'edit',
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.edit_outlined,
                                        ),
                                        SizedBox(width: 10),
                                        Text('Edit'),
                                      ],
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.delete_outline,
                                        ),
                                        SizedBox(width: 10),
                                        Text('Delete'),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                      const SizedBox(height: 20),

                      Text(
                        'Settlement history',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),

                      if (settlements.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(20),
                            child: Center(
                              child: Text(
                                'No payments recorded yet.',
                              ),
                            ),
                          ),
                        )
                      else
                        ...settlements.map(
                              (settlement) => Card(
                            child: ListTile(
                              leading: const CircleAvatar(
                                child: Icon(
                                  Icons.payments_outlined,
                                ),
                              ),
                              title: const Text(
                                'Payment recorded',
                              ),
                              subtitle: Text(
                                '${_shortId(settlement.fromUserId)} → '
                                    '${_shortId(settlement.toUserId)}',
                              ),
                              trailing: Text(
                                formatCurrency(
                                  settlement.amount,
                                  group.currencyCode,
                                ),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  static String _shortId(String value) {
    if (value.length <= 8) {
      return value;
    }

    return '${value.substring(0, 8)}…';
  }
}

class _DebtCard extends StatelessWidget {
  final DebtModel debt;
  final Map<String, UserModel> users;
  final VoidCallback onSettle;
  final String currencyCode;

  const _DebtCard({
    required this.debt,
    required this.users,
    required this.onSettle,
    required this.currencyCode,
  });

  @override
  Widget build(BuildContext context) {
    final fromName = _displayName(
      users[debt.fromUserId],
      debt.fromUserId,
    );

    final toName = _displayName(
      users[debt.toUserId],
      debt.toUserId,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: 6,
        ),
        child: ListTile(
          leading: const CircleAvatar(
            child: Icon(Icons.swap_horiz_rounded),
          ),
          title: Text(
            '$fromName owes $toName',
          ),
          subtitle: Text(
            formatCurrency(
              debt.amount,
              currencyCode,
            ),
          ),
          trailing: FilledButton.tonal(
            onPressed: onSettle,
            child: const Text('Settle Up'),
          ),
        ),
      ),
    );
  }

  static String _displayName(
      UserModel? user,
      String userId,
      ) {
    final name = user?.name.trim() ?? '';

    if (name.isNotEmpty) {
      return name;
    }

    final email = user?.email.trim() ?? '';

    if (email.isNotEmpty) {
      return email;
    }

    return _shortId(userId);
  }

  static String _shortId(String value) {
    if (value.length <= 8) {
      return value;
    }

    return '${value.substring(0, 8)}…';
  }
}