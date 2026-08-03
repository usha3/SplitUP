import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../models/scanned_receipt.dart';

class ReceiptScannerService {
  final TextRecognizer _textRecognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );

  Future<ScannedReceipt> scanReceipt(File imageFile) async {
    final inputImage = InputImage.fromFile(imageFile);

    final recognizedText = await _textRecognizer.processImage(
      inputImage,
    );

    final rawText = recognizedText.text.trim();

    return ScannedReceipt(
      rawText: rawText,
      merchantName: _extractMerchantName(rawText),
      total: _extractTotal(rawText),
      purchaseDate: _extractDate(rawText),
    );
  }

  String _extractMerchantName(String text) {
    final lines = text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    if (lines.isEmpty) {
      return '';
    }

    // The first meaningful receipt line is often the merchant name.
    return lines.first;
  }

  double? _extractTotal(String text) {
    final lines = text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    final totalKeywords = RegExp(
      r'\b(grand\s*total|amount\s*due|balance\s*due|total)\b',
      caseSensitive: false,
    );

    final moneyPattern = RegExp(
      r'(?:\$|USD\s*)?(\d{1,6}(?:,\d{3})*(?:\.\d{2}))',
      caseSensitive: false,
    );

    // Prefer numbers printed beside common total labels.
    for (final line in lines.reversed) {
      if (!totalKeywords.hasMatch(line)) {
        continue;
      }

      final matches = moneyPattern.allMatches(line).toList();

      if (matches.isNotEmpty) {
        return _parseAmount(matches.last.group(1));
      }
    }

    // Fallback: use the largest currency-like amount on the receipt.
    final values = <double>[];

    for (final match in moneyPattern.allMatches(text)) {
      final value = _parseAmount(match.group(1));

      if (value != null) {
        values.add(value);
      }
    }

    if (values.isEmpty) {
      return null;
    }

    values.sort();

    return values.last;
  }

  DateTime? _extractDate(String text) {
    final patterns = [
      RegExp(r'\b(\d{1,2})/(\d{1,2})/(\d{2,4})\b'),
      RegExp(r'\b(\d{1,2})-(\d{1,2})-(\d{2,4})\b'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);

      if (match == null) {
        continue;
      }

      final month = int.tryParse(match.group(1) ?? '');
      final day = int.tryParse(match.group(2) ?? '');
      var year = int.tryParse(match.group(3) ?? '');

      if (month == null || day == null || year == null) {
        continue;
      }

      if (year < 100) {
        year += 2000;
      }

      try {
        return DateTime(year, month, day);
      } on ArgumentError {
        continue;
      }
    }

    return null;
  }

  double? _parseAmount(String? value) {
    if (value == null) {
      return null;
    }

    return double.tryParse(
      value.replaceAll(',', '').trim(),
    );
  }

  Future<void> dispose() async {
    await _textRecognizer.close();
  }
}