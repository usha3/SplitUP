import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/expense_model.dart';
import '../../models/group_model.dart';
import '../../services/expense_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

class EditExpenseScreen extends StatefulWidget {
  final GroupModel group;
  final ExpenseModel expense;

  const EditExpenseScreen({
    super.key,
    required this.group,
    required this.expense,
  });

  @override
  State<EditExpenseScreen> createState() =>
      _EditExpenseScreenState();
}

enum _SplitMode {
  equal,
  itemized,
}

class _EditExpenseScreenState extends State<EditExpenseScreen> {
  final _formKey = GlobalKey<FormState>();

  final ExpenseService _expenseService = ExpenseService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  late final TextEditingController _titleController;
  late final TextEditingController _amountController;

  late String _category;
  late Set<String> _selectedMembers;
  late _SplitMode _splitMode;

  final List<_ExpenseItemDraft> _expenseItems = [];
  late Future<Map<String, _ParticipantData>> _participantsFuture;
  late double _receiptAdjustment;

  bool _isLoading = false;

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
        _addExpenseItem(
          notify: false,
        );
      }
    });
  }

  void _addExpenseItem({
    bool notify = true,
  }) {
    _expenseItems.add(
      _ExpenseItemDraft(
        participants:
        widget.group.members.toSet(),
      ),
    );

    if (notify && mounted) {
      setState(() {});
    }
  }

  void _removeExpenseItem(int index) {
    if (index < 0 ||
        index >= _expenseItems.length) {
      return;
    }

    final item =
    _expenseItems.removeAt(index);

    item.dispose();

    setState(() {});
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

  void _updateReceiptAdjustment() {
    if (_splitMode != _SplitMode.itemized) {
      _receiptAdjustment = 0;
      return;
    }

    final expenseTotal =
        double.tryParse(
          _amountController.text.trim(),
        ) ??
            0;

    final itemsTotal =
    _calculateItemsTotal();

    _receiptAdjustment =
        expenseTotal - itemsTotal;
  }

  Map<String, double> _calculateEqualShares(
      double amount,
      ) {
    final shares = <String, double>{};

    if (_selectedMembers.isEmpty) {
      return shares;
    }

    final share =
        amount / _selectedMembers.length;

    for (final memberId in _selectedMembers) {
      shares[memberId] = share;
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

      final share =
          amount / item.participants.length;

      for (final memberId
      in item.participants) {
        shares[memberId] =
            (shares[memberId] ?? 0) +
                share;
      }
    }
    if (_receiptAdjustment.abs() > 0.01) {
      final adjustmentParticipants =
      shares.keys.toSet();

      if (adjustmentParticipants.isNotEmpty) {
        final adjustmentPerPerson =
            _receiptAdjustment /
                adjustmentParticipants.length;

        for (final memberId
        in adjustmentParticipants) {
          shares[memberId] =
              (shares[memberId] ?? 0) +
                  adjustmentPerPerson;
        }
      }
    }
    return shares;
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
      final name =
      item.nameController.text.trim();

      final amount = double.tryParse(
        item.amountController.text.trim(),
      );

      if (name.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Enter a name for every item.',
            ),
          ),
        );

        return false;
      }

      if (amount == null || amount <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Enter a valid amount for $name.',
            ),
          ),
        );

        return false;
      }

      if (item.participants.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Select at least one participant for $name.',
            ),
          ),
        );

        return false;
      }
    }

    _updateReceiptAdjustment();

    return true;
  }

  @override
  void initState() {
    super.initState();

    _titleController = TextEditingController(
      text: widget.expense.title,
    );

    _amountController = TextEditingController(
      text: widget.expense.amount.toStringAsFixed(2),
    );

    _receiptAdjustment =
        widget.expense.receiptAdjustment;

    _category = _categories.contains(widget.expense.category)
        ? widget.expense.category
        : 'Other';

    _selectedMembers =
        widget.expense.participants.toSet();

    _splitMode =
    widget.expense.splitType == 'itemized'
        ? _SplitMode.itemized
        : _SplitMode.equal;

    if (_splitMode == _SplitMode.itemized) {
      for (final item in widget.expense.items) {
        _expenseItems.add(
          _ExpenseItemDraft(
            name: item.name,
            amount: item.amount.toStringAsFixed(2),
            participants:
            item.participants.toSet(),
          ),
        );
      }

      if (_expenseItems.isEmpty) {
        _addExpenseItem(
          notify: false,
        );
      }
    }

    _participantsFuture = _loadParticipants();
  }

  Future<Map<String, _ParticipantData>> _loadParticipants() async {
    final participants = <String, _ParticipantData>{};

    final currentUser =
        FirebaseAuth.instance.currentUser;

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
          // Continue using available group member details.
        }
      }

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

      if (isGuest &&
          name.isEmpty &&
          email.isEmpty) {
        name = 'Guest member';
      }

      participants[memberId] =
          _ParticipantData(
            name: name,
            email: email,
            isGuest: isGuest,
          );
    }

    return participants;
  }

  Future<void> _updateExpense() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    if (_splitMode == _SplitMode.equal &&
        _selectedMembers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select at least one participant.'),
        ),
      );
      return;
    }

    final amount = double.tryParse(
      _amountController.text.trim(),
    );

    if (amount == null || amount <= 0) {
      return;
    }

    if (_splitMode == _SplitMode.itemized &&
        !_validateItemizedSplit(amount)) {
      return;
    }

    late List<String> expenseParticipants;
    late List<ExpenseItem> expenseItems;
    late Map<String, double> shares;

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

      final participantIds = <String>{};

      for (final item in expenseItems) {
        participantIds.addAll(
          item.participants,
        );
      }

      expenseParticipants =
          participantIds.toList();

      shares =
          _calculateItemizedShares();
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await _expenseService.updateExpense(
        groupId: widget.group.id,
        expenseId: widget.expense.id,
        title: _titleController.text.trim(),
        amount: amount,
        category: _category,
        participants: expenseParticipants,
        splitType:
        _splitMode == _SplitMode.equal
            ? 'equal'
            : 'itemized',
        items: expenseItems,
        shares: shares,
        receiptUrl:
        widget.expense.receiptUrl,
        receiptAdjustment:
        _splitMode == _SplitMode.itemized
            ? _receiptAdjustment
            : 0,

        receiptAdjustmentLabel:
        _splitMode != _SplitMode.itemized ||
            _receiptAdjustment.abs() <= 0.01
            ? null
            : _receiptAdjustment > 0
            ? 'Tax / fees / adjustment'
            : 'Discount / adjustment',
      );

      if (!mounted) return;

      Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Expense updated successfully.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to update expense: $error'),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Expense'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _titleController,
                  enabled: !_isLoading,
                  decoration: const InputDecoration(
                    labelText: 'Expense title',
                    prefixIcon:
                    Icon(Icons.receipt_long_outlined),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null ||
                        value.trim().isEmpty) {
                      return 'Enter an expense title';
                    }

                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _amountController,
                  enabled: !_isLoading,
                  keyboardType:
                  const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
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
                    final amount = double.tryParse(
                      value?.trim() ?? '',
                    );

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
                    prefixIcon:
                    Icon(Icons.category_outlined),
                    border: OutlineInputBorder(),
                  ),
                  items: _categories
                      .map(
                        (category) =>
                        DropdownMenuItem<String>(
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
                    ButtonSegment(
                      value: _SplitMode.equal,
                      icon: Icon(Icons.people_outline),
                      label: Text('Equal'),
                    ),
                    ButtonSegment(
                      value: _SplitMode.itemized,
                      icon: Icon(
                        Icons.receipt_long_outlined,
                      ),
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
              if (_splitMode == _SplitMode.equal) ...[
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Participants',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _isLoading
                          ? null
                          : () {
                        setState(() {
                          _selectedMembers =
                              widget.group.members.toSet();
                        });
                      },
                      child: const Text('Select all'),
                    ),
                    TextButton(
                      onPressed: _isLoading
                          ? null
                          : () {
                        setState(() {
                          _selectedMembers.clear();
                        });
                      },
                      child: const Text('Clear'),
                    ),
                  ],
                ),
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
                            'Unable to load members: '
                                '${snapshot.error}',
                          ),
                        ),
                      );
                    }

                    final participants = snapshot.data ?? {};

                    return Card(
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children:
                        widget.group.members.map((memberId) {
                          final member =
                              participants[memberId] ??
                                  _ParticipantData(
                                    name: '',
                                    email: '',
                                    isGuest: memberId
                                        .startsWith('guest_'),
                                  );

                          return CheckboxListTile(
                            value: _selectedMembers
                                .contains(memberId),
                            onChanged: _isLoading
                                ? null
                                : (selected) {
                              setState(() {
                                if (selected == true) {
                                  _selectedMembers
                                      .add(memberId);
                                } else {
                                  _selectedMembers
                                      .remove(memberId);
                                }
                              });
                            },
                            secondary: CircleAvatar(
                              child: Text(
                                member.displayName[0]
                                    .toUpperCase(),
                              ),
                            ),
                            title: Text(member.displayName),
                            subtitle: Text(member.subtitle),
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
                      leading:
                      const Icon(Icons.calculate_outlined),
                      title: const Text('Equal split'),
                      subtitle: Text(
                        '\$${_sharePerPerson().toStringAsFixed(2)} '
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
                            fontWeight:
                            FontWeight.bold,
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
                    _isLoading ? null : _updateExpense,
                    child: _isLoading
                        ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                      ),
                    )
                        : const Text('Save Changes'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  double _sharePerPerson() {
    final amount =
        double.tryParse(_amountController.text.trim()) ?? 0;

    if (_selectedMembers.isEmpty) {
      return 0;
    }

    return amount / _selectedMembers.length;
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
                    style: const TextStyle(
                      fontWeight:
                      FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _isLoading
                      ? null
                      : () =>
                      _removeExpenseItem(
                        index,
                      ),
                  icon: const Icon(
                    Icons.delete_outline,
                  ),
                ),
              ],
            ),

            TextFormField(
              controller:
              item.nameController,
              enabled: !_isLoading,
              decoration:
              const InputDecoration(
                labelText: 'Item name',
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
                setState(() {
                  _updateReceiptAdjustment();
                });
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

            const Text(
              'Shared by',
              style: TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),

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
                onChanged: _isLoading
                    ? null
                    : (selected) {
                  setState(() {
                    if (selected == true) {
                      item.participants
                          .add(memberId);
                    } else {
                      item.participants
                          .remove(memberId);
                    }
                  });
                },
              ),
          ],
        ),
      ),
    );
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
                const Text(
                  'Split Summary',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 10),

                for (final memberId
                in widget.group.members)
                  if ((shares[memberId] ?? 0) >
                      0)
                    Padding(
                      padding:
                      const EdgeInsets
                          .symmetric(
                        vertical: 5,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              participants[memberId]
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

                Text(
                  'Items total: '
                      '\$${itemTotal.toStringAsFixed(2)}',
                ),
                if (_receiptAdjustment.abs() > 0.01) ...[
                  const SizedBox(height: 4),

                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _receiptAdjustment > 0
                              ? 'Tax / fees / adjustment'
                              : 'Discount / adjustment',
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
                Text(
                  'Expense total: '
                      '\$${expenseTotal.toStringAsFixed(2)}',
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
  final String name;
  final String email;
  final bool isGuest;

  const _ParticipantData({
    required this.name,
    required this.email,
    required this.isGuest,
  });

  String get displayName {
    if (name.isNotEmpty) {
      return name;
    }

    if (email.isNotEmpty) {
      return email;
    }

    return isGuest ? 'Guest member' : 'Unknown user';
  }

  String get subtitle {
    if (isGuest) {
      return email.isEmpty
          ? 'Guest member'
          : '$email • Guest member';
    }

    return email.isEmpty ? 'Registered member' : email;
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