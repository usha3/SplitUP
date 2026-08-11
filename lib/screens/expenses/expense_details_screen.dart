import 'package:flutter/material.dart';

import '../../models/expense_model.dart';
import '../../models/group_model.dart';
import '../../services/user_service.dart';
import '../../utils/currency_formatter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ExpenseDetailsScreen extends StatelessWidget {
  final GroupModel group;
  final ExpenseModel expense;

  const ExpenseDetailsScreen({
    super.key,
    required this.group,
    required this.expense,
  });

  Future<Map<String, String>> _loadMemberNames() async {
    final names = <String, String>{};

    final firestore = FirebaseFirestore.instance;
    final userService = UserService();
    final currentUser = FirebaseAuth.instance.currentUser;

    // Load registered users
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
        names[id] = currentUser.displayName!.trim();
      } else if (email.isNotEmpty) {
        names[id] = email;
      }
    });

    // Load guest member names
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

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expense Details'),
      ),
      body: FutureBuilder<Map<String, String>>(
        future: _loadMemberNames(),
        builder: (context, snapshot) {
          if (snapshot.connectionState ==
              ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          final memberNames = snapshot.data ?? {};

          String memberName(String memberId) {
            return memberNames[memberId] ?? 'Member';
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(
              16,
              16,
              16,
              32,
            ),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment:
                    CrossAxisAlignment.start,
                    children: [
                      Text(
                        expense.title,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(
                          fontWeight:
                          FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 12),

                      Text(
                        formatCurrency(
                          expense.amount,
                          group.currencyCode,
                        ),
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(
                          fontWeight:
                          FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 12),

                      Text(
                        'Category: ${expense.category}',
                      ),

                      const SizedBox(height: 4),

                      Text(
                        'Paid by: ${memberName(expense.paidBy)}',
                      ),

                      const SizedBox(height: 4),

                      Text(
                        expense.splitType == 'itemized'
                            ? 'Split: By item'
                            : 'Split: Equal',
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              if (expense.splitType ==
                  'itemized' &&
                  expense.items.isNotEmpty) ...[
                Text(
                  'Items',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(
                    fontWeight:
                    FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 10),

                ...expense.items.map(
                      (item) {
                    return Card(
                      margin:
                      const EdgeInsets.only(
                        bottom: 10,
                      ),
                      child: Padding(
                        padding:
                        const EdgeInsets.all(
                          16,
                        ),
                        child: Column(
                          crossAxisAlignment:
                          CrossAxisAlignment
                              .start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    item.name,
                                    style: const TextStyle(
                                      fontWeight:
                                      FontWeight
                                          .bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                                Text(
                                  formatCurrency(
                                    item.amount,
                                    group.currencyCode,
                                  ),
                                  style:
                                  const TextStyle(
                                    fontWeight:
                                    FontWeight
                                        .bold,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(
                              height: 10,
                            ),

                            const Text(
                              'Shared by',
                              style: TextStyle(
                                fontWeight:
                                FontWeight.w600,
                              ),
                            ),

                            const SizedBox(
                              height: 6,
                            ),

                            ...item.participants.map(
                                  (memberId) {
                                return Padding(
                                  padding:
                                  const EdgeInsets
                                      .symmetric(
                                    vertical: 2,
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons
                                            .check_circle_outline,
                                        size: 18,
                                      ),
                                      const SizedBox(
                                        width: 8,
                                      ),
                                      Expanded(
                                        child: Text(
                                          memberName(
                                            memberId,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),

                            if (item.participants
                                .isNotEmpty) ...[
                              const SizedBox(
                                height: 8,
                              ),

                              Text(
                                '${formatCurrency(
                                  item.amount,
                                  group.currencyCode,
                                )} ÷ '
                                    '${item.participants.length} = '
                                    '${formatCurrency(
                                  item.amount /
                                      item.participants
                                          .length,
                                  group.currencyCode,
                                )} each',
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],

              const SizedBox(height: 24),

              Text(
                'Split Summary',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(
                  fontWeight:
                  FontWeight.bold,
                ),
              ),

              const SizedBox(height: 10),

              Card(
                child: Padding(
                  padding:
                  const EdgeInsets.all(16),
                  child: Column(
                    children: group.members.map(
                          (memberId) {
                        final share =
                        expense.shareFor(
                          memberId,
                        );

                        if (share <= 0) {
                          return const SizedBox
                              .shrink();
                        }

                        return Padding(
                          padding:
                          const EdgeInsets
                              .symmetric(
                            vertical: 7,
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 17,
                                child: Text(
                                  memberName(memberId)
                                      .isNotEmpty
                                      ? memberName(
                                    memberId,
                                  )[0]
                                      .toUpperCase()
                                      : '?',
                                ),
                              ),

                              const SizedBox(
                                width: 12,
                              ),

                              Expanded(
                                child: Text(
                                  memberName(
                                    memberId,
                                  ),
                                ),
                              ),

                              Text(
                                formatCurrency(
                                  share,
                                  group.currencyCode,
                                ),
                                style:
                                const TextStyle(
                                  fontWeight:
                                  FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ).toList(),
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