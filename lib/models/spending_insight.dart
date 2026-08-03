import 'package:flutter/material.dart';

enum InsightType {
  positive,
  warning,
  information,
}

class SpendingInsight {
  final String title;
  final String message;
  final IconData icon;
  final InsightType type;

  const SpendingInsight({
    required this.title,
    required this.message,
    required this.icon,
    required this.type,
  });
}