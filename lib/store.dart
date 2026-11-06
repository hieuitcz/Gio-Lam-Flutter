import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'logic.dart';

/// Dữ liệu app lưu trong 1 file JSON (gio-lam.json) — không cần server,
/// không cần mạng. File nằm trong thư mục dữ liệu của app trên máy tính.

// Trạng thái ca — giống app iOS (WorkStatus): chỉ ca "Đi làm" mới tính giờ.
const List<(String, String)> shiftStatuses = [
  ('work', 'Đi làm'),
  ('paidLeave', 'Nghỉ phép'),
  ('unpaidLeave', 'Nghỉ không lương'),
  ('holiday', 'Nghỉ lễ'),
];

String shiftStatusTitle(String status) =>
    shiftStatuses.firstWhere((s) => s.$1 == status, orElse: () => ('work', 'Đi làm')).$2;

class Employee {
  String name;
  int rate;
  int annualLeaveAllowance; // tổng ngày phép năm
  Employee(this.name, this.rate, {this.annualLeaveAllowance = 0});
  Map<String, dynamic> toJson() => {
        'name': name,
        'rate': rate,
        'annualLeaveAllowance': annualLeaveAllowance,
      };
  factory Employee.fromJson(Map<String, dynamic> j) => Employee(
        j['name'] as String,
        (j['rate'] as num).toInt(),
        annualLeaveAllowance: (j['annualLeaveAllowance'] as num?)?.toInt() ?? 0,
      );
}

class Shift {
  String date; // yyyy-MM-dd, ngày BẮT ĐẦU ca
  int? clockIn; // phút từ 00:00
  int? clockOut;
  bool inManual;
  bool outManual;
  String status; // work | paidLeave | unpaidLeave | holiday
  int breakMinutes; // nghỉ giữa ca
  String note; // ghi chú
  Shift(this.date,
      {this.clockIn,
      this.clockOut,
      this.inManual = false,
      this.outManual = false,
      this.status = 'work',
      this.breakMinutes = 0,
      this.note = ''});

  /// Giờ công: chỉ ca "Đi làm" mới tính, trừ nghỉ giữa ca.
  int? get total {
    if (status != 'work') return 0;
    final d = durationMinutes(clockIn, clockOut);
    if (d == null) return null;
    return (d - breakMinutes).clamp(0, 24 * 60);
  }

  Map<String, dynamic> toJson() => {
        'date': date,
        'clockIn': clockIn,
        'clockOut': clockOut,
        'inManual': inManual,
        'outManual': outManual,
        'status': status,
        'breakMinutes': breakMinutes,
        'note': note,
      };
  factory Shift.fromJson(Map<String, dynamic> j) => Shift(
        j['date'] as String,
        clockIn: j['clockIn'] as int?,
        clockOut: j['clockOut'] as int?,
        inManual: j['inManual'] as bool? ?? false,
        outManual: j['outManual'] as bool? ?? false,
        status: j['status'] as String? ?? 'work',
        breakMinutes: (j['breakMinutes'] as num?)?.toInt() ?? 0,
        note: j['note'] as String? ?? '',
      );
}

class AppData {
  String storeName;
  List<Employee> employees;
  // key: tên nhân viên -> danh sách đoạn ca.
  // 1 ngày có thể có NHIỀU đoạn ca (tan ca rồi vào ca lại được,
  // chạy nhiều cửa hàng rồi quay lại vẫn tính tiếp) — giống app iOS.
  Map<String, List<Shift>> shifts;
  String? ownerHash; // SHA-256 của mật khẩu chủ, không lưu mật khẩu gốc
  // Giờ chuẩn 1 ngày (phút) — tăng ca tính khi giờ công trong ngày vượt quá số này.
  // Mặc định 480 phút = 8h, chủ cửa hàng đổi được ở tab Cài đặt.
  int standardMinutesPerDay;
  // Loại tiền lương: 'Kč' hoặc 'đ' (giống app iOS).
  String currency;
  // Font chữ giao diện: 'Lexend' (mặc định) hoặc 'System' (font hệ thống).
  String fontFamily;
  // Ẩn tiền công với nhân viên (chỉ chủ/admin mới thấy tiền). Mặc định bật.
  bool hidePay;
  // Mốc đồng bộ cloud gần nhất (millisecondsSinceEpoch của lần
  // upload/download cuối). Lưu trong JSON đã ký để app nhớ được sau
  // khi khởi động lại: chỉ tải dữ liệu cloud về khi bản cloud mới hơn
  // mốc này, tránh ghi đè giờ công nhập offline chưa kịp đẩy lên.
  int cloudUpdatedAt;
  AppData({required this.storeName, required this.employees, Map<String, List<Shift>>? shifts, this.ownerHash, this.standardMinutesPerDay = 480, this.currency = 'Kč', this.fontFamily = 'Lexend', this.hidePay = true, this.cloudUpdatedAt = 0})
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
        'currency': currency,
        'fontFamily': fontFamily,
        'hidePay': hidePay,
        'cloudUpdatedAt': cloudUpdatedAt,
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
        currency: j['currency'] as String? ?? 'Kč',
        fontFamily: j['fontFamily'] as String? ?? 'Lexend',
        hidePay: j['hidePay'] as bool? ?? true,
        cloudUpdatedAt: (j['cloudUpdatedAt'] as num?)?.toInt() ?? 0,
      );

  /// Tất cả đoạn ca của 1 ngày (đã sắp theo giờ vào).
  List<Shift> shiftsOn(String emp, String date) {
    final list = (shifts[emp] ?? []).where((s) => s.date == date).toList()
      ..sort((a, b) => (a.clockIn ?? 0).compareTo(b.clockIn ?? 0));
    return list;
  }

  /// Tổng giờ công (chỉ ca "Đi làm" đã chốt) của 1 ngày.
  int dayTotalMinutes(String emp, String date) {
    var total = 0;
    for (final s in shiftsOn(emp, date)) {
      if (s.status != 'work') continue;
      total += s.total ?? 0;
    }
    return total;
  }

  /// Tăng ca của 1 ngày = tổng giờ ngày đó vượt quá giờ chuẩn.
  int dayOvertime(String emp, String date) =>
      (dayTotalMinutes(emp, date) - standardMinutesPerDay).clamp(0, 24 * 60);

  /// Tổng tăng ca cả tháng (cộng tăng ca từng ngày).
  int monthOvertime(String emp, int year, int month) {
    final dates = <String>{};
    for (final s in monthShifts(emp, year, month)) {
      dates.add(s.date);
    }
    var total = 0;
    for (final d in dates) {
      total += dayOvertime(emp, d);
    }
    return total;
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
      ..sort((a, b) {
        final c = a.date.compareTo(b.date);
        return c != 0 ? c : (a.clockIn ?? 0).compareTo(b.clockIn ?? 0);
      });
  }

  ({int days, int minutes}) monthTotal(String emp, int year, int month) {
    final dates = <String>{};
    var minutes = 0;
    for (final s in monthShifts(emp, year, month)) {
      if (s.status != 'work') continue;
      final t = s.total;
      if (t != null) {
        dates.add(s.date);
        minutes += t;
      }
    }
    return (days: dates.length, minutes: minutes);
  }

  /// Số ngày nghỉ phép của nhân viên trong 1 tháng.
  int monthLeaveDays(String emp, int year, int month, {String status = 'paidLeave'}) {
    return monthShifts(emp, year, month)
        .where((s) => s.status == status)
        .map((s) => s.date)
        .toSet()
        .length;
  }

  /// Số ngày nghỉ phép đã dùng trong 1 năm.
  int yearPaidLeaveUsed(String emp, int year) {
    final list = shifts[emp] ?? [];
    return list
        .where((s) {
          final d = DateTime.parse(s.date);
          return d.year == year && s.status == 'paidLeave';
        })
        .map((s) => s.date)
        .toSet()
        .length;
  }
}

class DataStore {
  final File file;
  late AppData data;

  /// null = dữ liệu bình thường; 'recovered' = file bị sửa ngoài, đã khôi
  /// phục từ bản sao lưu; 'lost' = file bị sửa ngoài và không còn bản sao
  /// lưu tốt (dữ liệu về trắng, chủ khôi phục từ file sao lưu đã xuất).
  String? tamperStatus;
  String? _keyHex; // khóa ký HMAC, cache trong bộ nhớ

  DataStore(this.file);

  File get _keyFile => File('${file.path}.key');
  File get _bakFile => File('${file.path}.bak');
  // Mật khẩu tổng (admin) lưu RIÊNG 1 file, không nằm trong JSON dữ
  // liệu đã ký — để khôi phục dữ liệu cũng không mất mật khẩu tổng.
  File get _masterFile => File('${file.path}.master');
  String? _masterHash; // cache SHA-256 của mật khẩu tổng

  /// Đọc mật khẩu tổng (nếu có) lúc khởi động.
  Future<void> _loadMasterHash() async {
    try {
      if (await _masterFile.exists()) {
        final h = (await _masterFile.readAsString()).trim();
        if (h.length == 64) _masterHash = h;
      }
    } catch (_) {}
  }

  /// Khóa ký ngẫu nhiên 32 byte, lưu riêng 1 file. Tạo 1 lần rồi dùng mãi.
  Future<List<int>> _signKey() async {
    if (_keyHex != null) return _hexToBytes(_keyHex!);
    try {
      if (await _keyFile.exists()) {
        _keyHex = (await _keyFile.readAsString()).trim();
        if (_keyHex!.length == 64) return _hexToBytes(_keyHex!);
      }
    } catch (_) {}
    final rnd = Random.secure();
    final bytes = List<int>.generate(32, (_) => rnd.nextInt(256));
    _keyHex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    try {
      await _keyFile.parent.create(recursive: true);
      await _keyFile.writeAsString(_keyHex!);
    } catch (_) {}
    return bytes;
  }

  static List<int> _hexToBytes(String hex) {
    final out = <int>[];
    for (var i = 0; i + 1 < hex.length; i += 2) {
      out.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return out;
  }

  String _hmacHex(List<int> key, String payload) =>
      Hmac(sha256, key).convert(utf8.encode(payload)).toString();

  /// File hiện tại trên đĩa có còn nguyên vẹn không (đã ký đúng / file cũ).
  Future<bool> _onDiskFileOk(List<int> key) async {
    try {
      if (!await file.exists()) return true;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map && decoded.containsKey('sig')) {
        return _hmacHex(key, jsonEncode(decoded['data'])) == decoded['sig'];
      }
      return true; // file cũ chưa ký thì coi là nguyên vẹn
    } catch (_) {
      return false;
    }
  }

  Future<void> load() async {
    tamperStatus = null;
    await _loadMasterHash();
    if (!await file.exists()) {
      data = AppData.seed();
      await save();
      return;
    }
    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is Map && decoded.containsKey('sig') && decoded.containsKey('data')) {
        final key = await _signKey();
        if (_hmacHex(key, jsonEncode(decoded['data'])) == decoded['sig']) {
          data = AppData.fromJson(decoded['data'] as Map<String, dynamic>);
          return;
        }
        // Chữ ký không khớp: file đã bị sửa bên ngoài.
        tamperStatus = 'tampered';
        try {
          final now = DateTime.now();
          final stamp =
              '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
          await file.copy('${file.path}.tampered-$stamp');
        } catch (_) {}
        if (await _bakFile.exists()) {
          try {
            final braw = await _bakFile.readAsString();
            final bdec = jsonDecode(braw);
            if (bdec is Map && bdec.containsKey('sig')) {
              if (_hmacHex(key, jsonEncode(bdec['data'])) == bdec['sig']) {
                data = AppData.fromJson(bdec['data'] as Map<String, dynamic>);
                tamperStatus = 'recovered';
                await save();
                return;
              }
            } else {
              // Bản sao lưu cũ chưa ký: dùng tạm rồi ký lại.
              data = AppData.fromJson(bdec as Map<String, dynamic>);
              tamperStatus = 'recovered';
              await save();
              return;
            }
          } catch (_) {}
        }
        data = AppData.seed();
        tamperStatus = 'lost';
        await save();
        return;
      }
      // File cũ chưa ký (trước khi có tính năng này): đọc bình thường,
      // lần lưu sau sẽ tự ký.
      data = AppData.fromJson(decoded as Map<String, dynamic>);
    } catch (_) {
      // File hỏng: giữ lại bản hỏng rồi tạo mới, không mất hẳn không báo.
      try {
        await file.copy('${file.path}.hong');
      } catch (_) {}
      data = AppData.seed();
      await save();
    }
  }

  Future<void> save() async {
    await file.parent.create(recursive: true);
    final key = await _signKey();
    final payload = jsonEncode(data.toJson());
    final sig = _hmacHex(key, payload);
    // Sao lưu bản tốt hiện tại trước khi ghi đè (chỉ khi file trên đĩa
    // còn nguyên vẹn — không ghi đè bản sao lưu bằng file đã bị sửa).
    if (await _onDiskFileOk(key)) {
      try {
        if (await file.exists()) await file.copy(_bakFile.path);
      } catch (_) {}
    }
    final content = jsonEncode({'v': 1, 'data': data.toJson(), 'sig': sig});
    await file.writeAsString(content);
  }

  // -- mật khẩu chủ ---------------------------------------------------
  bool get ownerPasswordSet => data.ownerHash != null;
  void setOwnerPassword(String password) {
    data.ownerHash = sha256.convert(utf8.encode(password)).toString();
  }

  bool checkOwnerPassword(String password) =>
      data.ownerHash != null &&
      sha256.convert(utf8.encode(password)).toString() == data.ownerHash;

  // -- mật khẩu tổng (admin, quyền cao nhất) --------------------------
  // Lưu riêng file .master bên cạnh file dữ liệu, không nằm trong JSON
  // đã ký nên khôi phục dữ liệu cũng không mất. Mật khẩu tổng luôn mở
  // được chế độ admin, kể cả khi mật khẩu chủ đã bị đổi.
  bool get hasMasterPassword => _masterHash != null;

  Future<void> setMasterPassword(String password) async {
    _masterHash = sha256.convert(utf8.encode(password)).toString();
    try {
      await _masterFile.parent.create(recursive: true);
      await _masterFile.writeAsString(_masterHash!);
    } catch (_) {}
  }

  bool checkMasterPassword(String password) =>
      _masterHash != null &&
      sha256.convert(utf8.encode(password)).toString() == _masterHash;

  /// Vai trò khi nhập mật khẩu ở Ctrl+H: 'admin' nếu đúng mật khẩu tổng,
  /// 'owner' nếu đúng mật khẩu chủ, null nếu sai. Mật khẩu tổng được
  /// kiểm tra TRƯỚC nên admin luôn vào được dù mật khẩu chủ đã đổi.
  String? resolveLoginRole(String password) {
    if (checkMasterPassword(password)) return 'admin';
    if (checkOwnerPassword(password)) return 'owner';
    return null;
  }

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
    // Tan ca rồi vào ca lại được: 1 ngày nhiều đoạn ca (chạy nhiều
    // cửa hàng, quay lại làm tiếp). Chỉ chặn khi ca trước chưa tan.
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
    // Nhập tay tạo thêm 1 đoạn ca mới trong ngày (không ghi đè đoạn cũ).
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

  /// Kiểm tra đoạn ca mới/sửa có trùng giờ với đoạn khác cùng ngày không.
  void _checkOverlap(String emp, String date, int? clockIn, int? clockOut,
      {Shift? except}) {
    if (clockIn == null || clockOut == null) return;
    final aStart = clockIn;
    final aEnd = clockOut < clockIn ? clockOut + 24 * 60 : clockOut;
    for (final s in data.shiftsOn(emp, date)) {
      if (identical(s, except) || s.status != 'work') continue;
      if (s.clockIn == null || s.clockOut == null) continue;
      final bStart = s.clockIn!;
      final bEnd =
          s.clockOut! < s.clockIn! ? s.clockOut! + 24 * 60 : s.clockOut!;
      if (aStart < bEnd && bStart < aEnd) {
        throw StateError(
            'Trùng giờ với đoạn ca ${fmtHhmm(s.clockIn!)}–${fmtHhmm(s.clockOut!)} cùng ngày.');
      }
    }
  }

  ({int? ci, int? co}) _parseShiftTimes(
      String? clockIn, String? clockOut, int breakMinutes) {
    final ci = clockIn == null || clockIn.isEmpty ? null : parseHhmm(clockIn);
    final co = clockOut == null || clockOut.isEmpty ? null : parseHhmm(clockOut);
    if ((clockIn != null && clockIn.isNotEmpty && ci == null) ||
        (clockOut != null && clockOut.isNotEmpty && co == null)) {
      throw StateError('Giờ sai định dạng. Nhập dạng 9:00 hoặc 20:00.');
    }
    if (breakMinutes < 0 || breakMinutes > 240) {
      throw StateError('Nghỉ giữa ca từ 0 đến 240 phút.');
    }
    return (ci: ci, co: co);
  }

  /// Chủ cửa hàng THÊM 1 đoạn ca ngày bất kỳ (kể cả ngày cũ).
  void ownerAddShift(String emp, String date, String? clockIn, String? clockOut,
      {String status = 'work', int breakMinutes = 0, String note = ''}) {
    final t = _parseShiftTimes(clockIn, clockOut, breakMinutes);
    if (status == 'work') {
      _checkOverlap(emp, date, t.ci, t.co);
    }
    (data.shifts[emp] ??= []).add(Shift(date,
        clockIn: t.ci,
        clockOut: t.co,
        status: status,
        breakMinutes: breakMinutes,
        note: note));
  }

  /// Chủ cửa hàng SỬA 1 đoạn ca có sẵn.
  void ownerUpdateShift(Shift shift, String emp, String date, String? clockIn,
      String? clockOut,
      {String status = 'work', int breakMinutes = 0, String note = ''}) {
    final t = _parseShiftTimes(clockIn, clockOut, breakMinutes);
    if (status == 'work') {
      _checkOverlap(emp, date, t.ci, t.co, except: shift);
    }
    shift.date = date;
    shift.clockIn = t.ci;
    shift.clockOut = t.co;
    shift.status = status;
    shift.breakMinutes = breakMinutes;
    shift.note = note;
  }

  void deleteShift(Shift shift) {
    for (final list in data.shifts.values) {
      list.remove(shift);
    }
  }

  static String _dayStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
