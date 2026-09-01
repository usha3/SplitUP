import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

class SettlementProofUploadResult {
  final String downloadUrl;
  final String fileName;

  const SettlementProofUploadResult({
    required this.downloadUrl,
    required this.fileName,
  });
}

class SettlementProofService {
  final FirebaseAuth _auth;
  final FirebaseStorage _storage;

  SettlementProofService({
    FirebaseAuth? auth,
    FirebaseStorage? storage,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _storage = storage ?? FirebaseStorage.instance;

  Future<SettlementProofUploadResult> uploadProof({
    required File file,
    required String groupId,
  }) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw StateError(
        'You must be logged in.',
      );
    }

    final extension =
    _fileExtension(file.path);

    final timestamp =
        DateTime.now().millisecondsSinceEpoch;

    final fileName =
        'settlement_proof_$timestamp.$extension';

    final reference = _storage
        .ref()
        .child(
      'settlement_proofs/$groupId/${user.uid}/$fileName',
    );

    await reference.putFile(
      file,
      SettableMetadata(
        contentType:
        _contentType(extension),
        cacheControl: 'no-cache',
      ),
    );

    final downloadUrl =
    await reference.getDownloadURL();

    return SettlementProofUploadResult(
      downloadUrl: downloadUrl,
      fileName: fileName,
    );
  }

  Future<void> deleteProofByUrl(
      String proofUrl,
      ) async {
    if (proofUrl.trim().isEmpty) {
      return;
    }

    try {
      final reference =
      _storage.refFromURL(proofUrl);

      await reference.delete();
    } catch (_) {
      // Proof cleanup should not break
      // settlement operations.
    }
  }

  static String _fileExtension(
      String path,
      ) {
    final extension =
    path.split('.').last.toLowerCase();

    if (extension == 'png') {
      return 'png';
    }

    if (extension == 'jpeg') {
      return 'jpg';
    }

    return 'jpg';
  }

  static String _contentType(
      String extension,
      ) {
    return extension == 'png'
        ? 'image/png'
        : 'image/jpeg';
  }
}