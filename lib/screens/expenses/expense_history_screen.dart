import 'package:flutter/material.dart';

import '../../models/expense_model.dart';
import '../../models/group_model.dart';
import '../../services/expense_service.dart';
import '../../utils/currency_formatter.dart';

class ExpenseHistoryScreen extends StatefulWidget {
  final GroupModel group;

  const ExpenseHistoryScreen({
    super.key,
    required this.group,
  });

  @override
  State<ExpenseHistoryScreen> createState() =>
      _ExpenseHistoryScreenState();
}

class _ExpenseHistoryScreenState
    extends State<ExpenseHistoryScreen> {
  final ExpenseService _expenseService =
  ExpenseService();

  String _selectedPeriod = 'All';
  String _selectedCategory = 'All';
  String _selectedType = 'All';

  void _clearFilters() {
    setState(() {
      _selectedPeriod = 'All';
      _selectedCategory = 'All';
      _selectedType = 'All';
    });
  }

  List<ExpenseModel> _applyFilters(
      List<ExpenseModel> expenses,
      ) {
    final now = DateTime.now();

    return expenses.where((expense) {
      // Period
      if (_selectedPeriod == 'This Month') {
        final date = expense.createdAt;

        if (date == null ||
            date.year != now.year ||
            date.month != now.month) {
          return false;
        }
      }

      if (_selectedPeriod == 'Last Month') {
        final previousMonth =
        DateTime(now.year, now.month - 1);

        final date = expense.createdAt;

        if (date == null ||
            date.year != previousMonth.year ||
            date.month != previousMonth.month) {
          return false;
        }
      }

      // Category
      if (_selectedCategory != 'All' &&
          expense.category != _selectedCategory) {
        return false;
      }

      // Type
      if (_selectedType == 'Recurring' &&
          !expense.generatedFromRecurring) {
        return false;
      }

      if (_selectedType == 'Regular' &&
          expense.generatedFromRecurring) {
        return false;
      }

      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Expense History'),
        actions: [
          TextButton(
            onPressed: _clearFilters,
            child: const Text('Clear'),
          ),
        ],
      ),
      body: StreamBuilder<List<ExpenseModel>>(
        stream: _expenseService.getGroupExpenses(
          widget.group.id,
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
              child: Text(
                'Unable to load expenses: '
                    '${snapshot.error}',
              ),
            );
          }

          final expenses = snapshot.data ?? [];

          final categories = expenses
              .map((expense) => expense.category)
              .where((category) =>
          category.trim().isNotEmpty)
              .toSet()
              .toList()
            ..sort();

          final filteredExpenses =
          _applyFilters(expenses);

          final filteredTotal =
          filteredExpenses.fold<double>(
            0,
                (sum, expense) =>
            sum + expense.amount,
          );

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Filters',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 12),

              DropdownButtonFormField<String>(
                initialValue: _selectedPeriod,
                decoration: const InputDecoration(
                  labelText: 'Period',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'All',
                    child: Text('All time'),
                  ),
                  DropdownMenuItem(
                    value: 'This Month',
                    child: Text('This month'),
                  ),
                  DropdownMenuItem(
                    value: 'Last Month',
                    child: Text('Last month'),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) return;

                  setState(() {
                    _selectedPeriod = value;
                  });
                },
              ),

              const SizedBox(height: 12),

              DropdownButtonFormField<String>(
                initialValue: _selectedCategory,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(
                    value: 'All',
                    child: Text('All categories'),
                  ),
                  ...categories.map(
                        (category) =>
                        DropdownMenuItem(
                          value: category,
                          child: Text(category),
                        ),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) return;

                  setState(() {
                    _selectedCategory = value;
                  });
                },
              ),

              const SizedBox(height: 12),

              DropdownButtonFormField<String>(
                initialValue: _selectedType,
                decoration: const InputDecoration(
                  labelText: 'Type',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'All',
                    child: Text('All expenses'),
                  ),
                  DropdownMenuItem(
                    value: 'Regular',
                    child: Text('Regular'),
                  ),
                  DropdownMenuItem(
                    value: 'Recurring',
                    child: Text('Recurring'),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) return;

                  setState(() {
                    _selectedType = value;
                  });
                },
              ),

              const SizedBox(height: 24),

              Card(
                child: ListTile(
                  title: const Text(
                    'Filtered spending',
                  ),
                  subtitle: Text(
                    '${filteredExpenses.length} expense(s)',
                  ),
                  trailing: Text(
                    formatCurrency(
                      filteredTotal,
                      widget.group.currencyCode,
                    ),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              if (filteredExpenses.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        'No expenses match these filters.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                )
              else
                ...filteredExpenses.map(
                      (expense) => Card(
                    child: ListTile(
                      leading: const CircleAvatar(
                        child: Icon(
                          Icons.receipt_long_outlined,
                        ),
                      ),
                      title: Text(
                        expense.title,
                      ),
                      subtitle: Text(
                        expense.category,
                      ),
                      trailing: Text(
                        formatCurrency(
                          expense.amount,
                          widget.group.currencyCode,
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
      ),
    );
  }
}