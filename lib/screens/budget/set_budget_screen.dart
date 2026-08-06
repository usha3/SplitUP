import 'package:flutter/material.dart';

import '../../models/group_model.dart';
import '../../services/budget_service.dart';
import '../../models/currency_model.dart';

class SetBudgetScreen extends StatefulWidget {
  final GroupModel group;

  const SetBudgetScreen({
    super.key,
    required this.group,
  });

  @override
  State<SetBudgetScreen> createState() => _SetBudgetScreenState();
}

class _SetBudgetScreenState extends State<SetBudgetScreen> {
  final _formKey = GlobalKey<FormState>();
  final _budgetController = TextEditingController();

  final BudgetService _budgetService = BudgetService();

  bool _loading = false;
  bool _alertsEnabled = true;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _loading = true;
    });

    try {
      await _budgetService.saveBudget(
        groupId: widget.group.id,
        monthlyLimit:
        double.parse(_budgetController.text.trim()),
        currencyCode: widget.group.currencyCode,
        alertsEnabled: _alertsEnabled,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Monthly budget saved"),
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }

    if (mounted) {
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _budgetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Monthly Budget"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            children: [

              TextFormField(
                controller: _budgetController,
                keyboardType:
                const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: "Monthly Budget",
                  prefixText:
                  '${currencyByCode(widget.group.currencyCode).symbol} ',
                  border: const OutlineInputBorder(),
                ),
                validator: (value) {
                  final amount =
                  double.tryParse(value ?? "");

                  if (amount == null || amount <= 0) {
                    return "Enter a valid budget";
                  }

                  return null;
                },
              ),

              const SizedBox(height: 24),

              SwitchListTile(
                value: _alertsEnabled,
                onChanged: (value) {
                  setState(() {
                    _alertsEnabled = value;
                  });
                },
                title: const Text("Enable Budget Alerts"),
                subtitle: const Text(
                  "Notify when 80%, 90% and 100% are reached",
                ),
              ),

              const Spacer(),

              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _loading ? null : _save,
                  child: _loading
                      ? const CircularProgressIndicator()
                      : const Text("Save Budget"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}