import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../models/expense_model.dart';
import '../../models/group_model.dart';
import '../../models/settlement_model.dart';
import '../../services/report_service.dart';

class GroupReportScreen extends StatefulWidget {
  final GroupModel group;
  final List<ExpenseModel> expenses;
  final List<SettlementModel> settlements;
  final Map<String, String> memberNames;

  const GroupReportScreen({
    super.key,
    required this.group,
    required this.expenses,
    required this.settlements,
    required this.memberNames,
  });

  @override
  State<GroupReportScreen> createState() =>
      _GroupReportScreenState();
}

class _GroupReportScreenState extends State<GroupReportScreen> {
  final ReportService _reportService = ReportService();

  bool _isSharingPdf = false;
  bool _isSharingCsv = false;

  Future<void> _sharePdf() async {
    setState(() {
      _isSharingPdf = true;
    });

    try {
      final bytes = await _reportService.generateGroupPdf(
        group: widget.group,
        expenses: widget.expenses,
        settlements: widget.settlements,
        memberNames: widget.memberNames,
      );

      await _reportService.sharePdf(
        bytes: bytes,
        groupName: widget.group.name,
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to share PDF: $error'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSharingPdf = false;
        });
      }
    }
  }

  Future<void> _shareCsv() async {
    setState(() {
      _isSharingCsv = true;
    });

    try {
      final csvText = await _reportService.generateGroupCsv(
        group: widget.group,
        expenses: widget.expenses,
        memberNames: widget.memberNames,
      );

      await _reportService.shareCsv(
        csvText: csvText,
        groupName: widget.group.name,
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to share CSV: $error'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSharingCsv = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Group Report'),
        actions: [
          IconButton(
            tooltip: 'Share PDF',
            onPressed: _isSharingPdf ? null : _sharePdf,
            icon: _isSharingPdf
                ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
              ),
            )
                : const Icon(Icons.picture_as_pdf_outlined),
          ),
          IconButton(
            tooltip: 'Share CSV',
            onPressed: _isSharingCsv ? null : _shareCsv,
            icon: _isSharingCsv
                ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
              ),
            )
                : const Icon(Icons.table_view_outlined),
          ),
        ],
      ),
      body: PdfPreview(
        canChangeOrientation: false,
        canChangePageFormat: false,
        canDebug: false,
        pdfFileName:
        '${widget.group.name.replaceAll(' ', '_')}_report.pdf',
        build: (_) {
          return _reportService.generateGroupPdf(
            group: widget.group,
            expenses: widget.expenses,
            settlements: widget.settlements,
            memberNames: widget.memberNames,
          );
        },
      ),
    );
  }
}