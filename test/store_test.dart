import 'package:flutter_test/flutter_test.dart';
import 'package:gio_lam/store.dart';

void main() {
  test('thêm nhân viên trùng tên bị từ chối', () {
    final data = AppData.seed(); // Hieu-160, Hoan-170
    expect(data.addEmployee(Employee('Hoan', 170)), isFalse);
    expect(data.addEmployee(Employee('Minh', 150)), isTrue);
    expect(data.employees.map((e) => e.name), ['Hieu', 'Hoan', 'Minh']);
  });

  test('chuyển nhân viên sang cửa hàng khác kèm ca làm', () {
    final from = AppData.seed();
    from.shifts['Hieu'] = [Shift('2026-11-06', clockIn: 480, clockOut: 960)];
    final to = AppData(storeName: 'Rybna 2', employees: [Employee('Lan', 160)]);
    expect(from.moveEmployeeTo(to, 'Hieu'), isTrue);
    expect(from.employees.map((e) => e.name), ['Hoan']);
    expect(from.shifts.containsKey('Hieu'), isFalse);
    expect(to.employees.map((e) => e.name), ['Lan', 'Hieu']);
    expect(to.shifts['Hieu']!.length, 1);
    expect(to.shifts['Hieu']!.first.clockIn, 480);
  });

  test('chuyển nhân viên trùng tên ở cửa hàng đích bị từ chối', () {
    final from = AppData.seed();
    final to =
        AppData(storeName: 'Rybna 2', employees: [Employee('Hieu', 160)]);
    expect(from.moveEmployeeTo(to, 'Hieu'), isFalse);
    expect(from.employees.length, 2);
    expect(to.employees.length, 1);
  });

  test('chuyển nhân viên không có ở cửa hàng nguồn bị từ chối', () {
    final from = AppData.seed();
    final to = AppData(storeName: 'Rybna 2', employees: []);
    expect(from.moveEmployeeTo(to, 'KhongCo'), isFalse);
    expect(to.employees, isEmpty);
  });
}
