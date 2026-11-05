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

import 'ios_theme.dart';
import 'logic.dart';
import 'report_pdf.dart';
import 'store.dart';

// Giao diện kiểu app chấm công iOS: thanh tab dưới cùng (Chấm công / Báo cáo /
// Cài đặt), nền xám nhóm, thẻ trắng bo tròn, tiêu đề lớn.
// Tab Cài đặt chỉ chủ cửa hàng mới thấy — không có nút hiện ra ngoài,
// mở bằng phím tắt Ctrl+H rồi nhập mật khẩu chủ.

const _ink = iosLabel;
const _muted = iosSecondary;
const _line = iosBorder;
const _bg = iosPageBg;
const _accent = iosIndigo;
const _accentDark = iosTealDark;
const _teal = iosTeal;
const _danger = iosRed;
const _appVersion = '1.0.0';
const _developerName = 'Hiếu Lê';
const _supportUrl = 'https://fb.com/lehieuit';
const _amber = iosOrange;
const _amberBg = Color(0x1FFF9500);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Cửa sổ nhỏ kiểu iPad (800x1024), không mở rộng to như màn hình PC.
  await windowManager.ensureInitialized();
  const options = WindowOptions(
    size: Size(800, 1024),
    minimumSize: Size(520, 720),
    maximumSize: Size(900, 1150),
    center: true,
    title: 'Chấm công by Hiếu Lê',
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
      title: 'Chấm công by Hiếu Lê',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: _accent,
        useMaterial3: true,
        scaffoldBackgroundColor: _bg,
        fontFamily: 'Segoe UI',
      ),
      home: CupertinoTheme(
        data: const CupertinoThemeData(primaryColor: iosIndigo),
        child: HomePage(store: store),
      ),
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
  // Phần Giới thiệu giống hệt app iOS: tên người phát triển + 3 hàng
  // liên hệ bấm được (Facebook / Điện thoại / Email) + hàng Phiên bản.
  Future<void> _openLink(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Widget _developerHeader() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_developerName,
            style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.w600, color: _ink)),
        SizedBox(height: 3),
        Text('Người phát triển ứng dụng',
            style: TextStyle(color: _muted, fontSize: 13)),
      ],
    );
  }

  Widget _contactRow({
    required IconData icon,
    required Color tint,
    required String label,
    required String value,
    required String url,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openLink(url),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          IconTile(icon: icon, tint: tint),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(fontSize: 15, color: _ink)),
                  const SizedBox(height: 2),
                  Text(value,
                      style: const TextStyle(color: _muted, fontSize: 13)),
                ]),
          ),
          const Icon(CupertinoIcons.chevron_right, size: 14, color: _muted),
        ]),
      ),
    );
  }

  List<Widget> _aboutContactRows() {
    return [
      _contactRow(
          icon: CupertinoIcons.globe,
          tint: iosBlue,
          label: 'Facebook',
          value: 'facebook.com/lehieuit',
          url: 'https://www.facebook.com/lehieuit'),
      _contactRow(
          icon: CupertinoIcons.phone_fill,
          tint: _teal,
          label: 'Điện thoại',
          value: '+420 773 155 611',
          url: 'tel:+420773155611'),
      _contactRow(
          icon: CupertinoIcons.envelope_fill,
          tint: _accent,
          label: 'Email',
          value: 'lehieuit91@gmail.com',
          url: 'mailto:lehieuit91@gmail.com'),
    ];
  }

  Widget _versionRow() {
    return const Row(children: [
      Expanded(
          child: Text('Phiên bản',
              style: TextStyle(fontSize: 15, color: _ink))),
      Text('Chấm công $_appVersion',
          style: TextStyle(fontSize: 15, color: _muted)),
    ]);
  }

  Future<void> _showAboutDialog() async {
    await showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Chấm công by Hiếu Lê'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            _developerHeader(),
            const SizedBox(height: 4),
            ..._aboutContactRows(),
            const SizedBox(height: 8),
            _versionRow(),
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
            onPressed: () => launchUrl(Uri.parse(_supportUrl),
                mode: LaunchMode.externalApplication),
            child: const Text('Kiểm tra bản cập nhật'),
          ),
          CupertinoDialogAction(
            onPressed: () => launchUrl(Uri.parse(_supportUrl),
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
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28)),
        title: const Text('Hướng dẫn sử dụng',
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.bold, color: _ink)),
        content: const SingleChildScrollView(
          child: Text(
            'Chấm công\n'
            '• Đến làm: chọn tên mình rồi bấm Vào ca.\n'
            '• Về: bấm Tan ca. Quên bấm thì nhập tay giờ ra trong ngày.\n'
            '• Chạy đi cửa hàng khác rồi quay lại: tan ca rồi bấm Vào ca lại, 1 ngày chấm được nhiều lần.\n'
            '• Ca đêm (vd 20:00–05:00) được tính vào ngày bắt đầu ca.\n\n'
            'Báo cáo\n'
            '• Xem tổng giờ, tăng ca, tiền công theo tháng; bấm vào 1 ngày để sửa.\n'
            '• Nút Xuất PDF để lưu bảng chấm công tháng.',
            style: TextStyle(fontSize: 14, height: 1.5),
          ),
        ),
        actionsPadding: const EdgeInsets.only(right: 12, bottom: 8),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Đóng',
                style: TextStyle(
                    color: _accent, fontWeight: FontWeight.w600)),
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
          return Dialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28)),
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Thanh kéo như sheet iOS.
                        Center(
                          child: Container(
                            width: 36,
                            height: 5,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(shift == null ? 'Thêm ngày' : 'Sửa ngày $day',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: _ink)),
                        const SizedBox(height: 18),
                        if (shift == null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                                color: _bg,
                                borderRadius: BorderRadius.circular(12)),
                            child: Row(children: [
                              Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text('Ngày',
                                          style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: _muted)),
                                      const SizedBox(height: 2),
                                      Text(
                                          '${datePicked.day}/${datePicked.month}/${datePicked.year}',
                                          style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                              color: _ink)),
                                    ]),
                              ),
                              CupertinoButton(
                                padding: EdgeInsets.zero,
                                onPressed: () => pickDate(setState),
                                child: const Text('Chọn ngày'),
                              ),
                            ]),
                          ),
                          const SizedBox(height: 16),
                        ],
                        const Text('Trạng thái',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _muted)),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          children: shiftStatuses.map((s) {
                            final selected = status == s.$1;
                            return ChoiceChip(
                              label: Text(s.$2),
                              selected: selected,
                              showCheckmark: false,
                              onSelected: (_) =>
                                  setState(() => status = s.$1),
                              selectedColor: _accent,
                              backgroundColor: _bg,
                              side: BorderSide.none,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              labelStyle: TextStyle(
                                  color: selected ? Colors.white : _ink),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),
                        Row(children: [
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Giờ vào',
                                      style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: _muted)),
                                  const SizedBox(height: 6),
                                  CupertinoTextField(
                                    controller: inCtrl,
                                    placeholder: 'vd 9:00',
                                    keyboardType: TextInputType.datetime,
                                    onChanged: (_) => setState(() {}),
                                    decoration: BoxDecoration(
                                        color: _bg,
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 12),
                                  ),
                                ]),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Giờ ra',
                                      style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: _muted)),
                                  const SizedBox(height: 6),
                                  CupertinoTextField(
                                    controller: outCtrl,
                                    placeholder: 'vd 20:00',
                                    keyboardType: TextInputType.datetime,
                                    onChanged: (_) => setState(() {}),
                                    decoration: BoxDecoration(
                                        color: _bg,
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 12),
                                  ),
                                ]),
                          ),
                        ]),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                              color: _bg,
                              borderRadius: BorderRadius.circular(12)),
                          child: Row(children: [
                            const Text('Nghỉ giữa ca',
                                style:
                                    TextStyle(fontSize: 15, color: _ink)),
                            const Spacer(),
                            CupertinoButton(
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              onPressed: breakMinutes <= 0
                                  ? null
                                  : () => setState(() => breakMinutes -= 5),
                              child: const Icon(
                                  CupertinoIcons.minus_circle_fill,
                                  color: _accent,
                                  size: 24),
                            ),
                            SizedBox(
                              width: 76,
                              child: Text('$breakMinutes phút',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: _ink)),
                            ),
                            CupertinoButton(
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              onPressed: breakMinutes >= 240
                                  ? null
                                  : () => setState(() => breakMinutes += 5),
                              child: const Icon(
                                  CupertinoIcons.plus_circle_fill,
                                  color: _accent,
                                  size: 24),
                            ),
                          ]),
                        ),
                        const SizedBox(height: 16),
                        const Text('Ghi chú',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _muted)),
                        const SizedBox(height: 6),
                        CupertinoTextField(
                          controller: noteCtrl,
                          placeholder: 'Ghi chú (vd: tăng ca, đi muộn…)',
                          decoration: BoxDecoration(
                              color: _bg,
                              borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Giờ công: ${total == null ? '--' : fmtDuration(total)}',
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: _accentDark),
                        ),
                        const SizedBox(height: 20),
                        Row(children: [
                          if (shift != null)
                            TextButton(
                              onPressed: () async {
                                final ok = await _confirm('Xóa ngày',
                                    'Xóa ca ngày $day của ${emp.name}?');
                                if (ok) {
                                  _s.deleteShift(shift);
                                  await _save();
                                  if (ctx.mounted) Navigator.pop(ctx, true);
                                  _snack('Đã xóa ca ngày $day.');
                                }
                              },
                              child: const Text('Xóa',
                                  style: TextStyle(
                                      color: _danger,
                                      fontWeight: FontWeight.w600)),
                            ),
                          TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Hủy',
                                  style: TextStyle(
                                      color: _muted,
                                      fontWeight: FontWeight.w600))),
                          const SizedBox(width: 8),
                          Expanded(
                            child: PrimaryButton(
                              label: 'Lưu',
                              onPressed: () {
                                try {
                                  if (shift != null) {
                                    _s.ownerUpdateShift(
                                        shift,
                                        emp.name,
                                        dstr,
                                        inCtrl.text.isEmpty
                                            ? null
                                            : inCtrl.text,
                                        outCtrl.text.isEmpty
                                            ? null
                                            : outCtrl.text,
                                        status: status,
                                        breakMinutes: breakMinutes,
                                        note: noteCtrl.text.trim());
                                  } else {
                                    _s.ownerAddShift(
                                        emp.name,
                                        dstr,
                                        inCtrl.text.isEmpty
                                            ? null
                                            : inCtrl.text,
                                        outCtrl.text.isEmpty
                                            ? null
                                            : outCtrl.text,
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
                            ),
                          ),
                        ]),
                      ]),
                ),
              ),
            ),
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
              border: const Border(top: BorderSide(color: iosBorder)),
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
    final monthTotal = emp == null
        ? (days: 0, minutes: 0)
        : data.monthTotal(emp.name, _month.year, _month.month);
    final monthOvertime = emp == null
        ? 0
        : data.monthOvertime(emp.name, _month.year, _month.month);

    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 44, 24, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const IconTile(icon: CupertinoIcons.bag_fill, tint: _teal),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  data.storeName.toUpperCase(),
                  style: const TextStyle(
                      color: _muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.5),
                ),
              ),
              CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                onPressed: _showAboutDialog,
                child: const Icon(CupertinoIcons.info_circle,
                    color: _muted, size: 22),
              ),
            ]),
            const SizedBox(height: 14),
            const Text('Chấm công',
                style: TextStyle(
                    fontSize: 34, fontWeight: FontWeight.bold, color: _ink)),
            const SizedBox(height: 6),
            Text(
              '$weekday, ${_now.day} thg ${_now.month} ${_now.year}',
              style: const TextStyle(color: _muted, fontSize: 14),
            ),
            const SizedBox(height: 10),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(_clockStr,
                  style: const TextStyle(
                      color: _accent,
                      fontSize: 56,
                      fontWeight: FontWeight.w300,
                      height: 1)),
              const SizedBox(width: 8),
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('Giờ hiện tại',
                    style: TextStyle(color: _muted, fontSize: 13)),
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
            AppCard(
              padding: const EdgeInsets.all(20),
              child: open != null
                  ? Column(children: [
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _teal.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                    color: _teal, shape: BoxShape.circle)),
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
                              color: _accent,
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
                child: PrimaryButton(
                  icon: CupertinoIcons.play_circle_fill,
                  label: 'Vào ca',
                  onPressed: open != null || emp == null
                      ? null
                      : () => _act(() async => _s.clockIn(emp.name),
                          'Đã ghi giờ vào lúc $_clockStr.'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TintedButton(
                  tint: _danger,
                  icon: CupertinoIcons.stop_circle_fill,
                  label: 'Tan ca',
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
                ),
              ),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: TintedButton(
                  tint: _accent,
                  icon: CupertinoIcons.square_pencil,
                  label: 'Nhập tay giờ vào',
                  onPressed: emp == null
                      ? null
                      : () async {
                          final v = await _askTime('Nhập tay giờ vào', '');
                          if (v != null) {
                            await _act(() async => _s.manualIn(emp.name, v),
                                'Đã ghi giờ vào (nhập tay).');
                          }
                        },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TintedButton(
                  tint: _accent,
                  icon: CupertinoIcons.square_pencil,
                  label: 'Nhập tay giờ ra',
                  onPressed: emp == null
                      ? null
                      : () async {
                          final v = await _askTime('Nhập tay giờ ra', '');
                          if (v != null) {
                            await _act(() async => _s.manualOut(emp.name, v),
                                'Đã ghi giờ ra (nhập tay).');
                          }
                        },
                ),
              ),
            ]),
            const SizedBox(height: 8),
            const Text(
              'Nhập tay chỉ được trong đúng ngày hôm đó, giờ nhập tay được ghi chú rõ.',
              style: TextStyle(color: _muted, fontSize: 12),
            ),
            const SizedBox(height: 20),
            const AppSectionHeader(
                icon: CupertinoIcons.calendar, title: 'Bảng công tháng'),
            const SizedBox(height: 8),
            MonthSwitcher(
              monthLabel: 'Tháng ${_month.month}/${_month.year}',
              onPrev: () => setState(
                  () => _month = DateTime(_month.year, _month.month - 1)),
              onNext: () => setState(
                  () => _month = DateTime(_month.year, _month.month + 1)),
            ),
            const SizedBox(height: 16),
            const AppSectionHeader(
                icon: CupertinoIcons.chart_bar_fill, title: 'Tổng quan'),
            const SizedBox(height: 8),
            GradientSummaryCard(metrics: [
              MetricData(
                  icon: CupertinoIcons.calendar,
                  value: '${monthTotal.days}',
                  title: 'Ngày làm'),
              MetricData(
                  icon: CupertinoIcons.clock_fill,
                  value: fmtDuration(monthTotal.minutes),
                  title: 'Tổng giờ'),
              MetricData(
                  icon: CupertinoIcons.bolt_fill,
                  value: fmtDuration(monthOvertime),
                  title: 'Tăng ca'),
            ]),
            if (emp != null) ...[
              const SizedBox(height: 12),
              _salaryCard(data, emp, monthTotal.minutes),
            ],
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

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 48, 20, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Báo cáo',
              style: TextStyle(
                  fontSize: 34, fontWeight: FontWeight.bold, color: _ink)),
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
          MonthSwitcher(
            monthLabel: 'Tháng ${_month.month}/${_month.year}',
            onPrev: () => setState(
                () => _month = DateTime(_month.year, _month.month - 1)),
            onNext: () => setState(
                () => _month = DateTime(_month.year, _month.month + 1)),
          ),
          const SizedBox(height: 20),
          const AppSectionHeader(
              icon: CupertinoIcons.chart_bar_fill, title: 'Tổng hợp'),
          const SizedBox(height: 8),
          GradientSummaryCard(metrics: [
            MetricData(
                icon: CupertinoIcons.calendar,
                value: '${total.days}',
                title: 'Ngày làm'),
            MetricData(
                icon: CupertinoIcons.clock_fill,
                value: fmtDuration(total.minutes),
                title: 'Tổng giờ'),
            MetricData(
                icon: CupertinoIcons.bolt_fill,
                value: fmtDuration(overtime),
                title: 'Tăng ca'),
          ]),
          if (emp != null) ...[
            const SizedBox(height: 12),
            _salaryCard(data, emp, total.minutes),
          ],
          const SizedBox(height: 20),
          const AppSectionHeader(
              icon: CupertinoIcons.doc_text_fill, title: 'Xuất báo cáo'),
          const SizedBox(height: 8),
          _card(
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                IconTile(
                    icon: CupertinoIcons.doc_text_fill, tint: _accent),
                SizedBox(width: 12),
                Expanded(
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
                child: PrimaryButton(
                  icon: CupertinoIcons.doc_fill,
                  label: 'Tạo báo cáo PDF',
                  onPressed: emp == null ? null : _exportPdf,
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
            const Expanded(
                child: AppSectionHeader(
                    icon: CupertinoIcons.list_bullet,
                    title: 'Dữ liệu trong báo cáo')),
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
            Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  _shiftRow(rows[i]),
                ],
              ],
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
                  fontSize: 34, fontWeight: FontWeight.bold, color: _ink)),
          const SizedBox(height: 4),
          const Text('Chỉ chủ cửa hàng mới xem và sửa được mục này.',
              style: TextStyle(color: _muted, fontSize: 14)),
          const SizedBox(height: 20),
          const AppSectionHeader(icon: CupertinoIcons.bag_fill, title: 'Thông tin cửa hàng'),
          const SizedBox(height: 8),
          AppCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: const IconTile(
                  icon: CupertinoIcons.bag_fill, tint: _teal),
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
          const AppSectionHeader(icon: CupertinoIcons.person_2_fill, title: 'Nhân viên'),
          const SizedBox(height: 8),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < data.employees.length; i++) ...[
                  if (i > 0) const Divider(height: 1, color: _line),
                  _employeeRow(data.employees[i]),
                ],
                const Divider(height: 1, color: _line),
                ListTile(
                  leading: const IconTile(
                      icon: CupertinoIcons.plus_circle_fill,
                      tint: _accent),
                  title: const Text('Thêm nhân viên',
                      style: TextStyle(color: _accentDark)),
                  onTap: _addEmployee,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const AppSectionHeader(icon: CupertinoIcons.clock_fill, title: 'Giờ làm'),
          const SizedBox(height: 8),
          _card(
            Column(children: [
              Row(children: [
                const IconTile(
                    icon: CupertinoIcons.clock_fill, tint: _accent),
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
          const AppSectionHeader(icon: CupertinoIcons.money_dollar_circle_fill, title: 'Lương'),
          const SizedBox(height: 8),
          _card(
            Column(children: [
              Row(children: [
                const IconTile(
                    icon: CupertinoIcons.money_dollar_circle_fill,
                    tint: _teal),
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
          const AppSectionHeader(icon: CupertinoIcons.archivebox_fill, title: 'Sao lưu dữ liệu'),
          const SizedBox(height: 8),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              ListTile(
                leading: const IconTile(
                    icon: CupertinoIcons.square_arrow_up_on_square_fill,
                    tint: iosBlue),
                title: const Text('Xuất sao lưu (.json)'),
                subtitle: const Text(
                    'Lưu toàn bộ dữ liệu + cài đặt ra file JSON'),
                trailing: const Icon(CupertinoIcons.chevron_right,
                    size: 16, color: _muted),
                onTap: _exportBackup,
              ),
              const Divider(height: 1, color: _line),
              ListTile(
                leading: const IconTile(
                    icon: CupertinoIcons.square_arrow_down_on_square_fill,
                    tint: iosBlue),
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
          const AppSectionHeader(icon: CupertinoIcons.info_circle_fill, title: 'Giới thiệu'),
          const SizedBox(height: 8),
          _card(
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: _developerHeader(),
              ),
              const Divider(height: 1, color: _line),
              ..._aboutContactRows().expand((row) => [
                    row,
                    const Divider(height: 1, color: _line),
                  ]),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: _versionRow(),
              ),
            ]),
          ),
          const SizedBox(height: 20),
          const AppSectionHeader(icon: CupertinoIcons.question_circle_fill, title: 'Hỗ trợ'),
          const SizedBox(height: 8),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              ListTile(
                leading: const IconTile(
                    icon: CupertinoIcons.book_fill, tint: iosBlue),
                title: const Text('Hướng dẫn sử dụng'),
                trailing: const Icon(CupertinoIcons.chevron_right,
                    size: 16, color: _muted),
                onTap: _showGuideDialog,
              ),
              const Divider(height: 1, color: _line),
              ListTile(
                leading: const IconTile(
                    icon: CupertinoIcons.arrow_down_circle_fill,
                    tint: iosBlue),
                title: const Text('Kiểm tra bản cập nhật'),
                subtitle: const Text('Nhắn qua Facebook Hiếu Lê'),
                trailing: const Icon(CupertinoIcons.chevron_right,
                    size: 16, color: _muted),
                onTap: () => launchUrl(Uri.parse(_supportUrl),
                    mode: LaunchMode.externalApplication),
              ),
              const Divider(height: 1, color: _line),
              ListTile(
                leading: const IconTile(
                    icon: CupertinoIcons.chat_bubble_text_fill,
                    tint: iosBlue),
                title: const Text('Báo lỗi / Góp ý'),
                subtitle: const Text('Nhắn qua Facebook Hiếu Lê'),
                trailing: const Icon(CupertinoIcons.chevron_right,
                    size: 16, color: _muted),
                onTap: () => launchUrl(Uri.parse(_supportUrl),
                    mode: LaunchMode.externalApplication),
              ),
            ]),
          ),
          const SizedBox(height: 20),
          const AppSectionHeader(icon: CupertinoIcons.lock_fill, title: 'Chủ cửa hàng'),
          const SizedBox(height: 8),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              ListTile(
                leading: const IconTile(
                    icon: CupertinoIcons.lock_fill, tint: _accent),
                title: const Text('Đổi mật khẩu chủ'),
                trailing: const Icon(CupertinoIcons.chevron_right,
                    size: 16, color: _muted),
                onTap: _changeOwnerPassword,
              ),
              const Divider(height: 1, color: _line),
              ListTile(
                leading: const IconTile(
                    icon: CupertinoIcons.lock_open_fill, tint: _danger),
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
  // Thẻ tiền công tháng kiểu iOS (MonthlySalaryCard): IconTile banknote
  // teal, "Tiền công tháng", theo đơn giá, số tiền màu teal đậm.
  Widget _salaryCard(AppData data, Employee emp, int minutes) {
    final pay = minutes / 60 * emp.rate;
    return AppCard(
      child: Row(children: [
        const IconTile(
            icon: CupertinoIcons.money_dollar_circle_fill, tint: _teal),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Tiền công tháng',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: _ink)),
                const SizedBox(height: 3),
                Text('Theo ${emp.rate} ${data.currency}/giờ',
                    style: const TextStyle(color: _muted, fontSize: 13)),
              ]),
        ),
        Text('${pay.toStringAsFixed(0)} ${data.currency}',
            style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: _accentDark)),
      ]),
    );
  }

  Widget _card(Widget child) => AppCard(child: child);

  Widget _employeeRow(Employee e) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: _accent.withValues(alpha: 0.12),
        child: Text(e.name.isEmpty ? '?' : e.name[0].toUpperCase(),
            style: const TextStyle(
                color: _accent, fontWeight: FontWeight.bold)),
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

  // Hàng ngày công kiểu iOS (AttendanceRow): ô ngày 58x58 nền gradient
  // nhạt, số ngày to đậm màu indigo, chấm tròn màu trạng thái + tên
  // trạng thái, giờ vào-ra + ghi chú màu xám, bên phải là tổng giờ
  // và "Đã sửa" màu cam nếu giờ nhập tay.
  Widget _shiftRow(Shift s) {
    final d = DateTime.parse(s.date);
    final weekday = ['CN', 'T2', 'T3', 'T4', 'T5', 'T6', 'T7'][d.weekday % 7];
    final tint = statusTint(s.status);
    final sub = _shiftSubtitle(s);
    final showSub = s.status == 'work' || sub != shiftStatusTitle(s.status);
    final edited = s.inManual || s.outManual;
    return InkWell(
      onTap: () => _showEntryEditor(shift: s),
      child: AppCard(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              gradient: iosSoftBrandGradient,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('${d.day}',
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: _accent)),
                Text(weekday,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: _muted)),
              ],
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                    width: 7,
                    height: 7,
                    decoration:
                        BoxDecoration(color: tint, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(shiftStatusTitle(s.status),
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: _ink,
                        fontSize: 15)),
              ]),
              if (s.status == 'work') ...[
                const SizedBox(height: 4),
                Text(
                  '${s.clockIn == null ? '--:--' : fmtHhmm(s.clockIn!)} – ${s.clockOut == null ? '--:--' : fmtHhmm(s.clockOut!)}',
                  style: const TextStyle(color: _muted, fontSize: 13),
                ),
              ],
              if (showSub) ...[
                const SizedBox(height: 2),
                Text(sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _muted, fontSize: 13)),
              ],
            ]),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(s.status == 'work' ? fmtDuration(s.total) : '—',
                style: const TextStyle(
                    fontWeight: FontWeight.w600, color: _ink, fontSize: 15)),
            if (edited) ...[
              const SizedBox(height: 4),
              const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(CupertinoIcons.pencil, size: 10, color: _amber),
                SizedBox(width: 3),
                Text('Đã sửa',
                    style: TextStyle(fontSize: 11, color: _amber)),
              ]),
            ],
          ]),
        ]),
      ),
    );
  }
}
