import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/recurring_expense_model.dart';

class RecurringExpenseService {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  RecurringExpenseService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore =
      firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>>
  _recurringCollection(String groupId) {
    return _firestore
        .collection('groups')
        .doc(groupId)
        .collection('recurringExpenses');
  }

  Stream<List<RecurringExpenseModel>>
  watchRecurringExpenses(String groupId) {
    return _recurringCollection(groupId)
        .orderBy('nextDueDate')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
          .map(
        RecurringExpenseModel.fromFirestore,
      )
          .toList(),
    );
  }

  Future<String> createRecurringExpense({
    required String groupId,
    required String title,
    required double amount,
    required String category,
    required String paidBy,
    required List<String> participants,
    required RecurrenceFrequency frequency,
    required DateTime firstDueDate,
  }) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw StateError(
        'You must be logged in to create a recurring expense.',
      );
    }

    final trimmedTitle = title.trim();

    if (trimmedTitle.isEmpty) {
      throw ArgumentError('Expense title is required.');
    }

    if (amount <= 0) {
      throw ArgumentError(
        'The amount must be greater than zero.',
      );
    }

    if (participants.isEmpty) {
      throw ArgumentError(
        'Select at least one participant.',
      );
    }

    final groupDocument = await _firestore
        .collection('groups')
        .doc(groupId)
        .get();

    if (!groupDocument.exists) {
      throw StateError('Group not found.');
    }

    final groupData = groupDocument.data() ?? {};

    final members = List<String>.from(
      groupData['members'] as List<dynamic>? ?? const [],
    );

    if (!members.contains(user.uid)) {
      throw StateError(
        'Only group members can create recurring expenses.',
      );
    }

    if (!members.contains(paidBy)) {
      throw ArgumentError(
        'The payer must be a member of the group.',
      );
    }

    if (participants.any(
          (participant) => !members.contains(participant),
    )) {
      throw ArgumentError(
        'Every participant must belong to the group.',
      );
    }

    final document = _recurringCollection(groupId).doc();

    await document.set({
      'groupId': groupId,
      'title': trimmedTitle,
      'amount': amount,
      'category': category.trim().isEmpty
          ? 'Other'
          : category.trim(),
      'paidBy': paidBy,
      'participants': participants,
      'frequency': frequency.name,
      'dayOfMonth': firstDueDate.day,
      'nextDueDate': Timestamp.fromDate(firstDueDate),
      'lastGeneratedAt': null,
      'isActive': true,
      'createdBy': user.uid,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    return document.id;
  }

  Future<void> updateRecurringExpense({
    required String groupId,
    required String recurringExpenseId,
    required String title,
    required double amount,
    required String category,
    required String paidBy,
    required List<String> participants,
    required RecurrenceFrequency frequency,
    required DateTime nextDueDate,
    required bool isActive,
  }) async {
    if (_auth.currentUser == null) {
      throw StateError('You must be logged in.');
    }

    if (title.trim().isEmpty || amount <= 0) {
      throw ArgumentError(
        'Enter a valid title and amount.',
      );
    }

    if (participants.isEmpty) {
      throw ArgumentError(
        'Select at least one participant.',
      );
    }

    await _recurringCollection(groupId)
        .doc(recurringExpenseId)
        .update({
      'title': title.trim(),
      'amount': amount,
      'category': category.trim().isEmpty
          ? 'Other'
          : category.trim(),
      'paidBy': paidBy,
      'participants': participants,
      'frequency': frequency.name,
      'dayOfMonth': nextDueDate.day,
      'nextDueDate': Timestamp.fromDate(nextDueDate),
      'isActive': isActive,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Update generated recurring expenses for today/future.
// Historical expenses remain unchanged.

    final generatedExpenses = await _firestore
        .collection('groups')
        .doc(groupId)
        .collection('expenses')
        .where(
      'recurringExpenseId',
      isEqualTo: recurringExpenseId,
    )
        .get();

    QueryDocumentSnapshot<Map<String, dynamic>>? latestExpense;
    DateTime? latestDueDate;

    for (final expenseDocument in generatedExpenses.docs) {
      final data = expenseDocument.data();

      final dueTimestamp =
      data['recurringDueDate'] as Timestamp?;

      if (dueTimestamp == null) {
        continue;
      }

      final dueDate = dueTimestamp.toDate();

      if (latestDueDate == null ||
          dueDate.isAfter(latestDueDate)) {
        latestDueDate = dueDate;
        latestExpense = expenseDocument;
      }
    }

    if (latestExpense != null) {
      await latestExpense.reference.update({
        'title': title.trim(),
        'amount': amount,
        'category': category.trim().isEmpty
            ? 'Other'
            : category.trim(),
        'paidBy': paidBy,
        'participants': participants,
      });
    }

  }

  Future<void> setActive({
    required String groupId,
    required String recurringExpenseId,
    required bool isActive,
  }) async {
    if (_auth.currentUser == null) {
      throw StateError('You must be logged in.');
    }

    await _recurringCollection(groupId)
        .doc(recurringExpenseId)
        .update({
      'isActive': isActive,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteRecurringExpense({
    required String groupId,
    required String recurringExpenseId,
  }) async {
    if (_auth.currentUser == null) {
      throw StateError('You must be logged in.');
    }

    await _recurringCollection(groupId)
        .doc(recurringExpenseId)
        .delete();
  }

  DateTime calculateNextDueDate({
    required DateTime currentDueDate,
    required RecurrenceFrequency frequency,
  }) {
    switch (frequency) {
      case RecurrenceFrequency.weekly:
        return currentDueDate.add(
          const Duration(days: 7),
        );

      case RecurrenceFrequency.monthly:
        return _addOneMonth(currentDueDate);

      case RecurrenceFrequency.yearly:
        return _safeDate(
          year: currentDueDate.year + 1,
          month: currentDueDate.month,
          preferredDay: currentDueDate.day,
        );
    }
  }

  static DateTime _addOneMonth(DateTime date) {
    return _safeDate(
      year: date.year,
      month: date.month + 1,
      preferredDay: date.day,
    );
  }

  static DateTime _safeDate({
    required int year,
    required int month,
    required int preferredDay,
  }) {
    final normalizedStart = DateTime(year, month, 1);

    final lastDay = DateTime(
      normalizedStart.year,
      normalizedStart.month + 1,
      0,
    ).day;

    final day = preferredDay.clamp(1, lastDay);

    return DateTime(
      normalizedStart.year,
      normalizedStart.month,
      day,
    );
  }
  Future<int> generateDueExpenses(String groupId) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw StateError(
        'You must be logged in to generate recurring expenses.',
      );
    }

    final now = DateTime.now();

    final recurringSnapshot = await _recurringCollection(
      groupId,
    )
        .where('isActive', isEqualTo: true)
        .where(
      'nextDueDate',
      isLessThanOrEqualTo: Timestamp.fromDate(now),
    )
        .get();

    var generatedCount = 0;

    for (final recurringDocument
    in recurringSnapshot.docs) {
      final generated = await _firestore.runTransaction<bool>(
            (transaction) async {
          // Read the latest version inside the transaction.
          final freshDocument = await transaction.get(
            recurringDocument.reference,
          );

          if (!freshDocument.exists) {
            return false;
          }

          final recurring =
          RecurringExpenseModel.fromFirestore(
            freshDocument,
          );

          final transactionNow = DateTime.now();

          // Another device may already have processed it.
          if (!recurring.isActive ||
              recurring.nextDueDate.isAfter(
                transactionNow,
              )) {
            return false;
          }

          final dueDate = recurring.nextDueDate;

          // One deterministic expense ID per recurring occurrence.
          final occurrenceId =
              '${recurring.id}_${dueDate.millisecondsSinceEpoch}';

          final expenseReference = _firestore
              .collection('groups')
              .doc(groupId)
              .collection('expenses')
              .doc(occurrenceId);

          final existingExpense = await transaction.get(
            expenseReference,
          );

          final nextDueDate = calculateNextDueDate(
            currentDueDate: dueDate,
            frequency: recurring.frequency,
          );

          if (!existingExpense.exists) {
            transaction.set(
              expenseReference,
              {
                'title': recurring.title,
                'amount': recurring.amount,
                'category': recurring.category,
                'paidBy': recurring.paidBy,
                'groupId': groupId,
                'participants': recurring.participants,

                // Use the scheduled due date so analytics and
                // monthly budget calculations place it correctly.
                'createdAt': Timestamp.fromDate(dueDate),

                'generatedFromRecurring': true,
                'recurringExpenseId': recurring.id,
                'recurringOccurrenceId': occurrenceId,
                'recurringDueDate':
                Timestamp.fromDate(dueDate),
                'generatedAt':
                FieldValue.serverTimestamp(),
              },
            );
          }

          // Advance the recurring record even if the matching
          // expense already exists from an earlier attempt.
          transaction.update(
            freshDocument.reference,
            {
              'lastGeneratedAt':
              FieldValue.serverTimestamp(),
              'lastGeneratedDueDate':
              Timestamp.fromDate(dueDate),
              'nextDueDate':
              Timestamp.fromDate(nextDueDate),
              'updatedAt':
              FieldValue.serverTimestamp(),
            },
          );

          return !existingExpense.exists;
        },
      );

      if (generated) {
        generatedCount++;
      }
    }

    return generatedCount;
  }
}