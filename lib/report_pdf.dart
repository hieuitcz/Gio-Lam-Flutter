import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'logic.dart';
import 'store.dart';

// Xuất báo cáo PDF tháng — mẫu theo app iOS ChamCongHieuIT
// (Services/PDFReportGenerator.swift): khổ A4, tiêu đề "BẢNG CHẤM CÔNG",
// thông tin nhân viên/cửa hàng, bảng ca làm, phần tổng kết + tiền công.
// Tăng ca tính theo tổng giờ của cả ngày, vượt quá giờ chuẩn của cửa hàng
// (mặc định 8h/ngày, chủ cửa hàng đổi được ở tab Cài đặt).
// Tiếng Việt dùng font Roboto kèm trong app (assets/fonts).
// 1 ngày có thể có nhiều đoạn ca: mỗi đoạn 1 dòng, tăng ca của ngày
// chỉ ghi ở dòng cuối cùng của ngày đó — giống app iOS.

/// Tăng ca của 1 ngày = số phút vượt quá giờ chuẩn.
int dayOvertimeMinutes(int dayTotalMinutes, int standardMinutesPerDay) =>
    dayTotalMinutes > standardMinutesPerDay
        ? dayTotalMinutes - standardMinutesPerDay
        : 0;

String _dateStr(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

String _weekday(DateTime d) =>
    ['CN', 'T2', 'T3', 'T4', 'T5', 'T6', 'T7'][d.weekday % 7];

/// 1 dòng trong bảng PDF cho 1 đoạn ca (shifts[i]).
/// Tăng ca của ngày chỉ hiện ở dòng cuối cùng của ngày đó.
List<String> _pdfRow(
    List<Shift> shifts, int i, AppData data, String employeeName) {
  final s = shifts[i];
  final d = DateTime.parse(s.date);
  final isLastOfDay =
      i == shifts.length - 1 || shifts[i + 1].date != s.date;
  final notes = <String>[];
  if (s.status != 'work') notes.add(shiftStatusTitle(s.status));
  if (s.inManual) notes.add('vào: nhập tay');
  if (s.outManual) notes.add('ra: nhập tay');
  if (s.clockOut == null && s.status == 'work') {
    notes.add('chưa tan ca');
  }
  if (s.breakMinutes > 0) notes.add('nghỉ ${s.breakMinutes}p');
  if (s.note.isNotEmpty) notes.add(s.note);
  if (notes.isNotEmpty) {
    notes[0] = notes[0][0].toUpperCase() + notes[0].substring(1);
  }
  final isWork = s.status == 'work';
  final dayOt =
      isLastOfDay ? data.dayOvertime(employeeName, s.date) : 0;
  return [
    _dateStr(d),
    _weekday(d),
    s.clockIn == null ? '—' : fmtHhmm(s.clockIn!),
    s.clockOut == null ? '—' : fmtHhmm(s.clockOut!),
    isWork ? fmtDuration(s.total) : '—',
    !isWork || dayOt == 0 ? '—' : fmtDuration(dayOt),
    notes.join(', '),
  ];
}

Future<Uint8List> buildMonthPdf({
  required AppData data,
  required Employee employee,
  required int year,
  required int month,
}) async {
  final regular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
  final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Roboto-Bold.ttf'));
  final theme = pw.ThemeData.withFont(base: regular, bold: bold);

  final shifts = data.monthShifts(employee.name, year, month);
  final total = data.monthTotal(employee.name, year, month);
  final standard = data.standardMinutesPerDay;
  // Tăng ca tính theo TỔNG giờ của cả ngày (cộng các đoạn ca),
  // không tính riêng từng đoạn — giống app iOS.
  final overtimeTotal = data.monthOvertime(employee.name, year, month);
  final pay = total.minutes / 60 * employee.rate;

  final doc = pw.Document(theme: theme);
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (context) => [
        pw.Center(
          child: pw.Text('BẢNG CHẤM CÔNG',
              style: pw.TextStyle(font: bold, fontSize: 20)),
        ),
        pw.SizedBox(height: 6),
        pw.Center(
          child: pw.Text('Tháng $month/$year',
              style: const pw.TextStyle(fontSize: 12)),
        ),
        pw.SizedBox(height: 18),
        pw.Text('Họ và tên: ${employee.name}',
            style: const pw.TextStyle(fontSize: 11)),
        pw.SizedBox(height: 4),
        pw.Text('Cửa hàng: ${data.storeName}',
            style: const pw.TextStyle(fontSize: 11)),
        pw.SizedBox(height: 4),
        pw.Text(
            'Đơn giá: ${employee.rate} ${data.currency}/giờ',
            style: const pw.TextStyle(fontSize: 11)),
        pw.SizedBox(height: 16),
        pw.TableHelper.fromTextArray(
          headers: const [
            'Ngày',
            'Thứ',
            'Vào',
            'Ra',
            'Giờ công',
            'Tăng ca',
            'Ghi chú',
          ],
          data: [
            for (var i = 0; i < shifts.length; i++)
              _pdfRow(shifts, i, data, employee.name),
          ],
          headerStyle: pw.TextStyle(font: bold, fontSize: 9),
          cellStyle: const pw.TextStyle(fontSize: 9),
          headerDecoration:
              const pw.BoxDecoration(color: PdfColors.grey200),
          cellAlignment: pw.Alignment.center,
          headerAlignment: pw.Alignment.center,
          columnWidths: {
            0: const pw.FixedColumnWidth(70),
            1: const pw.FixedColumnWidth(34),
            2: const pw.FixedColumnWidth(44),
            3: const pw.FixedColumnWidth(44),
            4: const pw.FixedColumnWidth(60),
            5: const pw.FixedColumnWidth(56),
            6: const pw.FlexColumnWidth(),
          },
        ),
        pw.SizedBox(height: 18),
        pw.Text('Tổng kết tháng $month/$year',
            style: pw.TextStyle(font: bold, fontSize: 12)),
        pw.SizedBox(height: 6),
        pw.Text('Số ngày làm: ${total.days} ngày',
            style: const pw.TextStyle(fontSize: 11)),
        pw.SizedBox(height: 4),
        pw.Text('Tổng giờ: ${fmtDuration(total.minutes)}',
            style: const pw.TextStyle(fontSize: 11)),
        pw.SizedBox(height: 4),
        pw.Text(
            'Tăng ca (trên ${(standard / 60).toStringAsFixed(standard % 60 == 0 ? 0 : 1)}h/ngày): ${fmtDuration(overtimeTotal)}',
            style: const pw.TextStyle(fontSize: 11)),
        pw.SizedBox(height: 4),
        pw.Text(
            'Nghỉ phép: ${data.monthLeaveDays(employee.name, year, month)} ngày',
            style: const pw.TextStyle(fontSize: 11)),
        pw.SizedBox(height: 4),
        pw.Text(
            'Tiền công: ${pay.toStringAsFixed(0)} ${data.currency} (giá ${employee.rate} ${data.currency}/giờ)',
            style: pw.TextStyle(font: bold, fontSize: 11)),
      ],
    ),
  );
  return doc.save();
}
