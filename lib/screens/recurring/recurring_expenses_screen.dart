import 'package:flutter/material.dart';

import '../../models/group_model.dart';
import '../../models/recurring_expense_model.dart';
import '../../services/recurring_expense_service.dart';
import '../../utils/currency_formatter.dart';
import 'add_recurring_expense_screen.dart';

class RecurringExpensesScreen extends StatelessWidget {
  final GroupModel group;

  const RecurringExpensesScreen({
    super.key,
    required this.group,
  });

  @override
  Widget build(BuildContext context) {
    final service = RecurringExpenseService();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recurring Expenses'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => AddRecurringExpenseScreen(
                group: group,
              ),
            ),
          );
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Recurring'),
      ),
      body: StreamBuilder<List<RecurringExpenseModel>>(
        stream: service.watchRecurringExpenses(group.id),
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
                  'Unable to load recurring expenses:\n'
                      '${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final recurringExpenses = snapshot.data ?? [];

          if (recurringExpenses.isEmpty) {
            return _EmptyRecurringExpenses(
              onAdd: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        AddRecurringExpenseScreen(
                          group: group,
                        ),
                  ),
                );
              },
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              16,
              16,
              16,
              100,
            ),
            itemCount: recurringExpenses.length,
            separatorBuilder: (_, _) =>
            const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final recurring = recurringExpenses[index];

              return _RecurringExpenseCard(
                recurring: recurring,
                currencyCode: group.currencyCode,
                onEdit: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AddRecurringExpenseScreen(
                        group: group,
                        recurringExpense: recurring,
                      ),
                    ),
                  );
                },
                onActiveChanged: (isActive) async {
                  try {
                    await service.setActive(
                      groupId: group.id,
                      recurringExpenseId: recurring.id,
                      isActive: isActive,
                    );
                  } catch (error) {
                    if (!context.mounted) return;

                    ScaffoldMessenger.of(context)
                        .showSnackBar(
                      SnackBar(
                        content: Text(
                          'Unable to update recurring expense: '
                              '$error',
                        ),
                      ),
                    );
                  }
                },
                onDelete: () async {
                  final confirmed =
                  await _confirmDelete(
                    context,
                    recurring.title,
                  );

                  if (confirmed != true ||
                      !context.mounted) {
                    return;
                  }

                  try {
                    await service.deleteRecurringExpense(
                      groupId: group.id,
                      recurringExpenseId: recurring.id,
                    );
                  } catch (error) {
                    if (!context.mounted) return;

                    ScaffoldMessenger.of(context)
                        .showSnackBar(
                      SnackBar(
                        content: Text(
                          'Unable to delete recurring expense: '
                              '$error',
                        ),
                      ),
                    );
                  }
                },
              );
            },
          );
        },
      ),
    );
  }

  static Future<bool?> _confirmDelete(
      BuildContext context,
      String title,
      ) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            'Delete recurring expense?',
          ),
          content: Text(
            'Delete "$title"? Existing expenses will not '
                'be removed.',
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
  }
}

class _RecurringExpenseCard extends StatelessWidget {
  final RecurringExpenseModel recurring;
  final String currencyCode;
  final VoidCallback onEdit;
  final ValueChanged<bool> onActiveChanged;
  final VoidCallback onDelete;

  const _RecurringExpenseCard({
    required this.recurring,
    required this.currencyCode,
    required this.onEdit,
    required this.onActiveChanged,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = recurring.isActive
        ? Colors.green
        : Theme.of(context).colorScheme.outline;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: 6,
        ),
        child: Column(
          children: [
            ListTile(
              leading: CircleAvatar(
                backgroundColor: activeColor.withValues(
                  alpha: 0.12,
                ),
                child: Icon(
                  _categoryIcon(recurring.category),
                  color: activeColor,
                ),
              ),
              title: Text(
                recurring.title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_frequencyLabel(recurring.frequency)}'
                        ' • Next: ${_formatDate(recurring.nextDueDate)}',
                  ),

                  Text(
                    '${recurring.participants.length} participant(s)',
                  ),

                  if (recurring.lastGeneratedAt != null)
                    Text(
                      'Last generated: ${_formatDate(recurring.lastGeneratedAt!)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
              isThreeLine: recurring.lastGeneratedAt != null,
              trailing: PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') {
                    onEdit();
                  }

                  if (value == 'pause') {
                    onActiveChanged(!recurring.isActive);
                  }

                  if (value == 'delete') {
                    onDelete();
                  }
                },
                itemBuilder: (_) => [
                   PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined),
                        SizedBox(width: 10),
                        Text('Edit'),
                      ],
                    ),
                  ),

                  PopupMenuItem(
                    value: 'pause',
                    child: Row(
                      children: [
                        Icon(
                          recurring.isActive
                              ? Icons.pause_circle_outline
                              : Icons.play_circle_outline,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          recurring.isActive
                              ? 'Pause'
                              : 'Resume',
                        ),
                      ],
                    ),
                  ),

                  const PopupMenuDivider(),

                   PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline),
                        SizedBox(width: 10),
                        Text('Delete'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                16,
                0,
                12,
                8,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      formatCurrency(
                        recurring.amount,
                        currencyCode,
                      ),
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Chip(
                    avatar: Icon(
                      recurring.isActive
                          ? Icons.check_circle
                          : Icons.pause_circle,
                      size: 16,
                      color: activeColor,
                    ),
                    backgroundColor: activeColor.withValues(alpha: 0.1),
                    label: Text(
                      recurring.isActive
                          ? 'Active'
                          : 'Paused',
                    ),
                  ),
                  Switch(
                    value: recurring.isActive,
                    onChanged: onActiveChanged,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _frequencyLabel(
      RecurrenceFrequency frequency,
      ) {
    switch (frequency) {
      case RecurrenceFrequency.weekly:
        return 'Weekly';
      case RecurrenceFrequency.monthly:
        return 'Monthly';
      case RecurrenceFrequency.yearly:
        return 'Yearly';
    }
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

  static IconData _categoryIcon(String category) {
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
        return Icons.repeat_rounded;
    }
  }
}

class _EmptyRecurringExpenses extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyRecurringExpenses({
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 100),
        Icon(
          Icons.event_repeat_rounded,
          size: 72,
          color: Theme.of(context)
              .colorScheme
              .primary
              .withValues(alpha: 0.75),
        ),
        const SizedBox(height: 24),
        Text(
          'No recurring expenses',
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(
            fontWeight: FontWeight.bold,
            color:
            Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Add rent, utilities, subscriptions, or other '
              'repeating group costs.',
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .bodyLarge
              ?.copyWith(
            color: Theme.of(context)
                .colorScheme
                .onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 28),
        Center(
          child: FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded),
            label: const Text(
              'Add recurring expense',
            ),
          ),
        ),
      ],
    );
  }
}