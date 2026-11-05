import 'package:flutter_test/flutter_test.dart';
import 'package:gio_lam/report_pdf.dart';
import 'package:gio_lam/store.dart';

void main() {
  test('tang ca tinh theo ngay, vuot 8h', () {
    expect(dayOvertimeMinutes(540, 480), 60); // 9h00 -> tang ca 1h00
    expect(dayOvertimeMinutes(480, 480), 0); // dung 8h -> khong tang ca
    expect(dayOvertimeMinutes(300, 480), 0);
    expect(dayOvertimeMinutes(600, 720), 0); // gio chuan 12h thi 10h chua tang ca
  });

  test('xuat PDF thang co noi dung', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final data = AppData.seed();
    final now = DateTime.now();
    final day =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    data.shifts['Hieu'] = [
      Shift(day, clockIn: 20 * 60, clockOut: 5 * 60), // ca dem 9h00
    ];
    final bytes = await buildMonthPdf(
      data: data,
      employee: data.employees.first,
      year: now.year,
      month: now.month,
    );
    expect(bytes.length, greaterThan(1000));
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });
}
