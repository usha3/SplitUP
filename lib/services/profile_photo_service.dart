import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

class ProfilePhotoService {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  ProfilePhotoService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance;

  Future<String> uploadProfilePhoto(File file) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw StateError('You must be logged in.');
    }

    final extension = _fileExtension(file.path);

    final folder = _storage.ref().child(
      'profile_photos/${user.uid}',
    );

    final timestamp = DateTime.now().millisecondsSinceEpoch;

    final reference = folder.child(
      'profile_$timestamp.$extension',
    );

    await reference.putFile(
      file,
      SettableMetadata(
        contentType: _contentType(extension),
        cacheControl: 'no-cache',
      ),
    );

    final downloadUrl = await reference.getDownloadURL();

    await user.updatePhotoURL(downloadUrl);
    await user.reload();

    await _firestore.collection('users').doc(user.uid).set(
      {
        'photoUrl': downloadUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    return downloadUrl;
  }

  Future<void> deleteProfilePhoto() async {
    final user = _auth.currentUser;

    if (user == null) {
      throw StateError('You must be logged in.');
    }

    final folder = _storage.ref().child(
      'profile_photos/${user.uid}',
    );

    final result = await folder.listAll();

    for (final item in result.items) {
      await item.delete();
    }

    await user.updatePhotoURL(null);
    await user.reload();

    await _firestore.collection('users').doc(user.uid).set(
      {
        'photoUrl': '',
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  static String _fileExtension(String path) {
    final extension = path.split('.').last.toLowerCase();

    if (extension == 'png') {
      return 'png';
    }

    return 'jpg';
  }

  static String _contentType(String extension) {
    return extension == 'png' ? 'image/png' : 'image/jpeg';
  }
}