import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/group_model.dart';
import '../../services/expense_service.dart';
import '../../models/scanned_receipt.dart';
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

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();

  final ExpenseService _expenseService = ExpenseService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _isLoading = false;
  String _category = 'Other';

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

  @override
  void initState() {
    super.initState();

    _selectedMembers = widget.group.members.toSet();
    _participantsFuture = _loadParticipants();
  }

  Future<Map<String, _ParticipantData>> _loadParticipants() async {
    final groupDocument = await _firestore
        .collection('groups')
        .doc(widget.group.id)
        .get();

    final groupData = groupDocument.data() ?? {};

    final rawMemberDetails = groupData['memberDetails'];

    final memberDetails = rawMemberDetails is Map
        ? Map<String, dynamic>.from(rawMemberDetails)
        : <String, dynamic>{};

    final participants = <String, _ParticipantData>{};

    for (final memberId in widget.group.members) {
      final rawDetails = memberDetails[memberId];

      if (rawDetails is Map) {
        final details = Map<String, dynamic>.from(rawDetails);

        final name = details['name']?.toString().trim() ?? '';
        final email = details['email']?.toString().trim() ?? '';
        final isGuest =
            details['isGuest'] == true || memberId.startsWith('guest_');

        if (name.isNotEmpty || email.isNotEmpty || isGuest) {
          participants[memberId] = _ParticipantData(
            id: memberId,
            name: name,
            email: email,
            isGuest: isGuest,
          );

          continue;
        }
      }

      if (memberId.startsWith('guest_')) {
        participants[memberId] = _ParticipantData(
          id: memberId,
          name: 'Guest member',
          email: '',
          isGuest: true,
        );

        continue;
      }

      final userDocument =
      await _firestore.collection('users').doc(memberId).get();

      final userData = userDocument.data() ?? {};

      participants[memberId] = _ParticipantData(
        id: memberId,
        name: userData['name']?.toString().trim() ?? '',
        email: userData['email']?.toString().trim() ?? '',
        isGuest: false,
      );
    }

    return participants;
  }

  Future<void> _saveExpense() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedMembers.isEmpty) {
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a valid amount.'),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await _expenseService.addExpense(
        groupId: widget.group.id,
        title: _titleController.text.trim(),
        amount: amount,
        category: _category,
        participants: _selectedMembers.toList(),
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

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
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