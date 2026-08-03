import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/expense_model.dart';
import '../../models/group_model.dart';
import '../../services/expense_service.dart';

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

class _EditExpenseScreenState extends State<EditExpenseScreen> {
  final _formKey = GlobalKey<FormState>();

  final ExpenseService _expenseService = ExpenseService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  late final TextEditingController _titleController;
  late final TextEditingController _amountController;

  late String _category;
  late Set<String> _selectedMembers;
  late Future<Map<String, _ParticipantData>> _participantsFuture;

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

  @override
  void initState() {
    super.initState();

    _titleController = TextEditingController(
      text: widget.expense.title,
    );

    _amountController = TextEditingController(
      text: widget.expense.amount.toStringAsFixed(2),
    );

    _category = _categories.contains(widget.expense.category)
        ? widget.expense.category
        : 'Other';

    _selectedMembers =
        widget.expense.participants.toSet();

    _participantsFuture = _loadParticipants();
  }

  Future<Map<String, _ParticipantData>> _loadParticipants() async {
    final groupDocument = await _firestore
        .collection('groups')
        .doc(widget.group.id)
        .get();

    final data = groupDocument.data() ?? {};
    final rawDetails = data['memberDetails'];

    final memberDetails = rawDetails is Map
        ? Map<String, dynamic>.from(rawDetails)
        : <String, dynamic>{};

    final participants = <String, _ParticipantData>{};

    for (final memberId in widget.group.members) {
      final rawMember = memberDetails[memberId];

      if (rawMember is Map) {
        final details = Map<String, dynamic>.from(rawMember);

        participants[memberId] = _ParticipantData(
          name: details['name']?.toString().trim() ?? '',
          email: details['email']?.toString().trim() ?? '',
          isGuest: details['isGuest'] == true ||
              memberId.startsWith('guest_'),
        );

        continue;
      }

      if (memberId.startsWith('guest_')) {
        participants[memberId] = const _ParticipantData(
          name: 'Guest member',
          email: '',
          isGuest: true,
        );

        continue;
      }

      final userDocument = await _firestore
          .collection('users')
          .doc(memberId)
          .get();

      final userData = userDocument.data() ?? {};

      participants[memberId] = _ParticipantData(
        name: userData['name']?.toString().trim() ?? '',
        email: userData['email']?.toString().trim() ?? '',
        isGuest: false,
      );
    }

    return participants;
  }

  Future<void> _updateExpense() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
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
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await _expenseService.updateExpense(
        groupId: widget.group.id,
        expenseId: widget.expense.id,
        title: _titleController.text,
        amount: amount,
        category: _category,
        participants: _selectedMembers.toList(),
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
                    setState(() {});
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