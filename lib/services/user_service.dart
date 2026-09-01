import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/user_model.dart';

class UserService {
  final FirebaseFirestore _firestore;

  UserService({
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  Future<UserModel?> getUserById(String uid) async {
    final document =
    await _firestore.collection('users').doc(uid).get();

    if (!document.exists) {
      return null;
    }

    return UserModel.fromFirestore(document);
  }

  Future<Map<String, UserModel>> getUsersByIds(
      List<String> ids,
      ) async {
    final users = <String, UserModel>{};

    for (final id in ids) {
      final document =
      await _firestore.collection('users').doc(id).get();

      if (document.exists) {
        users[id] = UserModel.fromFirestore(document);
      }
    }

    return users;
  }

  Future<UserModel?> findUserByEmail(String email) async {
    final normalizedEmail = email.trim().toLowerCase();

    final snapshot = await _firestore
        .collection('users')
        .where(
      'email',
      isEqualTo: normalizedEmail,
    )
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) {
      return null;
    }

    return UserModel.fromFirestore(
      snapshot.docs.first,
    );
  }
}