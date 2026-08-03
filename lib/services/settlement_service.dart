import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/settlement_model.dart';

class SettlementService {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  SettlementService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

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

  Future<String> recordSettlement({
    required String groupId,
    required String fromUserId,
    required String toUserId,
    required double amount,
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
    );

    await document.set(settlement.toFirestore());

    return document.id;
  }
}