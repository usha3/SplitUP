# SplitUP

SplitUP is a cross-platform expense-sharing application built with Flutter and Firebase. It helps roommates, friends, families, and travel groups record shared expenses, manage members, calculate balances, and settle debts.

## Features

- Email and password authentication
- Password reset
- Automatic login
- Create and manage expense groups
- Add registered and guest members
- Add, edit, and delete expenses
- Select expense participants
- Equal expense splitting
- Real-time Firestore synchronization
- Automatic balance calculation
- Debt simplification
- Partial and full settlements
- Settlement history
- Live financial dashboard
- Monthly spending analytics
- Category-based pie charts
- Light, dark, and system themes
- Edit profile and change password
- Material 3 interface

## Technology Stack

- Flutter
- Dart
- Firebase Authentication
- Cloud Firestore
- Provider
- fl_chart
- Material 3

## Project Structure

```text
lib/
├── core/
│   └── theme/
├── models/
├── providers/
├── screens/
│   ├── analytics/
│   ├── auth/
│   ├── groups/
│   ├── home/
│   └── profile/
├── services/
├── firebase_options.dart
└── main.dart
