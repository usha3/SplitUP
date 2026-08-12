import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/recurring_expense_model.dart';
import 'package:flutter/foundation.dart';

import '../services/in_app_notification_service.dart';

class RecurringExpenseService {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  final InAppNotificationService
  _inAppNotificationService;

  RecurringExpenseService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    InAppNotificationService?
    inAppNotificationService,
  })  : _firestore =
      firestore ?? FirebaseFirestore.instance,
        _auth =
            auth ?? FirebaseAuth.instance,
        _inAppNotificationService =
            inAppNotificationService ??
                InAppNotificationService();

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

  Future<void> _createRecurringNotifications({
    required String groupId,
    required String expenseId,
    required String title,
    required double amount,
    required List<String> participants,
    required Map<String, double> shares,
  }) async {
    try {
      final groupDocument = await _firestore
          .collection('groups')
          .doc(groupId)
          .get();

      final groupData =
          groupDocument.data() ?? {};

      final groupName =
      groupData['name']?.toString().trim().isNotEmpty == true
          ? groupData['name'].toString().trim()
          : 'your group';

      for (final participantId in participants) {
        // Guests do not have an account/device notification inbox.
        if (participantId.startsWith('guest_')) {
          continue;
        }

        final participantShare =
            shares[participantId] ??
                (participants.isNotEmpty
                    ? amount / participants.length
                    : 0);

        await _inAppNotificationService
            .createNotification(
          userId: participantId,
          type: 'recurring_expense',
          title: 'Recurring expense added',
          message:
          '$title was automatically added in $groupName. '
              'Your share is '
              '\$${participantShare.toStringAsFixed(2)}.',
          groupId: groupId,
          expenseId: expenseId,
        );
      }
    } catch (error) {
      debugPrint(
        'Unable to create recurring expense notifications: '
            '$error',
      );
    }
  }

  Future<int> generateDueExpenses(
      String groupId,
      ) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw StateError(
        'You must be logged in to generate recurring expenses.',
      );
    }

    final now = DateTime.now();

    final recurringSnapshot =
    await _recurringCollection(groupId)
        .where(
      'isActive',
      isEqualTo: true,
    )
        .where(
      'nextDueDate',
      isLessThanOrEqualTo:
      Timestamp.fromDate(now),
    )
        .get();

    var generatedCount = 0;

    for (final recurringDocument
    in recurringSnapshot.docs) {
      final generatedInfo =
      await _firestore.runTransaction<
          _GeneratedRecurringExpense?>(
            (transaction) async {
          final freshDocument =
          await transaction.get(
            recurringDocument.reference,
          );

          if (!freshDocument.exists) {
            return null;
          }

          final recurring =
          RecurringExpenseModel.fromFirestore(
            freshDocument,
          );

          final transactionNow =
          DateTime.now();

          // Another device may already have
          // processed this recurring expense.
          if (!recurring.isActive ||
              recurring.nextDueDate.isAfter(
                transactionNow,
              )) {
            return null;
          }

          final dueDate =
              recurring.nextDueDate;

          // Recurring expenses currently use
          // equal splitting.
          final shares =
          <String, double>{};

          if (recurring
              .participants.isNotEmpty) {
            final share =
                recurring.amount /
                    recurring
                        .participants.length;

            for (final participantId
            in recurring.participants) {
              shares[participantId] =
                  share;
            }
          }

          // Deterministic ID prevents duplicate
          // expenses for the same occurrence.
          final occurrenceId =
              '${recurring.id}_'
              '${dueDate.millisecondsSinceEpoch}';

          final expenseReference =
          _firestore
              .collection('groups')
              .doc(groupId)
              .collection('expenses')
              .doc(occurrenceId);

          final existingExpense =
          await transaction.get(
            expenseReference,
          );

          final nextDueDate =
          calculateNextDueDate(
            currentDueDate: dueDate,
            frequency:
            recurring.frequency,
          );

          if (!existingExpense.exists) {
            transaction.set(
              expenseReference,
              {
                'title':
                recurring.title,
                'amount':
                recurring.amount,
                'category':
                recurring.category,
                'paidBy':
                recurring.paidBy,
                'groupId':
                groupId,
                'participants':
                recurring.participants,

                'splitType': 'equal',
                'items': const [],
                'shares': shares,

                // Use the scheduled due date
                // for analytics/budget placement.
                'createdAt':
                Timestamp.fromDate(
                  dueDate,
                ),

                'generatedFromRecurring':
                true,
                'recurringExpenseId':
                recurring.id,
                'recurringOccurrenceId':
                occurrenceId,
                'recurringDueDate':
                Timestamp.fromDate(
                  dueDate,
                ),
                'generatedAt':
                FieldValue
                    .serverTimestamp(),
              },
            );
          }

          // Always advance the recurring record,
          // even if this occurrence already exists.
          transaction.update(
            freshDocument.reference,
            {
              'lastGeneratedAt':
              FieldValue
                  .serverTimestamp(),
              'lastGeneratedDueDate':
              Timestamp.fromDate(
                dueDate,
              ),
              'nextDueDate':
              Timestamp.fromDate(
                nextDueDate,
              ),
              'updatedAt':
              FieldValue
                  .serverTimestamp(),
            },
          );

          // If another attempt already generated
          // this occurrence, don't notify again.
          if (existingExpense.exists) {
            return null;
          }

          return _GeneratedRecurringExpense(
            expenseId: occurrenceId,
            title: recurring.title,
            amount: recurring.amount,
            participants:
            List<String>.from(
              recurring.participants,
            ),
            shares:
            Map<String, double>.from(
              shares,
            ),
          );
        },
      );

      if (generatedInfo != null) {
        generatedCount++;

        await _createRecurringNotifications(
          groupId: groupId,
          expenseId:
          generatedInfo.expenseId,
          title:
          generatedInfo.title,
          amount:
          generatedInfo.amount,
          participants:
          generatedInfo.participants,
          shares:
          generatedInfo.shares,
        );
      }
    }

    return generatedCount;
  }
}

  class _GeneratedRecurringExpense {
  final String expenseId;
  final String title;
  final double amount;
  final List<String> participants;
  final Map<String, double> shares;

  const _GeneratedRecurringExpense({
  required this.expenseId,
  required this.title,
  required this.amount,
  required this.participants,
  required this.shares,
  });
  }