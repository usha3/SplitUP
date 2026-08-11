import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/group_model.dart';
import '../../services/expense_service.dart';
import '../../models/scanned_receipt.dart';
import 'receipt_scanner_screen.dart';
import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../../models/expense_model.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AddExpenseScreen extends StatefulWidget {
  final GroupModel group;

  const AddExpenseScreen({
    super.key,
    required this.group,
  });

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

enum _SplitMode {
  equal,
  itemized,
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();

  final ExpenseService _expenseService = ExpenseService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final TextRecognizer _textRecognizer =
  TextRecognizer(
    script: TextRecognitionScript.latin,
  );

  final ImagePicker _imagePicker =
  ImagePicker();

  XFile? _receiptImage;

  bool _isLoading = false;
  String _category = 'Other';
  String? _paidBy;
  _SplitMode _splitMode = _SplitMode.equal;

  final List<_ExpenseItemDraft> _expenseItems = [];

  late Set<String> _selectedMembers;
  late Future<Map<String, _ParticipantData>> _participantsFuture;

  final List<String> _categories = [
    'Food',
    'Groceries',
    'Rent',
    'Utilities',
    'Travel',
    'Entertainment',
    'Other',
  ];

  void _changeSplitMode(_SplitMode mode) {
    setState(() {
      _splitMode = mode;

      if (mode == _SplitMode.itemized &&
          _expenseItems.isEmpty) {
        _addExpenseItem();
      }
    });
  }

  void _addExpenseItem() {
    _expenseItems.add(
      _ExpenseItemDraft(
        participants:
        widget.group.members.toSet(),
      ),
    );

    setState(() {});
  }

  void _removeExpenseItem(int index) {
    if (index < 0 ||
        index >= _expenseItems.length) {
      return;
    }

    final item = _expenseItems.removeAt(index);

    item.dispose();

    setState(() {});
  }

  Map<String, double> _calculateEqualShares(
      double total,
      ) {
    final shares = <String, double>{};

    if (_selectedMembers.isEmpty) {
      return shares;
    }

    final perPerson =
        total / _selectedMembers.length;

    for (final memberId in _selectedMembers) {
      shares[memberId] = perPerson;
    }

    return shares;
  }

  Map<String, double> _calculateItemizedShares() {
    final shares = <String, double>{};

    for (final item in _expenseItems) {
      final amount = double.tryParse(
        item.amountController.text.trim(),
      ) ??
          0;

      if (amount <= 0 ||
          item.participants.isEmpty) {
        continue;
      }

      final amountPerPerson =
          amount / item.participants.length;

      for (final memberId
      in item.participants) {
        shares[memberId] =
            (shares[memberId] ?? 0) +
                amountPerPerson;
      }
    }

    return shares;
  }

  double _calculateItemsTotal() {
    double total = 0;

    for (final item in _expenseItems) {
      total += double.tryParse(
        item.amountController.text.trim(),
      ) ??
          0;
    }

    return total;
  }

  bool _validateItemizedSplit(
      double expenseTotal,
      ) {
    if (_expenseItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Add at least one item.',
          ),
        ),
      );

      return false;
    }

    for (final item in _expenseItems) {
      if (item.nameController.text
          .trim()
          .isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Enter a name for every item.',
            ),
          ),
        );

        return false;
      }

      final itemAmount = double.tryParse(
        item.amountController.text.trim(),
      );

      if (itemAmount == null ||
          itemAmount <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Enter a valid amount for '
                  '${item.nameController.text.trim()}.',
            ),
          ),
        );

        return false;
      }

      if (item.participants.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Select someone for '
                  '${item.nameController.text.trim()}.',
            ),
          ),
        );

        return false;
      }
    }

    final itemTotal =
    _calculateItemsTotal();

    if ((itemTotal - expenseTotal).abs() >
        0.01) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Items total \$${itemTotal.toStringAsFixed(2)} '
                'must match expense total '
                '\$${expenseTotal.toStringAsFixed(2)}.',
          ),
        ),
      );

      return false;
    }

    return true;
  }

  @override
  void initState() {
    super.initState();

    _selectedMembers = widget.group.members.toSet();
    _participantsFuture = _loadParticipants();
    if (widget.group.members.isNotEmpty) {
      _paidBy = widget.group.members.first;
    }
  }

  Future<Map<String, _ParticipantData>> _loadParticipants() async {
    final participants = <String, _ParticipantData>{};

    final currentUser =
        FirebaseAuth.instance.currentUser;

    // Load group memberDetails first.
    final groupDocument = await _firestore
        .collection('groups')
        .doc(widget.group.id)
        .get();

    final groupData = groupDocument.data() ?? {};

    final rawMemberDetails =
    groupData['memberDetails'];

    final memberDetails = rawMemberDetails is Map
        ? Map<String, dynamic>.from(
      rawMemberDetails,
    )
        : <String, dynamic>{};

    for (final memberId in widget.group.members) {
      String name = '';
      String email = '';
      bool isGuest =
      memberId.startsWith('guest_');

      // 1. Try group memberDetails.
      final rawDetails =
      memberDetails[memberId];

      if (rawDetails is Map) {
        final details =
        Map<String, dynamic>.from(
          rawDetails,
        );

        name =
            details['name']
                ?.toString()
                .trim() ??
                '';

        email =
            details['email']
                ?.toString()
                .trim() ??
                '';

        isGuest =
            details['isGuest'] == true ||
                memberId.startsWith('guest_');
      }

      // 2. For registered users, try users collection.
      if (!isGuest) {
        try {
          final userDocument =
          await _firestore
              .collection('users')
              .doc(memberId)
              .get();

          final userData =
              userDocument.data() ?? {};

          final firestoreName =
              userData['name']
                  ?.toString()
                  .trim() ??
                  '';

          final firestoreEmail =
              userData['email']
                  ?.toString()
                  .trim() ??
                  '';

          if (name.isEmpty &&
              firestoreName.isNotEmpty) {
            name = firestoreName;
          }

          if (email.isEmpty &&
              firestoreEmail.isNotEmpty) {
            email = firestoreEmail;
          }
        } catch (_) {
          // Continue with available member details.
        }
      }

      // 3. Current logged-in user fallback.
      if (memberId == currentUser?.uid) {
        final authName =
            currentUser?.displayName?.trim() ?? '';

        final authEmail =
            currentUser?.email?.trim() ?? '';

        if (name.isEmpty &&
            authName.isNotEmpty) {
          name = authName;
        }

        if (email.isEmpty &&
            authEmail.isNotEmpty) {
          email = authEmail;
        }
      }

      // 4. Final guest fallback.
      if (isGuest &&
          name.isEmpty &&
          email.isEmpty) {
        name = 'Guest member';
      }

      participants[memberId] =
          _ParticipantData(
            id: memberId,
            name: name,
            email: email,
            isGuest: isGuest,
          );
    }

    return participants;
  }

  Future<void> _saveExpense() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_splitMode == _SplitMode.equal &&
        _selectedMembers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Select at least one participant.',
          ),
        ),
      );

      return;
    }

    if (_paidBy == null ||
        _paidBy!.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Select who paid for this expense.',
          ),
        ),
      );

      return;
    }

    final amount = double.tryParse(
      _amountController.text.trim(),
    );

    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a valid amount.'),
        ),
      );
      return;
    }

    if (_splitMode == _SplitMode.itemized &&
        !_validateItemizedSplit(amount)) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      String? receiptUrl;

      if (_receiptImage != null) {
        receiptUrl = await _uploadReceiptImage();
      }

      List<String> expenseParticipants;
      List<ExpenseItem> expenseItems;
      Map<String, double> shares;

      if (_splitMode == _SplitMode.equal) {
        expenseParticipants =
            _selectedMembers.toList();

        expenseItems = [];

        shares =
            _calculateEqualShares(amount);
      } else {
        expenseItems = _expenseItems.map(
              (item) {
            return ExpenseItem(
              name:
              item.nameController.text.trim(),
              amount: double.parse(
                item.amountController.text.trim(),
              ),
              participants:
              item.participants.toList(),
            );
          },
        ).toList();

        final participantSet = <String>{};

        for (final item in expenseItems) {
          participantSet.addAll(
            item.participants,
          );
        }

        expenseParticipants =
            participantSet.toList();

        shares =
            _calculateItemizedShares();
      }

      await _expenseService.addExpense(
        groupId: widget.group.id,
        title: _titleController.text.trim(),
        amount: amount,
        category: _category,
        paidBy: _paidBy!,
        participants: expenseParticipants,
        receiptUrl: receiptUrl,
        splitType:
        _splitMode == _SplitMode.equal
            ? 'equal'
            : 'itemized',
        items: expenseItems,
        shares: shares,
      );

      if (!mounted) return;

      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to add expense: $error'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _selectAllMembers() {
    setState(() {
      _selectedMembers = widget.group.members.toSet();
    });
  }

  void _clearAllMembers() {
    setState(() {
      _selectedMembers.clear();
    });
  }

  Future<void> _pickReceiptImage() async {
    final XFile? image =
    await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1800,
    );

    if (image == null || !mounted) {
      return;
    }

    setState(() {
      _receiptImage = image;
    });

    await _extractReceiptData(image.path);
  }

  Future<void> _extractReceiptData(
      String imagePath,
      ) async {
    try {
      final inputImage =
      InputImage.fromFilePath(imagePath);

      final recognizedText =
      await _textRecognizer.processImage(
        inputImage,
      );

      final rawText = recognizedText.text.trim();

      if (rawText.isEmpty) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No readable text was found on the receipt.',
            ),
          ),
        );

        return;
      }

      debugPrint('======= RECEIPT OCR =======');
      debugPrint(rawText);
      debugPrint('===========================');

      final lines = recognizedText.blocks
          .expand((block) => block.lines)
          .map((line) => line.text.trim())
          .where((line) => line.isNotEmpty)
          .toList();

      final merchant = _findMerchant(lines);
      final total = _findReceiptTotal(lines);

      if (!mounted) return;

      setState(() {
        if (merchant != null &&
            merchant.isNotEmpty &&
            _titleController.text.trim().isEmpty) {
          _titleController.text = merchant;
        }

        if (total != null) {
          _amountController.text =
              total.toStringAsFixed(2);
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Receipt scanned. Please verify the details.',
          ),
        ),
      );
    } catch (error) {
      debugPrint(
        'Receipt OCR failed: $error',
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not read this receipt.',
          ),
        ),
      );
    }
  }

  String? _findMerchant(
      List<String> lines,
      ) {
    for (final line in lines.take(6)) {
      final clean = line.trim();

      if (clean.length < 3) {
        continue;
      }

      final lower = clean.toLowerCase();

      final looksLikeNoise =
          lower.contains('receipt') ||
              lower.contains('thank you') ||
              lower.contains('welcome') ||
              lower.contains('date') ||
              lower.contains('time') ||
              lower.contains('www.') ||
              lower.contains('http') ||
              RegExp(r'^\d+$').hasMatch(clean);

      if (!looksLikeNoise) {
        return clean;
      }
    }

    return null;
  }

  double? _findReceiptTotal(
      List<String> lines,
      ) {
    final strongKeywords = [
      'grand total',
      'amount due',
      'balance due',
      'total due',
      'total',
    ];

    for (final keyword in strongKeywords) {
      for (final line in lines.reversed) {
        final lower = line.toLowerCase();

        if (!lower.contains(keyword)) {
          continue;
        }

        final amount =
        _extractLargestAmount(line);

        if (amount != null) {
          return amount;
        }
      }
    }

    // Fallback: inspect the last part of the receipt.
    final candidates = <double>[];

    for (final line in lines.reversed.take(12)) {
      final amount =
      _extractLargestAmount(line);

      if (amount != null) {
        candidates.add(amount);
      }
    }

    if (candidates.isEmpty) {
      return null;
    }

    candidates.sort();

    return candidates.last;
  }

  double? _extractLargestAmount(
      String text,
      ) {
    final matches = RegExp(
      r'(?:\$|USD\s*)?(\d{1,6}(?:,\d{3})*(?:\.\d{2}))',
      caseSensitive: false,
    ).allMatches(text);

    final amounts = <double>[];

    for (final match in matches) {
      final value = match
          .group(1)
          ?.replaceAll(',', '');

      final amount =
      double.tryParse(value ?? '');

      if (amount != null) {
        amounts.add(amount);
      }
    }

    if (amounts.isEmpty) {
      return null;
    }

    amounts.sort();

    return amounts.last;
  }

  Future<String?> _uploadReceiptImage() async {
    final image = _receiptImage;

    if (image == null) {
      return null;
    }

    final extension =
    image.path.split('.').last.toLowerCase();

    final fileName =
        '${DateTime.now().millisecondsSinceEpoch}.$extension';

    final storageReference = _storage
        .ref()
        .child('receipts')
        .child(widget.group.id)
        .child(fileName);

    await storageReference.putFile(
      File(image.path),
    );

    return storageReference.getDownloadURL();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();

    for (final item in _expenseItems) {
      item.dispose();
    }

    _textRecognizer.close();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedCount = _selectedMembers.length;
    final totalMembers = widget.group.members.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Expense'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton.icon(
                  onPressed: _isLoading ? null : _scanReceipt,
                  icon: const Icon(Icons.document_scanner_outlined),
                  label: const Text('Scan Receipt'),
                ),
                const SizedBox(height: 12),

                OutlinedButton.icon(
                  onPressed:
                  _isLoading ? null : _pickReceiptImage,
                  icon: const Icon(
                    Icons.attach_file_rounded,
                  ),
                  label: Text(
                    _receiptImage == null
                        ? 'Attach Receipt'
                        : 'Change Receipt',
                  ),
                ),

                if (_receiptImage != null) ...[
                  const SizedBox(height: 12),

                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment:
                      CrossAxisAlignment.stretch,
                      children: [
                        Image.file(
                          File(_receiptImage!.path),
                          height: 180,
                          fit: BoxFit.cover,
                        ),

                        ListTile(
                          leading:
                          const Icon(Icons.receipt_long),
                          title:
                          const Text('Receipt attached'),
                          trailing: IconButton(
                            tooltip: 'Remove receipt',
                            icon: const Icon(
                              Icons.delete_outline,
                            ),
                            onPressed: _isLoading
                                ? null
                                : () {
                              setState(() {
                                _receiptImage = null;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                TextFormField(
                  controller: _titleController,
                  enabled: !_isLoading,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Expense title',
                    prefixIcon: Icon(Icons.receipt_long_outlined),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Enter an expense title';
                    }

                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _amountController,
                  enabled: !_isLoading,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.next,
                  onChanged: (_) {
                    setState(() {});
                  },
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                    prefixIcon: Icon(Icons.attach_money),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final amount = double.tryParse(value?.trim() ?? '');

                    if (amount == null || amount <= 0) {
                      return 'Enter a valid amount';
                    }

                    return null;
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _category,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    prefixIcon: Icon(Icons.category_outlined),
                    border: OutlineInputBorder(),
                  ),
                  items: _categories
                      .map(
                        (category) => DropdownMenuItem<String>(
                      value: category,
                      child: Text(category),
                    ),
                  )
                      .toList(),
                  onChanged: _isLoading
                      ? null
                      : (value) {
                    if (value != null) {
                      setState(() {
                        _category = value;
                      });
                    }
                  },
                ),
        if (_splitMode == _SplitMode.equal) ...[
                const SizedBox(height: 16),

                FutureBuilder<Map<String, _ParticipantData>>(
                  future: _participantsFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const LinearProgressIndicator();
                    }

                    if (snapshot.hasError) {
                      return const Text(
                        'Unable to load members for Paid by.',
                      );
                    }

                    final participants = snapshot.data ?? {};

                    return DropdownButtonFormField<String>(
                      initialValue: _paidBy,
                      decoration: const InputDecoration(
                        labelText: 'Paid by',
                        prefixIcon: Icon(
                          Icons.account_balance_wallet_outlined,
                        ),
                        border: OutlineInputBorder(),
                      ),
                      items: widget.group.members.map(
                            (memberId) {
                          final participant =
                          participants[memberId];

                          final name =
                              participant?.displayName ??
                                  'Unknown member';

                          return DropdownMenuItem<String>(
                            value: memberId,
                            child: Text(name),
                          );
                        },
                      ).toList(),
                      onChanged: _isLoading
                          ? null
                          : (value) {
                        setState(() {
                          _paidBy = value;
                        });
                      },
                      validator: (value) {
                        if (value == null ||
                            value.trim().isEmpty) {
                          return 'Select who paid';
                        }

                        return null;
                      },
                    );
                  },
                ),

                const SizedBox(height: 24),

                Text(
                  'Split method',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 12),

                SegmentedButton<_SplitMode>(
                  segments: const [
                    ButtonSegment<_SplitMode>(
                      value: _SplitMode.equal,
                      icon: Icon(Icons.people_outline),
                      label: Text('Equal'),
                    ),
                    ButtonSegment<_SplitMode>(
                      value: _SplitMode.itemized,
                      icon: Icon(Icons.receipt_long_outlined),
                      label: Text('By item'),
                    ),
                  ],
                  selected: {_splitMode},
                  onSelectionChanged: _isLoading
                      ? null
                      : (selection) {
                    _changeSplitMode(
                      selection.first,
                    );
                  },
                ),

                const SizedBox(height: 24),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Participants',
                        style:
                        Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed:
                      _isLoading ? null : _selectAllMembers,
                      child: const Text('Select all'),
                    ),
                    TextButton(
                      onPressed:
                      _isLoading ? null : _clearAllMembers,
                      child: const Text('Clear'),
                    ),
                  ],
                ),
                Text(
                  '$selectedCount of $totalMembers selected',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                FutureBuilder<Map<String, _ParticipantData>>(
                  future: _participantsFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Card(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(
                            child: CircularProgressIndicator(),
                          ),
                        ),
                      );
                    }

                    if (snapshot.hasError) {
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'Unable to load participant names: '
                                '${snapshot.error}',
                          ),
                        ),
                      );
                    }

                    final participants = snapshot.data ?? {};

                    return Card(
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: widget.group.members.map((memberId) {
                          final participant =
                              participants[memberId] ??
                                  _ParticipantData(
                                    id: memberId,
                                    name: '',
                                    email: '',
                                    isGuest:
                                    memberId.startsWith('guest_'),
                                  );

                          return CheckboxListTile(
                            value:
                            _selectedMembers.contains(memberId),
                            onChanged: _isLoading
                                ? null
                                : (selected) {
                              setState(() {
                                if (selected == true) {
                                  _selectedMembers.add(memberId);
                                } else {
                                  _selectedMembers.remove(memberId);
                                }
                              });
                            },
                            secondary: CircleAvatar(
                              child: participant.displayName.isEmpty
                                  ? const Icon(Icons.person)
                                  : Text(
                                participant.displayName[0]
                                    .toUpperCase(),
                              ),
                            ),
                            title: Text(
                              participant.displayName,
                            ),
                            subtitle: Text(
                              participant.subtitle,
                            ),
                            controlAffinity:
                            ListTileControlAffinity.trailing,
                          );
                        }).toList(),
                      ),
                    );
                  },
                ),
                if (_selectedMembers.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.calculate_outlined),
                      title: const Text('Split equally'),
                      subtitle: Text(
                        '\$${_calculateShare().toStringAsFixed(2)} '
                            'per participant',
                      ),
                    ),
                  ),
                ],
               ],
                if (_splitMode ==
                    _SplitMode.itemized) ...[
                  const SizedBox(height: 24),

                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Items',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      FilledButton.tonalIcon(
                        onPressed:
                        _isLoading
                            ? null
                            : _addExpenseItem,
                        icon: const Icon(Icons.add),
                        label: const Text('Add item'),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  Text(
                    'Choose who should share each item.',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium,
                  ),

                  const SizedBox(height: 12),

                  FutureBuilder<
                      Map<String, _ParticipantData>>(
                    future: _participantsFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState ==
                          ConnectionState.waiting) {
                        return const Center(
                          child:
                          CircularProgressIndicator(),
                        );
                      }

                      if (snapshot.hasError) {
                        return const Text(
                          'Unable to load members.',
                        );
                      }

                      final participants =
                          snapshot.data ?? {};

                      return Column(
                        children: [
                          for (int index = 0;
                          index <
                              _expenseItems.length;
                          index++)
                            _buildExpenseItemCard(
                              index,
                              participants,
                            ),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 12),

                  _buildItemizedSummary(),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed:
                    _isLoading ? null : _saveExpense,
                    child: _isLoading
                        ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                      ),
                    )
                        : const Text('Save Expense'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  double _calculateShare() {
    final amount =
        double.tryParse(_amountController.text.trim()) ?? 0;

    if (_selectedMembers.isEmpty) {
      return 0;
    }

    return amount / _selectedMembers.length;
  }

  Future<void> _scanReceipt() async {
    final result = await Navigator.of(context).push<ScannedReceipt>(
      MaterialPageRoute(
        builder: (_) => const ReceiptScannerScreen(),
      ),
    );

    if (result == null || !mounted) {
      return;
    }

    setState(() {
      if (result.merchantName.isNotEmpty) {
        _titleController.text = result.merchantName;
      }

      if (result.total != null) {
        _amountController.text =
            result.total!.toStringAsFixed(2);
      }
    });
  }
  Widget _buildExpenseItemCard(
      int index,
      Map<String, _ParticipantData> participants,
      ) {
    final item =
    _expenseItems[index];

    return Card(
      margin:
      const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment:
          CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Item ${index + 1}',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(
                      fontWeight:
                      FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove item',
                  onPressed: _isLoading
                      ? null
                      : () {
                    _removeExpenseItem(
                      index,
                    );
                  },
                  icon: const Icon(
                    Icons.delete_outline,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            TextFormField(
              controller:
              item.nameController,
              enabled: !_isLoading,
              decoration:
              const InputDecoration(
                labelText: 'Item name',
                hintText:
                'Example: Meat',
                border:
                OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 12),

            TextFormField(
              controller:
              item.amountController,
              enabled: !_isLoading,
              keyboardType:
              const TextInputType
                  .numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) {
                setState(() {});
              },
              decoration:
              const InputDecoration(
                labelText: 'Item amount',
                prefixText: '\$',
                border:
                OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 16),

            Text(
              'Shared by',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(
                fontWeight:
                FontWeight.bold,
              ),
            ),

            const SizedBox(height: 6),

            for (final memberId
            in widget.group.members)
              CheckboxListTile(
                contentPadding:
                EdgeInsets.zero,
                dense: true,
                value: item.participants
                    .contains(memberId),
                title: Text(
                  participants[memberId]
                      ?.displayName ??
                      'Unknown member',
                ),
                controlAffinity:
                ListTileControlAffinity
                    .trailing,
                onChanged: _isLoading
                    ? null
                    : (selected) {
                  setState(() {
                    if (selected ==
                        true) {
                      item.participants
                          .add(
                        memberId,
                      );
                    } else {
                      item.participants
                          .remove(
                        memberId,
                      );
                    }
                  });
                },
              ),

            if (item.participants
                .isNotEmpty) ...[
              const Divider(),

              Text(
                _itemSplitDescription(
                  item,
                ),
                style:
                Theme.of(context)
                    .textTheme
                    .bodyMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }
  String _itemSplitDescription(
      _ExpenseItemDraft item,
      ) {
    final amount =
        double.tryParse(
          item.amountController.text.trim(),
        ) ??
            0;

    if (item.participants.isEmpty) {
      return 'No participants selected';
    }

    final share =
        amount / item.participants.length;

    return '\$${amount.toStringAsFixed(2)} ÷ '
        '${item.participants.length} = '
        '\$${share.toStringAsFixed(2)} each';
  }
  Widget _buildItemizedSummary() {
    final shares =
    _calculateItemizedShares();

    final itemTotal =
    _calculateItemsTotal();

    final expenseTotal =
        double.tryParse(
          _amountController.text.trim(),
        ) ??
            0;

    return FutureBuilder<
        Map<String, _ParticipantData>>(
      future: _participantsFuture,
      builder: (context, snapshot) {
        final participants =
            snapshot.data ?? {};

        return Card(
          child: Padding(
            padding:
            const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Split summary',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(
                    fontWeight:
                    FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 12),

                for (final memberId
                in widget.group.members)
                  if ((shares[memberId] ??
                      0) >
                      0)
                    Padding(
                      padding:
                      const EdgeInsets
                          .symmetric(
                        vertical: 4,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              participants[
                              memberId]
                                  ?.displayName ??
                                  'Unknown member',
                            ),
                          ),
                          Text(
                            '\$${(shares[memberId] ?? 0).toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontWeight:
                              FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),

                const Divider(),

                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Items total',
                      ),
                    ),
                    Text(
                      '\$${itemTotal.toStringAsFixed(2)}',
                    ),
                  ],
                ),

                const SizedBox(height: 4),

                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Expense total',
                      ),
                    ),
                    Text(
                      '\$${expenseTotal.toStringAsFixed(2)}',
                    ),
                  ],
                ),

                if ((itemTotal -
                    expenseTotal)
                    .abs() >
                    0.01) ...[
                  const SizedBox(height: 10),

                  Text(
                    'Items must total '
                        '\$${expenseTotal.toStringAsFixed(2)} '
                        'before saving.',
                    style: TextStyle(
                      color:
                      Theme.of(context)
                          .colorScheme
                          .error,
                      fontWeight:
                      FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ParticipantData {
  final String id;
  final String name;
  final String email;
  final bool isGuest;

  const _ParticipantData({
    required this.id,
    required this.name,
    required this.email,
    required this.isGuest,
  });

  String get displayName {
    if (name.trim().isNotEmpty) {
      return name.trim();
    }

    if (email.trim().isNotEmpty) {
      return email.trim();
    }

    return isGuest ? 'Guest member' : 'Unknown user';
  }

  String get subtitle {
    if (isGuest) {
      if (email.trim().isNotEmpty) {
        return '${email.trim()} • Guest member';
      }

      return 'Guest member';
    }

    return email.trim().isEmpty
        ? 'Registered member'
        : email.trim();
  }
}

class _ExpenseItemDraft {
  final TextEditingController nameController;
  final TextEditingController amountController;
  final Set<String> participants;

  _ExpenseItemDraft({
    String name = '',
    String amount = '',
    required Set<String> participants,
  })  : nameController =
  TextEditingController(text: name),
        amountController =
        TextEditingController(text: amount),
        participants =
        Set<String>.from(participants);

  void dispose() {
    nameController.dispose();
    amountController.dispose();
  }
}