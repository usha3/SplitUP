class CurrencyModel {
  final String code;
  final String symbol;
  final String name;

  const CurrencyModel({
    required this.code,
    required this.symbol,
    required this.name,
  });
}

const supportedCurrencies = [
  CurrencyModel(
    code: 'USD',
    symbol: r'$',
    name: 'US Dollar',
  ),
  CurrencyModel(
    code: 'INR',
    symbol: '₹',
    name: 'Indian Rupee',
  ),
  CurrencyModel(
    code: 'EUR',
    symbol: '€',
    name: 'Euro',
  ),
  CurrencyModel(
    code: 'GBP',
    symbol: '£',
    name: 'British Pound',
  ),
  CurrencyModel(
    code: 'CAD',
    symbol: r'CA$',
    name: 'Canadian Dollar',
  ),
  CurrencyModel(
    code: 'AUD',
    symbol: r'A$',
    name: 'Australian Dollar',
  ),
  CurrencyModel(
    code: 'JPY',
    symbol: '¥',
    name: 'Japanese Yen',
  ),
];

CurrencyModel currencyByCode(String? code) {
  return supportedCurrencies.firstWhere(
        (currency) => currency.code == code,
    orElse: () => supportedCurrencies.first,
  );
}