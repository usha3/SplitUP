class ScannedReceipt {
  final String rawText;
  final String merchantName;
  final double? total;
  final DateTime? purchaseDate;

  const ScannedReceipt({
    required this.rawText,
    required this.merchantName,
    this.total,
    this.purchaseDate,
  });
}