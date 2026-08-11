import 'package:flutter/material.dart';

import '../../models/group_model.dart';
import '../../services/expense_service.dart';
import '../../services/settlement_service.dart';
import '../../services/user_service.dart';
import 'add_expense_screen.dart';
import 'manage_members_screen.dart';
import 'group_report_screen.dart';
import '../../widgets/budget_progress_card.dart';
import '../budget/set_budget_screen.dart';
import '../recurring/recurring_expenses_screen.dart';
import '../../services/recurring_expense_service.dart';
import 'group_expenses_screen.dart';
import 'balances_screen.dart';
import '../../models/expense_model.dart';
import '../../utils/currency_formatter.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../models/settlement_model.dart';
import '../../services/balance_service.dart';

class GroupDetailsScreen extends StatefulWidget {
  final GroupModel group;

  const GroupDetailsScreen({
    super.key,
    required this.group,
  });

  @override
  State<GroupDetailsScreen> createState() =>
      _GroupDetailsScreenState();
}

class _GroupDetailsScreenState
    extends State<GroupDetailsScreen> {
  final RecurringExpenseService _recurringService =
  RecurringExpenseService();
  final ExpenseService _expenseService = ExpenseService();
  final SettlementService _settlementService =
  SettlementService();

  final BalanceService _balanceService =
  BalanceService();

  @override
  void initState() {
    super.initState();

    _generateDueRecurringExpenses();
  }

  Future<void> _generateDueRecurringExpenses() async {
    try {
      final generatedCount =
      await _recurringService.generateDueExpenses(
        widget.group.id,
      );

      if (!mounted || generatedCount == 0) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            generatedCount == 1
                ? '1 recurring expense was added.'
                : '$generatedCount recurring expenses were added.',
          ),
        ),
      );
    } catch (error) {
      debugPrint(
        'Unable to generate recurring expenses: $error',
      );
    }
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.group.name),
        actions: [
          IconButton(
            tooltip: 'Reports',
            icon: const Icon(Icons.assessment_outlined),
            onPressed: () async {
              final expenseService = ExpenseService();
              final settlementService = SettlementService();
              final userService = UserService();

              final expenses = await expenseService
                  .getGroupExpenses(widget.group.id)
                  .first;

              final settlements = await settlementService
                  .getGroupSettlements(widget.group.id)
                  .first;

              final users =
              await userService.getUsersByIds(widget.group.members);

              final memberNames = <String, String>{};

              users.forEach((id, user) {
                memberNames[id] = user.name;
              });

              if (!context.mounted) return;

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => GroupReportScreen(
                    group: widget.group,
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
                group: widget.group,
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
                widget.group.name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                '${widget.group.description.isEmpty ? 'No description' : widget.group.description}'
                    '${widget.group.createdAt != null ? '\nCreated: ${_formatDate(widget.group.createdAt!)}' : ''}',
              ),
              isThreeLine: widget.group.createdAt != null,
            ),
          ),
          const SizedBox(height: 20),

          Text(
            'Overview',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 10),

          StreamBuilder<List<ExpenseModel>>(
            stream: _expenseService.getGroupExpenses(
              widget.group.id,
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState ==
                  ConnectionState.waiting) {
                return const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(
                      child: CircularProgressIndicator(),
                    ),
                  ),
                );
              }

              if (snapshot.hasError) {
                return const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      'Unable to load group summary.',
                    ),
                  ),
                );
              }

              final expenses = snapshot.data ?? [];

              final totalSpending = expenses.fold<double>(
                0,
                    (sum, expense) => sum + expense.amount,
              );

              return StreamBuilder<List<SettlementModel>>(
                stream: _settlementService.getGroupSettlements(
                  widget.group.id,
                ),
                builder: (context, settlementSnapshot) {
                  if (settlementSnapshot.connectionState ==
                      ConnectionState.waiting) {
                    return const Card(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(
                          child: CircularProgressIndicator(),
                        ),
                      ),
                    );
                  }

                  final settlements =
                      settlementSnapshot.data ?? [];

                  final debts = _balanceService.simplifyDebts(
                    memberIds: widget.group.members,
                    expenses: expenses,
                    settlements: settlements,
                  );

                  final currentUserId =
                      FirebaseAuth.instance.currentUser?.uid;

                  double youOwe = 0;
                  double youAreOwed = 0;

                  if (currentUserId != null) {
                    for (final debt in debts) {
                      if (debt.fromUserId == currentUserId) {
                        youOwe += debt.amount;
                      }

                      if (debt.toUserId == currentUserId) {
                        youAreOwed += debt.amount;
                      }
                    }
                  }

                  String balanceText;

                  if (youOwe > 0) {
                    balanceText =
                    'You owe ${formatCurrency(
                      youOwe,
                      widget.group.currencyCode,
                    )}';
                  } else if (youAreOwed > 0) {
                    balanceText =
                    'Owed ${formatCurrency(
                      youAreOwed,
                      widget.group.currencyCode,
                    )}';
                  } else {
                    balanceText = 'Settled up';
                  }

                  return Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _OverviewCard(
                              icon: Icons.payments_outlined,
                              label: 'Total Spending',
                              value: formatCurrency(
                                totalSpending,
                                widget.group.currencyCode,
                              ),
                            ),
                          ),

                          const SizedBox(width: 12),

                          Expanded(
                            child: _OverviewCard(
                              icon: Icons.receipt_long_outlined,
                              label: 'Expenses',
                              value: '${expenses.length}',
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      Row(
                        children: [
                          Expanded(
                            child: _OverviewCard(
                              icon:
                              Icons.account_balance_wallet_outlined,
                              label: 'Your Balance',
                              value: balanceText,
                            ),
                          ),

                          const SizedBox(width: 12),

                          Expanded(
                            child: _OverviewCard(
                              icon: Icons.people_outline,
                              label: 'Members',
                              value:
                              '${widget.group.members.length}',
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              );
            },
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
                '${widget.group.members.length} member(s)',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ManageMembersScreen(
                      group: widget.group,
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
            group: widget.group,
            onEditBudget: () async {
              await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => SetBudgetScreen(
                    group: widget.group,
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 16),

          Card(
            child: ListTile(
              leading: const CircleAvatar(
                child: Icon(Icons.repeat_rounded),
              ),
              title: const Text(
                'Recurring expenses',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: const Text(
                'Rent, utilities, and subscriptions',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => RecurringExpensesScreen(
                      group: widget.group,
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 16),

          Card(
            child: ListTile(
              leading: const CircleAvatar(
                child: Icon(
                  Icons.receipt_long_outlined,
                ),
              ),
              title: const Text(
                'Expenses',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: const Text(
                'View, add, edit, and manage expenses',
              ),
              trailing: const Icon(
                Icons.chevron_right,
              ),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => GroupExpensesScreen(
                      group: widget.group,
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 12),

          Card(
            child: ListTile(
              leading: const CircleAvatar(
                child: Icon(
                  Icons.account_balance_wallet_outlined,
                ),
              ),
              title: const Text(
                'Balances & Settlements',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: const Text(
                'See who owes whom and record payments',
              ),
              trailing: const Icon(
                Icons.chevron_right,
              ),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => BalancesScreen(
                      group: widget.group,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
        ],
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

    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}

class _OverviewCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _OverviewCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon),

            const SizedBox(height: 12),

            Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium,
            ),

            const SizedBox(height: 4),

            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}