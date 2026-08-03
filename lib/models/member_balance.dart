class MemberBalance {
  final String userId;
  final double amount;

  const MemberBalance({
    required this.userId,
    required this.amount,
  });

  bool get isOwedMoney => amount > 0;
  bool get owesMoney => amount < 0;
  bool get isSettled => amount.abs() < 0.01;
}