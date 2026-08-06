import '../models/currency_model.dart';

String formatCurrency(
    double amount,
    String currencyCode,
    ) {
  final currency = currencyByCode(currencyCode);

  final decimals =
  currency.code == 'JPY' ? 0 : 2;

  return '${currency.symbol}'
      '${amount.toStringAsFixed(decimals)}';
}