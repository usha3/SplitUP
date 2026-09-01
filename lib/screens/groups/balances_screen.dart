import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/debt_model.dart';
import '../../models/expense_model.dart';
import '../../models/group_model.dart';
import '../../models/settlement_model.dart';
import '../../services/balance_service.dart';
import '../../services/expense_service.dart';
import '../../services/settlement_service.dart';
import '../../services/user_service.dart';
import '../../utils/currency_formatter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/in_app_notification_service.dart';

import 'dart:io';

import 'package:image_picker/image_picker.dart';

import '../../services/settlement_proof_service.dart';

enum _PaymentMethod {
  venmo,
  paypal,
  cashApp,
  zelle,
  cash,
  bankTransfer,
  other,
}

class BalancesScreen extends StatefulWidget {
  final GroupModel group;

  const BalancesScreen({
    super.key,
    required this.group,
  });

  @override
  State<BalancesScreen> createState() => _BalancesScreenState();
}

class _BalancesScreenState extends State<BalancesScreen>
    with WidgetsBindingObserver {
  DebtModel? _pendingDebt;
  double? _pendingAmount;
  _PaymentMethod? _pendingPaymentMethod;
  Map<String, String> _memberNames = {};
  bool _openingPaymentApp = false;
  bool _confirmationDialogShowing = false;

  GroupModel get group => widget.group;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _openingPaymentApp &&
        _pendingDebt != null &&
        _pendingAmount != null &&
        _pendingPaymentMethod != null) {
      _openingPaymentApp = false;

      Future.delayed(
        const Duration(milliseconds: 500),
            () {
          if (!mounted) {
            return;
          }

          _showPaymentConfirmation();
        },
      );
    }
  }
  void _openPaymentProof({
    required BuildContext context,
    required String proofUrl,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(
            title: const Text('Payment Proof'),
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4,
              child: Image.network(
                proofUrl,
                fit: BoxFit.contain,
                loadingBuilder: (
                    context,
                    child,
                    loadingProgress,
                    ) {
                  if (loadingProgress == null) {
                    return child;
                  }

                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                },
                errorBuilder: (
                    context,
                    error,
                    stackTrace,
                    ) {
                  return const Center(
                    child: Text(
                      'Unable to load payment proof.',
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
  // ---------------------------------------------------------------------------
  // SETTLE UP FLOW
  // ---------------------------------------------------------------------------

  Future<void> _settleDebt({
    required BuildContext context,
    required DebtModel debt,
    required SettlementService settlementService,
  }) async {
    final amountController = TextEditingController(
      text: debt.amount.toStringAsFixed(2),
    );

    final formKey = GlobalKey<FormState>();

    final confirmedAmount = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Settle up'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${_memberName(debt.fromUserId)} owes '
                      '${_memberName(debt.toUserId)} '
                      '${formatCurrency(debt.amount, group.currencyCode)}.',
                ),
                const SizedBox(height: 12),
                const Text(
                  'Enter the amount you are paying now.',
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: amountController,
                  autofocus: true,
                  keyboardType:
                  const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Payment amount',
                    prefixIcon: Icon(Icons.attach_money),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final amount = double.tryParse(
                      value?.trim() ?? '',
                    );

                    if (amount == null || amount <= 0) {
                      return 'Enter a valid payment amount';
                    }

                    if (amount > debt.amount + 0.01) {
                      return 'Amount cannot exceed the current debt';
                    }

                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) {
                  Navigator.of(dialogContext).pop(true);
                }
              },
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );

    if (confirmedAmount != true) {
      // Give the dialog time to completely leave the widget tree
      // before disposing its controller.
      await Future.delayed(
        const Duration(milliseconds: 350),
      );

      amountController.dispose();
      return;
    }

    final amount = double.parse(
      amountController.text.trim(),
    );

// IMPORTANT:
// showDialog() completes as soon as Navigator.pop() is called,
// but the dialog dismissal animation is still running.
//
// Do not immediately dispose the controller or open another route.
    await Future.delayed(
      const Duration(milliseconds: 350),
    );

    amountController.dispose();

    if (!mounted) {
      return;
    }

    await _choosePaymentMethod(
      debt: debt,
      amount: amount,
      settlementService: settlementService,
    );
  }

  Future<void> _choosePaymentMethod({
    required DebtModel debt,
    required double amount,
    required SettlementService settlementService,
  }) async {
    final method =
    await showModalBottomSheet<_PaymentMethod>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                20,
                8,
                20,
                24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment:
                CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'How would you like to pay?',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(
                      fontWeight:
                      FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    formatCurrency(
                      amount,
                      group.currencyCode,
                    ),
                  ),

                  const SizedBox(height: 20),

                  _PaymentMethodTile(
                    icon: Icons
                        .account_balance_wallet_outlined,
                    title: 'Venmo',
                    subtitle: 'Pay using Venmo',
                    onTap: () {
                      Navigator.of(sheetContext).pop(
                        _PaymentMethod.venmo,
                      );
                    },
                  ),

                  _PaymentMethodTile(
                    icon: Icons.payments_outlined,
                    title: 'PayPal',
                    subtitle: 'Pay using PayPal',
                    onTap: () {
                      Navigator.of(sheetContext).pop(
                        _PaymentMethod.paypal,
                      );
                    },
                  ),

                  _PaymentMethodTile(
                    icon: Icons.attach_money,
                    title: 'Cash App',
                    subtitle: 'Pay using Cash App',
                    onTap: () {
                      Navigator.of(sheetContext).pop(
                        _PaymentMethod.cashApp,
                      );
                    },
                  ),

                  _PaymentMethodTile(
                    icon: Icons
                        .account_balance_outlined,
                    title: 'Zelle',
                    subtitle:
                    'Record a payment made with Zelle',
                    onTap: () {
                      Navigator.of(sheetContext).pop(
                        _PaymentMethod.zelle,
                      );
                    },
                  ),

                  _PaymentMethodTile(
                    icon: Icons.money_outlined,
                    title: 'Cash',
                    subtitle:
                    'Record a cash payment',
                    onTap: () {
                      Navigator.of(sheetContext).pop(
                        _PaymentMethod.cash,
                      );
                    },
                  ),

                  _PaymentMethodTile(
                    icon: Icons
                        .account_balance_outlined,
                    title: 'Bank Transfer',
                    subtitle:
                    'Record a bank transfer',
                    onTap: () {
                      Navigator.of(sheetContext).pop(
                        _PaymentMethod.bankTransfer,
                      );
                    },
                  ),

                  _PaymentMethodTile(
                    icon: Icons.more_horiz,
                    title: 'Other',
                    subtitle:
                    'Record another payment method',
                    onTap: () {
                      Navigator.of(sheetContext).pop(
                        _PaymentMethod.other,
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (method == null || !mounted) {
      return;
    }

    // These methods are recorded manually.
    if (method == _PaymentMethod.zelle ||
        method == _PaymentMethod.cash ||
        method == _PaymentMethod.bankTransfer ||
        method == _PaymentMethod.other) {
      await _showManualPaymentConfirmation(
        debt: debt,
        amount: amount,
        method: method,
        settlementService: settlementService,
      );

      return;
    }

    // Venmo, PayPal and Cash App use the
    // existing external-payment flow.
    await _startExternalPayment(
      debt: debt,
      amount: amount,
      method: method,
      settlementService: settlementService,
    );
  }

  // ---------------------------------------------------------------------------
  // EXTERNAL PAYMENT
  // ---------------------------------------------------------------------------

  Future<void> _startExternalPayment({
    required DebtModel debt,
    required double amount,
    required _PaymentMethod method,
    required SettlementService settlementService,
  }) async {
    try {
      // The person receiving the money.
      final recipientUser =
      await UserService().getUserById(debt.toUserId);

      if (!mounted) {
        return;
      }

      if (recipientUser == null) {
        _showError(
          'Unable to find the recipient\'s SplitUp profile.',
        );
        return;
      }

      final paymentKey = switch (method) {
        _PaymentMethod.venmo => 'venmo',
        _PaymentMethod.paypal => 'paypal',
        _PaymentMethod.cashApp => 'cashApp',

        _PaymentMethod.zelle ||
        _PaymentMethod.cash ||
        _PaymentMethod.bankTransfer ||
        _PaymentMethod.other => '',
      };

      if (paymentKey.isEmpty) {
        return;
      }

      final recipient =
          recipientUser.paymentMethods[paymentKey]
              ?.trim() ??
              '';

      if (recipient.isEmpty) {
        await _showMissingPaymentMethod(
          recipientName:
          recipientUser.name.trim().isNotEmpty
              ? recipientUser.name.trim()
              : 'This member',
          method: method,
        );

        return;
      }

      final paymentUrl = _buildPaymentUrl(
        method: method,
        recipient: recipient,
        amount: amount,
      );

      if (paymentUrl == null) {
        _showError(
          'Unable to create the payment link.',
        );
        return;
      }

      final uri = Uri.tryParse(paymentUrl);

      if (uri == null) {
        _showError(
          'Invalid payment link.',
        );
        return;
      }

      // Set pending payment BEFORE leaving SplitUp.
      //
      // This is important because the lifecycle callback can fire
      // immediately when the external payment destination opens.
      _pendingDebt = debt;
      _pendingAmount = amount;
      _pendingPaymentMethod = method;
      _openingPaymentApp = true;

      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched) {
        _clearPendingPayment();

        if (!mounted) {
          return;
        }

        await _showPaymentAppUnavailable(
          method,
          paymentUrl,
        );

        return;
      }

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_paymentMethodName(method)} opened. '
                'Complete the payment, then return to SplitUp.',
          ),
          duration: const Duration(
            seconds: 5,
          ),
        ),
      );
    } catch (error) {
      _clearPendingPayment();

      if (!mounted) {
        return;
      }

      _showError(
        'Unable to open '
            '${_paymentMethodName(method)}: $error',
      );
    }
  }

  String? _buildPaymentUrl({
    required _PaymentMethod method,
    required String recipient,
    required double amount,
  }) {
    final cleanAmount =
    amount.toStringAsFixed(2);

    switch (method) {
      case _PaymentMethod.venmo:
        final username = recipient
            .trim()
            .replaceFirst('@', '');

        if (username.isEmpty) {
          return null;
        }

        return Uri(
          scheme: 'https',
          host: 'venmo.com',
          path: '/u/$username',
          queryParameters: {
            'txn': 'pay',
            'amount': cleanAmount,
          },
        ).toString();

      case _PaymentMethod.paypal:
        final username = recipient
            .trim()
            .replaceFirst('@', '');

        if (username.isEmpty) {
          return null;
        }

        return Uri(
          scheme: 'https',
          host: 'paypal.me',
          path: '/$username/$cleanAmount',
        ).toString();

      case _PaymentMethod.cashApp:
        var cashtag = recipient.trim();

        if (!cashtag.startsWith('\$')) {
          cashtag = '\$$cashtag';
        }

        if (cashtag.length <= 1) {
          return null;
        }

        return Uri(
          scheme: 'https',
          host: 'cash.app',
          path: '$cashtag/$cleanAmount',
        ).toString();

      case _PaymentMethod.zelle:
      case _PaymentMethod.cash:
      case _PaymentMethod.bankTransfer:
      case _PaymentMethod.other:
        return null;
    }
  }

  Future<void> _showMissingPaymentMethod({
    required String recipientName,
    required _PaymentMethod method,
  }) async {
    if (!mounted) {
      return;
    }

    final methodName =
    _paymentMethodName(method);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            '$methodName not available',
          ),
          content: Text(
            '$recipientName has not added a '
                '$methodName account to their SplitUp profile.\n\n'
                'Ask them to add it under:\n'
                'Profile → Edit Profile → Payment Methods.',
          ),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.of(
                  dialogContext,
                ).pop();
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // RETURN TO SPLITUP
  // ---------------------------------------------------------------------------

  Future<void> _showPaymentConfirmation() async {
    if (!mounted ||
        _confirmationDialogShowing ||
        _pendingDebt == null ||
        _pendingAmount == null ||
        _pendingPaymentMethod == null) {
      return;
    }

    _confirmationDialogShowing = true;

    final debt = _pendingDebt!;
    final amount = _pendingAmount!;
    final method = _pendingPaymentMethod!;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Did you complete the payment?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.check_circle_outline,
                size: 52,
              ),
              const SizedBox(height: 16),
              Text(
                '${_memberName(debt.fromUserId)} paid '
                    '${formatCurrency(
                  amount,
                  group.currencyCode,
                )} to '
                    '${_memberName(debt.toUserId)} '
                    'using ${_paymentMethodName(method)}.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text(
                'Only confirm this if the payment was actually '
                    'completed.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Not yet'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Yes, mark as settled'),
            ),
          ],
        );
      },
    );

    _confirmationDialogShowing = false;

    if (!mounted) {
      return;
    }

    if (result == true) {
      await _recordPendingSettlement();
    } else {
      _clearPendingPayment();
    }
  }

  Future<void> _recordPendingSettlement() async {
    final debt = _pendingDebt;
    final amount = _pendingAmount;
    final method = _pendingPaymentMethod;

    if (debt == null ||
        amount == null ||
        method == null) {
      return;
    }

    SettlementProofUploadResult? proof;

    try {
      final proofFile = await _askForPaymentProof(
        methodName: _paymentMethodName(method),
      );

      if (proofFile != null) {
        if (!mounted) {
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Uploading payment proof...',
            ),
            duration: Duration(seconds: 2),
          ),
        );

        proof = await SettlementProofService().uploadProof(
          file: proofFile,
          groupId: group.id,
        );
      }

      final settlementService =
      SettlementService();

      await settlementService.recordSettlement(
        groupId: group.id,
        fromUserId: debt.fromUserId,
        toUserId: debt.toUserId,
        amount: amount,
        paymentMethod:
        _paymentMethodFirestoreValue(method),
        proofUrl: proof?.downloadUrl,
        proofFileName: proof?.fileName,
      );

      _clearPendingPayment();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            proof != null
                ? 'Payment recorded with proof using '
                '${_paymentMethodName(method)}.'
                : 'Payment recorded successfully using '
                '${_paymentMethodName(method)}.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unable to record payment: $error',
          ),
        ),
      );
    }
  }
  Future<File?> _askForPaymentProof({
    required String methodName,
  }) async {
    if (!mounted) {
      return null;
    }

    final addProof = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Add payment proof?'),
          content: Text(
            'Would you like to attach a screenshot or '
                'photo as proof of this $methodName payment?\n\n'
                'This is optional.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Skip'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              icon: const Icon(
                Icons.attach_file,
              ),
              label: const Text('Add proof'),
            ),
          ],
        );
      },
    );

    if (addProof != true || !mounted) {
      return null;
    }

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(
                  Icons.photo_library_outlined,
                ),
                title: const Text(
                  'Choose from gallery',
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop(
                    ImageSource.gallery,
                  );
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.camera_alt_outlined,
                ),
                title: const Text(
                  'Take a photo',
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop(
                    ImageSource.camera,
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (source == null) {
      return null;
    }

    final pickedFile = await ImagePicker().pickImage(
      source: source,
      imageQuality: 85,
    );

    if (pickedFile == null) {
      return null;
    }

    return File(pickedFile.path);
  }
  Future<void> _showManualPaymentConfirmation({
    required DebtModel debt,
    required double amount,
    required _PaymentMethod method,
    required SettlementService settlementService,
  }) async {
    final methodName = _paymentMethodName(method);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            'Record $methodName payment',
          ),
          content: Text(
            'Did ${_memberName(debt.fromUserId)} pay '
                '${formatCurrency(
              amount,
              group.currencyCode,
            )} '
                'to ${_memberName(debt.toUserId)} '
                'using $methodName?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Not yet'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text(
                'Yes, record payment',
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    try {
      final proofFile = await _askForPaymentProof(
        methodName: methodName,
      );

      SettlementProofUploadResult? proof;

      if (proofFile != null) {
        if (!mounted) {
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Uploading payment proof...',
            ),
            duration: Duration(seconds: 2),
          ),
        );

        proof = await SettlementProofService().uploadProof(
          file: proofFile,
          groupId: group.id,
        );
      }

      await settlementService.recordSettlement(
        groupId: group.id,
        fromUserId: debt.fromUserId,
        toUserId: debt.toUserId,
        amount: amount,
        paymentMethod:
        _paymentMethodFirestoreValue(method),
        proofUrl: proof?.downloadUrl,
        proofFileName: proof?.fileName,
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            proof != null
                ? '$methodName payment recorded with proof.'
                : '$methodName payment recorded successfully.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unable to record payment: $error',
          ),
        ),
      );
    }
  }

  Future<void> _showPaymentAppUnavailable(
      _PaymentMethod method,
      String paymentUrl,
      ) async {
    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            '${_paymentMethodName(method)} unavailable',
          ),
          content: const Text(
            'The payment app could not be opened. '
                'You can install the app and try again, or '
                'open the payment link manually.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Close'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();

                final uri = Uri.tryParse(paymentUrl);

                if (uri != null) {
                  await launchUrl(
                    uri,
                    mode: LaunchMode.externalApplication,
                  );
                }
              },
              child: const Text('Open link'),
            ),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // REMINDER
  // ---------------------------------------------------------------------------

  Future<void> _sendReminder({
    required BuildContext context,
    required DebtModel debt,
    required Map<String, String> memberNames,
  }) async {
    if (debt.fromUserId.startsWith('guest_')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Guest members cannot receive reminders.',
          ),
        ),
      );
      return;
    }

    final currentUser =
        FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      return;
    }

    if (currentUser.uid != debt.toUserId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Only the person who is owed money '
                'can send this reminder.',
          ),
        ),
      );
      return;
    }

    final debtorName =
        memberNames[debt.fromUserId] ??
            _shortId(debt.fromUserId);

    try {
      final notificationService =
      InAppNotificationService();

      await notificationService.createNotification(
        userId: debt.fromUserId,
        type: 'balance_reminder',
        title: 'Payment reminder',
        message:
        'You still owe '
            '${formatCurrency(debt.amount, group.currencyCode)} '
            'in ${group.name}.',
        groupId: group.id,
      );

      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Reminder sent to $debtorName.',
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unable to send reminder: $error',
          ),
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // MEMBER NAMES
  // ---------------------------------------------------------------------------

  Future<Map<String, String>> _loadMemberNames() async {
    final names = <String, String>{};

    final firestore = FirebaseFirestore.instance;
    final userService = UserService();
    final currentUser =
        FirebaseAuth.instance.currentUser;

    final users = await userService.getUsersByIds(
      group.members,
    );

    users.forEach((id, user) {
      final name = user.name.trim();
      final email = user.email.trim();

      if (name.isNotEmpty) {
        names[id] = name;
      } else if (id == currentUser?.uid &&
          currentUser?.displayName != null &&
          currentUser!.displayName!.trim().isNotEmpty) {
        names[id] =
            currentUser.displayName!.trim();
      } else if (email.isNotEmpty) {
        names[id] = email;
      }
    });

    final groupDocument = await firestore
        .collection('groups')
        .doc(group.id)
        .get();

    final groupData =
        groupDocument.data() ?? {};

    final rawMemberDetails =
    groupData['memberDetails'];

    if (rawMemberDetails is Map) {
      final memberDetails =
      Map<String, dynamic>.from(
        rawMemberDetails,
      );

      for (final memberId in group.members) {
        final rawDetails =
        memberDetails[memberId];

        if (rawDetails is! Map) {
          continue;
        }

        final details =
        Map<String, dynamic>.from(
          rawDetails,
        );

        final name =
            details['name']?.toString().trim() ?? '';

        final email =
            details['email']?.toString().trim() ?? '';

        if (name.isNotEmpty) {
          names[memberId] = name;
        } else if (!names.containsKey(memberId) &&
            email.isNotEmpty) {
          names[memberId] = email;
        }
      }
    }

    return names;
  }

  // ---------------------------------------------------------------------------
  // HELPERS
  // ---------------------------------------------------------------------------

  String _memberName(String userId) {
    final name = _memberNames[userId]?.trim() ?? '';

    if (name.isNotEmpty) {
      return name;
    }

    return _shortId(userId);
  }

  static String _paymentMethodName(
      _PaymentMethod method,
      ) {
    switch (method) {
      case _PaymentMethod.venmo:
        return 'Venmo';

      case _PaymentMethod.paypal:
        return 'PayPal';

      case _PaymentMethod.cashApp:
        return 'Cash App';

      case _PaymentMethod.zelle:
        return 'Zelle';

      case _PaymentMethod.cash:
        return 'Cash';

      case _PaymentMethod.bankTransfer:
        return 'Bank Transfer';

      case _PaymentMethod.other:
        return 'Other';
    }
  }

  static String _paymentMethodFirestoreValue(
      _PaymentMethod method,
      ) {
    switch (method) {
      case _PaymentMethod.venmo:
        return 'venmo';

      case _PaymentMethod.paypal:
        return 'paypal';

      case _PaymentMethod.cashApp:
        return 'cashApp';

      case _PaymentMethod.zelle:
        return 'zelle';

      case _PaymentMethod.cash:
        return 'cash';

      case _PaymentMethod.bankTransfer:
        return 'bankTransfer';

      case _PaymentMethod.other:
        return 'other';
    }
  }

  static String _settlementPaymentMethodName(
      String paymentMethod,
      ) {
    switch (paymentMethod.trim().toLowerCase()) {
      case 'venmo':
        return 'Venmo';

      case 'paypal':
        return 'PayPal';

      case 'cashapp':
      case 'cash_app':
        return 'Cash App';

      case 'cash':
        return 'Cash';

      case 'zelle':
        return 'Zelle';

      case 'banktransfer':
      case 'bank_transfer':
        return 'Bank Transfer';

      case 'other':
      case '':
        return 'Other';

      default:
        return paymentMethod;
    }
  }
  static IconData _settlementPaymentMethodIcon(
      String paymentMethod,
      ) {
    switch (paymentMethod.trim().toLowerCase()) {
      case 'venmo':
        return Icons.account_balance_wallet_outlined;

      case 'paypal':
        return Icons.payments_outlined;

      case 'cashapp':
      case 'cash_app':
        return Icons.attach_money;

      case 'zelle':
        return Icons.account_balance_outlined;

      case 'cash':
        return Icons.money_outlined;

      case 'banktransfer':
      case 'bank_transfer':
        return Icons.account_balance_outlined;

      case 'other':
      default:
        return Icons.more_horiz;
    }
  }
  void _clearPendingPayment() {
    _pendingDebt = null;
    _pendingAmount = null;
    _pendingPaymentMethod = null;
    _openingPaymentApp = false;
  }

  void _showError(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  static String _shortId(String value) {
    if (value.length <= 8) {
      return value;
    }

    return '${value.substring(0, 8)}…';
  }

  static String _formatSettlementDate(
      DateTime date,
      ) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    final hour = date.hour == 0
        ? 12
        : date.hour > 12
        ? date.hour - 12
        : date.hour;

    final minute = date.minute
        .toString()
        .padLeft(2, '0');

    final period =
    date.hour >= 12 ? 'PM' : 'AM';

    return '${months[date.month - 1]} '
        '${date.day}, ${date.year} • '
        '$hour:$minute $period';
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final expenseService = ExpenseService();
    final settlementService = SettlementService();
    final balanceService = BalanceService();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Balances & Settlements',
        ),
      ),
      body: StreamBuilder<List<ExpenseModel>>(
        stream: expenseService.getGroupExpenses(
          group.id,
        ),
        builder: (context, expenseSnapshot) {
          if (expenseSnapshot.connectionState ==
              ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (expenseSnapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Unable to load expenses: '
                      '${expenseSnapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final expenses =
              expenseSnapshot.data ?? [];

          return StreamBuilder<List<SettlementModel>>(
            stream:
            settlementService.getGroupSettlements(
              group.id,
            ),
            builder: (
                context,
                settlementSnapshot,
                ) {
              if (settlementSnapshot.connectionState ==
                  ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(),
                );
              }

              if (settlementSnapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Unable to load settlements: '
                          '${settlementSnapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }

              final settlements =
                  settlementSnapshot.data ?? [];

              final debts =
              balanceService.simplifyDebts(
                memberIds: group.members,
                expenses: expenses,
                settlements: settlements,
              );

              return FutureBuilder<Map<String, String>>(
                future: _loadMemberNames(),
                builder: (
                    context,
                    userSnapshot,
                    ) {
                  if (userSnapshot.connectionState ==
                      ConnectionState.waiting) {
                    return const Center(
                      child:
                      CircularProgressIndicator(),
                    );
                  }

                  if (userSnapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding:
                        const EdgeInsets.all(24),
                        child: Text(
                          'Unable to load member names: '
                              '${userSnapshot.error}',
                          textAlign:
                          TextAlign.center,
                        ),
                      ),
                    );
                  }

                  final memberNames =
                      userSnapshot.data ??
                          <String, String>{};
                  _memberNames = memberNames;
                  return ListView(
                    padding:
                    const EdgeInsets.fromLTRB(
                      16,
                      16,
                      16,
                      32,
                    ),
                    children: [
                      Text(
                        'Balances',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(
                          fontWeight:
                          FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 10),

                      if (debts.isEmpty)
                        const Card(
                          child: Padding(
                            padding:
                            EdgeInsets.all(20),
                            child: Center(
                              child: Text(
                                'Everyone is settled up.',
                              ),
                            ),
                          ),
                        )
                      else
                        ...debts.map(
                              (debt) => _DebtCard(
                            debt: debt,
                            memberNames:
                            memberNames,
                            currencyCode:
                            group.currencyCode,
                            onSettle: () {
                              _settleDebt(
                                context: context,
                                debt: debt,
                                settlementService:
                                settlementService,
                              );
                            },
                            onRemind: () {
                              _sendReminder(
                                context: context,
                                debt: debt,
                                memberNames:
                                memberNames,
                              );
                            },
                          ),
                        ),

                      const SizedBox(height: 28),

                      Text(
                        'Settlement history',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(
                          fontWeight:
                          FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 10),

                      if (settlements.isEmpty)
                        const Card(
                          child: Padding(
                            padding:
                            EdgeInsets.all(20),
                            child: Center(
                              child: Text(
                                'No payments recorded yet.',
                              ),
                            ),
                          ),
                        )
                      else
                        ...settlements.map(
                              (settlement) {
                            final fromName =
                                memberNames[
                                settlement
                                    .fromUserId] ??
                                    _shortId(
                                      settlement
                                          .fromUserId,
                                    );

                            final toName =
                                memberNames[
                                settlement
                                    .toUserId] ??
                                    _shortId(
                                      settlement
                                          .toUserId,
                                    );

                            return Card(
                              child: ListTile(
                                leading:
                                const CircleAvatar(
                                  child: Icon(
                                    Icons
                                        .payments_outlined,
                                  ),
                                ),
                                title: Text(
                                  '$fromName paid $toName',
                                  style:
                                  const TextStyle(
                                    fontWeight:
                                    FontWeight.w600,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment:
                                  CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const SizedBox(height: 4),

                                    Row(
                                      children: [
                                        Icon(
                                          _settlementPaymentMethodIcon(
                                            settlement.paymentMethod,
                                          ),
                                          size: 16,
                                        ),

                                        const SizedBox(width: 6),

                                        Text(
                                          _settlementPaymentMethodName(
                                            settlement.paymentMethod,
                                          ),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),

                                    const SizedBox(height: 3),

                                    Text(
                                      settlement.createdAt != null
                                          ? _formatSettlementDate(
                                        settlement.createdAt!,
                                      )
                                          : 'Payment recorded',
                                    ),
if (settlement.proofUrl != null &&
settlement.proofUrl!.trim().isNotEmpty) ...[
const SizedBox(height: 8),

InkWell(
  onTap: () {
    final proofUrl =
        settlement.proofUrl?.trim() ?? '';

    if (proofUrl.isEmpty) {
      return;
    }

    _openPaymentProof(
      context: context,
      proofUrl: proofUrl,
    );
  },
child: const Row(
mainAxisSize: MainAxisSize.min,
children: [
Icon(
Icons.attachment,
size: 17,
),
SizedBox(width: 5),
Text(
'View payment proof',
style: TextStyle(
fontWeight: FontWeight.w600,
decoration:
TextDecoration.underline,
),
),
],
),
),
],
                                  ],
                                ),
                                trailing: Text(
                                  formatCurrency(
                                    settlement.amount,
                                    group.currencyCode,
                                  ),
                                  style:
                                  const TextStyle(
                                    fontWeight:
                                    FontWeight.bold,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// PAYMENT METHOD TILE
// -----------------------------------------------------------------------------

class _PaymentMethodTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _PaymentMethodTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          child: Icon(icon),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(subtitle),
        trailing: const Icon(
          Icons.chevron_right,
        ),
        onTap: onTap,
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// DEBT CARD
// -----------------------------------------------------------------------------

class _DebtCard extends StatelessWidget {
  final DebtModel debt;
  final Map<String, String> memberNames;
  final VoidCallback onSettle;
  final VoidCallback onRemind;
  final String currencyCode;

  const _DebtCard({
    required this.debt,
    required this.memberNames,
    required this.onSettle,
    required this.onRemind,
    required this.currencyCode,
  });

  @override
  Widget build(BuildContext context) {
    final fromName =
        memberNames[debt.fromUserId] ??
            _shortId(debt.fromUserId);

    final toName =
        memberNames[debt.toUserId] ??
            _shortId(debt.toUserId);

    return Card(
      child: ListTile(
        leading: const CircleAvatar(
          child: Icon(
            Icons.swap_horiz_rounded,
          ),
        ),
        title: Text(
          '$fromName owes $toName',
        ),
        subtitle: Text(
          formatCurrency(
            debt.amount,
            currencyCode,
          ),
        ),
        trailing: PopupMenuButton<String>(
          tooltip: 'Balance actions',
          onSelected: (value) {
            if (value == 'remind') {
              onRemind();
            } else if (value == 'settle') {
              onSettle();
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: 'remind',
              child: Row(
                children: [
                  Icon(
                    Icons.notifications_active_outlined,
                  ),
                  SizedBox(width: 12),
                  Text('Send Reminder'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'settle',
              child: Row(
                children: [
                  Icon(
                    Icons.payments_outlined,
                  ),
                  SizedBox(width: 12),
                  Text('Settle Up'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _shortId(String value) {
    if (value.length <= 8) {
      return value;
    }

    return '${value.substring(0, 8)}…';
  }
}