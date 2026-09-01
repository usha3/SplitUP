import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/settlement_model.dart';
import 'package:flutter/foundation.dart';

import '../services/in_app_notification_service.dart';

class SettlementService {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  final InAppNotificationService
  _inAppNotificationService;

  SettlementService({
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

  Stream<List<SettlementModel>> getGroupSettlements(
      String groupId,
      ) {
    return _firestore
        .collection('groups')
        .doc(groupId)
        .collection('settlements')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
          .map(SettlementModel.fromFirestore)
          .toList(),
    );
  }

  Future<void> _createSettlementNotification({
    required String groupId,
    required String settlementId,
    required String fromUserId,
    required String toUserId,
    required double amount,
    required String createdByUserId,
  }) async {
    try {
      // Guests do not have accounts.
      if (toUserId.startsWith('guest_')) {
        return;
      }

      // Avoid notifying the same user about
      // an action they just recorded for themselves.
      if (toUserId == createdByUserId) {
        return;
      }

      final groupDocument = await _firestore
          .collection('groups')
          .doc(groupId)
          .get();

      final groupData =
          groupDocument.data() ?? {};

      final groupName =
          groupData['name']
              ?.toString()
              .trim() ??
              'your group';

      String payerName = 'A member';

      final rawMemberDetails =
      groupData['memberDetails'];

      if (rawMemberDetails is Map) {
        final memberDetails =
        Map<String, dynamic>.from(
          rawMemberDetails,
        );

        final rawPayer =
        memberDetails[fromUserId];

        if (rawPayer is Map) {
          final payerDetails =
          Map<String, dynamic>.from(
            rawPayer,
          );

          final name =
              payerDetails['name']
                  ?.toString()
                  .trim() ??
                  '';

          if (name.isNotEmpty) {
            payerName = name;
          }
        }
      }

      if (payerName == 'A member' &&
          !fromUserId.startsWith('guest_')) {
        final userDocument = await _firestore
            .collection('users')
            .doc(fromUserId)
            .get();

        final userData =
            userDocument.data() ?? {};

        final name =
            userData['name']
                ?.toString()
                .trim() ??
                '';

        final email =
            userData['email']
                ?.toString()
                .trim() ??
                '';

        if (name.isNotEmpty) {
          payerName = name;
        } else if (email.isNotEmpty) {
          payerName = email;
        }
      }

      await _inAppNotificationService
          .createNotification(
        userId: toUserId,
        type: 'settlement_recorded',
        title: 'Payment recorded',
        message:
        '$payerName recorded a payment of '
            '\$${amount.toStringAsFixed(2)} '
            'to you in $groupName.',
        groupId: groupId,
        settlementId: settlementId,
      );
    } catch (error) {
      debugPrint(
        'Unable to create settlement notification: '
            '$error',
      );
    }
  }

  Future<String> recordSettlement({
    required String groupId,
    required String fromUserId,
    required String toUserId,
    required double amount,
    String paymentMethod = 'other',
    String? proofUrl,
    String? proofFileName,
  }) async {
    final currentUser = _auth.currentUser;

    if (currentUser == null) {
      throw StateError('You must be logged in.');
    }

    if (fromUserId == toUserId) {
      throw ArgumentError(
        'The payer and recipient cannot be the same.',
      );
    }

    if (amount <= 0) {
      throw ArgumentError(
        'Settlement amount must be greater than zero.',
      );
    }

    final document = _firestore
        .collection('groups')
        .doc(groupId)
        .collection('settlements')
        .doc();

    final settlement = SettlementModel(
      id: document.id,
      groupId: groupId,
      fromUserId: fromUserId,
      toUserId: toUserId,
      amount: amount,
      createdBy: currentUser.uid,
      paymentMethod: paymentMethod,
      proofUrl: proofUrl,
      proofFileName: proofFileName,
    );

    await document.set(
      settlement.toFirestore(),
    );

    await _createSettlementNotification(
      groupId: groupId,
      settlementId: document.id,
      fromUserId: fromUserId,
      toUserId: toUserId,
      amount: amount,
      createdByUserId: currentUser.uid,
    );

    return document.id;
  }
}