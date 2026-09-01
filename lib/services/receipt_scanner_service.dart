import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;

import '../models/scanned_receipt.dart';

/// Receipt OCR + heuristic parsing for many common receipt layouts.
///
/// Designed for:
/// - grocery / big-box receipts (Walmart-style SKU/UPC + price columns)
/// - restaurant / cafe receipts
/// - receipts where ML Kit separates the description and amount columns
/// - inline "ITEM ... $12.34" receipts
/// - noisy OCR where $, commas, O/0, S/$, and tax flags are imperfect
///
/// Important:
/// No local heuristic parser can guarantee perfect results for every receipt.
/// Always let the user verify/edit detected items and totals before saving.
class ReceiptScannerService {
  ReceiptScannerService()
      : _textRecognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );

  final TextRecognizer _textRecognizer;

  static const double _moneyTolerance = 0.05;
  static const int _maxSecondPassWidth = 2200;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  Future<ScannedReceipt> scanReceipt(File imageFile) async {
    final firstText = await _recognizeFile(imageFile);

    debugPrint('======= RECEIPT OCR =======');
    debugPrint(firstText.text.trim());
    debugPrint('===========================');

    final first = _parseRecognizedText(firstText);

    _debugParsed('FIRST PASS', first);

    _ParsedReceipt finalParsed = first;

    final secondPassReason = _secondPassReason(first);

    if (secondPassReason != null) {
      debugPrint('SECOND PASS REASON: $secondPassReason');

      final second = await _runSecondPass(
        originalFile: imageFile,
        firstRecognizedText: firstText,
      );

      if (second != null) {
        _debugParsed('SECOND PASS', second);

        final firstScore = _scoreParse(first);
        final secondScore = _scoreParse(second);

        debugPrint(
          'FIRST PASS SCORE: ${firstScore.toStringAsFixed(2)}',
        );
        debugPrint(
          'SECOND PASS SCORE: ${secondScore.toStringAsFixed(2)}',
        );

        finalParsed = _mergePasses(
          first: first,
          second: second,
          firstScore: firstScore,
          secondScore: secondScore,
        );
      }
    }

    finalParsed = _cleanFinalReceipt(finalParsed);

    _debugParsed('FINAL RECEIPT', finalParsed);

    return ScannedReceipt(
      rawText: first.rawText,
      merchantName: finalParsed.merchantName ?? '',
      subtotal: finalParsed.subtotal,
      tax: finalParsed.tax,
      tip: finalParsed.tip,
      fees: finalParsed.fees,
      total: finalParsed.total,
      purchaseDate: finalParsed.purchaseDate,
      items: finalParsed.items,
    );
  }

  Future<void> dispose() async {
    await _textRecognizer.close();
  }

  // ---------------------------------------------------------------------------
  // OCR
  // ---------------------------------------------------------------------------

  Future<RecognizedText> _recognizeFile(File file) {
    return _textRecognizer.processImage(
      InputImage.fromFile(file),
    );
  }

  Future<_ParsedReceipt?> _runSecondPass({
    required File originalFile,
    required RecognizedText firstRecognizedText,
  }) async {
    File? temporaryFile;

    try {
      debugPrint('======= SECOND OCR PASS =======');

      final cropRect = _findLikelyItemArea(firstRecognizedText);

      if (cropRect == null) {
        debugPrint('SECOND PASS: no reliable item crop found');
        return null;
      }

      final bytes = await originalFile.readAsBytes();
      var decoded = img.decodeImage(bytes);

      if (decoded == null) {
        debugPrint('SECOND PASS: image decode failed');
        return null;
      }

      // Respect camera EXIF orientation before mapping ML Kit coordinates.
      decoded = img.bakeOrientation(decoded);

      final left = cropRect.left.floor().clamp(0, decoded.width - 1);
      final top = cropRect.top.floor().clamp(0, decoded.height - 1);
      final right = cropRect.right.ceil().clamp(left + 1, decoded.width);
      final bottom = cropRect.bottom.ceil().clamp(top + 1, decoded.height);

      final width = right - left;
      final height = bottom - top;

      if (width < 40 || height < 40) {
        return null;
      }

      debugPrint(
        'SECOND PASS CROP: x=$left, y=$top, w=$width, h=$height',
      );

      var cropped = img.copyCrop(
        decoded,
        x: left,
        y: top,
        width: width,
        height: height,
      );

      // Upscaling helps small thermal-receipt text.
      if (cropped.width < _maxSecondPassWidth) {
        final scale = math.min(
          2.4,
          _maxSecondPassWidth / cropped.width,
        );

        if (scale > 1.10) {
          cropped = img.copyResize(
            cropped,
            width: (cropped.width * scale).round(),
            height: (cropped.height * scale).round(),
            interpolation: img.Interpolation.cubic,
          );
        }
      }

      final tempPath =
          '${Directory.systemTemp.path}/splitup_receipt_'
          '${DateTime.now().microsecondsSinceEpoch}.jpg';

      temporaryFile = File(tempPath);

      await temporaryFile.writeAsBytes(
        img.encodeJpg(cropped, quality: 96),
        flush: true,
      );

      final recognized = await _recognizeFile(temporaryFile);

      for (final line in _flattenLines(recognized)) {
        debugPrint(line.text);
      }

      debugPrint('================================');

      return _parseRecognizedText(recognized);
    } catch (error, stackTrace) {
      debugPrint('SECOND PASS FAILED: $error');
      debugPrint('$stackTrace');
      return null;
    } finally {
      try {
        if (temporaryFile != null &&
            await temporaryFile.exists()) {
          await temporaryFile.delete();
        }
      } catch (_) {
        // Temporary-file cleanup should never fail the scan.
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Geometry / row building
  // ---------------------------------------------------------------------------

  List<_OcrLine> _flattenLines(RecognizedText recognizedText) {
    final result = <_OcrLine>[];

    for (final block in recognizedText.blocks) {
      for (final line in block.lines) {
        final text = _normalizeWhitespace(line.text);

        if (text.isEmpty) {
          continue;
        }

        result.add(
          _OcrLine(
            text: text,
            rect: line.boundingBox,
          ),
        );
      }
    }

    result.sort((a, b) {
      final top = a.rect.top.compareTo(b.rect.top);
      if (top != 0) return top;
      return a.rect.left.compareTo(b.rect.left);
    });

    return result;
  }

  List<_OcrRow> _buildRows(RecognizedText recognizedText) {
    final lines = _flattenLines(recognizedText);

    if (lines.isEmpty) {
      return [];
    }

    final heights = lines
        .map((e) => e.rect.height)
        .where((h) => h > 0)
        .toList()
      ..sort();

    final medianHeight = heights.isEmpty
        ? 12.0
        : heights[heights.length ~/ 2];

    final yTolerance = math.max(7.0, medianHeight * 0.70);

    final rows = <_MutableOcrRow>[];

    for (final line in lines) {
      _MutableOcrRow? best;
      var bestDistance = double.infinity;

      for (final row in rows.reversed.take(8)) {
        final distance =
        (row.centerY - line.centerY).abs();

        if (distance <= yTolerance &&
            distance < bestDistance) {
          best = row;
          bestDistance = distance;
        }
      }

      if (best == null) {
        rows.add(_MutableOcrRow([line]));
      } else {
        best.add(line);
      }
    }

    final output = rows
        .map((row) => row.freeze())
        .toList();

    output.sort((a, b) {
      final top = a.rect.top.compareTo(b.rect.top);
      if (top != 0) return top;
      return a.rect.left.compareTo(b.rect.left);
    });

    return output;
  }

  Rect? _findLikelyItemArea(
      RecognizedText recognizedText,
      ) {
    final rows = _buildRows(recognizedText);

    if (rows.length < 3) {
      return null;
    }

    final allLines = _flattenLines(recognizedText);
    if (allLines.isEmpty) return null;

    final receiptLeft =
    allLines.map((e) => e.rect.left).reduce(math.min);
    final receiptRight =
    allLines.map((e) => e.rect.right).reduce(math.max);
    final receiptTop =
    allLines.map((e) => e.rect.top).reduce(math.min);
    final receiptBottom =
    allLines.map((e) => e.rect.bottom).reduce(math.max);

    var startIndex = -1;

    // Prefer first row that strongly resembles an item.
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (_looksLikeItemRow(row)) {
        startIndex = i;
        break;
      }
    }

    // If the receipt has a QTY/DESC/ITEM header, start below it.
    for (var i = 0; i < rows.length; i++) {
      final lower = rows[i].text.toLowerCase();

      if (_containsAny(lower, const [
        'qty desc',
        'qty description',
        'description amount',
        'item amount',
        'item price',
        'description price',
      ])) {
        startIndex = i + 1;
        break;
      }
    }

    if (startIndex < 0) {
      // Conservative fallback: crop away the top ~12% header.
      startIndex = 0;
      final targetY =
          receiptTop + (receiptBottom - receiptTop) * 0.12;

      for (var i = 0; i < rows.length; i++) {
        if (rows[i].rect.top >= targetY) {
          startIndex = i;
          break;
        }
      }
    }

    var endIndex = rows.length - 1;

    for (var i = startIndex + 1; i < rows.length; i++) {
      if (_isSubtotalRow(rows[i].text) ||
          _isTotalRow(rows[i].text)) {
        endIndex = i;
        break;
      }
    }

    final startY = rows[startIndex].rect.top;
    final endY = rows[endIndex].rect.bottom;

    final verticalPadding =
    math.max(18.0, (endY - startY) * 0.08);
    final horizontalPadding =
    math.max(8.0, (receiptRight - receiptLeft) * 0.02);

    return Rect.fromLTRB(
      math.max(receiptLeft - horizontalPadding, 0),
      math.max(startY - verticalPadding, 0),
      receiptRight + horizontalPadding,
      math.min(endY + verticalPadding, receiptBottom),
    );
  }

  // ---------------------------------------------------------------------------
  // Main parser
  // ---------------------------------------------------------------------------

  _ParsedReceipt _parseRecognizedText(
      RecognizedText recognizedText,
      ) {
    final rows = _buildRows(recognizedText);
    final rawText = recognizedText.text.trim();

    if (rows.isEmpty) {
      return _ParsedReceipt(
        rawText: rawText,
        merchantName: '',
        subtotal: null,
        tax: null,
        tip: null,
        fees: null,
        total: null,
        purchaseDate: null,
        items: const [],
      );
    }

    final merchant = _extractMerchant(rows);
    final subtotal = _extractSubtotal(rows);
    final tax = _extractTax(rows);
    final tip = _extractTip(rows);
    final fees = _extractFees(rows);
    final total = _extractTotal(rows);
    final date = _extractDate(rows);

    final candidates = <List<ScannedReceiptItem>>[];

    final sameRowItems = _extractSameRowItems(rows);
    if (sameRowItems.isNotEmpty) {
      candidates.add(sameRowItems);
    }

    final columnItems = _extractSeparatedColumnItems(rows);
    if (columnItems.isNotEmpty) {
      candidates.add(columnItems);
    }

    final sequentialItems =
    _extractSequentialNamePriceItems(rows);
    if (sequentialItems.isNotEmpty) {
      candidates.add(sequentialItems);
    }

    final items = _chooseBestItemCandidate(
      candidates: candidates,
      subtotal: subtotal,
    );

    final couponItems = _extractCouponDiscountItems(rows);

    final mergedItems = _deduplicateItems([
      ...items,
      ...couponItems,
    ]);

    // Repair general-retail layouts where a quantity/extended-price row
    // appears immediately before or after the actual product description.
    // Example:
    //   2 @ $3.49 ea      $6.98
    //   Market Pantry Water 24pk
    final repairedItems = _repairRetailItemNames(
      items: mergedItems,
      rows: rows,
    );

    return _ParsedReceipt(
      rawText: rawText,
      merchantName: merchant,
      subtotal: subtotal,
      tax: tax,
      tip: tip,
      fees: fees,
      total: total,
      purchaseDate: date,
      items: repairedItems,
    );
  }

  // ---------------------------------------------------------------------------
  // Merchant
  // ---------------------------------------------------------------------------

  String _extractMerchant(List<_OcrRow> rows) {
    final limit = math.min(rows.length, 12);

    _MerchantCandidate? best;

    for (var i = 0; i < limit; i++) {
      final row = rows[i];
      var value = _cleanupMerchant(row.text);

      if (value.isEmpty ||
          _isHeaderNoise(value) ||
          _looksLikeDateOrTime(value) ||
          _isMoneyOnly(value) ||
          _isSubtotalRow(value) ||
          _looksLikeAddress(value) ||
          _looksLikePhone(value) ||
          _looksLikeTransactionMetadata(value)) {
        continue;
      }

      final letters =
          RegExp(r'[A-Za-z]').allMatches(value).length;

      if (letters < 2) {
        continue;
      }

      var score = 0.0;

      // ------------------------------------------------------------
      // Position:
      // Merchant names are normally very close to the top.
      // Give the first few rows the strongest score.
      // ------------------------------------------------------------
      score += math.max(0, 12 - i) * 2.0;

      // ------------------------------------------------------------
      // Business-name length.
      // ------------------------------------------------------------
      if (value.length <= 40) {
        score += 3;
      }

      if (value.length <= 25) {
        score += 2;
      }

      // Extremely short strings are less likely to be the merchant.
      if (letters <= 3) {
        score -= 2;
      }

      // ------------------------------------------------------------
      // Prefer text that contains several words.
      //
      // Examples:
      // "Target"              -> okay
      // "Luigis attoria"      -> strong
      // "WALMART SUPERCENTER" -> strong
      // ------------------------------------------------------------
      final words = value
          .split(RegExp(r'\s+'))
          .where((word) => word.trim().isNotEmpty)
          .length;

      if (words >= 2) {
        score += 3;
      }

      if (words >= 3) {
        score += 1;
      }

      // ------------------------------------------------------------
      // Don't over-reward uppercase text.
      //
      // OCR can turn noisy text into uppercase, so this is only
      // a small signal rather than a strong merchant indicator.
      // ------------------------------------------------------------
      final upperLetters =
          RegExp(r'[A-Z]').allMatches(value).length;

      if (letters > 0 &&
          upperLetters / letters >= 0.80) {
        score += 1;
      }

      // ------------------------------------------------------------
      // Penalize obvious non-merchant header text.
      // ------------------------------------------------------------
      final lower = value.toLowerCase();

      if (_containsAny(lower, const [
        'thank',
        'save money',
        'live better',
        'welcome',
        'customer copy',
        'receipt',
        'invoice',
        'store copy',
        'merchant copy',
        'transaction',
        'order number',
        'order no',
        'table',
        'server',
      ])) {
        score -= 10;
      }

      // ------------------------------------------------------------
      // A merchant normally doesn't look like a sentence.
      // ------------------------------------------------------------
      if (RegExp(r'[.!?]{2,}').hasMatch(value)) {
        score -= 5;
      }

      // ------------------------------------------------------------
      // Prefer names with normal business punctuation.
      // Apostrophes, &, hyphens, periods, etc. are valid.
      // ------------------------------------------------------------
      if (RegExp(r"[A-Za-z][&'’.\-][A-Za-z]")
          .hasMatch(value)) {
        score += 1;
      }

      debugPrint(
        'MERCHANT CANDIDATE: "$value" '
            'score=${score.toStringAsFixed(2)}',
      );

      if (best == null || score > best.score) {
        best = _MerchantCandidate(
          value: value,
          score: score,
        );
      }
    }

    debugPrint('======= MERCHANT DEBUG =======');

    for (var i = 0; i < math.min<int>(rows.length, 12); i++) {
      debugPrint(
        'HEADER ROW $i: "${rows[i].text}"',
      );
    }

    debugPrint(
      'SELECTED MERCHANT: ${best?.value}',
    );

    debugPrint('==============================');

    return best?.value ?? '';
  }

  String _cleanupMerchant(String value)
  {
    var result = _normalizeWhitespace(value);

    // Remove decorative characters while preserving normal business punctuation.
    result = result
        .replaceAll(RegExp(r'^[*#=_~\-\s]+'), '')
        .replaceAll(RegExp(r'[*#=_~\-\s]+$'), '')
        .trim();

    return result;
  }

  // ---------------------------------------------------------------------------
  // Totals / subtotal
  // ---------------------------------------------------------------------------

  double? _extractSubtotal(List<_OcrRow> rows) {
    final labeled = _extractLabeledAmount(
      rows,
      matcher: _isSubtotalRow,
    );

    if (labeled != null) {
      return labeled;
    }

    return null;
  }

  double? _extractTax(List<_OcrRow> rows) {
    return _extractChargeByLabel(
      rows,
      matcher: (text) {
        final lower = text.toLowerCase();

        if (lower.contains('taxable') ||
            lower.contains('tax id') ||
            lower.contains('tax#') ||
            lower.contains('tax #')) {
          return false;
        }

        return RegExp(r'\btax\b').hasMatch(lower);
      },
    );
  }

  double? _extractTip(List<_OcrRow> rows) {
    return _extractChargeByLabel(
      rows,
      matcher: (text) {
        final lower = text.toLowerCase();

        if (_containsAny(lower, const [
          'suggested tip',
          'tip guide',
          'tip suggestion',
          'suggested gratuity',
        ])) {
          return false;
        }

        return RegExp(r'\btip\b').hasMatch(lower) ||
            RegExp(r'\bgratuity\b').hasMatch(lower);
      },
    );
  }

  double? _extractFees(List<_OcrRow> rows) {
    final feeMatchers = <bool Function(String)>[
          (text) => text.toLowerCase().contains('service fee'),
          (text) => text.toLowerCase().contains('service charge'),
          (text) => text.toLowerCase().contains('delivery fee'),
          (text) => text.toLowerCase().contains('convenience fee'),
          (text) => text.toLowerCase().contains('processing fee'),
          (text) => text.toLowerCase().contains('platform fee'),
          (text) => text.toLowerCase().contains('transaction fee'),
          (text) => RegExp(r'\bsurcharge\b')
          .hasMatch(text.toLowerCase()),
    ];

    var total = 0.0;
    var found = false;

    for (final matcher in feeMatchers) {
      final value = _extractChargeByLabel(
        rows,
        matcher: matcher,
      );

      if (value != null && value.abs() > 0.001) {
        total += value;
        found = true;
      }
    }

    return found ? _roundMoney(total) : null;
  }

  double? _extractChargeByLabel(
      List<_OcrRow> rows, {
        required bool Function(String text) matcher,
      }) {
    // Search from the bottom because receipt totals/charges usually appear
    // below the item section.
    for (var i = rows.length - 1; i >= 0; i--) {
      final row = rows[i];

      if (!matcher(row.text)) {
        continue;
      }

      // _moneyMatches already rejects a number followed by %, so a line such
      // as "TAX 8.75% 1.79" returns 1.79 rather than 8.75.
      final sameRow = _moneyMatches(row.text);

      if (sameRow.isNotEmpty) {
        return sameRow.last.value.abs();
      }

      // Try each OCR cell. This handles label/amount cells on the same
      // geometric row.
      final cellAmounts = <_MoneyMatch>[];

      for (final cell in row.cells) {
        cellAmounts.addAll(_moneyMatches(cell.text));
      }

      if (cellAmounts.isNotEmpty) {
        return cellAmounts.last.value.abs();
      }

      // ML Kit may put the amount on the immediately following OCR row.
      // Keep this narrow so TAX cannot accidentally consume TIP/TOTAL.
      if (i + 1 < rows.length) {
        final nextRow = rows[i + 1];

        if (!_isSubtotalRow(nextRow.text) &&
            !_isTotalRow(nextRow.text) &&
            !_isPaymentRow(nextRow.text) &&
            !_looksLikeDateOrTime(nextRow.text) &&
            !_looksLikeTransactionMetadata(nextRow.text)) {
          final next = _moneyMatches(nextRow.text);

          if (next.length == 1 &&
              _isMoneyOnly(nextRow.text)) {
            return next.first.value.abs();
          }
        }
      }
    }

    return null;
  }

  double? _extractTotal(List<_OcrRow> rows) {
    // Highest priority: strong total labels.
    final priorityMatchers =
    <bool Function(String)>[
          (text) {
        final lower = text.toLowerCase();
        return lower.contains('grand total') ||
            lower.contains('amount due') ||
            lower.contains('balance due') ||
            lower.contains('total due') ||
            lower.contains('net total');
      },
      _isTotalRow,
    ];

    for (final matcher in priorityMatchers) {
      final value = _extractLabeledAmount(
        rows,
        matcher: matcher,
      );

      if (value != null) return value;
    }

    // Fallback: largest plausible amount near the bottom, excluding tender/change.
    final int start =
    math.max<int>(
      0,
      rows.length - math.min<int>(18, rows.length),
    );
    final candidates = <double>[];

    for (var i = start; i < rows.length; i++) {
      final text = rows[i].text;
      final lower = text.toLowerCase();

      if (_containsAny(lower, const [
        'change',
        'cash',
        'tender',
        'payment',
        'visa',
        'mastercard',
        'amex',
        'debit',
        'credit',
        'gift card',
        'approved',
        'auth',
      ])) {
        continue;
      }

      candidates.addAll(
        _moneyMatches(text)
            .map((e) => e.value)
            .where((e) => e > 0),
      );
    }

    if (candidates.isEmpty) {
      return null;
    }

    candidates.sort();
    return candidates.last;
  }
  List<ScannedReceiptItem> _extractCouponDiscountItems(
      List<_OcrRow> rows,
      ) {
    final discountNames = <String>[];
    final negativeAmounts = <double>[];
    final directItems = <ScannedReceiptItem>[];

    // -------------------------------------------------------
    // 1. Find actual coupon / discount rows.
    // -------------------------------------------------------
    for (final row in rows) {
      final text = row.text;
      final lower = text.toLowerCase();

      // These are receipt SUMMARY lines, not individual discounts.
      // Examples:
      // Savings this order   -13.00
      // Total savings        -13.00
      // You saved            -13.00
      if (_isDiscountSummaryRow(lower)) {
        continue;
      }

      final isDiscountRow =
          lower.contains('coupon') ||
              lower.contains('discount') ||
              lower.contains('promo') ||
              lower.contains('markdown');

      if (!isDiscountRow) {
        continue;
      }

      final matches = _moneyMatches(text);

      // Discount and amount are on the same OCR row.
      //
      // CVS COUPON -4.00
      // MFR COUPON -2.00
      // DISCOUNT 3.00-
      if (matches.isNotEmpty) {
        final value = matches.last.value;

        if (value.abs() > 0.001) {
          var name = _cleanupItemName(
            text.substring(
              0,
              matches.last.start,
            ),
          );

          if (name.isEmpty) {
            name = 'Coupon / Discount';
          }

          directItems.add(
            _makeItem(
              name: name,
              amount: -value.abs(),
            ),
          );

          continue;
        }
      }

      // Some receipts have the coupon label in the description
      // column and its negative amount later in a separate OCR column.
      var name = _cleanupItemName(text);

      if (name.isEmpty) {
        name = 'Coupon / Discount';
      }

      discountNames.add(name);
    }

    // -------------------------------------------------------
    // 2. Find standalone negative amounts.
    // -------------------------------------------------------
    for (final row in rows) {
      final text = row.text;
      final lower = text.toLowerCase();

      // Never use savings-summary amounts as individual coupons.
      if (_isDiscountSummaryRow(lower)) {
        continue;
      }

      if (_looksLikeDateOrTime(text) ||
          _looksLikeTransactionMetadata(text)) {
        continue;
      }

      // If this row already contains a discount label and amount,
      // it was handled above. Don't collect the amount again.
      final hasDiscountLabel =
          lower.contains('coupon') ||
              lower.contains('discount') ||
              lower.contains('promo') ||
              lower.contains('markdown');

      if (hasDiscountLabel) {
        continue;
      }

      final matches = _moneyMatches(text);

      for (final match in matches) {
        if (match.value < 0) {
          negativeAmounts.add(match.value);
        }
      }
    }

    // -------------------------------------------------------
    // 3. Pair label-only discounts with standalone negatives.
    // -------------------------------------------------------
    final int pairCount = math.min<int>(
      discountNames.length,
      negativeAmounts.length,
    );

    for (var i = 0; i < pairCount; i++) {
      directItems.add(
        _makeItem(
          name: discountNames[i],
          amount: negativeAmounts[i],
        ),
      );
    }

    return _deduplicateDiscountItems(directItems);
  }
  bool _isDiscountSummaryRow(String text) {
    final lower = text.toLowerCase().trim();

    return _containsAny(
      lower,
      const [
        'savings this order',
        'savings this purchase',
        'total savings',
        'total discount',
        'total discounts',
        'you saved',
        'you save',
        'your savings',
        'today\'s savings',
        'todays savings',
        'amount saved',
        'coupon savings',
        'discount savings',
        'subtotal after discount',
        'subtotal after discounts',
        'after discount subtotal',
        'after discounts subtotal',
      ],
    );
  }
  List<ScannedReceiptItem> _deduplicateDiscountItems(
      List<ScannedReceiptItem> items,
      ) {
    if (items.isEmpty) {
      return const [];
    }

    final result = <ScannedReceiptItem>[];
    final seen = <String>{};

    for (final item in items) {
      final name = _canonicalName(item.name);

      final amountCents =
      (item.amount * 100).round();

      final key = '$name|$amountCents';

      if (seen.contains(key)) {
        debugPrint(
          'REMOVED DUPLICATE DISCOUNT: '
              '${item.name} | '
              '${item.amount.toStringAsFixed(2)}',
        );
        continue;
      }

      seen.add(key);
      result.add(item);
    }

    return result;
  }
  List<ScannedReceiptItem> _reconcileDiscountItems({
    required List<ScannedReceiptItem> items,
    required double? subtotal,
  }) {
    if (subtotal == null || items.isEmpty) {
      return items;
    }

    final positiveItems = items
        .where((item) => item.amount > 0)
        .toList();

    final negativeItems = items
        .where((item) => item.amount < 0)
        .toList();

    if (negativeItems.isEmpty) {
      return items;
    }

    final positiveTotal = positiveItems.fold<double>(
      0,
          (runningTotal, item) =>
      runningTotal + item.amount,
    );

    final requiredDiscount =
        positiveTotal - subtotal;

    if (requiredDiscount <= _moneyTolerance) {
      return positiveItems;
    }

    final targetCents =
    (requiredDiscount * 100).round();

    final selected = <ScannedReceiptItem>[];
    var selectedCents = 0;

    for (final item in negativeItems) {
      final itemCents =
      (item.amount.abs() * 100).round();

      if (selectedCents + itemCents >
          targetCents + 1) {
        debugPrint(
          'REMOVED EXCESS DISCOUNT: '
              '${item.name} | '
              '${item.amount.toStringAsFixed(2)}',
        );

        continue;
      }

      selected.add(item);
      selectedCents += itemCents;

      if ((selectedCents - targetCents).abs() <= 1) {
        break;
      }
    }

    // Only trust this reconciliation if it actually reaches
    // the subtotal-implied discount amount.
    if ((selectedCents - targetCents).abs() > 1) {
      return items;
    }

    return [
      ...positiveItems,
      ...selected,
    ];
  }
  double? _extractLabeledAmount(
      List<_OcrRow> rows, {
        required bool Function(String text) matcher,
      }) {
    // Search from bottom because totals near the end are more trustworthy.
    for (var i = rows.length - 1; i >= 0; i--) {
      final row = rows[i];

      if (!matcher(row.text)) {
        continue;
      }

      final sameRow = _moneyMatches(row.text);

      if (sameRow.isNotEmpty) {
        return sameRow.last.value.abs();
      }

      // Geometry: label in one OCR cell and amount in neighboring cell.
      final rowAmounts = <_MoneyMatch>[];

      for (final cell in row.cells) {
        rowAmounts.addAll(_moneyMatches(cell.text));
      }

      if (rowAmounts.isNotEmpty) {
        return rowAmounts.last.value.abs();
      }

      // OCR sometimes puts the amount one row below.
      for (var j = i + 1;
      j < math.min(rows.length, i + 4);
      j++) {
        if (_isPaymentRow(rows[j].text)) break;

        final next = _moneyMatches(rows[j].text);

        if (next.length == 1 &&
            _isMoneyOnly(rows[j].text)) {
          return next.first.value.abs();
        }
      }
    }

    return null;
  }

  bool _isSubtotalRow(String text) {
    final lower = text.toLowerCase();
    return RegExp(r'\bsub\s*total\b').hasMatch(lower) ||
        RegExp(r'\bsubtotal\b').hasMatch(lower);
  }

  bool _isTotalRow(String text) {
    final lower = text.toLowerCase();

    if (_isSubtotalRow(lower)) return false;

    if (_containsAny(lower, const [
      'total savings',
      'total discount',
      'total tax',
      'total items',
      'item total',
      'items sold',
      'total purchase',
    ])) {
      return false;
    }

    return RegExp(
      r'\b(grand\s*total|amount\s*due|balance\s*due|'
      r'total\s*due|net\s*total|total)\b',
    ).hasMatch(lower);
  }

  // ---------------------------------------------------------------------------
  // Item extraction: strategy 1 - description and price in same geometry row
  // ---------------------------------------------------------------------------

  List<ScannedReceiptItem> _extractSameRowItems(
      List<_OcrRow> rows,
      ) {
    final items = <ScannedReceiptItem>[];

    for (final row in rows) {
      if (!_rowMayContainItem(row)) {
        continue;
      }

      // A row can have separate OCR cells:
      // [description] [UPC] [price] [tax flag]
      final moneyCells = <_CellMoney>[];

      for (var i = 0; i < row.cells.length; i++) {
        final matches = _moneyMatches(
          row.cells[i].text,
        );

        for (final match in matches) {
          moneyCells.add(
            _CellMoney(
              cellIndex: i,
              match: match,
            ),
          );
        }
      }

      if (moneyCells.isEmpty) {
        // Fall back to combined row text.
        final matches = _moneyMatches(row.text);

        if (matches.isEmpty) continue;

        final price = matches.last;
        final before = row.text
            .substring(0, price.start)
            .trim();

        final name = _cleanupItemName(before);

        if (_looksLikeItemName(name)) {
          items.add(
            _makeItem(
              name: name,
              amount: _signedItemAmount(
                row.text,
                price.value,
              ),
            ),
          );
        }

        continue;
      }

      // Receipt line price is usually the right-most monetary value.
      moneyCells.sort((a, b) {
        final leftA =
            row.cells[a.cellIndex].rect.left;
        final leftB =
            row.cells[b.cellIndex].rect.left;
        return leftA.compareTo(leftB);
      });

      final priceInfo = moneyCells.last;
      final priceCell = row.cells[priceInfo.cellIndex];

      final descriptionParts = <String>[];

      for (var i = 0; i < row.cells.length; i++) {
        final cell = row.cells[i];

        if (cell.rect.left >= priceCell.rect.left) {
          continue;
        }

        var part = cell.text;

        // If description and price share one cell, keep text before price.
        if (i == priceInfo.cellIndex) {
          part = part
              .substring(0, priceInfo.match.start)
              .trim();
        }

        if (_isLikelySkuOnly(part)) {
          continue;
        }

        descriptionParts.add(part);
      }

      // If there was only one cell, use text before price.
      if (descriptionParts.isEmpty &&
          row.cells.length == 1) {
        descriptionParts.add(
          row.cells.first.text
              .substring(0, priceInfo.match.start)
              .trim(),
        );
      }

      var name = _cleanupItemName(
        descriptionParts.join(' '),
      );

      if (!_looksLikeItemName(name)) {
        // Sometimes combined row text is easier than cell reconstruction.
        final allMatches = _moneyMatches(row.text);

        if (allMatches.isNotEmpty) {
          final last = allMatches.last;
          name = _cleanupItemName(
            row.text.substring(0, last.start),
          );
        }
      }

      if (!_looksLikeItemName(name)) {
        continue;
      }

      items.add(
        _makeItem(
          name: name,
          amount: _signedItemAmount(
            row.text,
            priceInfo.match.value,
          ),
        ),
      );
    }

    return _deduplicateItems(items);
  }

  // ---------------------------------------------------------------------------
  // Item extraction: strategy 2 - geometry-separated description/price columns
  // ---------------------------------------------------------------------------

  List<ScannedReceiptItem> _extractSeparatedColumnItems(
      List<_OcrRow> rows,
      ) {
    final itemRows = rows
        .where(_rowMayContainItem)
        .toList();

    if (itemRows.length < 2) {
      return const [];
    }

    final items = <ScannedReceiptItem>[];

    for (final row in itemRows) {
      final rightMoney = <_MoneyAtX>[];

      for (final cell in row.cells) {
        for (final match in _moneyMatches(cell.text)) {
          rightMoney.add(
            _MoneyAtX(
              value: match.value,
              x: cell.rect.right,
              match: match,
              cell: cell,
            ),
          );
        }
      }

      if (rightMoney.isEmpty) {
        continue;
      }

      rightMoney.sort((a, b) => a.x.compareTo(b.x));
      final chosen = rightMoney.last;

      final descriptionCells = row.cells.where(
            (cell) =>
        cell.rect.left <
            chosen.cell.rect.left,
      );

      var name = descriptionCells
          .where((cell) => !_isLikelySkuOnly(cell.text))
          .map((cell) => cell.text)
          .join(' ');

      if (name.trim().isEmpty &&
          chosen.cell == row.cells.first) {
        name = chosen.cell.text
            .substring(0, chosen.match.start);
      }

      name = _cleanupItemName(name);

      if (!_looksLikeItemName(name)) {
        continue;
      }

      items.add(
        _makeItem(
          name: name,
          amount: _signedItemAmount(
            row.text,
            chosen.value,
          ),
        ),
      );
    }

    return _deduplicateItems(items);
  }

  // ---------------------------------------------------------------------------
  // Item extraction: strategy 3 - OCR gives names first, prices later
  // ---------------------------------------------------------------------------

  List<ScannedReceiptItem> _extractSequentialNamePriceItems(
      List<_OcrRow> rows,
      ) {
    final subtotalIndex =
    rows.indexWhere((r) => _isSubtotalRow(r.text));

    final totalIndex =
    rows.indexWhere((r) => _isTotalRow(r.text));

    var logicalEnd = subtotalIndex >= 0
        ? subtotalIndex
        : totalIndex >= 0
        ? totalIndex
        : rows.length;

    if (logicalEnd <= 0) {
      logicalEnd = rows.length;
    }

    final possibleNames = <String>[];

    for (var i = 0; i < logicalEnd; i++) {
      final row = rows[i];

      if (_isReceiptNoise(row.text) ||
          _moneyMatches(row.text).isNotEmpty) {
        continue;
      }

      final name = _cleanupItemName(row.text);

      if (_looksLikeItemName(name)) {
        possibleNames.add(name);
      }
    }

    if (possibleNames.isEmpty) {
      return const [];
    }

    // Collect standalone money rows throughout the receipt. ML Kit can read
    // the right-hand price column after the left-hand description column.
    final prices = <double>[];

    for (final row in rows) {
      if (!_isMoneyOnly(row.text)) {
        continue;
      }

      final matches = _moneyMatches(row.text);

      if (matches.length == 1 &&
          matches.first.value.abs() > 0) {
        prices.add(matches.first.value.abs());
      }
    }

    if (prices.length < possibleNames.length) {
      return const [];
    }

    // Try contiguous windows and pick the one whose sum best matches subtotal.
    final maxWindowStart =
        prices.length - possibleNames.length;

    var bestStart = 0;
    var bestDifference = double.infinity;

    for (var start = 0;
    start <= maxWindowStart;
    start++) {
      final window = prices.sublist(
        start,
        start + possibleNames.length,
      );

      final sum = window.fold<double>(
        0,
            (a, b) => a + b,
      );

      // If no subtotal, prefer earliest plausible window.
      final target = _extractSubtotal(rows);

      final difference = target == null
          ? start.toDouble()
          : (sum - target).abs();

      if (difference < bestDifference) {
        bestDifference = difference;
        bestStart = start;
      }
    }

    final chosenPrices = prices.sublist(
      bestStart,
      bestStart + possibleNames.length,
    );

    final items = <ScannedReceiptItem>[];

    for (var i = 0;
    i < possibleNames.length;
    i++) {
      items.add(
        _makeItem(
          name: possibleNames[i],
          amount: chosenPrices[i],
        ),
      );
    }

    return _deduplicateItems(items);
  }

  // ---------------------------------------------------------------------------
  // Candidate scoring and pass merging
  // ---------------------------------------------------------------------------

  List<ScannedReceiptItem> _chooseBestItemCandidate({
    required List<List<ScannedReceiptItem>> candidates,
    required double? subtotal,
  }) {
    if (candidates.isEmpty) {
      return const [];
    }

    List<ScannedReceiptItem>? best;
    var bestScore = -double.infinity;

    for (final candidate in candidates) {
      final score = _scoreItems(
        candidate,
        subtotal,
      );

      if (score > bestScore) {
        bestScore = score;
        best = candidate;
      }
    }

    return best ?? const [];
  }

  double _scoreItems(
      List<ScannedReceiptItem> items,
      double? subtotal,
      ) {
    if (items.isEmpty) {
      return -1000;
    }

    var score = items.length * 10.0;

    final named = items.where(
          (e) => _looksLikeItemName(e.name),
    ).length;

    score += named * 2;

    final suspiciousNames = items.where(
          (e) => _isReceiptNoise(e.name),
    ).length;

    score -= suspiciousNames * 15;

    if (subtotal != null && subtotal > 0) {
      final positiveSum = items
          .where((e) => e.amount > 0)
          .fold<double>(
        0,
            (sum, e) => sum + e.amount,
      );

      final netSum = items.fold<double>(
        0,
            (sum, e) => sum + e.amount,
      );

      // Some retailers print SUBTOTAL before coupons, while others (for
      // example many pharmacy receipts) print a subtotal after coupons.
      // Score against whichever interpretation is closer instead of
      // assuming discounts are always excluded from the subtotal.
      final difference = math.min(
        (positiveSum - subtotal).abs(),
        (netSum - subtotal).abs(),
      );

      final relative =
          difference / subtotal;

      score += math.max(
        0,
        100 - (relative * 200),
      );

      if (difference <= _moneyTolerance) {
        score += 100;
      } else if (difference <= 0.50) {
        score += 40;
      } else if (difference > subtotal * 0.40) {
        score -= 50;
      }
    }

    return score;
  }

  double _scoreParse(_ParsedReceipt parsed) {
    var score = _scoreItems(
      parsed.items,
      parsed.subtotal,
    );

    if ((parsed.merchantName ?? '').isNotEmpty) {
      score += 20;
    }

    if (parsed.total != null) {
      score += 35;
    }

    if (parsed.subtotal != null) {
      score += 20;
    }

    if (parsed.purchaseDate != null) {
      score += 8;
    }

    if (parsed.total != null &&
        parsed.subtotal != null &&
        parsed.total! + _moneyTolerance >=
            parsed.subtotal!) {
      score += 10;
    }

    return score;
  }

  _ParsedReceipt _mergePasses({
    required _ParsedReceipt first,
    required _ParsedReceipt second,
    required double firstScore,
    required double secondScore,
  }) {
    final secondHasBetterItems =
        _scoreItems(second.items, first.subtotal ?? second.subtotal) >
            _scoreItems(first.items, first.subtotal ?? second.subtotal);

    return _ParsedReceipt(
      // Preserve complete OCR for debugging / storage.
      rawText: first.rawText,
      merchantName:
      _chooseMerchant(first.merchantName, second.merchantName),
      subtotal: first.subtotal ?? second.subtotal,
      tax: first.tax ?? second.tax,
      tip: first.tip ?? second.tip,
      fees: first.fees ?? second.fees,
      total: first.total ?? second.total,
      purchaseDate:
      first.purchaseDate ?? second.purchaseDate,
      items: secondHasBetterItems
          ? second.items
          : first.items,
    );
  }

  String _chooseMerchant(
      String? first,
      String? second,
      ) {
    final a = (first ?? '').trim();
    final b = (second ?? '').trim();

    if (a.isNotEmpty && !_isHeaderNoise(a)) {
      return a;
    }

    if (b.isNotEmpty && !_isHeaderNoise(b)) {
      return b;
    }

    return a.isNotEmpty ? a : b;
  }

  String? _secondPassReason(_ParsedReceipt parsed) {
    if (parsed.items.isEmpty) {
      return 'no items detected';
    }

    if (parsed.total == null) {
      return 'total not detected';
    }

    if (parsed.subtotal != null &&
        parsed.subtotal! > 0) {
      final positiveSum = parsed.items
          .where((e) => e.amount > 0)
          .fold<double>(
        0,
            (sum, item) => sum + item.amount,
      );

      final netSum = parsed.items.fold<double>(
        0,
            (sum, item) => sum + item.amount,
      );

      final difference = math.min(
        (positiveSum - parsed.subtotal!).abs(),
        (netSum - parsed.subtotal!).abs(),
      );

      final allowed = math.max(
        0.50,
        parsed.subtotal! * 0.02,
      );

      if (difference > allowed) {
        return 'subtotal difference '
            '${difference.toStringAsFixed(2)}';
      }
    }

    // A receipt with a known subtotal but only 1 item is often under-read.
    if (parsed.subtotal != null &&
        parsed.subtotal! >= 15 &&
        parsed.items.length <= 1) {
      return 'too few items';
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // Final cleanup / validation
  // ---------------------------------------------------------------------------

  _ParsedReceipt _cleanFinalReceipt(
      _ParsedReceipt parsed,
      ) {
    final cleanedItems = <ScannedReceiptItem>[];

    for (final item in parsed.items) {
      if (item.amount.abs() <= 0.001) {
        continue;
      }

      var name = _cleanupItemName(item.name);

      // Do not save sale/reference-price rows as merchandise.
      // Example: "Sale $11.99 Reg $15.99" is price metadata, not an item.
      if (item.amount > 0 && _isReferencePriceRow(name)) {
        debugPrint(
          'REMOVED REFERENCE PRICE ROW: '
              '$name | ${item.amount.toStringAsFixed(2)}',
        );
        continue;
      }

      // Negative receipt lines are coupons/discounts.
      // Do not throw them away merely because OCR produced
      // a poor label such as "$1", "-", or another noisy value.
      if (item.amount < 0) {
        if (!_looksLikeItemName(name)) {
          name = 'Coupon / Discount';
        }

        cleanedItems.add(
          ScannedReceiptItem(
            name: name,
            amount: _roundMoney(item.amount),
            detectedTag: null,
          ),
        );

        continue;
      }

      // Normal positive merchandise still requires
      // a believable item name.
      if (!_looksLikeItemName(name)) {
        continue;
      }

      cleanedItems.add(
        ScannedReceiptItem(
          name: name,
          amount: _roundMoney(item.amount),
          detectedTag: _detectItemTag(name),
        ),
      );
    }

    final deduplicatedItems =
    _deduplicateItems(cleanedItems);

    final items = _reconcileDiscountItems(
      items: deduplicatedItems,
      subtotal: parsed.subtotal,
    );

    // Never silently invent a missing item or force item values
    // to make the subtotal match.
    if (parsed.subtotal != null &&
        items.isNotEmpty) {
      final positiveSum = items
          .where((item) => item.amount > 0)
          .fold<double>(
        0,
            (sum, item) => sum + item.amount,
      );

      final netSum = items.fold<double>(
        0,
            (sum, item) => sum + item.amount,
      );

      final difference = math.min(
        (positiveSum - parsed.subtotal!).abs(),
        (netSum - parsed.subtotal!).abs(),
      );

      if (difference > _moneyTolerance) {
        debugPrint(
          'RECEIPT VALIDATION WARNING: '
              'positive item sum='
              '${positiveSum.toStringAsFixed(2)}, '
              'net item sum='
              '${netSum.toStringAsFixed(2)}, '
              'subtotal='
              '${parsed.subtotal!.toStringAsFixed(2)}, '
              'best difference='
              '${difference.toStringAsFixed(2)}',
        );
      }
    }

    return _ParsedReceipt(
      rawText: parsed.rawText,
      merchantName:
      _cleanupMerchant(parsed.merchantName ?? ''),
      subtotal: parsed.subtotal == null
          ? null
          : _roundMoney(parsed.subtotal!),
      tax: parsed.tax == null
          ? null
          : _roundMoney(parsed.tax!),
      tip: parsed.tip == null
          ? null
          : _roundMoney(parsed.tip!),
      fees: parsed.fees == null
          ? null
          : _roundMoney(parsed.fees!),
      total: parsed.total == null
          ? null
          : _roundMoney(parsed.total!),
      purchaseDate: parsed.purchaseDate,
      items: items,
    );
  }

  // ---------------------------------------------------------------------------
  // Dates
  // ---------------------------------------------------------------------------

  DateTime? _extractDate(List<_OcrRow> rows) {
    // Search each OCR row first so unrelated numbers from different lines
    // cannot accidentally be joined together.
    final candidates = <String>[
      for (final row in rows) row.text,
      // Also keep the complete OCR text as a final fallback.
      rows.map((row) => row.text).join('\n'),
    ];

    for (final candidate in candidates) {
      final normalized = _normalizeDateOcr(candidate);

      // US receipt formats:
      // 05/11/2025, 5-11-25, 05.11.2025
      final usMatch = RegExp(
        r'(?<!\d)(\d{1,2})\s*[/.\-]\s*(\d{1,2})\s*[/.\-]\s*(\d{2,4})(?!\d)',
      ).firstMatch(normalized);

      if (usMatch != null) {
        final result = _safeDate(
          year: int.tryParse(usMatch.group(3)!),
          month: int.tryParse(usMatch.group(1)!),
          day: int.tryParse(usMatch.group(2)!),
        );

        if (result != null) {
          return result;
        }
      }

      // ISO-style receipt format: 2025-05-11 / 2025.05.11
      final isoMatch = RegExp(
        r'(?<!\d)(\d{4})\s*[/.\-]\s*(\d{1,2})\s*[/.\-]\s*(\d{1,2})(?!\d)',
      ).firstMatch(normalized);

      if (isoMatch != null) {
        final result = _safeDate(
          year: int.tryParse(isoMatch.group(1)!),
          month: int.tryParse(isoMatch.group(2)!),
          day: int.tryParse(isoMatch.group(3)!),
        );

        if (result != null) {
          return result;
        }
      }

      final monthNames = <String, int>{
        'jan': 1,
        'january': 1,
        'feb': 2,
        'february': 2,
        'mar': 3,
        'march': 3,
        'apr': 4,
        'april': 4,
        'may': 5,
        'jun': 6,
        'june': 6,
        'jul': 7,
        'july': 7,
        'aug': 8,
        'august': 8,
        'sep': 9,
        'sept': 9,
        'september': 9,
        'oct': 10,
        'october': 10,
        'nov': 11,
        'november': 11,
        'dec': 12,
        'december': 12,
      };

      // May 11, 2025 / May 11 2025
      final namedMonthFirst = RegExp(
        r'\b([A-Za-z]{3,9})\s+'
        r'(\d{1,2})(?:st|nd|rd|th)?'
        r'(?:,)?\s+(\d{2,4})\b',
        caseSensitive: false,
      ).firstMatch(normalized);

      if (namedMonthFirst != null) {
        final month =
        monthNames[namedMonthFirst.group(1)!.toLowerCase()];

        final result = _safeDate(
          year: int.tryParse(namedMonthFirst.group(3)!),
          month: month,
          day: int.tryParse(namedMonthFirst.group(2)!),
        );

        if (result != null) {
          return result;
        }
      }

      // 11 May 2025
      final namedDayFirst = RegExp(
        r'\b(\d{1,2})(?:st|nd|rd|th)?\s+'
        r'([A-Za-z]{3,9})(?:,)?\s+(\d{2,4})\b',
        caseSensitive: false,
      ).firstMatch(normalized);

      if (namedDayFirst != null) {
        final month =
        monthNames[namedDayFirst.group(2)!.toLowerCase()];

        final result = _safeDate(
          year: int.tryParse(namedDayFirst.group(3)!),
          month: month,
          day: int.tryParse(namedDayFirst.group(1)!),
        );

        if (result != null) {
          return result;
        }
      }
    }

    return null;
  }

  String _normalizeDateOcr(String input) {
    var value = input;

    // Only correct OCR letter/number confusion inside date-like numeric runs.
    // This intentionally does NOT modify arbitrary receipt text.
    value = value.replaceAllMapped(
      RegExp(
        r'(?<![A-Za-z0-9])'
        r'([0-9OoIlSs]{1,4})'
        r'(\s*[/.\-]\s*)'
        r'([0-9OoIlSs]{1,2})'
        r'(\s*[/.\-]\s*)'
        r'([0-9OoIlSs]{2,4})'
        r'(?![A-Za-z0-9])',
      ),
          (match) {
        String fix(String part) {
          return part
              .replaceAll(RegExp(r'[Oo]'), '0')
              .replaceAll(RegExp(r'[Il]'), '1')
              .replaceAll(RegExp(r'[Ss]'), '5');
        }

        return '${fix(match.group(1)!)}'
            '${match.group(2)!}'
            '${fix(match.group(3)!)}'
            '${match.group(4)!}'
            '${fix(match.group(5)!)}';
      },
    );

    return value;
  }

  DateTime? _safeDate({
    required int? year,
    required int? month,
    required int? day,
  }) {
    if (year == null ||
        month == null ||
        day == null) {
      return null;
    }

    if (year < 100) {
      // Receipt dates are generally recent.
      year += year >= 70 ? 1900 : 2000;
    }

    if (year < 1970 ||
        year > DateTime.now().year + 1 ||
        month < 1 ||
        month > 12 ||
        day < 1 ||
        day > 31) {
      return null;
    }

    final date = DateTime(year, month, day);

    if (date.year != year ||
        date.month != month ||
        date.day != day) {
      return null;
    }

    return date;
  }

  // ---------------------------------------------------------------------------
  // Money parsing
  // ---------------------------------------------------------------------------

  List<_MoneyMatch> _moneyMatches(String text) {
    final result = <_MoneyMatch>[];

    // Supports:
    // $12.34
    // 12.34
    // 12,34  (OCR/European decimal)
    // S 17.00 (common OCR mistake for "$ 17.00")
    // -1.00 / 1.00-
    //
    // We intentionally require 2 decimal digits to avoid treating UPCs,
    // dates, quantities, percentages, and transaction IDs as prices.
    final pattern = RegExp(
      r'(?<!\d)'
      r'([\-−]?\s*(?:[$€£¥]|USD|CAD|AUD|EUR|GBP|S)?\s*'
      r'(?:[0-9Oo]{1,6}(?:[,.][0-9Oo]{3})*|[0-9Oo]{1,6})'
      r'[,.][0-9Oo]{2}\s*-?)'
      r'(?!\d)',
      caseSensitive: false,
    );

    for (final match in pattern.allMatches(text)) {
      final raw = match.group(1)!;
      final value = _parseMoneyToken(raw);

      if (value == null) continue;

      // Percentages such as "6.75 %" are not money.
      final tail = text
          .substring(
        match.end,
        math.min(text.length, match.end + 3),
      )
          .trimLeft();

      if (tail.startsWith('%')) {
        continue;
      }

      result.add(
        _MoneyMatch(
          value: value,
          start: match.start,
          end: match.end,
          raw: raw,
        ),
      );
    }

    return result;
  }

  double? _parseMoneyToken(String raw) {
    var value = raw.trim();

    var negative = false;

    if (value.startsWith('-') ||
        value.startsWith('−') ||
        value.endsWith('-')) {
      negative = true;
    }

    value = value
        .replaceAll('−', '-')
        .replaceAll(RegExp(r'(USD|CAD|AUD|EUR|GBP)',
        caseSensitive: false), '')
        .replaceAll(RegExp(r'[$€£¥]'), '')
        .replaceAll(' ', '')
        .replaceAll('O', '0')
        .replaceAll('o', '0')
        .replaceAll('-', '');

    // OCR may read the dollar sign as S only when it appears before digits.
    value = value.replaceFirst(
      RegExp(r'^[Ss](?=\d)'),
      '',
    );

    final commaCount =
        ','.allMatches(value).length;
    final dotCount =
        '.'.allMatches(value).length;

    if (commaCount > 0 && dotCount == 0) {
      final lastComma = value.lastIndexOf(',');
      final decimals =
          value.length - lastComma - 1;

      if (decimals == 2) {
        value = value.replaceAll(',', '.');
      } else {
        value = value.replaceAll(',', '');
      }
    } else if (commaCount > 0 && dotCount > 0) {
      // Assume commas are thousands separators.
      value = value.replaceAll(',', '');
    }

    final parsed = double.tryParse(value);

    if (parsed == null) {
      return null;
    }

    if (parsed > 1000000) {
      return null;
    }

    return negative ? -parsed : parsed;
  }

  bool _isMoneyOnly(String text) {
    final clean = text
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final matches = _moneyMatches(clean);

    if (matches.length != 1) {
      return false;
    }

    var leftover = clean
        .replaceRange(
      matches.first.start,
      matches.first.end,
      '',
    )
        .trim();

    // Common tax flags after price: F, X, N, O, T.
    leftover = leftover.replaceAll(
      RegExp(r'^[A-Za-z]{1,2}$'),
      '',
    );

    return leftover.trim().isEmpty;
  }

  // ---------------------------------------------------------------------------
  // Item / noise heuristics
  // ---------------------------------------------------------------------------

  bool _isReferencePriceRow(String text) {
    final lower = _normalizeWhitespace(text).toLowerCase();

    // Common retail comparison/reference-price layouts:
    //   Sale $11.99 Reg $15.99
    //   Sale 11.99 Regular 15.99
    //   Now $11.99 Was $15.99
    //
    // These lines describe pricing for a neighboring product and must never
    // become a second merchandise item.
    final hasSaleAndRegular =
        RegExp(r'\bsale\b').hasMatch(lower) &&
            (RegExp(r'\breg\b').hasMatch(lower) ||
                lower.contains('regular'));

    final hasNowAndWas =
        RegExp(r'\bnow\b').hasMatch(lower) &&
            RegExp(r'\bwas\b').hasMatch(lower);

    final hasOurAndRegularPrice =
        lower.contains('our price') &&
            lower.contains('regular price');

    return hasSaleAndRegular ||
        hasNowAndWas ||
        hasOurAndRegularPrice;
  }

  bool _looksLikeQuantityPriceName(String value) {
    final lower = _normalizeWhitespace(value).toLowerCase();

    // Examples:
    //   2 @ $3.49 ea
    //   2 @ 5.49 each
    //   3 x $2.00
    return RegExp(
      r'^\d{1,3}\s*(?:@|x)\s*'
      r'(?:[$€£¥]\s*)?'
      r'\d{1,6}[.,]\d{2}'
      r'(?:\s*(?:ea|each))?$',
      caseSensitive: false,
    ).hasMatch(lower);
  }

  bool _isRetailSectionHeader(String text) {
    final lower = _normalizeWhitespace(text).toLowerCase();

    return _containsAny(
      lower,
      const [
        'grocery',
        'household',
        'personal care',
        'health',
        'beauty',
        'apparel',
        'electronics',
        'produce',
        'bakery',
        'deli',
        'frozen',
        'store',
        'fuel',
      ],
    ) &&
        !lower.contains(RegExp(r'\d'));
  }

  List<ScannedReceiptItem> _repairRetailItemNames({
    required List<ScannedReceiptItem> items,
    required List<_OcrRow> rows,
  }) {
    if (items.isEmpty || rows.isEmpty) {
      return items;
    }

    final repaired = <ScannedReceiptItem>[];
    final usedQuantityRows = <int>{};

    for (final item in items) {
      if (!_looksLikeQuantityPriceName(item.name)) {
        repaired.add(item);
        continue;
      }

      String? replacementName;
      int? matchedRowIndex;

      // Match this specific item to the quantity row by its extended amount.
      // This prevents two Target-style quantity items from both being renamed
      // to the first nearby product description.
      for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
        if (usedQuantityRows.contains(rowIndex)) {
          continue;
        }

        final rowText = _normalizeWhitespace(rows[rowIndex].text);

        if (!RegExp(
          r'\b\d{1,3}\s*(?:@|x)\s*'
          r'(?:[$€£¥]\s*)?'
          r'\d{1,6}[.,]\d{2}',
          caseSensitive: false,
        ).hasMatch(rowText)) {
          continue;
        }

        final amounts = _moneyMatches(rowText);
        if (amounts.isEmpty) {
          continue;
        }

        // On a row such as "2 @ $3.49 ea  $6.98", the right-most monetary
        // value is the extended line amount.
        final extendedAmount = amounts.last.value.abs();
        if ((extendedAmount - item.amount.abs()).abs() > 0.02) {
          continue;
        }

        matchedRowIndex = rowIndex;
        break;
      }

      if (matchedRowIndex != null) {
        final neighborIndexes = <int>[
          matchedRowIndex - 1,
          matchedRowIndex + 1,
          matchedRowIndex - 2,
          matchedRowIndex + 2,
        ];

        for (final candidateIndex in neighborIndexes) {
          if (candidateIndex < 0 || candidateIndex >= rows.length) {
            continue;
          }

          final rawCandidate = rows[candidateIndex].text;
          final candidateText = _cleanupItemName(rawCandidate);

          if (candidateText.isEmpty ||
              _moneyMatches(rawCandidate).isNotEmpty ||
              _isRetailSectionHeader(candidateText) ||
              _isReceiptNoise(candidateText) ||
              _isSubtotalRow(candidateText) ||
              _isTotalRow(candidateText) ||
              _isPaymentRow(candidateText) ||
              _isReferencePriceRow(candidateText) ||
              _isLikelySkuOnly(candidateText) ||
              !_looksLikeItemName(candidateText)) {
            continue;
          }

          replacementName = candidateText;
          break;
        }

        usedQuantityRows.add(matchedRowIndex);
      }

      if (replacementName == null) {
        repaired.add(item);
        continue;
      }

      debugPrint(
        'REPAIRED RETAIL ITEM NAME: '
            '${item.name} -> $replacementName | '
            '${item.amount.toStringAsFixed(2)}',
      );

      repaired.add(
        ScannedReceiptItem(
          name: replacementName,
          amount: item.amount,
          detectedTag: _detectItemTag(replacementName),
        ),
      );
    }

    return _deduplicateItems(repaired);
  }

  bool _rowMayContainItem(_OcrRow row) {
    final text = row.text;

    if (_isReceiptNoise(text) ||
        _isSubtotalRow(text) ||
        _isTotalRow(text) ||
        _isPaymentRow(text) ||
        _isReferencePriceRow(text)) {
      return false;
    }

    final matches = _moneyMatches(text);

    if (matches.isEmpty) {
      return false;
    }

    if (_looksLikeDateOrTime(text) ||
        _looksLikeTransactionMetadata(text)) {
      return false;
    }

    // Need at least 2 letters somewhere before accepting as item row.
    final letters =
        RegExp(r'[A-Za-z]').allMatches(text).length;

    return letters >= 2;
  }

  bool _looksLikeItemRow(_OcrRow row) {
    if (_rowMayContainItem(row)) {
      return true;
    }

    final text = _cleanupItemName(row.text);
    return _looksLikeItemName(text) &&
        !_isHeaderNoise(text);
  }

  bool _looksLikeItemName(String value) {
    final clean = _cleanupItemName(value);

    if (clean.length < 2 ||
        clean.length > 100) {
      return false;
    }

    final letters =
        RegExp(r'[A-Za-z]').allMatches(clean).length;

    if (letters < 2) {
      return false;
    }

    if (_isReceiptNoise(clean) ||
        _looksLikeAddress(clean) ||
        _looksLikePhone(clean) ||
        _looksLikeDateOrTime(clean) ||
        _looksLikeTransactionMetadata(clean) ||
        _isLikelySkuOnly(clean)) {
      return false;
    }

    return true;
  }

  String _cleanupItemName(String input) {
    var value = _normalizeWhitespace(input);

    // Remove a common retail DPCI/SKU prefix while preserving the readable
    // product name. Example:
    //   261-00-0256 Good & Gather Almond Milk 64oz
    //   -> Good & Gather Almond Milk 64oz
    value = value.replaceFirst(
      RegExp(r'^\d{3}-\d{2}-\d{4}\s+'),
      '',
    );

    // Remove leading quantity marker:
    //   "2X CAESAR SALAD"
    //   "2 x Coffee"
    value = value.replaceFirst(
      RegExp(
        r'^\s*\d{1,3}\s*[xX]\s+',
      ),
      '',
    );

    // OCR can prepend stray one-letter tokens and/or a quantity before the
    // real item name, for example:
    //
    //   "N H N 1 Caesar Salad"
    //   "F N 1 Caesar Salad"
    //   "X 1 Caesar Salad"
    //
    // Only remove the prefix when there are at least two isolated single-letter
    // tokens before an optional quantity. This keeps legitimate names such as
    // "A&W Root Beer", "Vitamin D Milk", and "T Bone Steak" intact.
    value = value.replaceFirst(
      RegExp(
        r'^(?:[A-Za-z]\s+){2,}\d{0,3}\s*(?=[A-Za-z][A-Za-z])',
      ),
      '',
    );

    // A single OCR status/tax flag can also be inserted before a printed
    // quantity. Restrict this to the common retailer flag letters so normal
    // product names are not modified.
    value = value.replaceFirst(
      RegExp(
        r'^[FNXOT]\s+\d{1,3}\s+(?=[A-Za-z][A-Za-z])',
        caseSensitive: false,
      ),
      '',
    );

    // After removing OCR garbage, strip a normal standalone leading quantity:
    //   "1 Caesar Salad" -> "Caesar Salad"
    //
    // Do not remove numbers attached to words/units such as "7UP",
    // "2% Milk", or "16 oz".
    value = value.replaceFirst(
      RegExp(
        r'^\d{1,3}\s+(?=[A-Za-z]{2,})',
      ),
      '',
    );

    // Remove embedded long UPC/SKU values.
    value = value.replaceAll(
      RegExp(r'\s+\b\d{8,14}\b'),
      ' ',
    );

    // Remove common trailing tax/status flags from retailer receipts.
    value = value.replaceFirst(
      RegExp(
        r'\s+[FNXOT]\s*$',
        caseSensitive: false,
      ),
      '',
    );

    // Coupon/discount lines often contain long numeric reference codes after
    // the readable label, for example:
    //   COUPON 23100 052 310037000
    //
    // Preserve the negative receipt line while removing the reference payload.
    final lowerValue = value.toLowerCase();

    if (lowerValue.startsWith('coupon') ||
        lowerValue.startsWith('discount') ||
        lowerValue.startsWith('promo')) {
      value = value.replaceFirst(
        RegExp(
          r'^(coupon|discount|promo)\s+\d.*$',
          caseSensitive: false,
        ),
        r'$1',
      );
    }


    // Normalize a few very common OCR mistakes in measurement units only.
    // Keep this deliberately narrow so product/model numbers are untouched.
    //
    // Examples:
    //   "SPINACH 1L8" -> "SPINACH 1LB"
    //   "RICE 10L8"   -> "RICE 10LB"
    //   "18O2"        -> "18OZ" (only when used as a trailing unit token)
    value = value.replaceAllMapped(
      RegExp(
        r'\b(\d+(?:\.\d+)?)\s*L8\b',
        caseSensitive: false,
      ),
          (match) => '${match.group(1)}LB',
    );

    value = value.replaceAllMapped(
      RegExp(
        r'\b(\d+(?:\.\d+)?)\s*O2\b',
        caseSensitive: false,
      ),
          (match) => '${match.group(1)}OZ',
    );

    // Remove stray currency punctuation left after price removal.
    value = value
        .replaceAll(RegExp(r'[$€£¥]+$'), '')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();

    // Remove purely decorative prefix/suffix.
    value = value
        .replaceAll(
      RegExp(r'^[*#=_~|:;,\-]+\s*'),
      '',
    )
        .replaceAll(
      RegExp(r'\s*[*#=_~|:;,]+$'),
      '',
    )
        .trim();

    return value;
  }

  bool _isReceiptNoise(String text) {
    final clean =
    _normalizeWhitespace(text).toLowerCase();

    if (clean.isEmpty) return true;

    if (_isHeaderNoise(clean) ||
        _looksLikeAddress(text) ||
        _looksLikePhone(text) ||
        _looksLikeDateOrTime(text) ||
        _looksLikeTransactionMetadata(text)) {
      return true;
    }

    if (_containsAny(clean, const [
      'subtotal',
      'sub total',
      'subtotal after discount',
      'subtotal after discounts',
      'grand total',
      'amount due',
      'balance due',
      'total due',
      'sales tax',
      'sale tax',
      'tax ',
      ' tax',
      'change due',
      'change',
      'cash',
      'credit card',
      'debit card',
      'visa',
      'mastercard',
      'master card',
      'american express',
      'amex',
      'payment',
      'tender',
      'approved',
      'authorization',
      'auth code',
      'customer copy',
      'merchant copy',
      'signature',
      'server:',
      'cashier:',
      'host:',
      'table ',
      'table:',
      'guest ',
      'guests:',
      'items sold',
      'item count',
      'receipt #',
      'receipt:',
      'invoice:',
      'invoice #',
      'order #',
      'order no',
      'transaction',
      'trans id',
      'terminal',
      'register',
      'store #',
      'store:',
      'operator',
      'op#',
      'tr#',
      'te#',
      'st#',
      'thank you',
      'thanks for',
      'visit us',
      'survey',
      'www.',
      'http://',
      'https://',
      'save money. live better',
      'low prices you can trust',
      'qty desc',
      'qty description',
      'description amount',
      'description price',
      'item amount',
      'item price',
      'amount',
      'amt',
    ])) {
      return true;
    }

    return false;
  }

  bool _isHeaderNoise(String text) {
    final clean = text.toLowerCase().trim();

    return _containsAny(clean, const [
      'receipt',
      'tax invoice',
      'invoice',
      'customer copy',
      'merchant copy',
      'welcome',
      'thank you',
      'thanks for',
      'save money',
      'live better',
      'low prices',
      'qty desc',
      'description amount',
      'description price',
      'item amount',
      'item price',
    ]);
  }

  bool _isPaymentRow(String text) {
    final clean = text.toLowerCase();

    return _containsAny(clean, const [
      'cash',
      'change',
      'tender',
      'payment',
      'debit',
      'credit',
      'visa',
      'mastercard',
      'amex',
      'gift card',
      'approved',
      'auth',
      'account #',
      'card ending',
    ]);
  }

  bool _looksLikeTransactionMetadata(
      String text,
      ) {
    final clean = text.toLowerCase();

    if (_containsAny(clean, const [
      'st#',
      'op#',
      'te#',
      'tr#',
      'tc#',
      'ref #',
      'ref#',
      'trans id',
      'transaction id',
      'terminal #',
      'terminal#',
      'register #',
      'register#',
      'receipt #',
      'receipt:',
      'invoice #',
      'invoice:',
      'order #',
      'order:',
      'cashier',
      'manager ',
      'server ',
      'server:',
      'host:',
      'table ',
      'table:',
    ])) {
      return true;
    }

    // Long code-only / barcode lines.
    final compact =
    text.replaceAll(RegExp(r'[\s-]'), '');

    if (RegExp(r'^[A-Za-z]?\d{8,20}[A-Za-z]?$')
        .hasMatch(compact)) {
      return true;
    }

    return false;
  }

  bool _looksLikeAddress(String text) {
    final clean = text.trim();

    if (RegExp(
      r'^\d{1,6}\s+.+\b('
      r'st|street|rd|road|ave|avenue|'
      r'blvd|boulevard|dr|drive|ln|lane|'
      r'way|hwy|highway|pkwy|parkway|ct|court'
      r')\b',
      caseSensitive: false,
    ).hasMatch(clean)) {
      return true;
    }

    if (RegExp(
      r'\b[A-Z]{2}\s+\d{5}(?:-\d{4})?\b',
      caseSensitive: false,
    ).hasMatch(clean)) {
      return true;
    }

    return false;
  }

  bool _looksLikePhone(String text) {
    return RegExp(
      r'(?:\+?1[\s.-]?)?'
      r'\(?\d{3}\)?[\s.-]+'
      r'\d{3}[\s.-]+\d{4}',
    ).hasMatch(text);
  }

  bool _looksLikeDateOrTime(String text) {
    if (RegExp(
      r'\b\d{1,2}[/-]\d{1,2}[/-]\d{2,4}\b',
    ).hasMatch(text)) {
      return true;
    }

    if (RegExp(
      r'\b\d{4}-\d{1,2}-\d{1,2}\b',
    ).hasMatch(text)) {
      return true;
    }

    if (RegExp(
      r'\b\d{1,2}:\d{2}(?::\d{2})?\s*(?:am|pm)?\b',
      caseSensitive: false,
    ).hasMatch(text)) {
      return true;
    }

    return false;
  }

  bool _isLikelySkuOnly(String text) {
    final clean =
    text.replaceAll(RegExp(r'[\s-]'), '');

    if (RegExp(r'^\d{6,20}[A-Za-z]?$')
        .hasMatch(clean)) {
      return true;
    }

    // Mostly digits with very few letters.
    final digits =
        RegExp(r'\d').allMatches(clean).length;
    final letters =
        RegExp(r'[A-Za-z]').allMatches(clean).length;

    return clean.length >= 8 &&
        digits >= 6 &&
        letters <= 2;
  }

  double _signedItemAmount(
      String rowText,
      double parsedValue,
      ) {
    final lower = rowText.toLowerCase();

    final discountLike = _containsAny(
      lower,
      const [
        'coupon',
        'discount',
        'promo',
        'savings',
        'markdown',
      ],
    );

    // IMPORTANT: do not use rowText.contains('-') here. Product names such
    // as "T-Shirt", "Coca-Cola", and "T-Bone" contain hyphens but are
    // not negative amounts. _moneyMatches/_parseMoneyToken already detects a
    // minus sign that belongs to the actual money token (-1.00 or 1.00-).
    if (parsedValue < 0) {
      return parsedValue;
    }

    // Some OCR engines can lose the minus sign while still reading an
    // explicit coupon/discount label. In that case, preserve the semantic
    // discount by making only those known discount rows negative.
    if (discountLike && parsedValue > 0) {
      return -parsedValue;
    }

    return parsedValue;
  }

  ScannedReceiptItem _makeItem({
    required String name,
    required double amount,
  }) {
    final cleaned = _cleanupItemName(name);

    return ScannedReceiptItem(
      name: cleaned,
      amount: _roundMoney(amount),
      detectedTag: _detectItemTag(cleaned),
    );
  }

  List<ScannedReceiptItem> _deduplicateItems(
      List<ScannedReceiptItem> items,
      ) {
    if (items.isEmpty) {
      return const [];
    }

    final result = <ScannedReceiptItem>[];

    for (final item in items) {
      if (result.isNotEmpty) {
        final previous = result.last;

        // Only remove adjacent exact OCR duplicates. Do NOT globally dedupe,
        // because buying the same product twice is valid.
        if (_canonicalName(previous.name) ==
            _canonicalName(item.name) &&
            (previous.amount - item.amount).abs() <
                0.001) {
          continue;
        }
      }

      result.add(item);
    }

    return result;
  }

  String _canonicalName(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  // ---------------------------------------------------------------------------
  // Tags used by SplitUp item-exclusion UI
  // ---------------------------------------------------------------------------

  String? _detectItemTag(String itemName) {
    final value = itemName.toLowerCase();

    if (_containsAny(value, const [
      'chicken',
      'chkn',
      'beef',
      'pork',
      'turkey',
      'ham',
      'bacon',
      'sausage',
      'steak',
      'lamb',
      'meat',
      'pepperoni',
      'salami',
    ])) {
      return 'meat';
    }

    if (_containsAny(value, const [
      'salmon',
      'shrimp',
      'tuna',
      'fish',
      'crab',
      'lobster',
      'seafood',
      'prawn',
    ])) {
      return 'seafood';
    }

    if (_containsAny(value, const [
      'milk',
      'whole milk',
      'skim milk',
      'oat milk',
      'almond milk',
    ])) {
      return 'milk';
    }

    if (_containsAny(value, const [
      'egg',
      'eggs',
    ])) {
      return 'eggs';
    }

    if (_containsAny(value, const [
      'cheese',
      'yogurt',
      'yoghurt',
      'butter',
      'cream',
      'dairy',
    ])) {
      return 'dairy';
    }

    if (_containsAny(value, const [
      'beer',
      'wine',
      'vodka',
      'whiskey',
      'whisky',
      'rum',
      'tequila',
      'alcohol',
      'lager',
      'ale',
    ])) {
      return 'alcohol';
    }

    if (_containsAny(value, const [
      'coffee',
      'espresso',
      'latte',
      'cappuccino',
      'americano',
      'mocha',
    ])) {
      return 'coffee';
    }

    if (_containsAny(value, const [
      'diaper',
      'diapers',
      'baby wipes',
      'formula',
    ])) {
      return 'baby_products';
    }

    if (_containsAny(value, const [
      'dog food',
      'cat food',
      'pet food',
      'dog treat',
      'dog treats',
      'cat treat',
      'cat treats',
      'cat litter',
      'pet toy',
      'floppy puppy',
      'squeak',
      'dry dog',
    ])) {
      return 'pet_supplies';
    }

    if (_containsAny(value, const [
      'shampoo',
      'conditioner',
      'toothpaste',
      'deodorant',
      'body wash',
      'lotion',
      'soap',
    ])) {
      return 'personal_care';
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // Small utilities
  // ---------------------------------------------------------------------------

  bool _containsAny(
      String value,
      List<String> keywords,
      ) {
    for (final keyword in keywords) {
      if (value.contains(keyword)) {
        return true;
      }
    }

    return false;
  }

  String _normalizeWhitespace(String value) {
    return value
        .replaceAll(RegExp(r'[\t\r]+'), ' ')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
  }

  double _roundMoney(double value) {
    return double.parse(value.toStringAsFixed(2));
  }

  void _debugParsed(
      String title,
      _ParsedReceipt receipt,
      ) {
    debugPrint('======= $title =======');
    debugPrint(
      'MERCHANT: ${receipt.merchantName}',
    );
    debugPrint(
      'SUBTOTAL: ${receipt.subtotal}',
    );
    debugPrint(
      'TAX: ${receipt.tax}',
    );
    debugPrint(
      'TIP: ${receipt.tip}',
    );
    debugPrint(
      'FEES: ${receipt.fees}',
    );
    debugPrint(
      'TOTAL: ${receipt.total}',
    );
    debugPrint(
      'DATE: ${receipt.purchaseDate}',
    );
    debugPrint(
      'ITEM COUNT: ${receipt.items.length}',
    );

    for (final item in receipt.items) {
      debugPrint(
        '${item.name} | '
            '${item.amount.toStringAsFixed(2)} | '
            '${item.detectedTag}',
      );
    }

    debugPrint('=========================');
  }
}

// =============================================================================
// Internal data types
// =============================================================================

class _ParsedReceipt {
  final String rawText;
  final String? merchantName;
  final double? subtotal;
  final double? tax;
  final double? tip;
  final double? fees;
  final double? total;
  final DateTime? purchaseDate;
  final List<ScannedReceiptItem> items;

  const _ParsedReceipt({
    required this.rawText,
    required this.merchantName,
    required this.subtotal,
    required this.tax,
    required this.tip,
    required this.fees,
    required this.total,
    required this.purchaseDate,
    required this.items,
  });
}

class _OcrLine {
  final String text;
  final Rect rect;

  const _OcrLine({
    required this.text,
    required this.rect,
  });

  double get centerY =>
      (rect.top + rect.bottom) / 2;
}

class _MutableOcrRow {
  final List<_OcrLine> _cells;

  _MutableOcrRow(List<_OcrLine> cells)
      : _cells = List<_OcrLine>.from(cells);

  double get centerY {
    if (_cells.isEmpty) return 0;

    return _cells
        .map((e) => e.centerY)
        .reduce((a, b) => a + b) /
        _cells.length;
  }

  void add(_OcrLine line) {
    _cells.add(line);
  }

  _OcrRow freeze() {
    _cells.sort(
          (a, b) =>
          a.rect.left.compareTo(b.rect.left),
    );

    final left =
    _cells.map((e) => e.rect.left).reduce(math.min);
    final top =
    _cells.map((e) => e.rect.top).reduce(math.min);
    final right =
    _cells.map((e) => e.rect.right).reduce(math.max);
    final bottom =
    _cells.map((e) => e.rect.bottom).reduce(math.max);

    return _OcrRow(
      cells: List.unmodifiable(_cells),
      rect: Rect.fromLTRB(
        left,
        top,
        right,
        bottom,
      ),
    );
  }
}

class _OcrRow {
  final List<_OcrLine> cells;
  final Rect rect;

  const _OcrRow({
    required this.cells,
    required this.rect,
  });

  String get text =>
      cells.map((e) => e.text).join(' ');
}

class _MoneyMatch {
  final double value;
  final int start;
  final int end;
  final String raw;

  const _MoneyMatch({
    required this.value,
    required this.start,
    required this.end,
    required this.raw,
  });
}

class _CellMoney {
  final int cellIndex;
  final _MoneyMatch match;

  const _CellMoney({
    required this.cellIndex,
    required this.match,
  });
}

class _MoneyAtX {
  final double value;
  final double x;
  final _MoneyMatch match;
  final _OcrLine cell;

  const _MoneyAtX({
    required this.value,
    required this.x,
    required this.match,
    required this.cell,
  });
}

class _MerchantCandidate {
  final String value;
  final double score;

  const _MerchantCandidate({
    required this.value,
    required this.score,
  });
}
