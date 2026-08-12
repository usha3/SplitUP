import 'dart:io';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../models/expense_model.dart';
import '../models/group_model.dart';
import '../models/settlement_model.dart';
import '../utils/currency_formatter.dart';

class ReportService {
  Future<Uint8List> generateGroupPdf({
    required GroupModel group,
    required List<ExpenseModel> expenses,
    required List<SettlementModel> settlements,
    required Map<String, String> memberNames,
  }) async {
    final document = pw.Document();

    final memberShareTotals =
    <String, double>{};

    for (final expense in expenses) {
      for (final entry
      in expense.shares.entries) {
        memberShareTotals[entry.key] =
            (memberShareTotals[entry.key] ?? 0) +
                entry.value;
      }
    }

    final itemizedExpenses = expenses
        .where(
          (expense) =>
      expense.splitType == 'itemized' &&
          expense.items.isNotEmpty,
    )
        .toList();

    final totalSpending = expenses.fold<double>(
      0,
          (total, expense) =>
      total + expense.amount,
    );

    double equalSplitTotal = 0;
    double itemizedSplitTotal = 0;

    for (final expense in expenses) {
      if (expense.splitType == 'itemized') {
        itemizedSplitTotal += expense.amount;
      } else {
        equalSplitTotal += expense.amount;
      }
    }

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (context) {
          return pw.Container(
            padding: const pw.EdgeInsets.only(bottom: 12),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(
                  width: 1,
                  color: PdfColors.grey400,
                ),
              ),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'SplitUP Group Report',
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  _formatDate(DateTime.now()),
                  style: const pw.TextStyle(
                    fontSize: 10,
                    color: PdfColors.grey700,
                  ),
                ),
              ],
            ),
          );
        },
        footer: (context) {
          return pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: const pw.TextStyle(
                fontSize: 9,
                color: PdfColors.grey700,
              ),
            ),
          );
        },
        build: (context) {
          return [
            pw.SizedBox(height: 20),
            pw.Text(
              group.name,
              style: pw.TextStyle(
                fontSize: 26,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            if (group.description.trim().isNotEmpty) ...[
              pw.SizedBox(height: 6),
              pw.Text(group.description.trim()),
            ],
            pw.SizedBox(height: 18),
            pw.Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _summaryBox(
                  label: 'Members',
                  value: '${group.members.length}',
                ),
                _summaryBox(
                  label: 'Expenses',
                  value: '${expenses.length}',
                ),
                _summaryBox(
                  label: 'Total spending',
                  value: formatCurrency(
                    totalSpending,
                    group.currencyCode,
                  ),
                ),
                _summaryBox(
                  label: 'Settlements',
                  value: '${settlements.length}',
                ),
                _summaryBox(
                  label: 'Equal split',
                  value: formatCurrency(
                    equalSplitTotal,
                    group.currencyCode,
                  ),
                ),

                _summaryBox(
                  label: 'By item',
                  value: formatCurrency(
                    itemizedSplitTotal,
                    group.currencyCode,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 28),
            pw.Text(
              'Members',
              style: _sectionTitleStyle(),
            ),
            pw.SizedBox(height: 10),
            pw.TableHelper.fromTextArray(
              headers: const ['Name', 'Member ID'],
              data: group.members
                  .map(
                    (memberId) => [
                  memberNames[memberId] ?? _shortId(memberId),
                  memberId,
                ],
              )
                  .toList(),
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
              ),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey300,
              ),
              cellPadding: const pw.EdgeInsets.all(7),
              cellStyle: const pw.TextStyle(fontSize: 9),
            ),
            pw.SizedBox(height: 28),
            pw.Text(
              'Expenses',
              style: _sectionTitleStyle(),
            ),
            pw.SizedBox(height: 10),
            if (expenses.isEmpty)
              pw.Text('No expenses recorded.')
            else
              pw.TableHelper.fromTextArray(
                headers: const [
                  'Date',
                  'Title',
                  'Category',
                  'Paid by',
                  'Split',
                  'Participants',
                  'Total',
                ],

                data: expenses.map((expense) {
                  return [
                    _formatNullableDate(
                      expense.createdAt,
                    ),

                    expense.title,

                    expense.category,

                    memberNames[expense.paidBy] ??
                        _shortId(expense.paidBy),

                    expense.splitType == 'itemized'
                        ? 'By item'
                        : 'Equal',

                    expense.participants
                        .map(
                          (id) =>
                      memberNames[id] ??
                          _shortId(id),
                    )
                        .join(', '),

                    formatCurrency(
                      expense.amount,
                      group.currencyCode,
                    ),
                  ];
                }).toList(),

                headerStyle: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 8,
                ),

                headerDecoration:
                const pw.BoxDecoration(
                  color: PdfColors.grey300,
                ),

                cellPadding:
                const pw.EdgeInsets.all(5),

                cellStyle:
                const pw.TextStyle(
                  fontSize: 7,
                ),

                columnWidths: {
                  0: const pw.FlexColumnWidth(1.1),
                  1: const pw.FlexColumnWidth(1.5),
                  2: const pw.FlexColumnWidth(1.1),
                  3: const pw.FlexColumnWidth(1.2),
                  4: const pw.FlexColumnWidth(0.9),
                  5: const pw.FlexColumnWidth(1.8),
                  6: const pw.FlexColumnWidth(1),
                },
              ),

// ADD ITEMIZED DETAILS HERE
            if (itemizedExpenses.isNotEmpty) ...[
              pw.SizedBox(height: 28),

              pw.Text(
                'Itemized Expense Details',
                style: _sectionTitleStyle(),
              ),

              pw.SizedBox(height: 10),

              ...itemizedExpenses.map(
                    (expense) => pw.Container(
                  margin: const pw.EdgeInsets.only(
                    bottom: 16,
                  ),
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(
                      color: PdfColors.grey300,
                    ),
                    borderRadius:
                    pw.BorderRadius.circular(6),
                  ),
                  child: pw.Column(
                    crossAxisAlignment:
                    pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        expense.title,
                        style: pw.TextStyle(
                          fontSize: 13,
                          fontWeight:
                          pw.FontWeight.bold,
                        ),
                      ),

                      pw.SizedBox(height: 8),

                      pw.TableHelper.fromTextArray(
                        headers: const [
                          'Item',
                          'Amount',
                          'Shared by',
                        ],
                        data: expense.items.map(
                              (item) {
                            return [
                              item.name,
                              formatCurrency(
                                item.amount,
                                group.currencyCode,
                              ),
                              item.participants
                                  .map(
                                    (id) =>
                                memberNames[id] ??
                                    _shortId(id),
                              )
                                  .join(', '),
                            ];
                          },
                        ).toList(),
                        headerStyle: pw.TextStyle(
                          fontWeight:
                          pw.FontWeight.bold,
                        ),
                        headerDecoration:
                        const pw.BoxDecoration(
                          color: PdfColors.grey200,
                        ),
                        cellPadding:
                        const pw.EdgeInsets.all(6),
                        cellStyle:
                        const pw.TextStyle(
                          fontSize: 8,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            pw.SizedBox(height: 28),

            pw.Text(
              'Member Expense Shares',
              style: _sectionTitleStyle(),
            ),

            pw.SizedBox(height: 10),

            if (memberShareTotals.isEmpty)
              pw.Text(
                'No member share data available.',
              )
            else
              pw.TableHelper.fromTextArray(
                headers: const [
                  'Member',
                  'Expense Share',
                ],
                data: memberShareTotals.entries
                    .map(
                      (entry) => [
                    memberNames[entry.key] ??
                        _shortId(entry.key),

                    formatCurrency(
                      entry.value,
                      group.currencyCode,
                    ),
                  ],
                )
                    .toList(),
                headerStyle: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                ),
                headerDecoration:
                const pw.BoxDecoration(
                  color: PdfColors.grey300,
                ),
                cellPadding:
                const pw.EdgeInsets.all(7),
              ),

            pw.SizedBox(height: 28),

            pw.Text(
              'Settlement history',
              style: _sectionTitleStyle(),
            ),
            pw.SizedBox(height: 10),
            if (settlements.isEmpty)
              pw.Text('No settlements recorded.')
            else
              pw.TableHelper.fromTextArray(
                headers: const [
                  'Date',
                  'From',
                  'To',
                  'Amount',
                ],
                data: settlements.map((settlement) {
                  return [
                    _formatNullableDate(settlement.createdAt),
                    memberNames[settlement.fromUserId] ??
                        _shortId(settlement.fromUserId),
                    memberNames[settlement.toUserId] ??
                        _shortId(settlement.toUserId),
                    formatCurrency(
                      settlement.amount,
                      group.currencyCode,
                    ),
                  ];
                }).toList(),
                headerStyle: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                ),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.grey300,
                ),
                cellPadding: const pw.EdgeInsets.all(7),
                cellStyle: const pw.TextStyle(fontSize: 9),
              ),
          ];
        },
      ),
    );

    return document.save();
  }

  Future<String> generateGroupCsv({
    required GroupModel group,
    required List<ExpenseModel> expenses,
    required Map<String, String> memberNames,
  }) async {
    final rows = <List<dynamic>>[
      [
        'Group',
        'Expense ID',
        'Date',
        'Title',
        'Category',
        'Paid By',
        'Split Type',
        'Participant Count',
        'Participants',
        'Total Amount',
        'Member Shares',
        'Items',
      ],
      ...expenses.map(
            (expense) => [
          group.name,
          expense.id,
          _formatNullableDate(
            expense.createdAt,
          ),
          expense.title,
          expense.category,

          memberNames[expense.paidBy] ??
              _shortId(expense.paidBy),

          expense.splitType == 'itemized'
              ? 'By item'
              : 'Equal',

          expense.participants.length,

          expense.participants
              .map(
                (id) =>
            memberNames[id] ??
                _shortId(id),
          )
              .join(' | '),

          expense.amount.toStringAsFixed(2),

          expense.shares.entries
              .map(
                (entry) =>
            '${memberNames[entry.key] ?? _shortId(entry.key)}: '
                '${entry.value.toStringAsFixed(2)}',
          )
              .join(' | '),

          expense.items
              .map(
                (item) =>
            '${item.name}: '
                '${item.amount.toStringAsFixed(2)} '
                '[${item.participants.map(
                  (id) =>
              memberNames[id] ??
                  _shortId(id),
            ).join(', ')}]',
          )
              .join(' | '),
        ],
      ),
    ];

    return csv.encode(rows);
  }

  Future<File> savePdfFile({
    required Uint8List bytes,
    required String groupName,
  }) async {
    final directory = await getTemporaryDirectory();

    final file = File(
      '${directory.path}/${_safeFileName(groupName)}_report.pdf',
    );

    await file.writeAsBytes(bytes, flush: true);

    return file;
  }

  Future<File> saveCsvFile({
    required String csvText,
    required String groupName,
  }) async {
    final directory = await getTemporaryDirectory();

    final file = File(
      '${directory.path}/${_safeFileName(groupName)}_expenses.csv',
    );

    await file.writeAsString(csvText, flush: true);

    return file;
  }

  Future<void> sharePdf({
    required Uint8List bytes,
    required String groupName,
  }) async {
    final file = await savePdfFile(
      bytes: bytes,
      groupName: groupName,
    );

    await SharePlus.instance.share(
      ShareParams(
        title: '$groupName report',
        subject: '$groupName SplitUP report',
        text: 'SplitUP expense report for $groupName.',
        files: [
          XFile(
            file.path,
            mimeType: 'application/pdf',
          ),
        ],
      ),
    );
  }

  Future<void> shareCsv({
    required String csvText,
    required String groupName,
  }) async {
    final file = await saveCsvFile(
      csvText: csvText,
      groupName: groupName,
    );

    await SharePlus.instance.share(
      ShareParams(
        title: '$groupName expenses',
        subject: '$groupName SplitUP expense export',
        text: 'SplitUP CSV expense export for $groupName.',
        files: [
          XFile(
            file.path,
            mimeType: 'text/csv',
          ),
        ],
      ),
    );
  }

  static pw.Widget _summaryBox({
    required String label,
    required String value,
  }) {
    return pw.Container(
      width: 115,
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(
          color: PdfColors.grey300,
        ),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            style: const pw.TextStyle(
              fontSize: 9,
              color: PdfColors.grey700,
            ),
          ),
          pw.SizedBox(height: 5),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 15,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  static pw.TextStyle _sectionTitleStyle() {
    return pw.TextStyle(
      fontSize: 17,
      fontWeight: pw.FontWeight.bold,
    );
  }

  static String _formatNullableDate(DateTime? date) {
    return date == null ? '' : _formatDate(date);
  }

  static String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');

    return '$month/$day/${date.year}';
  }

  static String _safeFileName(String value) {
    final safe = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');

    return safe.isEmpty ? 'splitup_group' : safe;
  }

  static String _shortId(String value) {
    if (value.length <= 8) {
      return value;
    }

    return '${value.substring(0, 8)}…';
  }
}