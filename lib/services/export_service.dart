import 'package:excel/excel.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../models/expense.dart';
import '../models/income.dart';
import '../models/trip.dart';
import 'dart:typed_data';

class ExportService {
  static Future<void> exportToExcel({
    required Trip trip,
    required List<Expense> expenses,
    required List<Income> incomes,
    required String currencySymbol,
  }) async {
    final excel = Excel.createExcel();

    // 기본 시트 삭제
    excel.delete('Sheet1');

    // 요약 시트
    final summarySheet = excel['요약'];
    summarySheet.appendRow([TextCellValue('여행 정보')]);
    summarySheet.appendRow([TextCellValue('여행명'), TextCellValue(trip.name)]);
    summarySheet.appendRow([TextCellValue('국가'), TextCellValue(trip.country)]);
    summarySheet.appendRow([
      TextCellValue('기간'),
      TextCellValue(
        '${DateFormat('yyyy.MM.dd').format(trip.startDate)} - ${DateFormat('yyyy.MM.dd').format(trip.endDate)}',
      ),
    ]);
    summarySheet.appendRow([
      TextCellValue('통화'),
      TextCellValue('$currencySymbol ${trip.currency}'),
    ]);
    summarySheet.appendRow([]);

    final totalIncome = incomes.fold(0.0, (sum, income) => sum + income.amount);
    final totalExpense = expenses.fold(
      0.0,
      (sum, expense) => sum + expense.amount,
    );
    final balance = totalIncome - totalExpense;

    summarySheet.appendRow([TextCellValue('재무 요약')]);
    summarySheet.appendRow([
      TextCellValue('총 예산'),
      TextCellValue(
        '$currencySymbol ${NumberFormat('#,##0').format(totalIncome)}',
      ),
    ]);
    summarySheet.appendRow([
      TextCellValue('총 지출'),
      TextCellValue(
        '$currencySymbol ${NumberFormat('#,##0').format(totalExpense)}',
      ),
    ]);
    summarySheet.appendRow([
      TextCellValue('남은 금액'),
      TextCellValue('$currencySymbol ${NumberFormat('#,##0').format(balance)}'),
    ]);

    // 지출 내역 시트
    final expenseSheet = excel['지출 내역'];
    expenseSheet.appendRow([
      TextCellValue('날짜'),
      TextCellValue('시간'),
      TextCellValue('제목'),
      TextCellValue('카테고리'),
      TextCellValue('금액'),
      TextCellValue('결제방법'),
      TextCellValue('위치'),
      TextCellValue('메모'),
    ]);

    for (var expense in expenses) {
      expenseSheet.appendRow([
        TextCellValue(DateFormat('yyyy-MM-dd').format(expense.date)),
        TextCellValue(DateFormat('HH:mm').format(expense.date)),
        TextCellValue(expense.title ?? ''),
        TextCellValue(expense.category),
        TextCellValue(
          '$currencySymbol ${NumberFormat('#,##0').format(expense.amount)}',
        ),
        TextCellValue(expense.paymentMethod == 'cash' ? '현금' : '카드'),
        TextCellValue(expense.locationName ?? ''),
        TextCellValue(expense.note ?? ''),
      ]);
    }

    // 예산 내역 시트
    final incomeSheet = excel['예산 내역'];
    incomeSheet.appendRow([
      TextCellValue('날짜'),
      TextCellValue('금액'),
      TextCellValue('메모'),
    ]);

    for (var income in incomes) {
      incomeSheet.appendRow([
        TextCellValue(DateFormat('yyyy-MM-dd').format(income.date)),
        TextCellValue(
          '$currencySymbol ${NumberFormat('#,##0').format(income.amount)}',
        ),
        TextCellValue(income.note ?? ''),
      ]);
    }

    // 파일 저장
    final bytes = excel.encode();
    if (bytes != null) {
      await Printing.sharePdf(
        bytes: Uint8List.fromList(bytes),
        filename:
            '${trip.name}_가계부_${DateFormat('yyyyMMdd').format(DateTime.now())}.xlsx',
      );
    }
  }

  static Future<void> exportToPdf({
    required Trip trip,
    required List<Expense> expenses,
    required List<Income> incomes,
    required String currencySymbol,
  }) async {
    final pdf = pw.Document();

    final totalIncome = incomes.fold(0.0, (sum, income) => sum + income.amount);
    final totalExpense = expenses.fold(
      0.0,
      (sum, expense) => sum + expense.amount,
    );
    final balance = totalIncome - totalExpense;

    // 요약 페이지
    pdf.addPage(
      pw.Page(
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              trip.name,
              style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 20),
            pw.Text('국가: ${trip.country}'),
            pw.Text(
              '기간: ${DateFormat('yyyy.MM.dd').format(trip.startDate)} - ${DateFormat('yyyy.MM.dd').format(trip.endDate)}',
            ),
            pw.Text('통화: $currencySymbol ${trip.currency}'),
            pw.SizedBox(height: 30),
            pw.Text(
              '재무 요약',
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 10),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('총 예산:'),
                pw.Text(
                  '$currencySymbol ${NumberFormat('#,##0').format(totalIncome)}',
                ),
              ],
            ),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('총 지출:'),
                pw.Text(
                  '$currencySymbol ${NumberFormat('#,##0').format(totalExpense)}',
                ),
              ],
            ),
            pw.Divider(),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  '남은 금액:',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                pw.Text(
                  '$currencySymbol ${NumberFormat('#,##0').format(balance)}',
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    color: balance >= 0 ? PdfColors.green : PdfColors.red,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    // 지출 내역 페이지
    if (expenses.isNotEmpty) {
      pdf.addPage(
        pw.Page(
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                '지출 내역',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 10),
              pw.Table(
                border: pw.TableBorder.all(),
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(
                      color: PdfColors.grey300,
                    ),
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(5),
                        child: pw.Text(
                          '날짜',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(5),
                        child: pw.Text(
                          '제목/카테고리',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(5),
                        child: pw.Text(
                          '금액',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  ...expenses
                      .take(20)
                      .map(
                        (expense) => pw.TableRow(
                          children: [
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(5),
                              child: pw.Text(
                                DateFormat('MM/dd HH:mm').format(expense.date),
                              ),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(5),
                              child: pw.Text(expense.title ?? expense.category),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(5),
                              child: pw.Text(
                                '$currencySymbol ${NumberFormat('#,##0').format(expense.amount)}',
                              ),
                            ),
                          ],
                        ),
                      ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    // PDF 출력/공유
    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
      name:
          '${trip.name}_가계부_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );
  }
}
