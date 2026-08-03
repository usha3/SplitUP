import 'package:cloud_firestore/cloud_firestore.dart';

class GroupModel {
  final String id;
  final String name;
  final String description;
  final String createdBy;
  final List<String> members;
  final DateTime? createdAt;

  const GroupModel({
    required this.id,
    required this.name,
    required this.description,
    required this.createdBy,
    required this.members,
    this.createdAt,
  });

  factory GroupModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> document,
      ) {
    final data = document.data() ?? {};

    return GroupModel(
      id: document.id,
      name: data['name'] as String? ?? '',
      description: data['description'] as String? ?? '',
      createdBy: data['createdBy'] as String? ?? '',
      members: List<String>.from(
        data['members'] as List<dynamic>? ?? const [],
      ),
      createdAt: _toDateTime(data['createdAt']),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'description': description,
      'createdBy': createdBy,
      'members': members,
      'createdAt': createdAt ?? FieldValue.serverTimestamp(),
    };
  }

  GroupModel copyWith({
    String? id,
    String? name,
    String? description,
    String? createdBy,
    List<String>? members,
    DateTime? createdAt,
  }) {
    return GroupModel(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      createdBy: createdBy ?? this.createdBy,
      members: members ?? this.members,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  static DateTime? _toDateTime(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }

    return null;
  }
}