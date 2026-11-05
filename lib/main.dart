import 'dart:async';
import 'dart:io';

import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import 'logic.dart';
import 'report_pdf.dart';
import 'store.dart';

// Giao diện kiểu app chấm công iOS: thanh tab dưới cùng (Chấm công / Báo cáo /
// Cài đặt), nền xám nhóm, thẻ trắng bo tròn, tiêu đề lớn.
// Tab Cài đặt chỉ chủ cửa hàng mới thấy — không có nút hiện ra ngoài,
// mở bằng phím tắt Ctrl+H rồi nhập mật khẩu chủ.

const _ink = Color(0xFF0F172A);
const _muted = Color(0xFF64748B);
const _line = Color(0xFFE2E8F0);
const _bg = Color(0xFFF1F5F9);
const _accent = Color(0xFF0D9488);
const _accentDark = Color(0xFF0F766E);
const _danger = Color(0xFFDC2626);
const _appVersion = '1.0.0';
const _releasesUrl = 'https://github.com/hieuitcz/Gio-Lam-Flutter/releases';
const _issuesUrl = 'https://github.com/hieuitcz/Gio-Lam-Flutter/issues/new';
const _amber = Color(0xFFB45309);
const _amberBg = Color(0xFFFEF3C7);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Cửa sổ nhỏ kiểu iPad (800x1024), không mở rộng to như màn hình PC.
  await windowManager.ensureInitialized();
  const options = WindowOptions(
    size: Size(800, 1024),
    minimumSize: Size(520, 720),
    maximumSize: Size(900, 1150),
    center: true,
    title: 'Gio-Lam — Chấm công',
  );
  windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  // Dữ liệu lưu trong thư mục riêng của app (Windows: AppData),
  // không để lộ trong Documents cho nhân viên mò ra sửa.
  // File cũ ở Documents (nếu có) được chuyển qua đây 1 lần duy nhất.
  final supportDir = await getApplicationSupportDirectory();
  final dataFile = File('${supportDir.path}/gio-lam.json');
  if (!await dataFile.exists()) {
    final oldFile =
        File('${(await getApplicationDocumentsDirectory()).path}/gio-lam.json');
    if (await oldFile.exists()) {
      try {
        await oldFile.copy(dataFile.path);
        await oldFile.rename('${oldFile.path}.cu');
      } catch (_) {}
    }
  }
  final store = DataStore(dataFile);
  await store.load();
  runApp(GioLamApp(store: store));
}

class _OwnerIntent extends Intent {
  const _OwnerIntent();
}

class GioLamApp extends StatelessWidget {
  final DataStore store;
  const GioLamApp({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gio-Lam — Chấm công',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: _accent,
        useMaterial3: true,
        scaffoldBackgroundColor: _bg,
        fontFamily: 'Segoe UI',
      ),
      home: HomePage(store: store),
    );
  }
}

class HomePage extends StatefulWidget {
  final DataStore store;
  const HomePage({super.key, required this.store});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? _employee;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  bool _ownerMode = false;
  DateTime _now = DateTime.now();
  int _tab = 0;
  String? _lastPdfPath;

  @override
  void initState() {
    super.initState();
    _employee = widget.store.data.employees.isNotEmpty
        ? widget.store.data.employees.first.name
        : null;
    _tick();
    // Báo cho chủ biết nếu file dữ liệu đã bị sửa bên ngoài.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final status = _s.tamperStatus;
      if (status == 'recovered') {
        _showTamperDialog(
            'Phát hiện file dữ liệu đã bị sửa bên ngoài.',
            'App đã tự khôi phục từ bản sao lưu gần nhất còn nguyên vẹn. '
            'File bị sửa được giữ lại bên cạnh file dữ liệu để anh kiểm tra.');
      } else if (status == 'lost') {
        _showTamperDialog(
            'Phát hiện file dữ liệu đã bị sửa bên ngoài.',
            'Không còn bản sao lưu tốt nên dữ liệu đã về trắng. Anh khôi phục '
            'từ file sao lưu đã xuất trong Cài đặt > Sao lưu dữ liệu > '
            'Khôi phục từ file.');
      }
    });
  }

  // --- Giới thiệu + Hỗ trợ: ai cũng xem được (nut ⓘ ở đầu tab Chấm công) ---
  Future<void> _showAboutDialog() async {
    final data = _s.data;
    await showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Gio-Lam — Chấm công'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            const Text('Phiên bản $_appVersion'),
            const SizedBox(height: 4),
            Text('Phát triển bởi ${data.developerName}'),
            const SizedBox(height: 4),
            Text('Liên hệ: ${data.developerContact}'),
          ],
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () {
              Navigator.pop(ctx);
              _showGuideDialog();
            },
            child: const Text('Hướng dẫn sử dụng'),
          ),
          CupertinoDialogAction(
            onPressed: () => launchUrl(Uri.parse(_releasesUrl),
                mode: LaunchMode.externalApplication),
            child: const Text('Kiểm tra bản mới'),
          ),
          CupertinoDialogAction(
            onPressed: () => launchUrl(Uri.parse(_issuesUrl),
                mode: LaunchMode.externalApplication),
            child: const Text('Báo lỗi / Góp ý'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  Future<void> _showGuideDialog() async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hướng dẫn sử dụng'),
        content: const SingleChildScrollView(
          child: Text(
            'Chấm công\n'
            '• Đến làm: chọn tên mình rồi bấm Vào ca.\n'
            '• Về: bấm Tan ca. Quên bấm thì nhập tay giờ ra trong ngày.\n'
            '• Chạy đi cửa hàng khác rồi quay lại: tan ca rồi bấm Vào ca lại, 1 ngày chấm được nhiều lần.\n'
            '• Ca đêm (vd 20:00–05:00) được tính vào ngày bắt đầu ca.\n\n'
            'Báo cáo\n'
            '• Xem tổng giờ, tăng ca, tiền công theo tháng; bấm vào 1 ngày để sửa.\n'
            '• Nút Xuất PDF để lưu bảng chấm công tháng.\n\n'
            'Chủ cửa hàng\n'
            '• Nhấn Ctrl+H rồi nhập mật khẩu để mở tab Cài đặt (thêm nhân viên, giờ chuẩn, sao lưu dữ liệu).\n'
            '• Dữ liệu được ký chống sửa; file sao lưu xuất ra trong Cài đặt.',
            style: TextStyle(fontSize: 14, height: 1.5),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  Future<void> _showTamperDialog(String title, String message) async {
    if (!mounted) return;
    await showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Đã hiểu'),
          ),
        ],
      ),
    );
  }

  void _tick() {
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _tick();
    });
  }

  DataStore get _s => widget.store;
  String get _todayStr =>
      '${_now.year}-${_now.month.toString().padLeft(2, '0')}-${_now.day.toString().padLeft(2, '0')}';
  String get _clockStr =>
      '${_now.hour.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}';

  String _elapsed(Shift open) {
    var nowMin = _now.hour * 60 + _now.minute;
    if (open.date != _todayStr) nowMin += 24 * 60; // ca đêm từ hôm qua
    return fmtDuration(nowMin - open.clockIn!);
  }

  Future<void> _save() async {
    await _s.save();
    setState(() {});
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _act(FutureOr<void> Function() fn, String okMsg) async {
    try {
      await fn();
      await _save();
      if (okMsg.isNotEmpty) _snack(okMsg);
    } on StateError catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('Lỗi: $e');
    }
  }

  // --- Hỏi giờ / mật khẩu (dialog iOS) ---
  Future<String?> _askTime(String title, String initial) async {
    final ctrl = TextEditingController(text: initial);
    return showCupertinoDialog<String>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(title),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            controller: ctrl,
            autofocus: true,
            placeholder: 'vd 9:00',
            keyboardType: TextInputType.datetime,
          ),
        ),
        actions: [
          CupertinoDialogAction(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Hủy')),
          CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('Ghi')),
        ],
      ),
    );
  }

  Future<String?> _askPassword(String title) async {
    final ctrl = TextEditingController();
    return showCupertinoDialog<String>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(title),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            controller: ctrl,
            obscureText: true,
            autofocus: true,
            placeholder: 'Mật khẩu',
          ),
        ),
        actions: [
          CupertinoDialogAction(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Hủy')),
          CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('OK')),
        ],
      ),
    );
  }

  Future<bool> _confirm(String title, String message) async {
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Hủy')),
          CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Xóa')),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _ownerLogin() async {
    if (_ownerMode) {
      setState(() {
        _ownerMode = false;
        _tab = 0;
      });
      _snack('Đã thoát chế độ chủ cửa hàng.');
      return;
    }
    if (!_s.ownerPasswordSet) {
      final pw = await _askPassword('Đặt mật khẩu chủ lần đầu');
      if (pw == null || pw.isEmpty) return;
      final pw2 = await _askPassword('Nhập lại mật khẩu');
      if (pw != pw2) {
        _snack('Hai lần nhập không khớp.');
        return;
      }
      _s.setOwnerPassword(pw);
      await _save();
      _snack('Đã đặt mật khẩu. Giữ kỹ mật khẩu này.');
    }
    final pw = await _askPassword('Nhập mật khẩu chủ');
    if (pw != null && _s.checkOwnerPassword(pw)) {
      setState(() {
        _ownerMode = true;
        _tab = 2;
      });
      _snack('Đã vào chế độ chủ cửa hàng.');
    } else if (pw != null) {
      _snack('Mật khẩu không đúng.');
    }
  }

  Future<void> _changeOwnerPassword() async {
    final pw = await _askPassword('Mật khẩu chủ mới');
    if (pw == null || pw.isEmpty) return;
    final pw2 = await _askPassword('Nhập lại mật khẩu mới');
    if (pw != pw2) {
      _snack('Hai lần nhập không khớp.');
      return;
    }
    _s.setOwnerPassword(pw);
    await _save();
    _snack('Đã đổi mật khẩu chủ.');
  }

  Future<String?> _askText(String title, String initial) async {
    final ctrl = TextEditingController(text: initial);
    return showCupertinoDialog<String>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(title),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(controller: ctrl),
        ),
        actions: [
          CupertinoDialogAction(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Hủy')),
          CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('Lưu')),
        ],
      ),
    );
  }

  // --- Sửa/thêm từng ngày (EntryEditor kiểu iOS) ---
  // Ngày hôm nay ai cũng sửa được; ngày đã qua chỉ chủ cửa hàng mới sửa.
  Future<void> _showEntryEditor({Shift? shift, String? date}) async {
    final emp = _s.data.employees.where((e) => e.name == _employee).firstOrNull;
    if (emp == null) return;
    final day = shift?.date ?? date ?? _todayStr;
    if (day != _todayStr && !_ownerMode) {
      _snack('Ngày đã qua chỉ chủ cửa hàng mới sửa được. Nhấn Ctrl+H rồi nhập mật khẩu chủ.');
      return;
    }
    final inCtrl = TextEditingController(
        text: shift?.clockIn == null ? '' : fmtHhmm(shift!.clockIn!));
    final outCtrl = TextEditingController(
        text: shift?.clockOut == null ? '' : fmtHhmm(shift!.clockOut!));
    final noteCtrl = TextEditingController(text: shift?.note ?? '');
    var status = shift?.status ?? 'work';
    var breakMinutes = shift?.breakMinutes ?? 0;
    var datePicked = DateTime.parse(day);

    Future<void> pickDate(StateSetter setState) async {
      final picked = await showDatePicker(
        context: context,
        initialDate: datePicked,
        firstDate: DateTime(2020),
        lastDate: DateTime.now().add(const Duration(days: 365)),
      );
      if (picked != null) setState(() => datePicked = picked);
    }

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final dstr =
              '${datePicked.year}-${datePicked.month.toString().padLeft(2, '0')}-${datePicked.day.toString().padLeft(2, '0')}';
          final ci = parseHhmm(inCtrl.text);
          final co = parseHhmm(outCtrl.text);
          final total = status == 'work'
              ? durationMinutes(ci, co) == null
                  ? null
                  : ((durationMinutes(ci, co)! - breakMinutes).clamp(0, 24 * 60))
              : 0;
          return AlertDialog(
            title: Text(shift == null ? 'Thêm ngày' : 'Sửa ngày $day'),
            content: SingleChildScrollView(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (shift == null)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Ngày'),
                        subtitle: Text(
                            '${datePicked.day}/${datePicked.month}/${datePicked.year}'),
                        trailing: CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: () => pickDate(setState),
                          child: const Text('Chọn ngày'),
                        ),
                      ),
                    const Text('Trạng thái',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      children: shiftStatuses.map((s) {
                        final selected = status == s.$1;
                        return ChoiceChip(
                          label: Text(s.$2),
                          selected: selected,
                          onSelected: (_) =>
                              setState(() => status = s.$1),
                          selectedColor: _accent,
                          labelStyle: TextStyle(
                              color: selected ? Colors.white : _ink),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                        child: TextField(
                          controller: inCtrl,
                          decoration: const InputDecoration(
                              labelText: 'Giờ vào (vd 9:00)',
                              border: OutlineInputBorder()),
                          keyboardType: TextInputType.datetime,
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: outCtrl,
                          decoration: const InputDecoration(
                              labelText: 'Giờ ra (vd 20:00)',
                              border: OutlineInputBorder()),
                          keyboardType: TextInputType.datetime,
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    Row(children: [
                      const Text('Nghỉ giữa ca: '),
                      IconButton(
                        icon: const Icon(CupertinoIcons.minus_circle_fill),
                        color: _accent,
                        onPressed: breakMinutes <= 0
                            ? null
                            : () => setState(() => breakMinutes -= 5),
                      ),
                      Text('$breakMinutes phút',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(CupertinoIcons.plus_circle_fill),
                        color: _accent,
                        onPressed: breakMinutes >= 240
                            ? null
                            : () => setState(() => breakMinutes += 5),
                      ),
                    ]),
                    TextField(
                      controller: noteCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Ghi chú (vd: tăng ca, đi muộn…)',
                          border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Giờ công: ${total == null ? '--' : fmtDuration(total)}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, color: _accentDark),
                    ),
                  ]),
            ),
            actions: [
              if (shift != null)
                TextButton(
                  onPressed: () async {
                    final ok = await _confirm(
                        'Xóa ngày', 'Xóa ca ngày $day của ${emp.name}?');
                    if (ok) {
                      _s.deleteShift(shift);
                      await _save();
                      if (ctx.mounted) Navigator.pop(ctx, true);
                      _snack('Đã xóa ca ngày $day.');
                    }
                  },
                  child:
                      const Text('Xóa', style: TextStyle(color: _danger)),
                ),
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Hủy')),
              FilledButton(
                onPressed: () {
                  try {
                    if (shift != null) {
                      _s.ownerUpdateShift(shift, emp.name, dstr,
                          inCtrl.text.isEmpty ? null : inCtrl.text,
                          outCtrl.text.isEmpty ? null : outCtrl.text,
                          status: status,
                          breakMinutes: breakMinutes,
                          note: noteCtrl.text.trim());
                    } else {
                      _s.ownerAddShift(emp.name, dstr,
                          inCtrl.text.isEmpty ? null : inCtrl.text,
                          outCtrl.text.isEmpty ? null : outCtrl.text,
                          status: status,
                          breakMinutes: breakMinutes,
                          note: noteCtrl.text.trim());
                    }
                  } on StateError catch (e) {
                    _snack(e.message);
                    return;
                  }
                  Navigator.pop(ctx, true);
                },
                child: const Text('Lưu'),
              ),
            ],
          );
        },
      ),
    );
    if (saved == true) {
      await _save();
      _snack('Đã lưu ca.');
    }
  }

  // --- Nhân viên (chỉ chủ) ---
  Future<void> _editEmployee(Employee emp) async {
    final nameCtrl = TextEditingController(text: emp.name);
    final rateCtrl = TextEditingController(text: emp.rate.toString());
    final leaveCtrl = TextEditingController(
        text: emp.annualLeaveAllowance.toString());
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Sửa nhân viên'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          CupertinoTextField(controller: nameCtrl, placeholder: 'Tên'),
          const SizedBox(height: 8),
          CupertinoTextField(
              controller: rateCtrl,
              placeholder: 'Đơn giá/giờ (vd 160)',
              keyboardType: TextInputType.number),
          const SizedBox(height: 8),
          CupertinoTextField(
              controller: leaveCtrl,
              placeholder: 'Ngày phép năm (vd 10)',
              keyboardType: TextInputType.number),
        ]),
        actions: [
          CupertinoDialogAction(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Hủy')),
          CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Lưu')),
        ],
      ),
    );
    if (ok != true) return;
    final rate = int.tryParse(rateCtrl.text.trim());
    final leave = int.tryParse(leaveCtrl.text.trim()) ?? emp.annualLeaveAllowance;
    if (nameCtrl.text.trim().isEmpty || rate == null) {
      _snack('Tên hoặc giá giờ không hợp lệ.');
      return;
    }
    setState(() {
      emp.name = nameCtrl.text.trim();
      emp.rate = rate;
      emp.annualLeaveAllowance = leave;
      _employee = emp.name;
    });
    await _save();
    _snack('Đã cập nhật nhân viên.');
  }

  Future<void> _addEmployee() async {
    final nameCtrl = TextEditingController();
    final rateCtrl = TextEditingController();
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Thêm nhân viên'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          CupertinoTextField(controller: nameCtrl, placeholder: 'Tên'),
          const SizedBox(height: 8),
          CupertinoTextField(
              controller: rateCtrl,
              placeholder: 'Đơn giá/giờ (vd 160)',
              keyboardType: TextInputType.number),
        ]),
        actions: [
          CupertinoDialogAction(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Hủy')),
          CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Thêm')),
        ],
      ),
    );
    if (ok != true) return;
    final rate = int.tryParse(rateCtrl.text.trim());
    if (nameCtrl.text.trim().isEmpty || rate == null) {
      _snack('Tên hoặc giá giờ không hợp lệ.');
      return;
    }
    _s.data.employees.add(Employee(nameCtrl.text.trim(), rate));
    setState(() => _employee = nameCtrl.text.trim());
    await _save();
    _snack('Đã thêm nhân viên.');
  }

  Future<void> _removeEmployee(Employee emp) async {
    if (_s.data.employees.length <= 1) {
      _snack('Phải còn ít nhất 1 nhân viên.');
      return;
    }
    final ok = await _confirm('Xóa nhân viên',
        'Xóa ${emp.name} cùng toàn bộ ca làm của người này?');
    if (!ok) return;
    setState(() {
      _s.data.employees.remove(emp);
      _s.data.shifts.remove(emp.name);
      if (_employee == emp.name) {
        _employee = _s.data.employees.first.name;
      }
    });
    await _save();
    _snack('Đã xóa ${emp.name}.');
  }

  // --- Xuất PDF ---
  Future<void> _exportPdf() async {
    final emp = _s.data.employees.where((e) => e.name == _employee).firstOrNull;
    if (emp == null) return;
    try {
      final bytes = await buildMonthPdf(
        data: _s.data,
        employee: emp,
        year: _month.year,
        month: _month.month,
      );
      final dir = await getApplicationDocumentsDirectory();
      final file = File(
          '${dir.path}/Gio-Lam-${_month.year}-${_month.month.toString().padLeft(2, '0')}-${emp.name}.pdf');
      await file.writeAsBytes(bytes);
      setState(() => _lastPdfPath = file.path);
      _snack('Đã xuất PDF: ${file.path}');
      await OpenFilex.open(file.path);
    } catch (e) {
      _snack('Xuất PDF lỗi: $e');
    }
  }

  // --- Sao lưu / khôi phục JSON (giống app iOS) ---
  Future<void> _exportBackup() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final now = DateTime.now();
      final name =
          'Gio-Lam-backup-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}.json';
      final file = File('${dir.path}/$name');
      await file.writeAsString(
          const JsonEncoder.withIndent('  ').convert(_s.data.toJson()));
      _snack('Đã xuất sao lưu: ${file.path}');
      await OpenFilex.open(file.path);
    } catch (e) {
      _snack('Xuất sao lưu lỗi: $e');
    }
  }

  Future<void> _importBackup() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        dialogTitle: 'Chọn file sao lưu Gio-Lam (.json)',
      );
      final path = result?.files.single.path;
      if (path == null) return;
      final restored =
          AppData.fromJson(jsonDecode(await File(path).readAsString()));
      if (!mounted) return;
      final ok = await showCupertinoDialog<bool>(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('Khôi phục dữ liệu?'),
          content: Text(
              'Toàn bộ dữ liệu hiện tại sẽ bị thay thế bằng file sao lưu '
              '(cửa hàng ${restored.storeName}, ${restored.employees.length} nhân viên).'),
          actions: [
            CupertinoDialogAction(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Hủy')),
            CupertinoDialogAction(
                isDestructiveAction: true,
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Khôi phục')),
          ],
        ),
      );
      if (ok != true) return;
      _s.data = restored;
      await _save();
      setState(() {
        _employee = _s.data.employees.isNotEmpty
            ? _s.data.employees.first.name
            : null;
        _tab = 0;
      });
      _snack('Đã khôi phục dữ liệu từ file sao lưu.');
    } catch (e) {
      _snack('Khôi phục lỗi: file không đúng định dạng sao lưu Gio-Lam. ($e)');
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = <BottomNavigationBarItem>[
      const BottomNavigationBarItem(
          icon: Icon(CupertinoIcons.clock_fill), label: 'Chấm công'),
      const BottomNavigationBarItem(
          icon: Icon(CupertinoIcons.doc_text_fill), label: 'Báo cáo'),
      if (_ownerMode)
        const BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.gear_alt_fill), label: 'Cài đặt'),
    ];
    final pages = <Widget>[
      _attendanceTab(),
      _reportTab(),
      if (_ownerMode) _settingsTab(),
    ];
    // Phím tắt Ctrl+H mở đăng nhập chủ cửa hàng (không có nút hiện ngoài).
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.keyH, control: true):
            _OwnerIntent(),
      },
      child: Actions(
        actions: {
          _OwnerIntent: CallbackAction<_OwnerIntent>(onInvoke: (_) {
            _ownerLogin();
            return null;
          }),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            body: IndexedStack(index: _tab, children: pages),
            bottomNavigationBar: CupertinoTabBar(
              currentIndex: _tab,
              onTap: (i) => setState(() => _tab = i),
              activeColor: _accent,
              inactiveColor: CupertinoColors.systemGrey,
              backgroundColor: Colors.white,
              items: items,
            ),
          ),
        ),
      ),
    );
  }

  // ================= TAB CHẤM CÔNG =================
  Widget _attendanceTab() {
    final data = _s.data;
    final emp = data.employees.where((e) => e.name == _employee).firstOrNull;
    final open = _employee == null ? null : data.openShift(_employee!);
    final todaySegments = _employee == null
        ? <Shift>[]
        : data.shiftsOn(_employee!, _todayStr);
    final todayClosed =
        todaySegments.where((s) => s.clockOut != null).toList();
    final todayTotal = _employee == null
        ? 0
        : data.dayTotalMinutes(_employee!, _todayStr);
    final weekday = ['CN', 'T2', 'T3', 'T4', 'T5', 'T6', 'T7'][_now.weekday % 7];

    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
          decoration: const BoxDecoration(
            color: _ink,
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(28),
              bottomRight: Radius.circular(28),
            ),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.store_rounded, color: Colors.white70, size: 20),
              const SizedBox(width: 8),
              Text(
                data.storeName.toUpperCase(),
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.5),
              ),
              const Spacer(),
              CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                onPressed: _showAboutDialog,
                child: const Icon(CupertinoIcons.info_circle,
                    color: Colors.white70, size: 20),
              ),
            ]),
            const SizedBox(height: 18),
            Text(
              '$weekday, ${_now.day} thg ${_now.month} ${_now.year}',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 4),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(_clockStr,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 56,
                      fontWeight: FontWeight.w300,
                      height: 1)),
              const SizedBox(width: 8),
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('Giờ hiện tại',
                    style: TextStyle(color: Colors.white60, fontSize: 13)),
              ),
            ]),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: data.employees.map((e) {
                  final selected = e.name == _employee;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text('${e.name} · ${e.rate} ${data.currency}/giờ'),
                      selected: selected,
                      onSelected: (_) => setState(() => _employee = e.name),
                      selectedColor: _accent,
                      labelStyle: TextStyle(
                        color: selected ? Colors.white : _ink,
                        fontWeight: FontWeight.w600,
                      ),
                      backgroundColor: Colors.white,
                      side: const BorderSide(color: _line),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _line),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 4)),
                ],
              ),
              child: open != null
                  ? Column(children: [
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                    color: _accent, shape: BoxShape.circle)),
                            const SizedBox(width: 6),
                            const Text('ĐANG LÀM VIỆC',
                                style: TextStyle(
                                    color: _accentDark,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1)),
                          ]),
                        ),
                        const Spacer(),
                        if (open.date != _todayStr)
                          const Chip(
                            label: Text('Ca đêm từ hôm qua',
                                style: TextStyle(fontSize: 11)),
                            backgroundColor: _amberBg,
                            side: BorderSide.none,
                            visualDensity: VisualDensity.compact,
                          ),
                      ]),
                      const SizedBox(height: 16),
                      Text(_elapsed(open),
                          style: const TextStyle(
                              fontSize: 52,
                              fontWeight: FontWeight.w200,
                              color: _ink,
                              height: 1)),
                      const SizedBox(height: 4),
                      Text(
                        'Vào ca lúc ${fmtHhmm(open.clockIn!)}'
                        '${open.date != _todayStr ? ' ngày ${open.date}' : ' hôm nay'}',
                        style: const TextStyle(color: _muted, fontSize: 14),
                      ),
                    ])
                  : Column(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _bg,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          todayClosed.isNotEmpty
                              ? 'ĐÃ TAN CA HÔM NAY'
                              : 'CHƯA VÀO CA',
                          style: const TextStyle(
                              color: _muted,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        todayClosed.isNotEmpty
                            ? '${fmtHhmm(todayClosed.first.clockIn ?? 0)} – ${fmtHhmm(todayClosed.last.clockOut!)}'
                            : '--:--',
                        style: const TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.w200,
                            color: _ink),
                      ),
                      Text(
                        todayClosed.isNotEmpty
                            ? 'Hôm nay làm ${fmtDuration(todayTotal)}${todayClosed.length > 1 ? ' · ${todayClosed.length} đoạn ca' : ''}'
                            : 'Bấm Vào ca để bắt đầu tính giờ.',
                        style: const TextStyle(color: _muted, fontSize: 14),
                      ),
                    ]),
            ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: open != null || emp == null
                      ? null
                      : () => _act(() async => _s.clockIn(emp.name),
                          'Đã ghi giờ vào lúc $_clockStr.'),
                  icon: const Icon(Icons.login_rounded),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: Text('Vào ca', style: TextStyle(fontSize: 17)),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: open == null
                      ? null
                      : () {
                          _act(() async {
                            final sh = _s.clockOut(emp!.name);
                            final night = sh.date != _todayStr;
                            _snack(night
                                ? 'Ca đêm ${sh.date}: ${fmtHhmm(sh.clockIn!)}–${fmtHhmm(sh.clockOut!)} = ${fmtDuration(sh.total)}.'
                                : 'Đã tan ca. Hôm nay làm ${fmtDuration(sh.total)}.');
                          }, '');
                        },
                  icon: const Icon(Icons.logout_rounded),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: Text('Tan ca', style: TextStyle(fontSize: 17)),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: _danger,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: emp == null
                      ? null
                      : () async {
                          final v = await _askTime('Nhập tay giờ vào', '');
                          if (v != null) {
                            await _act(() async => _s.manualIn(emp.name, v),
                                'Đã ghi giờ vào (nhập tay).');
                          }
                        },
                  icon: const Icon(Icons.edit_note_rounded, size: 18),
                  label: const Text('Nhập tay giờ vào'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _ink,
                    side: const BorderSide(color: _line),
                    backgroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: emp == null
                      ? null
                      : () async {
                          final v = await _askTime('Nhập tay giờ ra', '');
                          if (v != null) {
                            await _act(() async => _s.manualOut(emp.name, v),
                                'Đã ghi giờ ra (nhập tay).');
                          }
                        },
                  icon: const Icon(Icons.edit_note_rounded, size: 18),
                  label: const Text('Nhập tay giờ ra'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _ink,
                    side: const BorderSide(color: _line),
                    backgroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            const Text(
              'Nhập tay chỉ được trong đúng ngày hôm đó, giờ nhập tay được ghi chú rõ.',
              style: TextStyle(color: _muted, fontSize: 12),
            ),
          ]),
        ),
      ]),
    );
  }

  // ================= TAB BÁO CÁO =================
  Widget _reportTab() {
    final data = _s.data;
    final emp = data.employees.where((e) => e.name == _employee).firstOrNull;
    final total = emp == null
        ? (days: 0, minutes: 0)
        : data.monthTotal(emp.name, _month.year, _month.month);
    final rows =
        emp == null ? <Shift>[] : data.monthShifts(emp.name, _month.year, _month.month);
    final overtime = emp == null
        ? 0
        : data.monthOvertime(emp.name, _month.year, _month.month);
    final pay = emp == null ? 0.0 : total.minutes / 60 * emp.rate;

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 48, 20, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Báo cáo',
              style: TextStyle(
                  fontSize: 32, fontWeight: FontWeight.bold, color: _ink)),
          const SizedBox(height: 4),
          Text(data.storeName,
              style: const TextStyle(color: _muted, fontSize: 14)),
          const SizedBox(height: 16),
          // Chọn nhân viên + tháng
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: data.employees.map((e) {
                final selected = e.name == _employee;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text('${e.name} · ${e.rate} ${data.currency}/giờ'),
                    selected: selected,
                    onSelected: (_) => setState(() => _employee = e.name),
                    selectedColor: _accent,
                    labelStyle: TextStyle(
                      color: selected ? Colors.white : _ink,
                      fontWeight: FontWeight.w600,
                    ),
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: _line),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),
          _card(
            Row(children: [
              IconButton(
                icon: const Icon(CupertinoIcons.chevron_left),
                onPressed: () => setState(
                    () => _month = DateTime(_month.year, _month.month - 1)),
              ),
              Expanded(
                child: Text('Tháng ${_month.month}/${_month.year}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.bold, color: _ink)),
              ),
              IconButton(
                icon: const Icon(CupertinoIcons.chevron_right),
                onPressed: () => setState(
                    () => _month = DateTime(_month.year, _month.month + 1)),
              ),
            ]),
          ),
          const SizedBox(height: 20),
          _sectionTitle('Tổng hợp'),
          const SizedBox(height: 8),
          Row(children: [
            _statCard('${total.days}', 'Ngày làm'),
            const SizedBox(width: 10),
            _statCard(fmtDuration(total.minutes), 'Tổng giờ'),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            _statCard(fmtDuration(overtime), 'Tăng ca'),
            const SizedBox(width: 10),
            _statCard('${pay.toStringAsFixed(0)} ${data.currency}', 'Tiền công', highlight: true),
          ]),
          const SizedBox(height: 20),
          _sectionTitle('Xuất báo cáo'),
          const SizedBox(height: 8),
          _card(
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(CupertinoIcons.doc_text_fill,
                      color: _accentDark, size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Báo cáo PDF theo tháng',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: _ink)),
                        SizedBox(height: 2),
                        Text('Tạo bảng công để lưu hoặc chia sẻ.',
                            style: TextStyle(color: _muted, fontSize: 13)),
                      ]),
                ),
              ]),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: emp == null ? null : _exportPdf,
                  icon: const Icon(CupertinoIcons.doc_fill, size: 18),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Text('Tạo báo cáo PDF',
                        style: TextStyle(fontSize: 16)),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: _accent,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              if (_lastPdfPath != null) ...[
                const SizedBox(height: 10),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: () => OpenFilex.open(_lastPdfPath!),
                  child: const Text('Mở báo cáo vừa tạo',
                      style: TextStyle(fontSize: 14)),
                ),
              ],
            ]),
          ),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: _sectionTitle('Dữ liệu trong báo cáo')),
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              onPressed: emp == null
                  ? null
                  : () => _showEntryEditor(),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(CupertinoIcons.plus_circle_fill, size: 16),
                SizedBox(width: 4),
                Text('Thêm ngày', style: TextStyle(fontSize: 14)),
              ]),
            ),
          ]),
          const SizedBox(height: 8),
          if (emp != null && emp.annualLeaveAllowance > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Nghỉ phép năm ${_month.year}: đã dùng ${_s.data.yearPaidLeaveUsed(emp.name, _month.year)} / ${emp.annualLeaveAllowance} ngày, còn lại ${emp.annualLeaveAllowance - _s.data.yearPaidLeaveUsed(emp.name, _month.year)} ngày.',
                style: const TextStyle(color: _muted, fontSize: 13),
              ),
            ),
          if (rows.isEmpty)
            _card(const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Tháng này chưa có ca làm nào.',
                  style: TextStyle(color: _muted)),
            ))
          else
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _line),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < rows.length; i++) ...[
                    if (i > 0) const Divider(height: 1, color: _line),
                    _shiftRow(rows[i]),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 12),
          const Text(
            'Bấm vào ca trong danh sách để sửa (chỉ chủ cửa hàng mới sửa được ngày đã qua).',
            style: TextStyle(color: _muted, fontSize: 12),
          ),
        ]),
      ),
    );
  }

  // ================= TAB CÀI ĐẶT (CHỈ CHỦ) =================
  Future<void> _editStoreName() async {
    final ctrl = TextEditingController(text: _s.data.storeName);
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Tên cửa hàng'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(controller: ctrl, autofocus: true),
        ),
        actions: [
          CupertinoDialogAction(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Hủy')),
          CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Lưu')),
        ],
      ),
    );
    if (ok != true || ctrl.text.trim().isEmpty) return;
    setState(() => _s.data.storeName = ctrl.text.trim());
    await _save();
    _snack('Đã đổi tên cửa hàng.');
  }

  Widget _settingsTab() {
    final data = _s.data;
    final standardHours = data.standardMinutesPerDay / 60;

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 48, 20, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Cài đặt',
              style: TextStyle(
                  fontSize: 32, fontWeight: FontWeight.bold, color: _ink)),
          const SizedBox(height: 4),
          const Text('Chỉ chủ cửa hàng mới xem và sửa được mục này.',
              style: TextStyle(color: _muted, fontSize: 14)),
          const SizedBox(height: 20),
          _sectionTitle('Thông tin cửa hàng'),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _line),
            ),
            child: ListTile(
              leading:
                  const Icon(CupertinoIcons.bag_fill, color: _muted),
              title: const Text('Tên cửa hàng'),
              subtitle: Text(data.storeName,
                  style: const TextStyle(
                      color: _ink, fontWeight: FontWeight.w600)),
              trailing: const Icon(CupertinoIcons.chevron_right,
                  size: 16, color: _muted),
              onTap: _editStoreName,
            ),
          ),
          const SizedBox(height: 20),
          _sectionTitle('Nhân viên'),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _line),
            ),
            child: Column(
              children: [
                for (var i = 0; i < data.employees.length; i++) ...[
                  if (i > 0) const Divider(height: 1, color: _line),
                  _employeeRow(data.employees[i]),
                ],
                const Divider(height: 1, color: _line),
                ListTile(
                  leading: const Icon(CupertinoIcons.plus_circle_fill,
                      color: _accent),
                  title: const Text('Thêm nhân viên',
                      style: TextStyle(color: _accentDark)),
                  onTap: _addEmployee,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _sectionTitle('Giờ làm'),
          const SizedBox(height: 8),
          _card(
            Column(children: [
              Row(children: [
                const Icon(CupertinoIcons.clock_fill,
                    size: 20, color: _muted),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('Giờ chuẩn',
                      style: TextStyle(fontSize: 15, color: _ink)),
                ),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  onPressed: data.standardMinutesPerDay <= 60
                      ? null
                      : () async {
                          setState(() =>
                              data.standardMinutesPerDay -= 30);
                          await _save();
                        },
                  child: const Icon(CupertinoIcons.minus_circle_fill,
                      color: _accent),
                ),
                Text(
                    '${standardHours.toStringAsFixed(standardHours % 1 == 0 ? 0 : 1)}h',
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: _ink)),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  onPressed: data.standardMinutesPerDay >= 1440
                      ? null
                      : () async {
                          setState(() =>
                              data.standardMinutesPerDay += 30);
                          await _save();
                        },
                  child: const Icon(CupertinoIcons.plus_circle_fill,
                      color: _accent),
                ),
              ]),
              const SizedBox(height: 8),
              const Text(
                'Tăng ca được tính khi giờ công trong ngày vượt quá giờ chuẩn.',
                style: TextStyle(color: _muted, fontSize: 12),
              ),
            ]),
          ),
          const SizedBox(height: 20),
          _sectionTitle('Lương'),
          const SizedBox(height: 8),
          _card(
            Column(children: [
              Row(children: [
                const Icon(CupertinoIcons.money_dollar_circle_fill,
                    size: 20, color: _muted),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('Loại tiền',
                      style: TextStyle(fontSize: 15, color: _ink)),
                ),
                CupertinoSegmentedControl<String>(
                  groupValue: data.currency,
                  onValueChanged: (v) async {
                    setState(() => data.currency = v);
                    await _save();
                  },
                  children: const {
                    'Kč': Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('Kč')),
                    'đ': Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('đ')),
                  },
                ),
              ]),
              const SizedBox(height: 8),
              const Text(
                'Đơn giá theo giờ của từng nhân viên sửa ở mục Nhân viên bên trên. Tiền công hiện theo loại tiền này.',
                style: TextStyle(color: _muted, fontSize: 12),
              ),
            ]),
          ),
          const SizedBox(height: 20),
          _sectionTitle('Sao lưu dữ liệu'),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _line),
            ),
            child: Column(children: [
              ListTile(
                leading: const Icon(
                    CupertinoIcons.square_arrow_up_on_square_fill,
                    color: _muted),
                title: const Text('Xuất sao lưu (.json)'),
                subtitle: const Text(
                    'Lưu toàn bộ dữ liệu + cài đặt ra file JSON'),
                trailing: const Icon(CupertinoIcons.chevron_right,
                    size: 16, color: _muted),
                onTap: _exportBackup,
              ),
              const Divider(height: 1, color: _line),
              ListTile(
                leading: const Icon(
                    CupertinoIcons.square_arrow_down_on_square_fill,
                    color: _muted),
                title: const Text('Khôi phục từ file'),
                subtitle: const Text(
                    'Thay thế dữ liệu hiện tại bằng file sao lưu'),
                trailing: const Icon(CupertinoIcons.chevron_right,
                    size: 16, color: _muted),
                onTap: _importBackup,
              ),
            ]),
          ),
          const SizedBox(height: 20),
          _sectionTitle('Giới thiệu'),
          const SizedBox(height: 8),
          _card(
            Column(children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(CupertinoIcons.person_fill,
                    size: 20, color: _muted),
                title: const Text('Phát triển bởi'),
                subtitle: Text(data.developerName),
                trailing: const Icon(CupertinoIcons.pencil,
                    size: 16, color: _muted),
                onTap: () async {
                  final v = await _askText(
                      'Tên người phát triển', data.developerName);
                  if (v != null && v.trim().isNotEmpty) {
                    setState(() => data.developerName = v.trim());
                    await _save();
                  }
                },
              ),
              const Divider(height: 1, color: _line),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(CupertinoIcons.at,
                    size: 20, color: _muted),
                title: const Text('Liên hệ'),
                subtitle: Text(data.developerContact),
                trailing: const Icon(CupertinoIcons.pencil,
                    size: 16, color: _muted),
                onTap: () async {
                  final v = await _askText(
                      'Liên hệ (số điện thoại / Zalo / link)',
                      data.developerContact);
                  if (v != null && v.trim().isNotEmpty) {
                    setState(() => data.developerContact = v.trim());
                    await _save();
                  }
                },
              ),
              const Divider(height: 1, color: _line),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(CupertinoIcons.info_circle,
                    size: 20, color: _muted),
                title: Text('Phiên bản'),
                subtitle: Text('Gio-Lam $_appVersion'),
              ),
            ]),
          ),
          const SizedBox(height: 20),
          _sectionTitle('Hỗ trợ'),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _line),
            ),
            child: Column(children: [
              ListTile(
                leading: const Icon(CupertinoIcons.book_fill,
                    color: _muted),
                title: const Text('Hướng dẫn sử dụng'),
                trailing: const Icon(CupertinoIcons.chevron_right,
                    size: 16, color: _muted),
                onTap: _showGuideDialog,
              ),
              const Divider(height: 1, color: _line),
              ListTile(
                leading: const Icon(
                    CupertinoIcons.arrow_down_circle_fill,
                    color: _muted),
                title: const Text('Kiểm tra bản mới'),
                subtitle: const Text('Mở trang tải bản mới nhất'),
                trailing: const Icon(CupertinoIcons.chevron_right,
                    size: 16, color: _muted),
                onTap: () => launchUrl(Uri.parse(_releasesUrl),
                    mode: LaunchMode.externalApplication),
              ),
              const Divider(height: 1, color: _line),
              ListTile(
                leading: const Icon(
                    CupertinoIcons.chat_bubble_text_fill,
                    color: _muted),
                title: const Text('Báo lỗi / Góp ý'),
                trailing: const Icon(CupertinoIcons.chevron_right,
                    size: 16, color: _muted),
                onTap: () => launchUrl(Uri.parse(_issuesUrl),
                    mode: LaunchMode.externalApplication),
              ),
            ]),
          ),
          const SizedBox(height: 20),
          _sectionTitle('Chủ cửa hàng'),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _line),
            ),
            child: Column(children: [
              ListTile(
                leading:
                    const Icon(CupertinoIcons.lock_fill, color: _muted),
                title: const Text('Đổi mật khẩu chủ'),
                trailing: const Icon(CupertinoIcons.chevron_right,
                    size: 16, color: _muted),
                onTap: _changeOwnerPassword,
              ),
              const Divider(height: 1, color: _line),
              ListTile(
                leading: const Icon(CupertinoIcons.lock_open_fill,
                    color: _danger),
                title: const Text('Thoát chế độ chủ cửa hàng',
                    style: TextStyle(color: _danger)),
                onTap: _ownerLogin,
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  // ================= Dùng chung =================
  Widget _card(Widget child) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _line),
      ),
      child: child,
    );
  }

  Widget _sectionTitle(String title) {
    return Text(title.toUpperCase(),
        style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: _muted,
            letterSpacing: 1));
  }

  Widget _statCard(String value, String label, {bool highlight = false}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: highlight ? _ink : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: highlight ? _ink : _line),
        ),
        child: Column(children: [
          Text(value,
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: highlight ? Colors.white : _ink)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  fontSize: 12, color: highlight ? Colors.white70 : _muted)),
        ]),
      ),
    );
  }

  Widget _employeeRow(Employee e) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: _accent.withValues(alpha: 0.12),
        child: Text(e.name.isEmpty ? '?' : e.name[0].toUpperCase(),
            style: const TextStyle(
                color: _accentDark, fontWeight: FontWeight.bold)),
      ),
      title: Text(e.name,
          style: const TextStyle(fontWeight: FontWeight.w600, color: _ink)),
      subtitle: Text(
          '${e.rate} ${_s.data.currency}/giờ'
          '${e.annualLeaveAllowance > 0 ? ' · phép còn ${e.annualLeaveAllowance - _s.data.yearPaidLeaveUsed(e.name, DateTime.now().year)} ngày' : ''}',
          style: const TextStyle(color: _muted, fontSize: 13)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          icon: const Icon(CupertinoIcons.pencil, size: 18),
          onPressed: () => _editEmployee(e),
        ),
        IconButton(
          icon: const Icon(CupertinoIcons.trash,
              size: 18, color: _danger),
          onPressed: () => _removeEmployee(e),
        ),
      ]),
    );
  }

  String _shiftSubtitle(Shift s) {
    final notes = <String>[];
    if (s.status != 'work') notes.add(shiftStatusTitle(s.status));
    if (s.inManual) notes.add('vào: nhập tay');
    if (s.outManual) notes.add('ra: nhập tay');
    if (s.clockOut == null && s.status == 'work') notes.add('chưa tan ca');
    if (s.breakMinutes > 0) notes.add('nghỉ ${s.breakMinutes}p');
    if (s.note.isNotEmpty) notes.add(s.note);
    if (notes.isEmpty) return 'Ca làm bình thường';
    final joined = notes.join(' · ');
    return joined[0].toUpperCase() + joined.substring(1);
  }

  Widget _shiftRow(Shift s) {
    final d = DateTime.parse(s.date);
    return InkWell(
      onTap: () => _showEntryEditor(shift: s),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: s.clockOut == null
                  ? _amberBg
                  : _accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text('${d.day}',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: s.clockOut == null ? _amber : _accentDark)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                '${['CN', 'T2', 'T3', 'T4', 'T5', 'T6', 'T7'][d.weekday % 7]}, ${d.day}/${d.month}/${d.year}',
                style: const TextStyle(
                    fontWeight: FontWeight.w600, color: _ink, fontSize: 14),
              ),
              const SizedBox(height: 2),
              Text(
                _shiftSubtitle(s),
                style: const TextStyle(color: _muted, fontSize: 12),
              ),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(
              s.status == 'work'
                  ? '${s.clockIn == null ? '--:--' : fmtHhmm(s.clockIn!)} – ${s.clockOut == null ? '--:--' : fmtHhmm(s.clockOut!)}'
                  : shiftStatusTitle(s.status),
              style: const TextStyle(
                  fontWeight: FontWeight.w600, color: _ink, fontSize: 13),
            ),
            const SizedBox(height: 2),
            Text(s.status == 'work' ? fmtDuration(s.total) : '—',
                style: const TextStyle(color: _accentDark, fontSize: 13)),
          ]),
        ]),
      ),
    );
  }
}
