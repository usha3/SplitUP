import 'package:flutter/material.dart';

import '../../models/debt_model.dart';
import '../../models/expense_model.dart';
import '../../models/group_model.dart';
import '../../models/settlement_model.dart';
import '../../services/balance_service.dart';
import '../../services/expense_service.dart';
import '../../services/settlement_service.dart';
import '../../services/user_service.dart';
import '../../utils/currency_formatter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class BalancesScreen extends StatelessWidget {
  final GroupModel group;

  const BalancesScreen({
    super.key,
    required this.group,
  });

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
                  keyboardType:
                  const TextInputType.numberWithOptions(
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
                if (formKey.currentState?.validate() ??
                    false) {
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

      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Payment recorded successfully.',
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unable to record payment: $error',
          ),
        ),
      );
    }
  }

  static String _shortId(String value) {
    if (value.length <= 8) {
      return value;
    }

    return '${value.substring(0, 8)}…';
  }

  Future<Map<String, String>> _loadMemberNames() async {
    final names = <String, String>{};

    final firestore = FirebaseFirestore.instance;
    final userService = UserService();
    final currentUser = FirebaseAuth.instance.currentUser;

    // Load registered users.
    final users = await userService.getUsersByIds(
      group.members,
    );

    users.forEach((id, user) {
      final name = user.name.trim();
      final email = user.email.trim();

      if (name.isNotEmpty) {
        names[id] = name;
      } else if (id == currentUser?.uid &&
          currentUser?.displayName != null &&
          currentUser!.displayName!.trim().isNotEmpty) {
        names[id] =
            currentUser.displayName!.trim();
      } else if (email.isNotEmpty) {
        names[id] = email;
      }
    });

    // Load memberDetails, including guests.
    final groupDocument = await firestore
        .collection('groups')
        .doc(group.id)
        .get();

    final groupData = groupDocument.data() ?? {};

    final rawMemberDetails =
    groupData['memberDetails'];

    if (rawMemberDetails is Map) {
      final memberDetails =
      Map<String, dynamic>.from(
        rawMemberDetails,
      );

      for (final memberId in group.members) {
        final rawDetails =
        memberDetails[memberId];

        if (rawDetails is! Map) {
          continue;
        }

        final details =
        Map<String, dynamic>.from(
          rawDetails,
        );

        final name =
            details['name']?.toString().trim() ?? '';

        final email =
            details['email']?.toString().trim() ?? '';

        if (name.isNotEmpty) {
          names[memberId] = name;
        } else if (!names.containsKey(memberId) &&
            email.isNotEmpty) {
          names[memberId] = email;
        }
      }
    }

    return names;
  }

  static String _formatSettlementDate(
      DateTime date,
      ) {
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

    final hour =
    date.hour == 0
        ? 12
        : date.hour > 12
        ? date.hour - 12
        : date.hour;

    final minute =
    date.minute
        .toString()
        .padLeft(2, '0');

    final period =
    date.hour >= 12
        ? 'PM'
        : 'AM';

    return '${months[date.month - 1]} '
        '${date.day}, ${date.year} • '
        '$hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    final expenseService = ExpenseService();
    final settlementService = SettlementService();
    final balanceService = BalanceService();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Balances & Settlements'),
      ),
      body: StreamBuilder<List<ExpenseModel>>(
        stream: expenseService.getGroupExpenses(
          group.id,
        ),
        builder: (context, expenseSnapshot) {
          if (expenseSnapshot.connectionState ==
              ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (expenseSnapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Unable to load expenses: '
                      '${expenseSnapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final expenses =
              expenseSnapshot.data ?? [];

          return StreamBuilder<List<SettlementModel>>(
            stream:
            settlementService.getGroupSettlements(
              group.id,
            ),
            builder: (
                context,
                settlementSnapshot,
                ) {
              if (settlementSnapshot.connectionState ==
                  ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(),
                );
              }

              if (settlementSnapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Unable to load settlements: '
                          '${settlementSnapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }

              final settlements =
                  settlementSnapshot.data ?? [];

              final debts =
              balanceService.simplifyDebts(
                memberIds: group.members,
                expenses: expenses,
                settlements: settlements,
              );

              return FutureBuilder<Map<String, String>>(
                future: _loadMemberNames(),
                builder: (
                    context,
                    userSnapshot,
                    ) {
                  if (userSnapshot.connectionState ==
                      ConnectionState.waiting) {
                    return const Center(
                      child:
                      CircularProgressIndicator(),
                    );
                  }

                  if (userSnapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding:
                        const EdgeInsets.all(24),
                        child: Text(
                          'Unable to load member names: '
                              '${userSnapshot.error}',
                          textAlign:
                          TextAlign.center,
                        ),
                      ),
                    );
                  }

                  final memberNames =
                      userSnapshot.data ?? <String, String>{};

                  return ListView(
                    padding:
                    const EdgeInsets.fromLTRB(
                      16,
                      16,
                      16,
                      32,
                    ),
                    children: [
                      Text(
                        'Balances',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(
                          fontWeight:
                          FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 10),

                      if (debts.isEmpty)
                        const Card(
                          child: Padding(
                            padding:
                            EdgeInsets.all(20),
                            child: Center(
                              child: Text(
                                'Everyone is settled up.',
                              ),
                            ),
                          ),
                        )
                      else
                        ...debts.map(
                              (debt) => _DebtCard(
                                debt: debt,
                                memberNames: memberNames,
                                currencyCode:
                                group.currencyCode,
                                onSettle: () {
                              _settleDebt(
                                context: context,
                                debt: debt,
                                settlementService:
                                settlementService,
                              );
                            },
                          ),
                        ),

                      const SizedBox(height: 28),

                      Text(
                        'Settlement history',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(
                          fontWeight:
                          FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 10),

                      if (settlements.isEmpty)
                        const Card(
                          child: Padding(
                            padding:
                            EdgeInsets.all(20),
                            child: Center(
                              child: Text(
                                'No payments recorded yet.',
                              ),
                            ),
                          ),
                        )
                      else
                        ...settlements.map(
                              (settlement) {
                                final fromName =
                                    memberNames[settlement.fromUserId] ??
                                        _shortId(
                                          settlement.fromUserId,
                                        );

                                final toName =
                                    memberNames[settlement.toUserId] ??
                                        _shortId(
                                          settlement.toUserId,
                                        );

                                return Card(
                                  child: ListTile(
                                    leading: const CircleAvatar(
                                      child: Icon(
                                        Icons.payments_outlined,
                                      ),
                                    ),
                                    title: Text(
                                      '$fromName paid $toName',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    subtitle: Text(
                                      settlement.createdAt != null
                                          ? _formatSettlementDate(
                                        settlement.createdAt!,
                                      )
                                          : 'Payment recorded',
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
                                );
                          },
                        ),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _DebtCard extends StatelessWidget {
  final DebtModel debt;
  final Map<String, String> memberNames;
  final VoidCallback onSettle;
  final String currencyCode;

  const _DebtCard({
    required this.debt,
    required this.memberNames,
    required this.onSettle,
    required this.currencyCode,
  });

  @override
  Widget build(BuildContext context) {
    final fromName =
        memberNames[debt.fromUserId] ??
            _shortId(debt.fromUserId);

    final toName =
        memberNames[debt.toUserId] ??
            _shortId(debt.toUserId);

    return Card(
      child: ListTile(
        leading: const CircleAvatar(
          child: Icon(
            Icons.swap_horiz_rounded,
          ),
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
    );
  }

  static String _shortId(String value) {
    if (value.length <= 8) {
      return value;
    }

    return '${value.substring(0, 8)}…';
  }
}