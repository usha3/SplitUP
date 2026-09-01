class ScannedReceiptItem {
  final String name;
  final double amount;

  /// Optional category/tag detected by your existing parser.
  /// Examples:
  /// meat, milk, personal_care, alcohol
  final String? detectedTag;

  /// Optional structured fields for AI extraction.
  final int? quantity;
  final double? unitPrice;
  final String? sku;

  /// Confidence from 0.0 to 1.0.
  final double? confidence;

  const ScannedReceiptItem({
    required this.name,
    required this.amount,
    this.detectedTag,
    this.quantity,
    this.unitPrice,
    this.sku,
    this.confidence,
  });

  ScannedReceiptItem copyWith({
    String? name,
    double? amount,
    String? detectedTag,
    int? quantity,
    double? unitPrice,
    String? sku,
    double? confidence,
  }) {
    return ScannedReceiptItem(
      name: name ?? this.name,
      amount: amount ?? this.amount,
      detectedTag: detectedTag ?? this.detectedTag,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      sku: sku ?? this.sku,
      confidence: confidence ?? this.confidence,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'amount': amount,
      'detectedTag': detectedTag,
      'quantity': quantity,
      'unitPrice': unitPrice,
      'sku': sku,
      'confidence': confidence,
    };
  }

  factory ScannedReceiptItem.fromJson(
      Map<String, dynamic> json,
      ) {
    return ScannedReceiptItem(
      name: json['name']?.toString() ?? '',
      amount: _toDouble(json['amount']) ?? 0,
      detectedTag: json['detectedTag']?.toString(),
      quantity: _toInt(json['quantity']),
      unitPrice: _toDouble(json['unitPrice']),
      sku: json['sku']?.toString(),
      confidence: _toDouble(json['confidence']),
    );
  }
}

class ScannedReceipt {
  /// Full OCR text from ML Kit.
  final String rawText;

  /// Clean merchant name used by SplitUp.
  ///
  /// Example:
  /// Target
  /// Walmart
  /// The Burger Spot
  final String merchantName;

  /// Original merchant text detected from the receipt.
  ///
  /// Examples:
  /// "target San Francisco Downtown"
  /// "Walmart Supercenter #2457"
  /// "THE BURGER SPOT"
  final String? merchantRaw;

  final double? subtotal;
  final double? tax;
  final double? tip;
  final double? fees;
  final double? total;

  final DateTime? purchaseDate;

  final List<ScannedReceiptItem> items;

  /// Receipt-level discounts/coupons.
  ///
  /// Store these as positive values:
  /// [2.16, 1.00, 2.00]
  ///
  /// The validator will subtract them.
  final List<double> discounts;

  /// Total value of returned merchandise.
  /// Store as a positive number.
  final double? returnsTotal;

  /// Currency code when available.
  ///
  /// USD, EUR, INR, GBP, etc.
  final String? currencyCode;

  /// AI/parser confidence from 0.0 to 1.0.
  final double? confidence;

  /// Where the final parsed receipt came from.
  ///
  /// Examples:
  /// ai
  /// local_parser
  /// ai_with_local_fallback
  final String? source;

  const ScannedReceipt({
    required this.rawText,
    required this.merchantName,
    this.merchantRaw,
    this.subtotal,
    this.tax,
    this.tip,
    this.fees,
    this.total,
    this.purchaseDate,
    this.items = const [],
    this.discounts = const [],
    this.returnsTotal,
    this.currencyCode,
    this.confidence,
    this.source,
  });

  double get discountTotal {
    return discounts.fold<double>(
      0,
          (sum, value) => sum + value.abs(),
    );
  }

  double get merchandiseTotal {
    return items
        .where((item) => item.amount > 0)
        .fold<double>(
      0,
          (sum, item) => sum + item.amount,
    );
  }

  ScannedReceipt copyWith({
    String? rawText,
    String? merchantName,
    String? merchantRaw,
    double? subtotal,
    double? tax,
    double? tip,
    double? fees,
    double? total,
    DateTime? purchaseDate,
    List<ScannedReceiptItem>? items,
    List<double>? discounts,
    double? returnsTotal,
    String? currencyCode,
    double? confidence,
    String? source,
  }) {
    return ScannedReceipt(
      rawText: rawText ?? this.rawText,
      merchantName: merchantName ?? this.merchantName,
      merchantRaw: merchantRaw ?? this.merchantRaw,
      subtotal: subtotal ?? this.subtotal,
      tax: tax ?? this.tax,
      tip: tip ?? this.tip,
      fees: fees ?? this.fees,
      total: total ?? this.total,
      purchaseDate: purchaseDate ?? this.purchaseDate,
      items: items ?? this.items,
      discounts: discounts ?? this.discounts,
      returnsTotal: returnsTotal ?? this.returnsTotal,
      currencyCode: currencyCode ?? this.currencyCode,
      confidence: confidence ?? this.confidence,
      source: source ?? this.source,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'rawText': rawText,
      'merchantName': merchantName,
      'merchantRaw': merchantRaw,
      'subtotal': subtotal,
      'tax': tax,
      'tip': tip,
      'fees': fees,
      'total': total,
      'purchaseDate':
      purchaseDate?.toIso8601String(),
      'items':
      items.map((item) => item.toJson()).toList(),
      'discounts': discounts,
      'returnsTotal': returnsTotal,
      'currencyCode': currencyCode,
      'confidence': confidence,
      'source': source,
    };
  }

  factory ScannedReceipt.fromJson(
      Map<String, dynamic> json,
      ) {
    return ScannedReceipt(
      rawText: json['rawText']?.toString() ?? '',
      merchantName:
      json['merchantName']?.toString() ?? '',
      merchantRaw:
      json['merchantRaw']?.toString(),
      subtotal: _toDouble(json['subtotal']),
      tax: _toDouble(json['tax']),
      tip: _toDouble(json['tip']),
      fees: _toDouble(json['fees']),
      total: _toDouble(json['total']),
      purchaseDate:
      _toDateTime(json['purchaseDate']),
      items: (json['items'] as List<dynamic>?)
          ?.whereType<Map>()
          .map(
            (item) =>
            ScannedReceiptItem.fromJson(
              Map<String, dynamic>.from(item),
            ),
      )
          .toList() ??
          const [],
      discounts: (json['discounts']
      as List<dynamic>?)
          ?.map(_toDouble)
          .whereType<double>()
          .toList() ??
          const [],
      returnsTotal:
      _toDouble(json['returnsTotal']),
      currencyCode:
      json['currencyCode']?.toString(),
      confidence:
      _toDouble(json['confidence']),
      source: json['source']?.toString(),
    );
  }
}

double? _toDouble(dynamic value) {
  if (value == null) {
    return null;
  }

  if (value is num) {
    return value.toDouble();
  }

  final cleaned = value
      .toString()
      .replaceAll(r'$', '')
      .replaceAll(',', '')
      .trim();

  return double.tryParse(cleaned);
}

int? _toInt(dynamic value) {
  if (value == null) {
    return null;
  }

  if (value is int) {
    return value;
  }

  if (value is num) {
    return value.toInt();
  }

  return int.tryParse(
    value.toString().trim(),
  );
}

DateTime? _toDateTime(dynamic value) {
  if (value == null) {
    return null;
  }

  if (value is DateTime) {
    return value;
  }

  return DateTime.tryParse(
    value.toString(),
  );
}