import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/group_model.dart';
import '../models/user_model.dart';

class GroupService {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  GroupService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  Stream<List<GroupModel>> getCurrentUserGroups() {
    final user = _auth.currentUser;

    if (user == null) {
      return Stream.value([]);
    }

    return _firestore
        .collection('groups')
        .where('members', arrayContains: user.uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) =>
          snapshot.docs.map(GroupModel.fromFirestore).toList(),
    );
  }

  Stream<GroupModel?> watchGroup(String groupId) {
    return _firestore
        .collection('groups')
        .doc(groupId)
        .snapshots()
        .map((document) {
      if (!document.exists) {
        return null;
      }

      return GroupModel.fromFirestore(document);
    });
  }

  Future<String> createGroup({
    required String name,
    required String description,
  }) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw StateError('You must be logged in to create a group.');
    }

    final document = _firestore.collection('groups').doc();

    await document.set({
      'name': name.trim(),
      'description': description.trim(),
      'createdBy': user.uid,
      'members': [user.uid],
      'memberDetails': {
        user.uid: {
          'name': user.displayName?.trim() ?? '',
          'email': user.email?.trim().toLowerCase() ?? '',
          'isGuest': false,
        },
      },
      'createdAt': FieldValue.serverTimestamp(),
    });

    return document.id;
  }

  Future<void> addMember({
    required String groupId,
    required String userId,
  }) async {
    final currentUser = _auth.currentUser;

    if (currentUser == null) {
      throw StateError('You must be logged in.');
    }

    await _firestore.collection('groups').doc(groupId).update({
      'members': FieldValue.arrayUnion([userId]),
    });
  }

  Future<void> addRegisteredMember({
    required String groupId,
    required UserModel user,
  }) async {
    final currentUser = _auth.currentUser;

    if (currentUser == null) {
      throw StateError('You must be logged in.');
    }

    await _firestore.collection('groups').doc(groupId).update({
      'members': FieldValue.arrayUnion([user.uid]),
      'memberDetails.${user.uid}': {
        'name': user.name.trim(),
        'email': user.email.trim().toLowerCase(),
        'isGuest': false,
      },
    });
  }

  Future<String> addGuestMember({
    required String groupId,
    required String name,
    String email = '',
  }) async {
    final currentUser = _auth.currentUser;

    if (currentUser == null) {
      throw StateError('You must be logged in.');
    }

    final trimmedName = name.trim();

    if (trimmedName.isEmpty) {
      throw ArgumentError('Guest name is required.');
    }

    final guestId = 'guest_${DateTime.now().microsecondsSinceEpoch}';

    await _firestore.collection('groups').doc(groupId).update({
      'members': FieldValue.arrayUnion([guestId]),
      'memberDetails.$guestId': {
        'name': trimmedName,
        'email': email.trim().toLowerCase(),
        'isGuest': true,
        'addedAt': FieldValue.serverTimestamp(),
      },
    });

    return guestId;
  }

  Future<void> removeMember({
    required String groupId,
    required String userId,
  }) async {
    final currentUser = _auth.currentUser;

    if (currentUser == null) {
      throw StateError('You must be logged in.');
    }

    final groupDocument =
    await _firestore.collection('groups').doc(groupId).get();

    if (!groupDocument.exists) {
      throw StateError('Group not found.');
    }

    final data = groupDocument.data() ?? {};

    if (data['createdBy'] == userId) {
      throw StateError('The group creator cannot be removed.');
    }

    await groupDocument.reference.update({
      'members': FieldValue.arrayRemove([userId]),
      'memberDetails.$userId': FieldValue.delete(),
    });
  }

  Future<void> deleteGroup(String groupId) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw StateError('You must be logged in.');
    }

    final document =
    await _firestore.collection('groups').doc(groupId).get();

    if (!document.exists) {
      throw StateError('Group not found.');
    }

    final data = document.data();

    if (data?['createdBy'] != user.uid) {
      throw StateError('Only the group creator can delete this group.');
    }

    await document.reference.delete();
  }
}