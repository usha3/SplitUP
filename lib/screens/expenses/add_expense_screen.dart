import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/expense_model.dart';
import '../../models/group_model.dart';
import '../../models/scanned_receipt.dart';
import '../../services/expense_service.dart';
import 'receipt_scanner_screen.dart';

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

enum _ReceiptTotalChoice {
  calculated,
  receipt,
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();

  final ExpenseService _expenseService = ExpenseService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  final ImagePicker _imagePicker =
  ImagePicker();

  XFile? _receiptImage;

  bool _isLoading = false;
  String _category = 'Other';
  String? _paidBy;
  _SplitMode _splitMode = _SplitMode.equal;

  final List<_ExpenseItemDraft> _expenseItems = [];

  double _receiptAdjustment = 0;

  // Structured receipt breakdown for display.
  // Splitting still uses _receiptAdjustment, so the existing itemized math and
  // exact-cent rounding remain unchanged.
  bool _hasStructuredReceiptBreakdown = false;
  double _receiptTax = 0;
  double _receiptTipAndFees = 0;
  double _receiptReconciliation = 0;

  static const double _receiptMismatchTolerance = 0.02;

  void _updateReceiptAdjustment() {
    final expenseTotal =
        double.tryParse(
          _amountController.text.trim(),
        ) ??
            0;

    final itemsTotal =
    _calculateItemsTotal();

    _receiptAdjustment =
        expenseTotal - itemsTotal;

    if (_hasStructuredReceiptBreakdown) {
      final reconciliation =
          expenseTotal -
              itemsTotal -
              _receiptTax -
              _receiptTipAndFees;

      _receiptReconciliation =
      reconciliation.abs() <=
          _receiptMismatchTolerance
          ? 0
          : reconciliation;
    }
  }

  Set<String> _remainingItemParticipants = {};

  Map<String, Set<String>> _memberExcludedTags = {};

  late Set<String> _selectedMembers;
  late Future<Map<String, _ParticipantData>> _participantsFuture;

  bool _isPreferenceItem(
      _ExpenseItemDraft item,
      ) {
    final tag = item.detectedTag;

    if (tag == null || tag.isEmpty) {
      return false;
    }

    return _memberExcludedTags.values.any(
          (excludedTags) =>
          excludedTags.contains(tag),
    );
  }
  List<_ExpenseItemDraft>
  get _preferenceItems {
    return _expenseItems
        .where(_isPreferenceItem)
        .toList();
  }
  List<_ExpenseItemDraft>
  get _remainingItems {
    return _expenseItems
        .where(
          (item) =>
      !_isPreferenceItem(item) &&
          _isNormalMerchandiseItem(item),
    )
        .toList();
  }

  final List<String> _categories = [
    'Food',
    'Groceries',
    'Rent',
    'Utilities',
    'Travel',
    'Entertainment',
    'Other',
  ];

  String _displayExpenseTag(
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

      default:
        return tag;
    }
  }

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

  Map<String, double> _calculateEqualShares(
      double total,
      ) {
    final participantIds = widget.group.members
        .where(_selectedMembers.contains)
        .toList();

    final rawShares = <String, double>{};

    if (participantIds.isEmpty) {
      return rawShares;
    }

    final perPerson = total / participantIds.length;

    for (final memberId in participantIds) {
      rawShares[memberId] = perPerson;
    }

    return _roundSharesToExactTotal(
      rawShares: rawShares,
      targetTotal: total,
      participantOrder: participantIds,
    );
  }

  Map<String, double> _calculateItemizedShares() {
    final rawShares = <String, double>{};

    // First calculate mathematically exact shares using doubles.
    // Do NOT round each individual item, because doing that repeatedly can
    // move multiple cents to the same people across a receipt.
    for (final item in _expenseItems) {
      final amount = double.tryParse(
        item.amountController.text.trim(),
      ) ??
          0;

      if (amount == 0 || item.participants.isEmpty) {
        continue;
      }

      final participantIds = widget.group.members
          .where(item.participants.contains)
          .toList();

      if (participantIds.isEmpty) {
        continue;
      }

      final perPerson = amount / participantIds.length;

      for (final memberId in participantIds) {
        rawShares[memberId] =
            (rawShares[memberId] ?? 0) + perPerson;
      }
    }

    // Add receipt-level tax / fees / reconciliation without rounding yet.
    if (_receiptAdjustment.abs() > 0.001 &&
        _remainingItemParticipants.isNotEmpty) {
      final participantIds = widget.group.members
          .where(_remainingItemParticipants.contains)
          .toList();

      if (participantIds.isNotEmpty) {
        final perPerson =
            _receiptAdjustment / participantIds.length;

        for (final memberId in participantIds) {
          rawShares[memberId] =
              (rawShares[memberId] ?? 0) + perPerson;
        }
      }
    }

    final expenseTotal =
        double.tryParse(_amountController.text.trim()) ??
            rawShares.values.fold<double>(
              0,
                  (currentTotal, value) => currentTotal + value,
            );

    final participantOrder = widget.group.members
        .where(rawShares.containsKey)
        .toList();

    return _roundSharesToExactTotal(
      rawShares: rawShares,
      targetTotal: expenseTotal,
      participantOrder: participantOrder,
    );
  }

  Map<String, double> _roundSharesToExactTotal({
    required Map<String, double> rawShares,
    required double targetTotal,
    required List<String> participantOrder,
  }) {
    if (rawShares.isEmpty || participantOrder.isEmpty) {
      return <String, double>{};
    }

    final targetCents = (targetTotal * 100).round();

    // Start by flooring each final participant share to cents.
    // This follows the rule: round down first, then distribute remaining cents.
    final cents = <String, int>{};

    for (final memberId in participantOrder) {
      final raw = rawShares[memberId] ?? 0;

      // Final expense shares are expected to be non-negative.
      // If a rare receipt creates a negative net share, truncate toward zero
      // so we can still reconcile deterministically below.
      final rawCents = raw * 100;
      cents[memberId] =
      rawCents >= 0 ? rawCents.floor() : rawCents.ceil();
    }

    var currentCents =
    cents.values.fold<int>(
      0,
          (runningTotal, value) =>
      runningTotal + value,
    );

    var difference = targetCents - currentCents;

    if (difference > 0) {
      // Add remaining cents in stable participant order.
      var index = 0;

      while (difference > 0) {
        final memberId =
        participantOrder[index % participantOrder.length];

        cents[memberId] = (cents[memberId] ?? 0) + 1;

        difference -= 1;
        index += 1;
      }
    } else if (difference < 0) {
      // Defensive case: remove extra cents in reverse order.
      var index = participantOrder.length - 1;

      while (difference < 0) {
        final memberId =
        participantOrder[index % participantOrder.length];

        cents[memberId] = (cents[memberId] ?? 0) - 1;

        difference += 1;
        index -= 1;

        if (index < 0) {
          index = participantOrder.length - 1;
        }
      }
    }

    return cents.map(
          (memberId, value) =>
          MapEntry(memberId, value / 100.0),
    );
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
          itemAmount == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Enter a valid non-zero amount for '
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

    _updateReceiptAdjustment();

    if (_receiptAdjustment.abs() > 0.01 &&
        _remainingItemParticipants.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Select at least one member to share '
                'the receipt adjustment.',
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
    _remainingItemParticipants =
        widget.group.members.toSet();
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

  Future<Map<String, Set<String>>>
  _loadMemberExpensePreferences() async {
    final snapshot = await _firestore
        .collection('groups')
        .doc(widget.group.id)
        .collection('memberPreferences')
        .get();

    final preferences =
    <String, Set<String>>{};

    for (final document in snapshot.docs) {
      final data = document.data();

      final rawTags =
      data['excludedTags'];

      if (rawTags is List) {
        preferences[document.id] =
            rawTags
                .map(
                  (tag) => tag
                  .toString()
                  .trim()
                  .toLowerCase(),
            )
                .where(
                  (tag) => tag.isNotEmpty,
            )
                .toSet();
      }
    }

    return preferences;
  }

  Set<String> _participantsForScannedItem(
      ScannedReceiptItem item,
      ) {
    final participants =
    widget.group.members.toSet();

    final tag =
    item.detectedTag
        ?.trim()
        .toLowerCase();

    if (tag == null || tag.isEmpty) {
      return participants;
    }

    for (final memberId
    in widget.group.members) {
      final excludedTags =
          _memberExcludedTags[memberId] ??
              const <String>{};

      if (excludedTags.contains(tag)) {
        participants.remove(memberId);
      }
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
        receiptAdjustment:
        _receiptAdjustment,

        receiptAdjustmentLabel:
        _receiptAdjustment.abs() <= 0.01
            ? null
            : 'Receipt adjustment',
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

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Receipt attached. Use Scan Receipt to extract receipt details.',
        ),
      ),
    );
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
                    setState(() {
                      _updateReceiptAdjustment();
                    });
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

                      final preferenceItems =
                          _preferenceItems;

                      final remainingItems =
                          _remainingItems;

                      return Column(
                        crossAxisAlignment:
                        CrossAxisAlignment.stretch,
                        children: [
                          if (preferenceItems.isNotEmpty) ...[
                            Text(
                              'Excluded / Special Items',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),

                            const SizedBox(height: 8),

                            for (final item
                            in preferenceItems)
                              _buildPreferenceItemCard(
                                item,
                                participants,
                              ),

                            const SizedBox(height: 20),
                          ],

                          if (remainingItems.isNotEmpty)
                            _buildRemainingItemsCard(
                              remainingItems,
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

  void _setReceiptBreakdown({
    required ScannedReceipt result,
    required double chosenTotal,
  }) {
    final tax = result.tax ?? 0.0;
    final tipAndFees =
        (result.tip ?? 0.0) + (result.fees ?? 0.0);

    final netItems = _calculateItemsTotal();

    final reconciliation =
        chosenTotal - netItems - tax - tipAndFees;

    _hasStructuredReceiptBreakdown =
        result.tax != null ||
            result.tip != null ||
            result.fees != null;

    _receiptTax =
    tax.abs() <= 0.005 ? 0 : tax;

    _receiptTipAndFees =
    tipAndFees.abs() <= 0.005
        ? 0
        : tipAndFees;

    _receiptReconciliation =
    reconciliation.abs() <=
        _receiptMismatchTolerance
        ? 0
        : reconciliation;
  }
  bool _isDiscountName(String rawName) {
    final name = rawName
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return name.contains('coupon') ||
        name.contains('cpn') ||
        name.contains('discount') ||
        name.contains('promo') ||
        name.contains('promotion') ||
        name.contains('savings') ||
        name.contains('reward') ||
        name.contains('redcard') ||
        name.contains('circle bonus') ||
        name.contains('manufacturer') ||
        name.contains('markdown') ||
        name.contains('loyalty');
  }

  bool _isReceiptDiscountItem(ScannedReceiptItem item) {
    return item.amount < 0 && _isDiscountName(item.name);
  }

  bool _isDraftDiscountItem(_ExpenseItemDraft item) {
    final amount = double.tryParse(
      item.amountController.text.trim(),
    ) ??
        0;

    return amount < 0 && _isDiscountName(item.nameController.text);
  }

  bool _isDraftReturnItem(_ExpenseItemDraft item) {
    final amount = double.tryParse(
      item.amountController.text.trim(),
    ) ??
        0;

    return amount < 0 && !_isDraftDiscountItem(item);
  }
  bool _isNormalMerchandiseItem(
      _ExpenseItemDraft item,
      ) {
    final amount = double.tryParse(
      item.amountController.text.trim(),
    ) ??
        0;

    // Discounts/coupons should never appear as
    // normal "Remaining Items".
    if (_isDraftDiscountItem(item)) {
      return false;
    }

    // Returns/negative adjustments should also
    // not be counted as normal merchandise.
    if (amount < 0) {
      return false;
    }

    return true;
  }
  Future<void> _scanReceipt() async {
    final result =
    await Navigator.of(context).push<ScannedReceipt>(
      MaterialPageRoute(
        builder: (_) => const ReceiptScannerScreen(),
      ),
    );

    if (result == null || !mounted) {
      return;
    }

    debugPrint(
      'SCANNED ITEMS COUNT: ${result.items.length}',
    );

    for (final item in result.items) {
      debugPrint(
        'ITEM: ${item.name} | '
            '${item.amount} | '
            'TAG: ${item.detectedTag}',
      );
    }

    try {
      final preferences =
      await _loadMemberExpensePreferences();

      if (!mounted) return;

      _memberExcludedTags = preferences;
      _remainingItemParticipants =
          widget.group.members.toSet();

      for (final item in _expenseItems) {
        item.dispose();
      }

      _expenseItems.clear();

      final discountItems = result.items
          .where(_isReceiptDiscountItem)
          .toList();

      final merchandiseItems = result.items
          .where((item) => !_isReceiptDiscountItem(item))
          .toList();

      for (final scannedItem in merchandiseItems) {
        _expenseItems.add(
          _ExpenseItemDraft(
            name: scannedItem.name,
            amount: scannedItem.amount.toStringAsFixed(2),
            participants: _participantsForScannedItem(scannedItem),
            detectedTag: scannedItem.detectedTag,
          ),
        );
      }
// Keep receipt discounts/coupons as itemized negative rows.
// This preserves rows such as:
// MFG CPN SAVINGS   -3.50
      for (final scannedItem in discountItems) {
        _expenseItems.add(
          _ExpenseItemDraft(
            name: scannedItem.name,
            amount: scannedItem.amount.toStringAsFixed(2),

            // Receipt-level discounts should normally apply to everyone
            // sharing the remaining/normal merchandise.
            participants: _remainingItemParticipants.toSet(),

            // Discounts are not preference-category items.
            detectedTag: null,
          ),
        );
      }
      final detectedItemsTotal = _calculateItemsTotal();
      final printedTotal = result.total;

      final receiptTax = result.tax ?? 0.0;
      final receiptTip = result.tip ?? 0.0;
      final receiptFees = result.fees ?? 0.0;

      // Build the calculated total only from the parsed items plus explicit
      // receipt-level components. Negative coupon items are already included
      // in detectedItemsTotal.
      final calculatedTotal =
          detectedItemsTotal +
              receiptTax +
              receiptTip +
              receiptFees;

      final difference = printedTotal == null
          ? 0.0
          : printedTotal - calculatedTotal;

      var chosenTotal = printedTotal ?? calculatedTotal;
      var usePrintedTotal = true;

      if (printedTotal != null &&
          difference.abs() > _receiptMismatchTolerance) {
        final choice = await _showReceiptTotalMismatchDialog(
          calculatedTotal: calculatedTotal,
          receiptTotal: printedTotal,
          difference: difference,
        );

        if (!mounted) return;

        // Closing the dialog without choosing keeps the printed receipt total.
        usePrintedTotal =
            (choice ?? _ReceiptTotalChoice.receipt) ==
                _ReceiptTotalChoice.receipt;

        chosenTotal = usePrintedTotal
            ? printedTotal
            : calculatedTotal;
      }

      if (!mounted) return;

      _setReceiptBreakdown(
        result: result,
        chosenTotal: chosenTotal,
      );

      setState(() {
        if (result.merchantName.isNotEmpty) {
          _titleController.text = result.merchantName;
        }

        _amountController.text =
            chosenTotal.toStringAsFixed(2);

        if (result.items.isNotEmpty) {
          _splitMode = _SplitMode.itemized;
          _category = 'Groceries';
        }

        // This is the NET adjustment used for splitting.
        // It guarantees item shares + adjustment == chosen expense total.
        _updateReceiptAdjustment();
      });

      if (result.items.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              difference.abs() > _receiptMismatchTolerance
                  ? usePrintedTotal
                  ? 'Receipt items added. Printed receipt total selected.'
                  : 'Receipt items added. Calculated total selected.'
                  : 'Receipt items added. Member exclusions were applied automatically. Please review before saving.',
            ),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Receipt detected, but member '
                'preferences could not be applied: $error',
          ),
        ),
      );
    }
  }

  Future<_ReceiptTotalChoice?> _showReceiptTotalMismatchDialog({
    required double calculatedTotal,
    required double receiptTotal,
    required double difference,
  }) {
    return showDialog<_ReceiptTotalChoice>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Receipt total mismatch'),
          content: Text(
            'The detected items, discounts, and tax/fees add up to '
                '\$${calculatedTotal.toStringAsFixed(2)}, but the receipt '
                'total is \$${receiptTotal.toStringAsFixed(2)}.\n\n'
                'Difference: '
                '${difference >= 0 ? '+' : '-'}'
                '\$${difference.abs().toStringAsFixed(2)}.\n\n'
                'Which total should SplitUP use?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(
                  _ReceiptTotalChoice.calculated,
                );
              },
              child: Text(
                'Use calculated total '
                    '(\$${calculatedTotal.toStringAsFixed(2)})',
              ),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(
                  _ReceiptTotalChoice.receipt,
                );
              },
              child: Text(
                'Use receipt total '
                    '(\$${receiptTotal.toStringAsFixed(2)})',
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPreferenceItemCard(
      _ExpenseItemDraft item,
      Map<String, _ParticipantData> participants,
      ) {
    final amount =
        double.tryParse(
          item.amountController.text.trim(),
        ) ??
            0;

    return Card(
      margin: const EdgeInsets.only(
        bottom: 12,
      ),
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
                    item.nameController.text,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(
                      fontWeight:
                      FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  '\$${amount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),

            if (item.detectedTag != null) ...[
              const SizedBox(height: 6),

              Text(
                'Detected: '
                    '${_displayExpenseTag(
                  item.detectedTag!,
                )}',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall,
              ),
            ],

            const SizedBox(height: 12),

            Text(
              'Shared by',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 4),

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
                    if (selected == true) {
                      item.participants.add(
                        memberId,
                      );
                    } else {
                      item.participants.remove(
                        memberId,
                      );
                    }
                  });
                },
              ),

            if (item.participants.isNotEmpty) ...[
              const Divider(),
              Text(
                _itemSplitDescription(item),
              ),
            ],
          ],
        ),
      ),
    );
  }
  Widget _buildRemainingItemsCard(
      List<_ExpenseItemDraft> items,
      Map<String, _ParticipantData> participants,
      ) {
    final total = items.fold<double>(
      0,
          (currentTotal, item) =>
      currentTotal +
          (double.tryParse(
            item.amountController.text.trim(),
          ) ??
              0),
    );

    return Card(
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
                    'Remaining Items',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(
                      fontWeight:
                      FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  '\$${total.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 4),

            Text(
              '${items.length} item(s) '
                  'without exclusions',
            ),

            const SizedBox(height: 8),

            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding:
              EdgeInsets.zero,
              title: const Text(
                'View items',
              ),
              children: [
                for (final item in items)
                  ListTile(
                    dense: true,
                    contentPadding:
                    EdgeInsets.zero,
                    title: Text(
                      item.nameController.text,
                    ),
                    trailing: Text(
                      '\$${item.amountController.text}',
                    ),
                  ),
              ],
            ),

            const Divider(),

            Text(
              'Shared by',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 4),

            for (final memberId
            in widget.group.members)
              CheckboxListTile(
                contentPadding:
                EdgeInsets.zero,
                dense: true,
                value:
                _remainingItemParticipants
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
                    if (selected == true) {
                      _remainingItemParticipants
                          .add(memberId);
                    } else {
                      _remainingItemParticipants
                          .remove(memberId);
                    }

                    // Apply the same selection
                    // to every normal item.
                    for (final item in items) {
                      item.participants.clear();
                      item.participants.addAll(
                        _remainingItemParticipants,
                      );
                    }
                  });
                },
              ),

            if (_remainingItemParticipants
                .isNotEmpty) ...[
              const Divider(),

              Text(
                '\$${total.toStringAsFixed(2)} ÷ '
                    '${_remainingItemParticipants.length} = '
                    '\$${(
                    total /
                        _remainingItemParticipants.length
                ).toStringAsFixed(2)} each',
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

    final merchandiseTotal = _expenseItems.fold<double>(
      0,
          (runningTotal, item) {
        final amount = double.tryParse(
          item.amountController.text.trim(),
        ) ??
            0;
        return amount > 0 ? runningTotal + amount : runningTotal;
      },
    );

    final returnsTotal = _expenseItems.fold<double>(
      0,
          (runningTotal, item) {
        final amount = double.tryParse(
          item.amountController.text.trim(),
        ) ??
            0;

        return _isDraftReturnItem(item)
            ? runningTotal + amount
            : runningTotal;
      },
    );

    final discountsTotal = _expenseItems.fold<double>(
      0,
          (runningTotal, item) {
        final amount = double.tryParse(
          item.amountController.text.trim(),
        ) ??
            0;

        return _isDraftDiscountItem(item)
            ? runningTotal + amount
            : runningTotal;
      },
    );

    final netMerchandiseTotal =
        merchandiseTotal + returnsTotal;

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
                      child: Text('Merchandise total'),
                    ),
                    Text(
                      '\$${merchandiseTotal.toStringAsFixed(2)}',
                    ),
                  ],
                ),

                if (returnsTotal.abs() > 0.005) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Returns'),
                      ),
                      Text(
                        '-\$${returnsTotal.abs().toStringAsFixed(2)}',
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Net merchandise'),
                      ),
                      Text(
                        '\$${netMerchandiseTotal.toStringAsFixed(2)}',
                      ),
                    ],
                  ),
                ],

                if (discountsTotal.abs() > 0.005) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Discounts / coupons'),
                      ),
                      Text(
                        '-\$${discountsTotal.abs().toStringAsFixed(2)}',
                      ),
                    ],
                  ),
                ],

                if (_receiptTax.abs() > 0.005) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Expanded(child: Text('Tax')),
                      Text(
                        '+\$${_receiptTax.toStringAsFixed(2)}',
                      ),
                    ],
                  ),
                ],

                if (_receiptTipAndFees.abs() > 0.005) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Expanded(child: Text('Tip / fees')),
                      Text(
                        _receiptTipAndFees >= 0
                            ? '+\$${_receiptTipAndFees.toStringAsFixed(2)}'
                            : '-\$${_receiptTipAndFees.abs().toStringAsFixed(2)}',
                      ),
                    ],
                  ),
                ],

                if (_receiptReconciliation.abs() > 0.005) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Receipt adjustment'),
                      ),
                      Text(
                        _receiptReconciliation >= 0
                            ? '+\$${_receiptReconciliation.toStringAsFixed(2)}'
                            : '-\$${_receiptReconciliation.abs().toStringAsFixed(2)}',
                      ),
                    ],
                  ),
                ],

                // For manually entered itemized expenses, or old scans that do
                // not have a component breakdown, keep the existing net line.
                if (!_hasStructuredReceiptBreakdown &&
                    _receiptTax.abs() <= 0.005 &&
                    _receiptTipAndFees.abs() <= 0.005 &&
                    _receiptReconciliation.abs() <= 0.005 &&
                    _receiptAdjustment.abs() > 0.01) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Receipt adjustment',
                        ),
                      ),
                      Text(
                        _receiptAdjustment > 0
                            ? '+\$${_receiptAdjustment.toStringAsFixed(2)}'
                            : '-\$${_receiptAdjustment.abs().toStringAsFixed(2)}',
                      ),
                    ],
                  ),
                ],

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
  final TextEditingController
  nameController;

  final TextEditingController
  amountController;

  final Set<String> participants;

  final String? detectedTag;

  _ExpenseItemDraft({
    String name = '',
    String amount = '',
    required Set<String> participants,
    this.detectedTag,
  })  : nameController =
  TextEditingController(
    text: name,
  ),
        amountController =
        TextEditingController(
          text: amount,
        ),
        participants =
        Set<String>.from(
          participants,
        );

  void dispose() {
    nameController.dispose();
    amountController.dispose();
  }
}

