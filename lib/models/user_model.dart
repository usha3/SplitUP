import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String name;
  final String email;
  final String photoUrl;
  final DateTime? createdAt;

  /// Payment handles used when other SplitUp members
  /// settle balances with this user.
  ///
  /// Supported keys:
  /// - venmo
  /// - paypal
  /// - cashApp
  final Map<String, String> paymentMethods;

  const UserModel({
    required this.uid,
    required this.name,
    required this.email,
    this.photoUrl = '',
    this.createdAt,
    this.paymentMethods = const {},
  });

  factory UserModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> document,
      ) {
    final data = document.data() ?? {};

    final rawPaymentMethods =
    data['paymentMethods'];

    final paymentMethods = <String, String>{};

    if (rawPaymentMethods is Map) {
      rawPaymentMethods.forEach((key, value) {
        final normalizedKey = key.toString();
        final normalizedValue =
            value?.toString().trim() ?? '';

        if (normalizedValue.isNotEmpty) {
          paymentMethods[normalizedKey] =
              normalizedValue;
        }
      });
    }

    return UserModel(
      uid: data['uid'] as String? ?? document.id,
      name: data['name'] as String? ?? '',
      email: data['email'] as String? ?? '',
      photoUrl: data['photoUrl'] as String? ?? '',
      createdAt: _toDateTime(data['createdAt']),
      paymentMethods: paymentMethods,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'uid': uid,
      'name': name,
      'email': email,
      'photoUrl': photoUrl,
      'createdAt':
      createdAt ?? FieldValue.serverTimestamp(),
      'paymentMethods': paymentMethods,
    };
  }

  UserModel copyWith({
    String? uid,
    String? name,
    String? email,
    String? photoUrl,
    DateTime? createdAt,
    Map<String, String>? paymentMethods,
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      name: name ?? this.name,
      email: email ?? this.email,
      photoUrl: photoUrl ?? this.photoUrl,
      createdAt: createdAt ?? this.createdAt,
      paymentMethods:
      paymentMethods ?? this.paymentMethods,
    );
  }

  static DateTime? _toDateTime(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    return null;
  }
}