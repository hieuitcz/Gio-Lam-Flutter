// Logic thuần túy của app chấm công Gio-Lam — không phụ thuộc Flutter UI,
// để kiểm thử được bằng `flutter test`.
//
// Quy tắc:
// - Ca đêm: vào 20:00 hôm trước, ra 05:00 sáng hôm sau = 9h00, tính vào
//   ngày bắt đầu ca (ngày vào ca).
// - Nhập tay chỉ được trong đúng ngày hôm đó, và được ghi chú "nhập tay".
// - Ngày đã qua: nhân viên không sửa được, chỉ chủ cửa hàng mới sửa được.

/// "9:00" / "09:00" -> số phút từ 00:00, hoặc null nếu sai định dạng.
int? parseHhmm(String text) {
  final m = RegExp(r'^([01]?\d|2[0-3]):([0-5]\d)$').firstMatch(text.trim());
  if (m == null) return null;
  return int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!);
}

String fmtHhmm(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

String fmtDuration(int? totalMinutes) {
  if (totalMinutes == null) return '';
  return '${totalMinutes ~/ 60}h${(totalMinutes % 60).toString().padLeft(2, '0')}';
}

/// Số phút làm. Ca đêm (ra < vào) tính sang ngày hôm sau.
/// Vd: 20:00 -> 05:00 = 540 phút = 9h00.
/// Vào/ra cùng phút = 0 phút, không phải 24h (vd: vào 00:24 ra luôn 00:24).
int? durationMinutes(int? clockIn, int? clockOut) {
  if (clockIn == null || clockOut == null) return null;
  var out = clockOut;
  if (out < clockIn) out += 24 * 60;
  return out - clockIn;
}

String _dateStr(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Ngày kết thúc của ca (dạng yyyy-MM-dd). Ca qua đêm (ra < vào) kết
/// thúc vào ngày hôm sau; ca thường kết thúc cùng ngày bắt đầu.
String shiftEndDateStr(String dateStr, int? clockIn, int? clockOut) {
  if (clockIn == null || clockOut == null || clockOut >= clockIn) {
    return dateStr;
  }
  return _dateStr(DateTime.parse(dateStr).add(const Duration(days: 1)));
}

/// Nhân viên được sửa ca khi ca bắt đầu hôm nay, hoặc ca qua đêm kết
/// thúc hôm nay (sáng hôm sau ca vừa xong vẫn sửa được). Ngày khác:
/// chỉ chủ cửa hàng mới sửa được.
bool canEmployeeEditShift(String dateStr, int? clockIn, int? clockOut,
    {DateTime? now}) {
  final today = _dateStr(now ?? DateTime.now());
  return dateStr == today ||
      shiftEndDateStr(dateStr, clockIn, clockOut) == today;
}

/// Tách tên sheet/nhân viên dạng "Tên-ĐơnGiá" thành (tên, đơn giá).
/// "Hieu-160" -> ("Hieu", 160); "110" -> ("110", 110); "Hieu" -> ("Hieu", null).
(String, int?) parseEmployee(String title) {
  final t = title.trim();
  if (RegExp(r'^\d+$').hasMatch(t)) return (t, int.parse(t));
  final idx = t.lastIndexOf('-');
  if (idx > 0) {
    final tail = t.substring(idx + 1).trim();
    if (RegExp(r'^\d+$').hasMatch(tail)) {
      return (t.substring(0, idx).trim(), int.parse(tail));
    }
  }
  return (t, null);
}

/// "Rybna-gio-lam.xlsx" -> "Rybna"; "gio-lam.xlsx" -> "".
String storeNameFromFile(String fileName) {
  final stem = fileName.split('/').last.split('.').first;
  if (stem.endsWith('-gio-lam')) return stem.substring(0, stem.length - '-gio-lam'.length);
  return stem == 'gio-lam' ? '' : stem;
}

bool isToday(DateTime day, {DateTime? now}) {
  now ??= DateTime.now();
  return day.year == now.year && day.month == now.month && day.day == now.day;
}
