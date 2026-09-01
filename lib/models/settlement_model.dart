import 'package:cloud_firestore/cloud_firestore.dart';

class SettlementModel {
  final String id;
  final String groupId;
  final String fromUserId;
  final String toUserId;
  final double amount;
  final String createdBy;
  final String paymentMethod;

  /// Optional Firebase Storage URL for a payment screenshot/receipt.
  final String? proofUrl;

  /// Optional original file name shown in the UI.
  final String? proofFileName;

  final DateTime? createdAt;

  const SettlementModel({
    required this.id,
    required this.groupId,
    required this.fromUserId,
    required this.toUserId,
    required this.amount,
    required this.createdBy,
    this.paymentMethod = 'other',
    this.proofUrl,
    this.proofFileName,
    this.createdAt,
  });

  factory SettlementModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> document,
      ) {
    final data = document.data() ?? {};

    final rawProofUrl =
        data['proofUrl']?.toString().trim() ?? '';

    final rawProofFileName =
        data['proofFileName']?.toString().trim() ?? '';

    return SettlementModel(
      id: document.id,
      groupId:
      data['groupId'] as String? ?? '',
      fromUserId:
      data['fromUserId'] as String? ?? '',
      toUserId:
      data['toUserId'] as String? ?? '',
      amount: _toDouble(
        data['amount'],
      ),
      createdBy:
      data['createdBy'] as String? ?? '',
      paymentMethod:
      data['paymentMethod']
          ?.toString()
          .trim() ??
          'other',
      proofUrl:
      rawProofUrl.isEmpty
          ? null
          : rawProofUrl,
      proofFileName:
      rawProofFileName.isEmpty
          ? null
          : rawProofFileName,
      createdAt: _toDateTime(
        data['createdAt'],
      ),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'groupId': groupId,
      'fromUserId': fromUserId,
      'toUserId': toUserId,
      'amount': amount,
      'createdBy': createdBy,
      'paymentMethod': paymentMethod,

      if (proofUrl != null &&
          proofUrl!.trim().isNotEmpty)
        'proofUrl': proofUrl!.trim(),

      if (proofFileName != null &&
          proofFileName!.trim().isNotEmpty)
        'proofFileName':
        proofFileName!.trim(),

      'createdAt':
      createdAt ??
          FieldValue.serverTimestamp(),
    };
  }

  SettlementModel copyWith({
    String? id,
    String? groupId,
    String? fromUserId,
    String? toUserId,
    double? amount,
    String? createdBy,
    String? paymentMethod,
    String? proofUrl,
    String? proofFileName,
    DateTime? createdAt,
  }) {
    return SettlementModel(
      id: id ?? this.id,
      groupId: groupId ?? this.groupId,
      fromUserId:
      fromUserId ?? this.fromUserId,
      toUserId:
      toUserId ?? this.toUserId,
      amount: amount ?? this.amount,
      createdBy:
      createdBy ?? this.createdBy,
      paymentMethod:
      paymentMethod ??
          this.paymentMethod,
      proofUrl:
      proofUrl ?? this.proofUrl,
      proofFileName:
      proofFileName ??
          this.proofFileName,
      createdAt:
      createdAt ?? this.createdAt,
    );
  }

  static double _toDouble(
      dynamic value,
      ) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(
      value?.toString() ?? '',
    ) ??
        0;
  }

  static DateTime? _toDateTime(
      dynamic value,
      ) {
    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    if (value is int) {
      return DateTime
          .fromMillisecondsSinceEpoch(
        value,
      );
    }

    return null;
  }
}