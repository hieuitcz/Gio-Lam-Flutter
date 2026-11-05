import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'logic.dart';

/// Dữ liệu app lưu trong 1 file JSON (gio-lam.json) — không cần server,
/// không cần mạng. File nằm trong thư mục dữ liệu của app trên máy tính.

class Employee {
  String name;
  int rate;
  Employee(this.name, this.rate);
  Map<String, dynamic> toJson() => {'name': name, 'rate': rate};
  factory Employee.fromJson(Map<String, dynamic> j) =>
      Employee(j['name'] as String, (j['rate'] as num).toInt());
}

class Shift {
  String date; // yyyy-MM-dd, ngày BẮT ĐẦU ca
  int? clockIn; // phút từ 00:00
  int? clockOut;
  bool inManual;
  bool outManual;
  Shift(this.date, {this.clockIn, this.clockOut, this.inManual = false, this.outManual = false});

  int? get total => durationMinutes(clockIn, clockOut);
  Map<String, dynamic> toJson() => {
        'date': date,
        'clockIn': clockIn,
        'clockOut': clockOut,
        'inManual': inManual,
        'outManual': outManual,
      };
  factory Shift.fromJson(Map<String, dynamic> j) => Shift(
        j['date'] as String,
        clockIn: j['clockIn'] as int?,
        clockOut: j['clockOut'] as int?,
        inManual: j['inManual'] as bool? ?? false,
        outManual: j['outManual'] as bool? ?? false,
      );
}

class AppData {
  String storeName;
  List<Employee> employees;
  // key: tên nhân viên -> danh sách ca (mỗi ngày tối đa 1 ca)
  Map<String, List<Shift>> shifts;
  String? ownerHash; // SHA-256 của mật khẩu chủ, không lưu mật khẩu gốc
  // Giờ chuẩn 1 ngày (phút) — tăng ca tính khi giờ công trong ngày vượt quá số này.
  // Mặc định 480 phút = 8h, chủ cửa hàng đổi được ở tab Cài đặt.
  int standardMinutesPerDay;

  AppData({required this.storeName, required this.employees, Map<String, List<Shift>>? shifts, this.ownerHash, this.standardMinutesPerDay = 480})
      : shifts = shifts ?? {};

  factory AppData.seed() => AppData(
        storeName: 'Rybna',
        employees: [Employee('Hieu', 160), Employee('Hoan', 170)],
      );

  Map<String, dynamic> toJson() => {
        'storeName': storeName,
        'employees': employees.map((e) => e.toJson()).toList(),
        'shifts': shifts.map((k, v) => MapEntry(k, v.map((s) => s.toJson()).toList())),
        'ownerHash': ownerHash,
        'standardMinutesPerDay': standardMinutesPerDay,
      };

  factory AppData.fromJson(Map<String, dynamic> j) => AppData(
        storeName: j['storeName'] as String? ?? 'Rybna',
        employees: (j['employees'] as List? ?? [])
            .map((e) => Employee.fromJson(e as Map<String, dynamic>))
            .toList(),
        shifts: (j['shifts'] as Map<String, dynamic>? ?? {}).map((k, v) => MapEntry(
            k,
            (v as List).map((s) => Shift.fromJson(s as Map<String, dynamic>)).toList())),
        ownerHash: j['ownerHash'] as String?,
        standardMinutesPerDay: (j['standardMinutesPerDay'] as num?)?.toInt() ?? 480,
      );

  Shift? shiftOn(String emp, String date) {
    final list = shifts[emp];
    if (list == null) return null;
    for (final s in list) {
      if (s.date == date) return s;
    }
    return null;
  }

  Shift? openShift(String emp) {
    final list = shifts[emp];
    if (list == null) return null;
    Shift? open;
    for (final s in list) {
      if (s.clockOut == null && s.clockIn != null) {
        if (open == null || s.date.compareTo(open.date) > 0) open = s;
      }
    }
    return open;
  }

  List<Shift> monthShifts(String emp, int year, int month) {
    final list = shifts[emp] ?? [];
    return list.where((s) {
      final d = DateTime.parse(s.date);
      return d.year == year && d.month == month;
    }).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  ({int days, int minutes}) monthTotal(String emp, int year, int month) {
    var days = 0;
    var minutes = 0;
    for (final s in monthShifts(emp, year, month)) {
      final t = s.total;
      if (t != null) {
        days++;
        minutes += t;
      }
    }
    return (days: days, minutes: minutes);
  }
}

class DataStore {
  final File file;
  late AppData data;

  DataStore(this.file);

  Future<void> load() async {
    if (await file.exists()) {
      try {
        data = AppData.fromJson(jsonDecode(await file.readAsString()) as Map<String, dynamic>);
        return;
      } catch (_) {
        // File hỏng: giữ lại bản hỏng rồi tạo mới, không mất hẳn không báo.
        try {
          await file.copy('${file.path}.hong');
        } catch (_) {}
      }
    }
    data = AppData.seed();
    await save();
  }

  Future<void> save() async {
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(data.toJson()));
  }

  // -- mật khẩu chủ ---------------------------------------------------
  bool get ownerPasswordSet => data.ownerHash != null;
  void setOwnerPassword(String password) {
    data.ownerHash = sha256.convert(utf8.encode(password)).toString();
  }

  bool checkOwnerPassword(String password) =>
      data.ownerHash != null &&
      sha256.convert(utf8.encode(password)).toString() == data.ownerHash;

  // -- ca làm ----------------------------------------------------------
  String _today() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  void clockIn(String emp, {DateTime? when}) {
    when ??= DateTime.now();
    if (data.openShift(emp) != null) {
      throw StateError('Ca trước chưa tan ca. Tan ca trước đã rồi mới vào ca mới được.');
    }
    final day = _dayStr(when);
    if (data.shiftOn(emp, day) != null) throw StateError('Hôm nay đã có ca rồi.');
    final minutes = when.hour * 60 + when.minute;
    (data.shifts[emp] ??= []).add(Shift(day, clockIn: minutes));
  }

  /// Tan ca. Đóng ca đang mở — ca đó có thể là ca đêm hôm qua.
  Shift clockOut(String emp, {DateTime? when}) {
    when ??= DateTime.now();
    final shift = data.openShift(emp);
    if (shift == null) throw StateError('Chưa vào ca nên không tan ca được.');
    final start = DateTime.parse(shift.date);
    if (when.difference(start).inDays > 1) {
      throw StateError('Ca này đã quá 1 ngày. Nhờ chủ cửa hàng sửa.');
    }
    shift.clockOut = when.hour * 60 + when.minute;
    return shift;
  }

  void manualIn(String emp, String hhmm, {DateTime? now}) {
    now ??= DateTime.now();
    final day = _dayStr(now);
    if (day != _today()) {
      throw StateError('Chỉ nhập tay được trong đúng ngày hôm đó, không nhập ngày cũ được.');
    }
    final minutes = parseHhmm(hhmm);
    if (minutes == null) throw StateError('Giờ sai định dạng. Nhập dạng 9:00 hoặc 20:00.');
    if (data.openShift(emp) != null) throw StateError('Ca trước chưa tan ca.');
    if (data.shiftOn(emp, day) != null) throw StateError('Hôm nay đã có ca rồi.');
    (data.shifts[emp] ??= []).add(Shift(day, clockIn: minutes, inManual: true));
  }

  /// Nhập tay giờ ra trong đúng ngày hôm nay (kể cả đóng ca đêm hôm qua).
  Shift manualOut(String emp, String hhmm, {DateTime? now}) {
    now ??= DateTime.now();
    if (_dayStr(now) != _today()) {
      throw StateError('Chỉ nhập tay được trong đúng ngày hôm đó, không nhập ngày cũ được.');
    }
    final minutes = parseHhmm(hhmm);
    if (minutes == null) throw StateError('Giờ sai định dạng. Nhập dạng 9:00 hoặc 20:00.');
    final shift = data.openShift(emp);
    if (shift == null) throw StateError('Chưa vào ca nên không nhập giờ ra được.');
    final start = DateTime.parse(shift.date);
    if (now.difference(start).inDays > 1) {
      throw StateError('Ca này đã quá 1 ngày. Nhờ chủ cửa hàng sửa.');
    }
    shift.clockOut = minutes;
    shift.outManual = true;
    return shift;
  }

  /// Chủ cửa hàng sửa/thêm ca ngày bất kỳ (kể cả ngày cũ).
  void ownerSetShift(String emp, String date, String? clockIn, String? clockOut) {
    final ci = clockIn == null || clockIn.isEmpty ? null : parseHhmm(clockIn);
    final co = clockOut == null || clockOut.isEmpty ? null : parseHhmm(clockOut);
    if ((clockIn != null && clockIn.isNotEmpty && ci == null) ||
        (clockOut != null && clockOut.isNotEmpty && co == null)) {
      throw StateError('Giờ sai định dạng. Nhập dạng 9:00 hoặc 20:00.');
    }
    final existing = data.shiftOn(emp, date);
    if (existing != null) {
      existing.clockIn = ci;
      existing.clockOut = co;
    } else {
      (data.shifts[emp] ??= []).add(Shift(date, clockIn: ci, clockOut: co));
    }
  }

  static String _dayStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
