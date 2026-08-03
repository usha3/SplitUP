class DebtModel {
  final String fromUserId;
  final String toUserId;
  final double amount;

  const DebtModel({
    required this.fromUserId,
    required this.toUserId,
    required this.amount,
  });
}