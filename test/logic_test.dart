import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gio_lam/logic.dart';
import 'package:gio_lam/store.dart';

void main() {
  test('ca dem 20:00 -> 05:00 = 9h00', () {
    expect(durationMinutes(20 * 60, 5 * 60), 540);
    expect(fmtDuration(540), '9h00');
  });

  test('ca ngay thuong', () {
    expect(durationMinutes(9 * 60, 20 * 60), 660);
    expect(parseHhmm('9:00'), 540);
    expect(parseHhmm('abc'), isNull);
  });

  test('tach Ten-Gia', () {
    expect(parseEmployee('Hieu-160'), ('Hieu', 160));
    expect(parseEmployee('Hoan-170'), ('Hoan', 170));
    expect(parseEmployee('110'), ('110', 110));
  });

  test('gio chuan luu/khoi phuc dung', () {
    final data = AppData.seed();
    data.standardMinutesPerDay = 720;
    final restored = AppData.fromJson(data.toJson());
    expect(restored.standardMinutesPerDay, 720);
    expect(AppData.fromJson({}).standardMinutesPerDay, 480);
  });

  test('nhap tay ngay cu bi chan, ca dem dong dung', () {
    final store = DataStore(File('/tmp/test-gio-lam.json'));
    store.data = AppData.seed();
    // Ca dem: vao 20:00 hom qua
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    store.clockIn('Hieu', when: DateTime(yesterday.year, yesterday.month, yesterday.day, 20, 0));
    // Chua tan ca cu thi khong vao ca moi duoc
    expect(() => store.clockIn('Hieu'), throwsStateError);
    // Tan ca 05:00 sang hom nay
    final now = DateTime.now();
    final sh = store.clockOut('Hieu', when: DateTime(now.year, now.month, now.day, 5, 0));
    expect(sh.total, 540);
    // Nhap tay ngay cu bi chan
    expect(() => store.manualIn('Hoan', '9:00', now: DateTime(2026, 11, 1)), throwsStateError);
  });

  test('trang thai nghi khong tinh gio, nghi giua ca tru gio', () {
    final s = Shift('2026-11-05', clockIn: 9 * 60, clockOut: 20 * 60, breakMinutes: 60);
    expect(s.total, 600); // 11h - 1h nghi = 10h00
    final leave = Shift('2026-11-06', status: 'paidLeave');
    expect(leave.total, 0);
    final data = AppData.seed();
    data.shifts['Hieu'] = [s, leave];
    expect(data.monthTotal('Hieu', 2026, 11), (days: 1, minutes: 600));
    expect(data.monthLeaveDays('Hieu', 2026, 11), 1);
    expect(data.yearPaidLeaveUsed('Hieu', 2026), 1);
  });

  test('sao luu JSON giu nguyen du lieu moi', () {
    final data = AppData.seed();
    data.currency = 'đ';
    data.standardMinutesPerDay = 720;
    data.employees.first.annualLeaveAllowance = 12;
    data.shifts['Hieu'] = [
      Shift('2026-11-05', clockIn: 540, clockOut: 1200,
          status: 'work', breakMinutes: 30, note: 'tăng ca')
    ];
    final restored = AppData.fromJson(
        jsonDecode(jsonEncode(data.toJson())) as Map<String, dynamic>);
    expect(restored.currency, 'đ');
    expect(restored.standardMinutesPerDay, 720);
    expect(restored.employees.first.annualLeaveAllowance, 12);
    final sh = restored.shifts['Hieu']!.first;
    expect(sh.breakMinutes, 30);
    expect(sh.note, 'tăng ca');
    expect(sh.total, 630);
  });

  test('nhieu doan ca/ngay: tan ca roi vao lai duoc, tong cong don', () {
    final store = DataStore(File('/tmp/test-gio-lam-multi.json'));
    store.data = AppData.seed();
    // Doan 1: 9:00-12:00 (3h), doan 2: 14:00-20:00 (6h) cung ngay
    store.clockIn('Hieu', when: DateTime(2026, 11, 5, 9, 0));
    store.clockOut('Hieu', when: DateTime(2026, 11, 5, 12, 0));
    store.clockIn('Hieu', when: DateTime(2026, 11, 5, 14, 0));
    store.clockOut('Hieu', when: DateTime(2026, 11, 5, 20, 0));
    final data = store.data;
    expect(data.shiftsOn('Hieu', '2026-11-05').length, 2);
    expect(data.dayTotalMinutes('Hieu', '2026-11-05'), 540);
    expect(data.monthTotal('Hieu', 2026, 11), (days: 1, minutes: 540));
    // 9h vuot 8h chuan -> tang ca 1h, tinh theo tong ngay
    expect(data.dayOvertime('Hieu', '2026-11-05'), 60);
    expect(data.monthOvertime('Hieu', 2026, 11), 60);
  });

  test('chua tan ca thi khong vao ca moi duoc', () {
    final store = DataStore(File('/tmp/test-gio-lam-multi2.json'));
    store.data = AppData.seed();
    store.clockIn('Hieu', when: DateTime(2026, 11, 5, 9, 0));
    expect(() => store.clockIn('Hieu', when: DateTime(2026, 11, 5, 14, 0)),
        throwsStateError);
  });

  test('chu them doan trung gio bi chan', () {
    final store = DataStore(File('/tmp/test-gio-lam-multi3.json'));
    store.data = AppData.seed();
    store.ownerAddShift('Hieu', '2026-11-05', '9:00', '12:00');
    expect(() => store.ownerAddShift('Hieu', '2026-11-05', '11:00', '15:00'),
        throwsStateError);
    // Khong trung thi them duoc
    store.ownerAddShift('Hieu', '2026-11-05', '13:00', '17:00');
    expect(store.data.shiftsOn('Hieu', '2026-11-05').length, 2);
  });
}
