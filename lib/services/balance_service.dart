import '../models/debt_model.dart';
import '../models/expense_model.dart';
import '../models/member_balance.dart';
import '../models/settlement_model.dart';

class BalanceService {
  Map<String, double> calculateNetBalances({
    required List<String> memberIds,
    required List<ExpenseModel> expenses,
    List<SettlementModel> settlements = const [],
  }) {
    final balances = <String, double>{
      for (final memberId in memberIds) memberId: 0,
    };

    for (final expense in expenses) {
      balances.putIfAbsent(expense.paidBy, () => 0);

      balances[expense.paidBy] =
          balances[expense.paidBy]! + expense.amount;

      if (expense.participants.isEmpty) {
        continue;
      }

      final share =
          expense.amount / expense.participants.length;

      for (final participantId in expense.participants) {
        balances.putIfAbsent(participantId, () => 0);

        balances[participantId] =
            balances[participantId]! - share;
      }
    }

    for (final settlement in settlements) {
      balances.putIfAbsent(
        settlement.fromUserId,
            () => 0,
      );

      balances.putIfAbsent(
        settlement.toUserId,
            () => 0,
      );

      // The debtor paid money, so their negative balance moves toward zero.
      balances[settlement.fromUserId] =
          balances[settlement.fromUserId]! +
              settlement.amount;

      // The creditor received money, so their positive balance moves toward zero.
      balances[settlement.toUserId] =
          balances[settlement.toUserId]! -
              settlement.amount;
    }

    return balances;
  }

  List<MemberBalance> getMemberBalances({
    required List<String> memberIds,
    required List<ExpenseModel> expenses,
    List<SettlementModel> settlements = const [],
  }) {
    final balances = calculateNetBalances(
      memberIds: memberIds,
      expenses: expenses,
      settlements: settlements,
    );

    final result = balances.entries
        .map(
          (entry) => MemberBalance(
        userId: entry.key,
        amount: entry.value,
      ),
    )
        .toList();

    result.sort(
          (a, b) => b.amount.compareTo(a.amount),
    );

    return result;
  }

  List<DebtModel> simplifyDebts({
    required List<String> memberIds,
    required List<ExpenseModel> expenses,
    List<SettlementModel> settlements = const [],
  }) {
    final balances = calculateNetBalances(
      memberIds: memberIds,
      expenses: expenses,
      settlements: settlements,
    );

    final creditors = balances.entries
        .where((entry) => entry.value > 0.01)
        .map((entry) => MapEntry(entry.key, entry.value))
        .toList();

    final debtors = balances.entries
        .where((entry) => entry.value < -0.01)
        .map((entry) => MapEntry(entry.key, -entry.value))
        .toList();

    creditors.sort((a, b) => b.value.compareTo(a.value));
    debtors.sort((a, b) => b.value.compareTo(a.value));

    final debts = <DebtModel>[];

    var creditorIndex = 0;
    var debtorIndex = 0;

    while (creditorIndex < creditors.length &&
        debtorIndex < debtors.length) {
      final creditor = creditors[creditorIndex];
      final debtor = debtors[debtorIndex];

      final amount = creditor.value < debtor.value
          ? creditor.value
          : debtor.value;

      debts.add(
        DebtModel(
          fromUserId: debtor.key,
          toUserId: creditor.key,
          amount: amount,
        ),
      );

      final remainingCredit = creditor.value - amount;
      final remainingDebt = debtor.value - amount;

      creditors[creditorIndex] = MapEntry(
        creditor.key,
        remainingCredit,
      );

      debtors[debtorIndex] = MapEntry(
        debtor.key,
        remainingDebt,
      );

      if (remainingCredit <= 0.01) {
        creditorIndex++;
      }

      if (remainingDebt <= 0.01) {
        debtorIndex++;
      }
    }

    return debts;
  }
}