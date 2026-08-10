import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/currency_model.dart';
import '../../models/group_model.dart';
import '../../models/recurring_expense_model.dart';
import '../../services/recurring_expense_service.dart';

class AddRecurringExpenseScreen extends StatefulWidget {
  final GroupModel group;
  final RecurringExpenseModel? recurringExpense;

  const AddRecurringExpenseScreen({
    super.key,
    required this.group,
    this.recurringExpense,
  });

  bool get isEditing => recurringExpense != null;

  @override
  State<AddRecurringExpenseScreen> createState() =>
      _AddRecurringExpenseScreenState();
}

class _AddRecurringExpenseScreenState
    extends State<AddRecurringExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();

  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  final RecurringExpenseService _recurringService =
  RecurringExpenseService();

  final List<String> _categories = const [
    'Food',
    'Groceries',
    'Rent',
    'Utilities',
    'Travel',
    'Entertainment',
    'Other',
  ];

  bool _isLoading = false;
  String _category = 'Other';

  RecurrenceFrequency _frequency =
      RecurrenceFrequency.monthly;

  DateTime _firstDueDate = DateTime.now();

  late Set<String> _selectedMembers;
  late Future<Map<String, _ParticipantData>>
  _participantsFuture;

  @override
  @override
  void initState() {
    super.initState();

    final recurring = widget.recurringExpense;

    if (recurring != null) {
      _titleController.text = recurring.title;
      _amountController.text =
          recurring.amount.toStringAsFixed(2);

      _category = recurring.category;
      _frequency = recurring.frequency;
      _firstDueDate = recurring.nextDueDate;

      _selectedMembers =
          recurring.participants.toSet();
    } else {
      _selectedMembers =
          widget.group.members.toSet();
    }

    _participantsFuture = _loadParticipants();
  }

  Future<Map<String, _ParticipantData>>
  _loadParticipants() async {
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
        final details =
        Map<String, dynamic>.from(rawDetails);

        final name =
            details['name']?.toString().trim() ?? '';

        final email =
            details['email']?.toString().trim() ?? '';

        final isGuest = details['isGuest'] == true ||
            memberId.startsWith('guest_');

        if (name.isNotEmpty ||
            email.isNotEmpty ||
            isGuest) {
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

      final userDocument = await _firestore
          .collection('users')
          .doc(memberId)
          .get();

      final userData = userDocument.data() ?? {};

      participants[memberId] = _ParticipantData(
        id: memberId,
        name:
        userData['name']?.toString().trim() ?? '',
        email:
        userData['email']?.toString().trim() ?? '',
        isGuest: false,
      );
    }

    return participants;
  }

  Future<void> _selectDueDate() async {
    final today = DateTime.now();

    final minimumDate =
    widget.isEditing &&
        _firstDueDate.isBefore(today)
        ? _firstDueDate
        : today;

    final selectedDate = await showDatePicker(
      context: context,
      initialDate: _firstDueDate,
      firstDate: minimumDate,
      lastDate: DateTime(
        DateTime.now().year + 10,
      ),
    );

    if (selectedDate == null || !mounted) {
      return;
    }

    setState(() {
      _firstDueDate = selectedDate;
    });
  }

  Future<void> _saveRecurringExpense() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    if (_selectedMembers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Select at least one participant.',
          ),
        ),
      );

      return;
    }

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You must be logged in.'),
        ),
      );

      return;
    }

    if (!widget.group.members.contains(user.uid)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The current user is not a group member.',
          ),
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
      if (widget.isEditing) {
        await _recurringService.updateRecurringExpense(
          groupId: widget.group.id,
          recurringExpenseId: widget.recurringExpense!.id,
          title: _titleController.text.trim(),
          amount: amount,
          category: _category,
          paidBy: widget.recurringExpense!.paidBy,
          participants: _selectedMembers.toList(),
          frequency: _frequency,
          nextDueDate: _firstDueDate,
          isActive: widget.recurringExpense!.isActive,
        );
      } else {
        await _recurringService.createRecurringExpense(
          groupId: widget.group.id,
          title: _titleController.text.trim(),
          amount: amount,
          category: _category,
          paidBy: user.uid,
          participants: _selectedMembers.toList(),
          frequency: _frequency,
          firstDueDate: _firstDueDate,
        );
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isEditing
                ? 'Recurring expense updated.'
                : 'Recurring expense created.',
          ),
        ),
      );

      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              widget.isEditing
                  ? 'Unable to update recurring expense: $error'
                  : 'Unable to create recurring expense: $error'
          ),
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
      _selectedMembers =
          widget.group.members.toSet();
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
    final currency =
    currencyByCode(widget.group.currencyCode);

    final selectedCount = _selectedMembers.length;
    final totalMembers = widget.group.members.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isEditing
              ? 'Edit Recurring Expense'
              : 'Add Recurring Expense',
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding:
          const EdgeInsets.fromLTRB(16, 16, 16, 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _titleController,
                  enabled: !_isLoading,
                  textInputAction:
                  TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Expense title',
                    hintText: 'Rent, internet, electricity',
                    prefixIcon:
                    Icon(Icons.repeat_rounded),
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
                  textInputAction:
                  TextInputAction.next,
                  onChanged: (_) {
                    setState(() {});
                  },
                  decoration: InputDecoration(
                    labelText: 'Amount',
                    prefixText: '${currency.symbol} ',
                    prefixIcon: const Icon(
                      Icons.payments_outlined,
                    ),
                    border:
                    const OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final amount = double.tryParse(
                      value?.trim() ?? '',
                    );

                    if (amount == null ||
                        amount <= 0) {
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
                    if (value == null) return;

                    setState(() {
                      _category = value;
                    });
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<
                    RecurrenceFrequency>(
                  initialValue: _frequency,
                  decoration: const InputDecoration(
                    labelText: 'Repeats',
                    prefixIcon:
                    Icon(Icons.event_repeat),
                    border: OutlineInputBorder(),
                  ),
                  items: RecurrenceFrequency.values
                      .map(
                        (frequency) =>
                        DropdownMenuItem<
                            RecurrenceFrequency>(
                          value: frequency,
                          child: Text(
                            _frequencyLabel(frequency),
                          ),
                        ),
                  )
                      .toList(),
                  onChanged: _isLoading
                      ? null
                      : (value) {
                    if (value == null) return;

                    setState(() {
                      _frequency = value;
                    });
                  },
                ),
                const SizedBox(height: 16),
                Card(
                  child: ListTile(
                    leading: const Icon(
                      Icons.calendar_month_outlined,
                    ),
                    title: Text(
                      widget.isEditing
                          ? 'Next due date'
                          : 'First due date',
                    ),
                    subtitle: Text(
                      _formatDate(_firstDueDate),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right,
                    ),
                    onTap:
                    _isLoading ? null : _selectDueDate,
                  ),
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
                          fontWeight:
                          FontWeight.bold,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _isLoading
                          ? null
                          : _selectAllMembers,
                      child: const Text('Select all'),
                    ),
                    TextButton(
                      onPressed: _isLoading
                          ? null
                          : _clearAllMembers,
                      child: const Text('Clear'),
                    ),
                  ],
                ),
                Text(
                  '$selectedCount of $totalMembers selected',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                FutureBuilder<
                    Map<String, _ParticipantData>>(
                  future: _participantsFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Card(
                        child: Padding(
                          padding:
                          EdgeInsets.all(24),
                          child: Center(
                            child:
                            CircularProgressIndicator(),
                          ),
                        ),
                      );
                    }

                    if (snapshot.hasError) {
                      return Card(
                        child: Padding(
                          padding:
                          const EdgeInsets.all(16),
                          child: Text(
                            'Unable to load participants: '
                                '${snapshot.error}',
                          ),
                        ),
                      );
                    }

                    final participants =
                        snapshot.data ?? {};

                    return Card(
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: widget.group.members
                            .map((memberId) {
                          final participant =
                              participants[memberId] ??
                                  _ParticipantData(
                                    id: memberId,
                                    name: '',
                                    email: '',
                                    isGuest: memberId
                                        .startsWith(
                                        'guest_'),
                                  );

                          return CheckboxListTile(
                            value: _selectedMembers
                                .contains(memberId),
                            onChanged: _isLoading
                                ? null
                                : (selected) {
                              setState(() {
                                if (selected ==
                                    true) {
                                  _selectedMembers
                                      .add(
                                      memberId);
                                } else {
                                  _selectedMembers
                                      .remove(
                                      memberId);
                                }
                              });
                            },
                            secondary: CircleAvatar(
                              child: participant
                                  .displayName
                                  .isEmpty
                                  ? const Icon(
                                  Icons.person)
                                  : Text(
                                participant
                                    .displayName[0]
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
                            ListTileControlAffinity
                                .trailing,
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
                      leading: const Icon(
                        Icons.calculate_outlined,
                      ),
                      title:
                      const Text('Split equally'),
                      subtitle: Text(
                        '${currency.symbol}'
                            '${_calculateShare().toStringAsFixed(2)} '
                            'per participant',
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _isLoading
                        ? null
                        : _saveRecurringExpense,
                    icon: _isLoading
                        ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                      ),
                    )
                        : Icon(
                      widget.isEditing
                          ? Icons.save_outlined
                          : Icons.repeat_rounded,
                    ),
                    label: Text(
                      _isLoading
                          ? 'Saving...'
                          : widget.isEditing
                          ? 'Save Changes'
                          : 'Create Recurring Expense',
                    ),
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
    final amount = double.tryParse(
      _amountController.text.trim(),
    ) ??
        0;

    if (_selectedMembers.isEmpty) {
      return 0;
    }

    return amount / _selectedMembers.length;
  }

  static String _frequencyLabel(
      RecurrenceFrequency frequency,
      ) {
    switch (frequency) {
      case RecurrenceFrequency.weekly:
        return 'Weekly';
      case RecurrenceFrequency.monthly:
        return 'Monthly';
      case RecurrenceFrequency.yearly:
        return 'Yearly';
    }
  }

  static String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    return '${months[date.month - 1]} '
        '${date.day}, ${date.year}';
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

    return isGuest
        ? 'Guest member'
        : 'Unknown user';
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