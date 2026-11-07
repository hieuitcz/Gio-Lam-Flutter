// Logic thuần túy của app chấm công Gio-Lam — không phụ thuộc Flutter UI,
// để kiểm thử được bằng `flutter test`.
//
// Quy tắc:
// - Ca đêm: vào 20:00 hôm trước, ra 05:00 sáng hôm sau = 9h00, tính vào
//   ngày bắt đầu ca (ngày vào ca).
// - Nhập tay chỉ được trong đúng ngày hôm đó, và được ghi chú "nhập tay".
// - Ngày đã qua: nhân viên không sửa được, chỉ chủ cửa hàng mới sửa được.
// - Mã PIN đăng nhập cloud: 4-6 chữ số, mỗi cửa hàng 1 PIN riêng;
//   PIN suy ra tài khoản Firebase Auth của cửa hàng đó.
import 'dart:convert';

import 'package:crypto/crypto.dart';

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

/// Nhân viên thêm ngày mới chỉ được thêm đúng hôm nay.
bool canEmployeeAddShift(String dateStr, {DateTime? now}) {
  return dateStr == _dateStr(now ?? DateTime.now());
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
  if (stem.endsWith('-gio-lam')) {
    return stem.substring(0, stem.length - '-gio-lam'.length);
  }
  return stem == 'gio-lam' ? '' : stem;
}

bool isToday(DateTime day, {DateTime? now}) {
  now ??= DateTime.now();
  return day.year == now.year && day.month == now.month && day.day == now.day;
}

// --- Mã PIN đăng nhập cloud -------------------------------------------
// Mỗi cửa hàng có 1 mã PIN riêng (4-6 chữ số). Nhập PIN là vào luôn,
// thay cho đăng nhập email/mật khẩu: PIN suy ra tài khoản Firebase
// Auth của đối tượng đó (email + mật khẩu đều suy ra từ PIN nên chủ
// chỉ cần nhớ PIN, không cần nhớ email/mật khẩu).
// GIỚI HẠN TRUNG THỰC: PIN ngắn + hash lưu công khai trong doc
// pins/config nên PIN chỉ ngăn người tò mò xem nhầm cửa hàng, không
// chống được người cố tình dò (4-6 số thì dò hết cũng nhanh). Đừng
// dùng PIN làm mật khẩu cho dữ liệu nhạy cảm khác.

/// Mã PIN hợp lệ: 4-6 chữ số.
bool isValidPin(String pin) => RegExp(r'^\d{4,6}$').hasMatch(pin);

/// SHA-256 hex của mã PIN (lưu trong pins/config, không lưu PIN gốc).
String pinHash(String pin) => sha256.convert(utf8.encode(pin)).toString();

/// Tìm lại mã PIN (4-6 chữ số) từ SHA-256 hash của nó: thử hết các
/// mã 0000-999999, 4 số trước rồi 5, 6 số. PIN ngắn nên dò hết chỉ
/// mất 1-2 giây — đúng như giới hạn đã nói ở trên (hash công khai,
/// PIN chỉ ngăn người tò mò). Dùng để admin xem lại mã PIN chủ sau
/// khi chủ tự đổi, không cần hỏi chủ và không lưu thêm mã PIN ở đâu.
/// Trả về null nếu hash không khớp mã PIN 4-6 chữ số nào.
String? recoverPinFromHash(String hash) {
  for (var len = 4; len <= 6; len++) {
    final max = len == 4
        ? 10000
        : len == 5
            ? 100000
            : 1000000;
    for (var n = 0; n < max; n++) {
      if (pinHash(n.toString().padLeft(len, '0')) == hash) {
        return n.toString().padLeft(len, '0');
      }
    }
  }
  return null;
}

const _viDiacritics = {
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ã': 'a',
  'ả': 'a',
  'ạ': 'a',
  'ă': 'a',
  'ằ': 'a',
  'ắ': 'a',
  'ẳ': 'a',
  'ẵ': 'a',
  'ặ': 'a',
  'ầ': 'a',
  'ấ': 'a',
  'ẩ': 'a',
  'ẫ': 'a',
  'ậ': 'a',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ẻ': 'e',
  'ẹ': 'e',
  'ề': 'e',
  'ế': 'e',
  'ể': 'e',
  'ễ': 'e',
  'ệ': 'e',
  'ì': 'i',
  'í': 'i',
  'î': 'i',
  'ỉ': 'i',
  'ị': 'i',
  'ò': 'o',
  'ó': 'o',
  'ô': 'o',
  'õ': 'o',
  'ỏ': 'o',
  'ọ': 'o',
  'ơ': 'o',
  'ờ': 'o',
  'ớ': 'o',
  'ở': 'o',
  'ỡ': 'o',
  'ợ': 'o',
  'ồ': 'o',
  'ố': 'o',
  'ổ': 'o',
  'ỗ': 'o',
  'ộ': 'o',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'ủ': 'u',
  'ụ': 'u',
  'ư': 'u',
  'ừ': 'u',
  'ứ': 'u',
  'ử': 'u',
  'ữ': 'u',
  'ự': 'u',
  'ỳ': 'y',
  'ý': 'y',
  'ỵ': 'y',
  'ỷ': 'y',
  'ỹ': 'y',
  'đ': 'd',
};

/// Tên cửa hàng -> slug viết thường không dấu, chỉ chữ + số
/// (vd "Rybna" -> "rybna", "Cửa Hàng A" -> "cuahanga").
/// Dùng trong email/mật khẩu tài khoản Firebase của cửa hàng.
String storeSlug(String storeName) {
  final lower = storeName.toLowerCase();
  final buf = StringBuffer();
  for (final ch in lower.split('')) {
    final mapped = _viDiacritics[ch];
    if (mapped != null) {
      buf.write(mapped);
    } else if (RegExp(r'[a-z0-9]').hasMatch(ch)) {
      buf.write(ch);
    }
  }
  return buf.toString();
}

/// Email tài khoản Firebase Auth theo vai trò:
/// cửa hàng -> store-<slug>@gio-lam.local; chủ -> owner@gio-lam.local;
/// admin -> admin@gio-lam.local.
String accountEmail(String role, String storeId) {
  if (role == 'owner') return 'owner@gio-lam.local';
  if (role == 'admin') return 'admin@gio-lam.local';
  return 'store-${storeSlug(storeId)}@gio-lam.local';
}

/// Mật khẩu tài khoản Firebase Auth suy ra từ vai trò + PIN
/// (luôn >= 6 ký tự theo yêu cầu của Firebase Auth).
String accountPassword(String role, String storeId, String pin) {
  if (role == 'owner') return 'gio-lam-owner-$pin';
  if (role == 'admin') return 'gio-lam-admin-$pin';
  return 'gio-lam-${storeSlug(storeId)}-$pin';
}

/// Tìm vai trò từ mã PIN nhập vào, dựa trên hash đã lưu trong
/// pins/config: trả về (role, storeId) — storeId '*' với chủ/admin —
/// hoặc null nếu PIN không khớp cái nào. PIN chủ/admin được kiểm tra
/// TRƯỚC nên nếu trùng hash thì quyền cao hơn thắng.
({String role, String storeId})? resolvePinRole(Map<String, String> storePins,
    String? ownerPinHash, String? adminPinHash, String pin) {
  final h = pinHash(pin);
  if (adminPinHash != null && h == adminPinHash) {
    return (role: 'admin', storeId: '*');
  }
  if (ownerPinHash != null && h == ownerPinHash) {
    return (role: 'owner', storeId: '*');
  }
  for (final entry in storePins.entries) {
    if (h == entry.value) return (role: 'store', storeId: entry.key);
  }
  return null;
}
