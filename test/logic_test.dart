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
}
