import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/scanned_receipt.dart';
import '../../services/receipt_scanner_service.dart';

class ReceiptScannerScreen extends StatefulWidget {
  const ReceiptScannerScreen({super.key});

  @override
  State<ReceiptScannerScreen> createState() =>
      _ReceiptScannerScreenState();
}

class _ReceiptScannerScreenState
    extends State<ReceiptScannerScreen> {
  final ImagePicker _imagePicker = ImagePicker();
  final ReceiptScannerService _scannerService =
  ReceiptScannerService();

  File? _selectedImage;
  ScannedReceipt? _receipt;

  bool _isScanning = false;
  String? _errorMessage;
  ScannedReceipt _sanitizeReceiptForExpense(ScannedReceipt receipt)
  {
    final cleanedItems = receipt.items.where((item) {
      final name = item.name
          .toLowerCase()
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

      const summaryPhrases = <String>[
        'year to date savings',
        'ytd savings',
        'total savings',
        'savings this order',
        'savings this purchase',
        'you saved',
        'you save',
        'your savings',
        'today\'s savings',
        'todays savings',
        'amount saved',
        'opening balance',
        'closing balance',
        'earned this visit',
        'rewards balance',
        'points balance',
        'original price',
        'return value',
        'net sale',
        'refund total',
        'return total',
        'mywalgreens savings',
        'mywalgreens rewards',
        'walgreens cash',
      ];

      if (summaryPhrases.any(name.contains)) {
        return false;
      }

      // "Spend" is normally a rewards/accounting line, not merchandise.
      if (RegExp(r'^spend\b').hasMatch(name)) {
        return false;
      }

      return true;
    }).toList();

    return ScannedReceipt(
      rawText: receipt.rawText,
      merchantName: receipt.merchantName,
      subtotal: receipt.subtotal,
      tax: receipt.tax,
      tip: receipt.tip,
      fees: receipt.fees,
      total: receipt.total,
      purchaseDate: receipt.purchaseDate,
      items: cleanedItems,
    );
  }
  Future<void> _pickAndScan(ImageSource source) async {
    setState(() {
      _isScanning = true;
      _errorMessage = null;
      _receipt = null;
    });

    try {
      final image = await _imagePicker.pickImage(
        source: source,
        imageQuality: 90,
        maxWidth: 2200,
      );

      if (image == null) {
        return;
      }

      final file = File(image.path);

      final scannedReceipt =
      await _scannerService.scanReceipt(file);

      final receipt =
      _sanitizeReceiptForExpense(scannedReceipt);

      if (!mounted) return;

      setState(() {
        _selectedImage = file;
        _receipt = receipt;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _errorMessage = 'Unable to scan receipt: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
      }
    }
  }

  bool _shouldShowDetectedItem(ScannedReceiptItem item) {
    final name = item.name
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // Hide receipt-level discounts, coupons, rewards and savings.
    // Do NOT hide an item merely because its amount is negative:
    // negative merchandise may represent a return/refund.
    const adjustmentWords = <String>[
      'coupon',
      'cpn',
      'discount',
      'savings',
      'reward',
      'rewards',
      'redcard',
      'circle bonus',
      'manufacturer coupon',
      'store coupon',
      'promo',
      'promotion',
      'loyalty',
    ];

    return !adjustmentWords.any(name.contains);
  }
  void _useReceipt() {
    final receipt = _receipt;

    if (receipt == null) {
      return;
    }

    final sanitizedReceipt =
    _sanitizeReceiptForExpense(receipt);

    debugPrint(
      'RETURNING SANITIZED ITEMS: '
          '${sanitizedReceipt.items.length}',
    );

    for (final item in sanitizedReceipt.items) {
      debugPrint(
        'RETURN ITEM: ${item.name} | ${item.amount}',
      );
    }

    Navigator.of(context).pop(sanitizedReceipt);
  }
  @override
  void dispose() {
    _scannerService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Receipt'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_selectedImage == null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(30),
                child: Column(
                  children: [
                    Icon(
                      Icons.document_scanner_outlined,
                      size: 72,
                      color: Theme.of(context)
                          .colorScheme
                          .primary,
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Scan a receipt',
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Take a clear photo showing the merchant '
                          'name and total amount.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.file(
                _selectedImage!,
                height: 300,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _isScanning
                      ? null
                      : () {
                    _pickAndScan(ImageSource.camera);
                  },
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('Camera'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isScanning
                      ? null
                      : () {
                    _pickAndScan(ImageSource.gallery);
                  },
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Gallery'),
                ),
              ),
            ],
          ),
          if (_isScanning) ...[
            const SizedBox(height: 28),
            const Center(
              child: Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('Reading receipt…'),
                ],
              ),
            ),
          ],
          if (_errorMessage != null) ...[
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .error,
                  ),
                ),
              ),
            ),
          ],
          if (_receipt != null) ...[
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Detected information',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _DetectedValue(
                      label: 'Merchant',
                      value: _receipt!.merchantName.isEmpty
                          ? 'Not detected'
                          : _receipt!.merchantName,
                    ),
                    _DetectedValue(
                      label: 'Total',
                      value: _receipt!.total == null
                          ? 'Not detected'
                          : '\$${_receipt!.total!.toStringAsFixed(2)}',
                    ),
                    _DetectedValue(
                      label: 'Date',
                      value: _formatDate(
                        _receipt!.purchaseDate,
                      ),
                    ),
                    const Divider(),

                    const SizedBox(height: 12),

                    Text(
                      'Detected items',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 12),

                    Builder(
                      builder: (context) {
                        final visibleItems = _receipt!.items
                            .where(_shouldShowDetectedItem)
                            .toList();

                        if (visibleItems.isEmpty) {
                          return const Text(
                            'No individual items detected. '
                                'You can still use the receipt total.',
                          );
                        }

                        return Column(
                          children: visibleItems
                              .map(
                                (item) => Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                dense: true,
                                title: Text(item.name),
                                subtitle: item.amount < 0
                                    ? const Text(
                                  'Returned item',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w500,
                                  ),
                                )
                                    : item.detectedTag == null
                                    ? const Text(
                                  'No exclusion category detected',
                                )
                                    : Text(
                                  'Detected: ${_formatTag(item.detectedTag!)}',
                                ),
                                trailing: Text(
                                  item.amount < 0
                                      ? '-\$${item.amount.abs().toStringAsFixed(2)}'
                                      : '\$${item.amount.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          )
                              .toList(),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _useReceipt,
                      icon: const Icon(Icons.check_rounded),
                      label: const Text(
                        'Use Detected Information',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _formatDate(DateTime? date) {
    if (date == null) {
      return 'Not detected';
    }

    return '${date.month}/${date.day}/${date.year}';
  }

  static String _formatTag(
      String tag,
      ) {
    switch (tag) {
      case 'meat':
        return 'Meat';

      case 'milk':
        return 'Milk';

      case 'seafood':
        return 'Seafood';

      case 'eggs':
        return 'Eggs';

      case 'dairy':
        return 'Dairy';

      case 'alcohol':
        return 'Alcohol';

      case 'gluten':
        return 'Gluten';

      case 'coffee':
        return 'Coffee';

      case 'baby_products':
        return 'Baby products';

      case 'pet_supplies':
        return 'Pet supplies';

      case 'personal_care':
        return 'Personal care';

      case 'health':
        return 'Health / Medicine';

      case 'household':
        return 'Household';

      case 'grocery':
        return 'Grocery';
      default:
        return tag;
    }
  }
}

class _DetectedValue extends StatelessWidget {
  final String label;
  final String value;

  const _DetectedValue({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }
}
