import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/dashboard_summary.dart';
import '../models/expense_model.dart';
import '../models/group_model.dart';
import '../models/settlement_model.dart';
import 'balance_service.dart';

class DashboardService {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final BalanceService _balanceService;

  DashboardService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    BalanceService? balanceService,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _balanceService = balanceService ?? BalanceService();

  Stream<DashboardSummary> watchSummary() {
    final currentUser = _auth.currentUser;

    if (currentUser == null) {
      return Stream.value(const DashboardSummary.empty());
    }

    final controller = StreamController<DashboardSummary>();

    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
    groupSubscription;

    final expenseSubscriptions =
    <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];

    final settlementSubscriptions =
    <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];

    final groups = <String, GroupModel>{};
    final expensesByGroup = <String, List<ExpenseModel>>{};
    final settlementsByGroup = <String, List<SettlementModel>>{};

    Future<void> emitSummary() async {
      double netBalance = 0;
      double youOwe = 0;
      double youAreOwed = 0;
      double monthlySpending = 0;

      final now = DateTime.now();
      final monthStart = DateTime(now.year, now.month);

      for (final group in groups.values) {
        final expenses = expensesByGroup[group.id] ?? [];
        final settlements = settlementsByGroup[group.id] ?? [];

        final balances = _balanceService.calculateNetBalances(
          memberIds: group.members,
          expenses: expenses,
          settlements: settlements,
        );

        final currentBalance = balances[currentUser.uid] ?? 0;

        netBalance += currentBalance;

        if (currentBalance < 0) {
          youOwe += currentBalance.abs();
        } else {
          youAreOwed += currentBalance;
        }

        for (final expense in expenses) {
          final createdAt = expense.createdAt;

          if (createdAt != null &&
              createdAt.isAfter(
                monthStart.subtract(
                  const Duration(milliseconds: 1),
                ),
              ) &&
              expense.participants.contains(currentUser.uid)) {
            monthlySpending += expense.amountPerPerson;
          }
        }
      }

      if (!controller.isClosed) {
        controller.add(
          DashboardSummary(
            netBalance: netBalance,
            youOwe: youOwe,
            youAreOwed: youAreOwed,
            monthlySpending: monthlySpending,
            activeGroups: groups.length,
          ),
        );
      }
    }

    Future<void> clearChildSubscriptions() async {
      for (final subscription in expenseSubscriptions) {
        await subscription.cancel();
      }

      for (final subscription in settlementSubscriptions) {
        await subscription.cancel();
      }

      expenseSubscriptions.clear();
      settlementSubscriptions.clear();
    }

    groupSubscription = _firestore
        .collection('groups')
        .where(
      'members',
      arrayContains: currentUser.uid,
    )
        .snapshots()
        .listen(
          (snapshot) async {
        await clearChildSubscriptions();

        groups
          ..clear()
          ..addEntries(
            snapshot.docs.map(
                  (document) {
                final group =
                GroupModel.fromFirestore(document);

                return MapEntry(group.id, group);
              },
            ),
          );

        expensesByGroup.clear();
        settlementsByGroup.clear();

        if (groups.isEmpty) {
          await emitSummary();
          return;
        }

        for (final group in groups.values) {
          final expenseSubscription = _firestore
              .collection('groups')
              .doc(group.id)
              .collection('expenses')
              .snapshots()
              .listen(
                (expenseSnapshot) {
              expensesByGroup[group.id] = expenseSnapshot.docs
                  .map(ExpenseModel.fromFirestore)
                  .toList();

              emitSummary();
            },
            onError: controller.addError,
          );

          expenseSubscriptions.add(expenseSubscription);

          final settlementSubscription = _firestore
              .collection('groups')
              .doc(group.id)
              .collection('settlements')
              .snapshots()
              .listen(
                (settlementSnapshot) {
              settlementsByGroup[group.id] =
                  settlementSnapshot.docs
                      .map(SettlementModel.fromFirestore)
                      .toList();

              emitSummary();
            },
            onError: controller.addError,
          );

          settlementSubscriptions.add(
            settlementSubscription,
          );
        }

        await emitSummary();
      },
      onError: controller.addError,
    );

    controller.onCancel = () async {
      await groupSubscription?.cancel();
      await clearChildSubscriptions();
    };

    return controller.stream;
  }
}