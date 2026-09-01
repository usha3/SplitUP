import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

class AccountService {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  AccountService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance;

  Future<void> deleteCurrentUserAccount() async {
    final user = _auth.currentUser;

    if (user == null) {
      throw StateError('No signed-in user found.');
    }

    final uid = user.uid;
    final photoUrl = user.photoURL?.trim() ?? '';

    debugPrint('DELETE ACCOUNT: deleting notifications');

    await _deleteCollection(
      _firestore
          .collection('users')
          .doc(uid)
          .collection('notifications'),
    );

    debugPrint('DELETE ACCOUNT: notifications deleted');

    debugPrint('DELETE ACCOUNT: deleting tokens');

    await _deleteCollection(
      _firestore
          .collection('users')
          .doc(uid)
          .collection('tokens'),
    );

    debugPrint('DELETE ACCOUNT: tokens deleted');

    if (photoUrl.isNotEmpty) {
      debugPrint('DELETE ACCOUNT: deleting profile photo');

      try {
        await _storage.refFromURL(photoUrl).delete();
        debugPrint('DELETE ACCOUNT: profile photo deleted');
      } catch (error) {
        debugPrint(
          'DELETE ACCOUNT: profile photo delete skipped: $error',
        );
      }
    }

    debugPrint('DELETE ACCOUNT: anonymizing user document');

    await _firestore.collection('users').doc(uid).set(
      {
        'uid': uid,
        'name': 'Deleted user',
        'email': '',
        'photoUrl': '',
        'accountDeleted': true,
        'deletedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: false),
    );

    debugPrint('DELETE ACCOUNT: user document anonymized');

    try {
      debugPrint('DELETE ACCOUNT: clearing auth profile');

      await user.updateDisplayName(null);
      await user.updatePhotoURL(null);

      debugPrint('DELETE ACCOUNT: auth profile cleared');
    } catch (error) {
      debugPrint(
        'DELETE ACCOUNT: auth profile clearing skipped: $error',
      );
    }

    debugPrint('DELETE ACCOUNT: deleting Firebase Auth user');

    await user.delete();

    debugPrint('DELETE ACCOUNT: Firebase Auth user deleted');
  }

  Future<void> _deleteCollection(
      CollectionReference<Map<String, dynamic>> collection,
      ) async {
    const batchSize = 100;

    while (true) {
      final snapshot = await collection.limit(batchSize).get();

      if (snapshot.docs.isEmpty) {
        break;
      }

      final batch = _firestore.batch();

      for (final document in snapshot.docs) {
        batch.delete(document.reference);
      }

      await batch.commit();

      if (snapshot.docs.length < batchSize) {
        break;
      }
    }
  }
}