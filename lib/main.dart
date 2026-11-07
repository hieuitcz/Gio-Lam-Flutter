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

import 'cloud_sync.dart';
import 'ios_theme.dart';
import 'logic.dart';
import 'report_pdf.dart';
import 'store.dart';

// Giao diện kiểu app chấm công iOS: thanh tab dưới cùng (Chấm công / Báo cáo /
// Cài đặt), nền xám nhóm, thẻ trắng bo tròn, tiêu đề lớn.
// 3 vai trò: nhân viên (mặc định khi mở app, chỉ thấy giờ làm của mình,
// không thấy tiền), chủ cửa hàng (tài khoản quản lý, thấy đầy đủ app),
// admin (quyền cao nhất, đầy đủ như chủ + mục Quản trị riêng).
// Tab Cài đặt chỉ chủ/admin mới thấy — không có nút hiện ra ngoài,
// mở bằng phím tắt Ctrl+H rồi nhập mật khẩu (chủ hoặc tổng).

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
    // Bọc cả bước chuyển file cũ: nếu không lấy được thư mục
    // Documents trên máy này thì bỏ qua, app vẫn mở bình thường
    // với dữ liệu mới (không được crash lúc khởi động).
    try {
      final oldFile = File(
          '${(await getApplicationDocumentsDirectory()).path}/gio-lam.json');
      if (await oldFile.exists()) {
        try {
          await oldFile.copy(dataFile.path);
          await oldFile.rename('${oldFile.path}.cu');
        } catch (_) {}
      }
    } catch (_) {}
  }
  final store = DataStore(dataFile);
  await store.load();
  // Khởi tạo Firebase (đồng bộ cloud). Lỗi (không mạng/chưa cấu hình)
  // thì app vẫn chạy hoàn toàn offline bằng JSON local, không crash.
  await cloudSync.initFirebase();
  runApp(GioLamApp(store: store));
}

class _OwnerIntent extends Intent {
  const _OwnerIntent();
}

class GioLamApp extends StatefulWidget {
  final DataStore store;
  const GioLamApp({super.key, required this.store});

  @override
  State<GioLamApp> createState() => _GioLamAppState();
}

class _GioLamAppState extends State<GioLamApp> {
  late String _fontFamily;

  @override
  void initState() {
    super.initState();
    _fontFamily = widget.store.data.fontFamily;
  }

  /// 'Lexend' -> dùng font Lexend; 'System' -> null = font mặc định của hệ thống.
  String? get _effectiveFontFamily => _fontFamily == 'Lexend' ? 'Lexend' : null;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chấm công by Hiếu Lê',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: _accent,
        useMaterial3: true,
        scaffoldBackgroundColor: _bg,
        fontFamily: _effectiveFontFamily,
      ),
      home: CupertinoTheme(
        data: CupertinoThemeData(
          brightness: Brightness.light,
          primaryColor: iosIndigo,
          textTheme: CupertinoTextThemeData(
            textStyle: TextStyle(fontFamily: _effectiveFontFamily, color: _ink),
          ),
        ),
        child: HomePage(
          store: widget.store,
          onFontChanged: (f) => setState(() => _fontFamily = f),
        ),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  final DataStore store;
  final ValueChanged<String>? onFontChanged;
  const HomePage({super.key, required this.store, this.onFontChanged});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  String? _employee;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  // Vai trò hiện tại: 'employee' (mặc định) | 'owner' (chủ cửa hàng) |
  // 'admin' (quyền cao nhất). Chủ và admin đều có quyền chủ ở các chỗ cũ.
  String _role = 'employee';
  // Chủ/admin có quyền chủ; admin có đầy đủ mọi chức năng như chủ.
  bool get _isOwner => _role == 'owner' || _role == 'admin';
  bool get _isAdmin => _role == 'admin';
  // Nhân viên + đang bật ẩn tiền công thì không được thấy tiền/đơn giá.
  bool get _payHidden => _role == 'employee' && _s.data.hidePay;
  DateTime _now = DateTime.now();
  int _tab = 0;
  String? _lastPdfPath;
  // Điều khiển hiệu ứng nhấp nháy của nút ⓘ hỗ trợ.
  late final AnimationController _pulseCtrl;
  // Đồng bộ cloud: true = đang hiện màn hình nhập mã PIN
  // (chưa có tài khoản đăng nhập). false = vào app bình thường.
  bool _showCloudLogin = false;
  // true = màn hình đặt mã PIN admin lần đầu (chưa có pins/config).
  bool _pinSetupMode = false;
  // Đang đăng nhập / đổi cửa hàng trên cloud (khóa nút lúc chờ).
  bool _cloudBusy = false;
  final _pinCtrl = TextEditingController();
  final _pinCtrl2 = TextEditingController();

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _employee = widget.store.data.employees.isNotEmpty
        ? widget.store.data.employees.first.name
        : null;
    _tick();
    // Đồng bộ cloud (nếu Firebase khởi tạo được): đăng nhập rồi thì
    // tải quyền + dữ liệu mới nhất về, chưa đăng nhập thì hiện màn
    // hình đăng nhập. Firebase lỗi thì bỏ qua, chạy offline.
    _cloudInit();
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

  @override
  void dispose() {
    cloudSync.stopPinChangeWatch();
    _pulseCtrl.dispose();
    _pinCtrl.dispose();
    _pinCtrl2.dispose();
    super.dispose();
  }

  // Huy hiệu vai trò ở đầu tab Chấm công: chip "CHỦ" indigo khi ở chế
  // độ chủ, chip "ADMIN" teal khi ở chế độ admin. Nhân viên không có chip.
  Widget _roleBadge() {
    if (_role == 'owner') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: iosIndigo.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Text('CHỦ',
            style: TextStyle(
                color: iosIndigo,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1)),
      );
    }
    if (_role == 'admin') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: _teal.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Text('ADMIN',
            style: TextStyle(
                color: _accentDark,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1)),
      );
    }
    return const SizedBox.shrink();
  }

  // Nhãn chip chọn nhân viên: nhân viên + đang ẩn tiền thì chỉ hiện tên,
  // không hiện đơn giá giờ (có đơn giá là tính ra được tiền).
  String _employeeChipLabel(Employee e) =>
      _payHidden ? e.name : '${e.name} · ${e.rate} ${_s.data.currency}/giờ';

  // Nút ⓘ hỗ trợ: icon indigo đặc trong vòng tròn tint + vòng lan tỏa
  // nhấp nháy liên tục cho dễ nhận biết.
  Widget _pulsingInfoButton() {
    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (context, child) {
        final t = _pulseCtrl.value; // 0..1, lên xuống liên tục
        return GestureDetector(
          onTap: _showAboutDialog,
          child: SizedBox(
            width: 56,
            height: 56,
            child: Stack(alignment: Alignment.center, children: [
              Transform.scale(
                scale: 1.0 + t * 0.6,
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: iosIndigo.withValues(alpha: 0.25 * (1 - t)),
                  ),
                ),
              ),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: iosIndigo.withValues(alpha: 0.12),
                ),
                child: const Icon(Icons.info, color: iosIndigo, size: 22),
              ),
            ]),
          ),
        );
      },
    );
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
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 15, color: _ink)),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(color: _muted, fontSize: 13)),
            ]),
          ),
          const Icon(Icons.chevron_right, size: 14, color: _muted),
        ]),
      ),
    );
  }

  List<Widget> _aboutContactRows() {
    return [
      _contactRow(
          icon: Icons.public,
          tint: iosBlue,
          label: 'Facebook',
          value: 'facebook.com/lehieuit',
          url: 'https://www.facebook.com/lehieuit'),
      _contactRow(
          icon: Icons.phone,
          tint: _teal,
          label: 'Điện thoại',
          value: '+420 773 155 611',
          url: 'tel:+420773155611'),
      _contactRow(
          icon: Icons.email,
          tint: _accent,
          label: 'Email',
          value: 'lehieuit91@gmail.com',
          url: 'mailto:lehieuit91@gmail.com'),
    ];
  }

  Widget _versionRow() {
    return const Row(children: [
      Expanded(
          child:
              Text('Phiên bản', style: TextStyle(fontSize: 15, color: _ink))),
      Text('Chấm công $_appVersion',
          style: TextStyle(fontSize: 15, color: _muted)),
    ]);
  }

  // Popup Giới thiệu kiểu iOS: Dialog bo 28, rộng và vuông (không dọc,
  // không nhỏ) như sheet EntryEditor. Chỉ còn nút Hướng dẫn + Đóng.
  Future<void> _showAboutDialog() async {
    await showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
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
                  const SizedBox(height: 18),
                  // Logo + tên + phiên bản trên 1 hàng.
                  Row(children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        gradient: iosBrandGradient,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: iosIndigo.withValues(alpha: 0.25),
                            blurRadius: 12,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.access_time_filled,
                          color: Colors.white, size: 32),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Chấm công by Hiếu Lê',
                              style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: _ink)),
                          SizedBox(height: 4),
                          Text('Chấm công $_appVersion',
                              style: TextStyle(fontSize: 13, color: _muted)),
                        ],
                      ),
                    ),
                  ]),
                  const SizedBox(height: 18),
                  // Thẻ tác giả + liên hệ nền xám, các hàng ngăn bằng kẻ mờ.
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: _bg,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 8),
                        _developerHeader(),
                        const SizedBox(height: 6),
                        ..._aboutContactRowsSeparated(),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  PrimaryButton(
                    label: 'Hướng dẫn sử dụng',
                    icon: Icons.menu_book,
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showGuideDialog();
                    },
                  ),
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Đóng',
                        style: TextStyle(
                            color: _muted, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Các hàng liên hệ ngăn nhau bằng kẻ mờ (kiểu list iOS).
  List<Widget> _aboutContactRowsSeparated() {
    final rows = _aboutContactRows();
    final out = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      out.add(rows[i]);
      if (i < rows.length - 1) {
        out.add(const Divider(height: 1, color: _line));
      }
    }
    return out;
  }

  // Popup Hướng dẫn kiểu iOS: rộng và vuông, 2 mục đặt cạnh nhau,
  // tiêu đề căn giữa, nút Đã hiểu gradient toàn chiều rộng.
  Future<void> _showGuideDialog() async {
    await showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                  const Text('Hướng dẫn sử dụng',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: _ink)),
                  const SizedBox(height: 18),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _guideSection(
                          icon: Icons.access_time_filled,
                          tint: iosIndigo,
                          title: 'Chấm công',
                          bullets: const [
                            'Mở app: nhập mã PIN của cửa hàng (do chủ cấp).',
                            'Đến làm: chọn tên mình rồi bấm Vào ca.',
                            'Về: bấm Tan ca. Quên bấm thì nhập tay giờ ra trong ngày.',
                            'Chạy đi cửa hàng khác rồi quay lại: tan ca rồi bấm Vào ca lại, 1 ngày chấm được nhiều lần.',
                            'Ca đêm (vd 20:00–05:00) được tính vào ngày bắt đầu ca.',
                          ],
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: _guideSection(
                          icon: Icons.description,
                          tint: _teal,
                          title: 'Báo cáo',
                          bullets: [
                            // Đang bật ẩn tiền: nhắc rõ tiền công chỉ chủ mới thấy.
                            _s.data.hidePay
                                ? 'Xem tổng giờ, tăng ca theo tháng (tiền công chỉ chủ mới thấy); bấm vào 1 ngày để sửa.'
                                : 'Xem tổng giờ, tăng ca, tiền công theo tháng; bấm vào 1 ngày để sửa.',
                            'Nút Xuất PDF để lưu bảng chấm công tháng.',
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  PrimaryButton(
                    label: 'Đã hiểu',
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Một mục trong hướng dẫn: tiêu đề có icon + các dòng gạch đầu dòng.
  Widget _guideSection({
    required IconData icon,
    required Color tint,
    required String title,
    required List<String> bullets,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          IconTile(icon: icon, tint: tint),
          const SizedBox(width: 10),
          Text(title,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, color: _ink)),
        ]),
        const SizedBox(height: 10),
        for (final b in bullets) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.only(top: 7, left: 6, right: 10),
                decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
              ),
              Expanded(
                child: Text(b,
                    style: const TextStyle(
                        fontSize: 15, height: 1.5, color: _ink)),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ],
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
    // Đẩy lên cloud (nếu đã đăng nhập). Chạy nền, không chờ: mất mạng
    // hay lỗi thì lần lưu sau tự đẩy lại, không chặn người dùng.
    unawaited(cloudSync.uploadBestEffort(_s));
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

  // --- Đồng bộ cloud (Firebase) + mã PIN ------------------------------
  // Chạy lúc mở app: Firebase chưa khởi tạo được thì bỏ qua, chạy
  // offline hoàn toàn; chưa đăng nhập thì hiện màn hình nhập mã PIN.
  // Chưa có mã PIN nào (pins/config chưa tồn tại) thì hiện màn hình
  // đặt mã PIN admin lần đầu. Mất mạng (không tải được pins/config)
  // thì hiện màn hình nhập PIN thường, bấm Vào sẽ báo mất mạng.
  Future<void> _cloudInit() async {
    if (!cloudSync.firebaseReady) return;
    final cfg = await cloudSync.fetchPinConfig();
    if (cloudSync.signedIn) {
      // Bản cũ đăng nhập bằng email: coi như admin, cho đặt PIN luôn
      // nếu chưa có PIN nào; đã có PIN thì vào app bình thường.
      if (cfg == null && !cloudSync.pinFetchFailed) {
        if (mounted) {
          setState(() {
            _showCloudLogin = true;
            _pinSetupMode = true;
          });
        }
        return;
      }
      await _afterCloudSignIn();
      return;
    }
    if (cfg == null && !cloudSync.pinFetchFailed) {
      if (mounted) {
        setState(() {
          _showCloudLogin = true;
          _pinSetupMode = true;
        });
      }
      return;
    }
    if (mounted) setState(() => _showCloudLogin = true);
  }

  // Sau khi đăng nhập cloud (lúc mở app hoặc nhập PIN): tải quyền
  // xem (users/{uid}), xử lý máy cửa hàng giữ sai cửa hàng, liệt kê
  // các cửa hàng, rồi đồng bộ dữ liệu mới nhất về. Vai trò local
  // (Ctrl+H) đi theo vai trò cloud: PIN chủ/admin thì mở luôn quyền
  // chủ/admin trên máy này; PIN cửa hàng thì ở vai trò nhân viên.
  Future<void> _afterCloudSignIn() async {
    await cloudSync.loadUserProfile(_s.data.storeName);
    // Chủ/admin vừa đổi mã PIN cửa hàng này: máy tự đăng xuất,
    // phải nhập mã PIN mới.
    if (await cloudSync.signOutIfStorePinChanged()) {
      if (!mounted) return;
      setState(() {
        _showCloudLogin = true;
        _role = 'employee';
        _tab = 0;
      });
      _snack('Mã PIN cửa hàng đã đổi. Nhập mã PIN mới để vào lại.');
      return;
    }
    _role = cloudSync.cloudRole == 'admin'
        ? 'admin'
        : cloudSync.cloudRole == 'owner'
            ? 'owner'
            : 'employee';
    // Tài khoản cửa hàng: máy chỉ được giữ đúng cửa hàng của tài khoản.
    if (cloudSync.cloudRole == 'store' &&
        cloudSync.cloudStoreId != null &&
        cloudSync.cloudStoreId != '*' &&
        cloudSync.cloudStoreId != _s.data.storeName) {
      final target = cloudSync.cloudStoreId!;
      final isEmptySeed = _s.data.ownerHash == null &&
          _s.data.shifts.values.every((l) => l.isEmpty);
      if (isEmptySeed) {
        // Máy mới chưa có dữ liệu thật: đổi tên cửa hàng local theo
        // tài khoản rồi đẩy lên cloud làm dữ liệu ban đầu.
        _s.data.storeName = target;
        await cloudSync.uploadBestEffort(_s);
      } else {
        final ok = await cloudSync.switchStore(_s, target);
        if (!ok && mounted) {
          _snack(
              'Tài khoản này là của cửa hàng $target, máy đang giữ dữ liệu cửa hàng ${_s.data.storeName}. Nhờ chủ cửa hàng kiểm tra.');
        }
      }
    }
    await cloudSync.fetchStoreIds();
    final changed = await cloudSync.syncOnStartup(_s);
    if (!mounted) return;
    setState(() {
      if (changed) {
        _employee =
            _s.data.employees.isNotEmpty ? _s.data.employees.first.name : null;
      }
    });
    if (changed) _snack('Đã đồng bộ dữ liệu mới nhất từ cloud.');
    // Theo dõi đổi PIN lúc đang chạy: chủ/admin đổi PIN cửa hàng thì
    // máy cửa hàng đó tự đăng xuất ngay (chỉ tài khoản cửa hàng).
    cloudSync.startPinChangeWatch(onStorePinChanged: () {
      if (!mounted) return;
      setState(() {
        _showCloudLogin = true;
        _role = 'employee';
        _tab = 0;
      });
      _snack('Mã PIN cửa hàng đã đổi. Nhập mã PIN mới để vào lại.');
    });
  }

  // Đăng nhập cloud bằng mã PIN (thay cho email/mật khẩu): PIN khớp
  // hash trong pins/config thì đăng nhập bằng tài khoản Firebase suy
  // ra từ PIN. Sai PIN / mất mạng thì báo lỗi, không kẹt.
  Future<void> _pinLogin() async {
    final pin = _pinCtrl.text.trim();
    if (!isValidPin(pin)) {
      _snack('Mã PIN gồm 4-6 chữ số.');
      return;
    }
    setState(() => _cloudBusy = true);
    try {
      await cloudSync.signInWithPin(pin);
      await _afterCloudSignIn();
      if (!mounted) return;
      setState(() {
        _showCloudLogin = false;
        _cloudBusy = false;
        _pinCtrl.clear();
      });
      _snack(cloudSync.cloudRole == 'admin'
          ? 'Đã vào bằng mã PIN admin.'
          : cloudSync.cloudRole == 'owner'
              ? 'Đã vào bằng mã PIN chủ.'
              : 'Đã vào cửa hàng ${cloudSync.cloudStoreId ?? _s.data.storeName}.');
    } on StateError catch (e) {
      if (!mounted) return;
      setState(() => _cloudBusy = false);
      _snack(e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _cloudBusy = false);
      _snack('Mất mạng, thử lại sau.');
    }
  }

  // Đặt mã PIN admin lần đầu (chưa có mã PIN nào): người mở app đầu
  // tiên làm việc này, nhập 2 lần rồi vào luôn với vai trò admin.
  Future<void> _pinSetup() async {
    final pin = _pinCtrl.text.trim();
    final pin2 = _pinCtrl2.text.trim();
    if (!isValidPin(pin)) {
      _snack('Mã PIN gồm 4-6 chữ số.');
      return;
    }
    if (pin != pin2) {
      _snack('Hai lần nhập không khớp.');
      return;
    }
    setState(() => _cloudBusy = true);
    try {
      await cloudSync.setupAdminPin(pin);
      await _afterCloudSignIn();
      if (!mounted) return;
      setState(() {
        _showCloudLogin = false;
        _cloudBusy = false;
        _pinSetupMode = false;
        _pinCtrl.clear();
        _pinCtrl2.clear();
      });
      _snack('Đã đặt mã PIN admin. Giữ kỹ mã PIN này.');
    } on StateError catch (e) {
      if (!mounted) return;
      setState(() => _cloudBusy = false);
      _snack(e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _cloudBusy = false);
      _snack('Mất mạng, thử lại sau.');
    }
  }

  // Đăng xuất cloud (Cài đặt, chỉ chủ/admin): về màn hình đăng nhập.
  // Dữ liệu local trên máy vẫn giữ nguyên, chỉ là không đồng bộ nữa.
  Future<void> _cloudSignOut() async {
    cloudSync.stopPinChangeWatch();
    await cloudSync.signOut();
    setState(() {
      _showCloudLogin = true;
      _role = 'employee';
      _tab = 0;
    });
  }

  // Nút "Đồng bộ ngay" trong Cài đặt: tải về nếu cloud mới hơn,
  // không thì đẩy local lên.
  Future<void> _syncNow() async {
    if (!cloudSync.available) {
      _snack('Chưa đăng nhập đồng bộ.');
      return;
    }
    setState(() => _cloudBusy = true);
    final changed = await cloudSync.syncNow(_s);
    if (!mounted) return;
    setState(() {
      _cloudBusy = false;
      if (changed) {
        _employee =
            _s.data.employees.isNotEmpty ? _s.data.employees.first.name : null;
      }
    });
    _snack(changed
        ? 'Đã tải dữ liệu mới nhất từ cloud.'
        : 'Đã đồng bộ xong (dữ liệu local đã đẩy lên cloud).');
  }

  // Đổi sang xem cửa hàng khác (chỉ chủ/admin, có ô chọn ở đầu tab
  // Chấm công). Đẩy dữ liệu cửa hàng hiện tại lên trước rồi mới tải
  // cửa hàng mới về; mất mạng thì chặn đổi.
  Future<void> _switchStore(String storeId) async {
    if (storeId == _s.data.storeName || _cloudBusy) return;
    setState(() => _cloudBusy = true);
    final ok = await cloudSync.switchStore(_s, storeId);
    if (!mounted) return;
    setState(() => _cloudBusy = false);
    if (!ok) {
      _snack('Mất mạng, không đổi được cửa hàng.');
      return;
    }
    setState(() {
      _employee =
          _s.data.employees.isNotEmpty ? _s.data.employees.first.name : null;
    });
    _snack('Đang xem cửa hàng $storeId.');
  }

  // --- Chủ tự quản lý cửa hàng (chỉ chủ/admin) ------------------------
  // Chủ thêm cửa hàng + mã PIN trong app, rồi gửi bộ cài app cho cửa
  // hàng đó; cửa hàng nhập PIN là vào đúng cửa hàng của mình.
  Future<void> _addStore() async {
    if (!cloudSync.available || !cloudSync.canPickStore) {
      _snack('Chưa đăng nhập chủ cửa hàng.');
      return;
    }
    final nameCtrl = TextEditingController();
    final pinCtrl = TextEditingController();
    final pin2Ctrl = TextEditingController();
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Thêm cửa hàng'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          CupertinoTextField(
              style: const TextStyle(color: _ink),
              controller: nameCtrl,
              placeholder: 'Tên cửa hàng'),
          const SizedBox(height: 8),
          CupertinoTextField(
              style: const TextStyle(color: _ink),
              controller: pinCtrl,
              placeholder: 'Mã PIN (4-6 chữ số)',
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 6),
          const SizedBox(height: 8),
          CupertinoTextField(
              style: const TextStyle(color: _ink),
              controller: pin2Ctrl,
              placeholder: 'Nhập lại mã PIN',
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 6),
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
    final name = nameCtrl.text.trim();
    final pin = pinCtrl.text.trim();
    if (name.isEmpty) {
      _snack('Nhập tên cửa hàng.');
      return;
    }
    if (!isValidPin(pin) || pin != pin2Ctrl.text.trim()) {
      _snack('Mã PIN gồm 4-6 chữ số và 2 lần nhập phải khớp.');
      return;
    }
    setState(() => _cloudBusy = true);
    try {
      await cloudSync.createStore(name, pin);
      if (!mounted) return;
      setState(() => _cloudBusy = false);
      // Hiện mã PIN để chủ báo cho cửa hàng (sau này xem lại được ở
      // Cài đặt > Cửa hàng, nút mắt).
      await showCupertinoDialog(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: Text('Đã thêm cửa hàng $name'),
          content:
              Text('Mã PIN của cửa hàng là: $pin\nBáo mã này cho cửa hàng. '
                  'Sau này xem lại được ở Cài đặt > Cửa hàng.'),
          actions: [
            CupertinoDialogAction(
                isDefaultAction: true,
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Đã ghi nhớ')),
          ],
        ),
      );
    } on StateError catch (e) {
      if (!mounted) return;
      setState(() => _cloudBusy = false);
      _snack(e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _cloudBusy = false);
      _snack('Mất mạng, thử lại sau.');
    }
  }

  // Xem lại mã PIN 1 cửa hàng (chỉ chủ/admin).
  Future<void> _showStorePin(String storeId) async {
    setState(() => _cloudBusy = true);
    final pin = await cloudSync.fetchStorePin(storeId);
    if (!mounted) return;
    setState(() => _cloudBusy = false);
    if (pin == null) {
      _snack(
          'Cửa hàng này tạo từ bản cũ, chưa lưu mã PIN. Tạo cửa hàng mới rồi xóa cửa hàng cũ.');
      return;
    }
    await showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text('Mã PIN cửa hàng $storeId'),
        content: Text('Mã PIN là: $pin\nChỉ chủ cửa hàng xem được mã này.'),
        actions: [
          CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Đã ghi nhớ')),
        ],
      ),
    );
  }

  // Đổi mã PIN 1 cửa hàng (chỉ chủ/admin): nhập mã mới 2 lần. Đổi
  // xong máy cửa hàng đó tự đăng xuất, phải nhập mã PIN mới.
  Future<void> _changeStorePin(String storeId) async {
    final pinCtrl = TextEditingController();
    final pin2Ctrl = TextEditingController();
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text('Đổi mã PIN $storeId'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          CupertinoTextField(
              style: const TextStyle(color: _ink),
              controller: pinCtrl,
              placeholder: 'Mã PIN mới (4-6 chữ số)',
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 6),
          const SizedBox(height: 8),
          CupertinoTextField(
              style: const TextStyle(color: _ink),
              controller: pin2Ctrl,
              placeholder: 'Nhập lại mã PIN mới',
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 6),
        ]),
        actions: [
          CupertinoDialogAction(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Hủy')),
          CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Đổi')),
        ],
      ),
    );
    if (ok != true) return;
    final pin = pinCtrl.text.trim();
    if (!isValidPin(pin) || pin != pin2Ctrl.text.trim()) {
      _snack('Mã PIN gồm 4-6 chữ số và 2 lần nhập phải khớp.');
      return;
    }
    setState(() => _cloudBusy = true);
    try {
      await cloudSync.setStorePin(storeId, pin);
      if (!mounted) return;
      setState(() => _cloudBusy = false);
      _snack(
          'Đã đổi mã PIN cửa hàng $storeId. Máy cửa hàng sẽ bị đăng xuất, phải nhập mã PIN mới.');
    } on StateError catch (e) {
      if (!mounted) return;
      setState(() => _cloudBusy = false);
      _snack(e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _cloudBusy = false);
      _snack('Mất mạng, thử lại sau.');
    }
  }

  // Xóa cửa hàng (chỉ chủ/admin): xóa dữ liệu cloud + quyền xem +
  // mã PIN của cửa hàng đó. Không xóa được cửa hàng đang xem (đổi
  // sang cửa hàng khác trước) để dữ liệu local không đẩy lại lên
  // cloud làm cửa hàng sống lại.
  Future<void> _deleteStore(String storeName) async {
    if (!cloudSync.available || !cloudSync.canPickStore) {
      _snack('Chưa đăng nhập chủ cửa hàng.');
      return;
    }
    if (storeName == _s.data.storeName) {
      _snack(
          'Không xóa được cửa hàng đang xem — đổi sang cửa hàng khác trước.');
      return;
    }
    final ok = await _confirm('Xóa cửa hàng',
        'Xóa cửa hàng $storeName cùng toàn bộ dữ liệu chấm công và mã PIN của nó?');
    if (!ok) return;
    setState(() => _cloudBusy = true);
    try {
      await cloudSync.deleteStore(storeName);
      if (!mounted) return;
      setState(() => _cloudBusy = false);
      _snack('Đã xóa cửa hàng $storeName.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _cloudBusy = false);
      _snack('Mất mạng, thử lại sau.');
    }
  }

  // Admin ĐẶT/ĐỔI mã PIN chủ hoặc mã PIN admin (mục Quản trị).
  // Đổi mã PIN admin xong thì phiên admin hiện tại mất quyền nên phải
  // đăng xuất rồi đăng nhập lại bằng PIN mới.
  Future<void> _setRolePin(String kind) async {
    final title = kind == 'owner' ? 'mã PIN chủ' : 'mã PIN admin';
    // PIN đã có thì đây là ĐỔI pin: hỏi thêm mã PIN hiện tại để app
    // đổi được cả mật khẩu tài khoản (mật khẩu suy ra từ PIN).
    final exists = kind == 'owner'
        ? cloudSync.pinConfig?.ownerPinHash != null
        : cloudSync.pinConfig?.adminPinHash != null;
    final curCtrl = TextEditingController();
    final pinCtrl = TextEditingController();
    final pin2Ctrl = TextEditingController();
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(exists ? 'Đổi $title' : 'Đặt $title'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          if (exists)
            CupertinoTextField(
                style: const TextStyle(color: _ink),
                controller: curCtrl,
                placeholder: '$title hiện tại',
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 6),
          if (exists) const SizedBox(height: 8),
          CupertinoTextField(
              style: const TextStyle(color: _ink),
              controller: pinCtrl,
              placeholder: '$title mới (4-6 chữ số)',
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 6),
          const SizedBox(height: 8),
          CupertinoTextField(
              style: const TextStyle(color: _ink),
              controller: pin2Ctrl,
              placeholder: 'Nhập lại $title',
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 6),
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
    final pin = pinCtrl.text.trim();
    if (!isValidPin(pin) || pin != pin2Ctrl.text.trim()) {
      _snack('Mã PIN gồm 4-6 chữ số và 2 lần nhập phải khớp.');
      return;
    }
    final cur = curCtrl.text.trim();
    if (exists && !isValidPin(cur)) {
      _snack('Nhập mã PIN hiện tại để đổi.');
      return;
    }
    setState(() => _cloudBusy = true);
    try {
      await cloudSync.setRolePin(kind, pin, currentPin: exists ? cur : null);
      if (!mounted) return;
      setState(() => _cloudBusy = false);
      if (kind == 'admin') {
        _snack('Đã đổi mã PIN admin. Đăng nhập lại bằng mã PIN mới.');
        await _cloudSignOut();
      } else {
        _snack('Đã đặt $title. Báo mã này cho chủ cửa hàng.');
      }
    } on StateError catch (e) {
      if (!mounted) return;
      setState(() => _cloudBusy = false);
      _snack(e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _cloudBusy = false);
      _snack('Đổi mã PIN lỗi: $e');
    }
  }

  // Màn hình nhập mã PIN: hiện khi Firebase khởi tạo được mà chưa
  // có tài khoản đăng nhập. PIN cửa hàng chỉ hiện đúng cửa hàng đó;
  // PIN chủ/admin thì xem được hết. Có nút "Dùng offline" để máy
  // chưa có PIN vẫn dùng được bình thường (lần mở sau hỏi lại).
  // Chưa có mã PIN nào thì hiện màn hình đặt mã PIN admin lần đầu.
  Widget _cloudLoginScreen() {
    final setup = _pinSetupMode;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: iosBrandGradient,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(Icons.access_time_filled,
                      color: Colors.white, size: 32),
                ),
              ),
              const SizedBox(height: 16),
              Text(setup ? 'Đặt mã PIN admin' : 'Nhập mã PIN',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold, color: _ink)),
              const SizedBox(height: 8),
              Text(
                setup
                    ? 'Chưa có mã PIN nào. Người mở app đầu tiên đặt mã PIN admin (4-6 chữ số) — mã này mở được tất cả các cửa hàng. Giữ kỹ mã PIN này.'
                    : 'Nhập mã PIN của cửa hàng (do chủ cấp) để vào đúng cửa hàng đó. Mã PIN chủ thì xem được hết các cửa hàng. Mất mạng vẫn dùng được offline.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: _muted, fontSize: 14),
              ),
              const SizedBox(height: 24),
              CupertinoTextField(
                style: const TextStyle(color: _ink),
                controller: _pinCtrl,
                placeholder: setup ? 'Mã PIN admin mới' : 'Mã PIN',
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 6,
                onSubmitted: (_) => setup ? _pinSetup() : _pinLogin(),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              if (setup) ...[
                const SizedBox(height: 12),
                CupertinoTextField(
                  style: const TextStyle(color: _ink),
                  controller: _pinCtrl2,
                  placeholder: 'Nhập lại mã PIN admin',
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  maxLength: 6,
                  onSubmitted: (_) => _pinSetup(),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ],
              const SizedBox(height: 20),
              PrimaryButton(
                label: _cloudBusy
                    ? 'Đang kiểm tra…'
                    : setup
                        ? 'Đặt mã PIN'
                        : 'Vào',
                onPressed: _cloudBusy
                    ? null
                    : setup
                        ? _pinSetup
                        : _pinLogin,
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _cloudBusy
                    ? null
                    : () => setState(() => _showCloudLogin = false),
                child: const Text('Dùng offline (không đồng bộ)',
                    style:
                        TextStyle(color: _muted, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Ô chọn cửa hàng ở đầu tab Chấm công: chỉ tài khoản cloud là chủ
  // cửa hàng (quản lý) hoặc admin tổng mới thấy; tài khoản cửa hàng
  // chỉ xem cửa hàng của mình nên không có ô chọn.
  Widget _storePicker() {
    if (!cloudSync.canPickStore || cloudSync.storeIds.isEmpty) {
      return const SizedBox.shrink();
    }
    final items = {...cloudSync.storeIds, _s.data.storeName}.toList()..sort();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(children: [
        const Icon(Icons.store, size: 16, color: _muted),
        const SizedBox(width: 8),
        const Text('Cửa hàng',
            style: TextStyle(
                color: _muted, fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _line)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: items.contains(_s.data.storeName)
                    ? _s.data.storeName
                    : null,
                isExpanded: true,
                items: items
                    .map((id) => DropdownMenuItem(
                        value: id,
                        child: Text(id,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, color: _ink))))
                    .toList(),
                onChanged: _cloudBusy
                    ? null
                    : (v) {
                        if (v != null) _switchStore(v);
                      },
              ),
            ),
          ),
        ),
      ]),
    );
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
            style: const TextStyle(color: _ink),
            controller: ctrl,
            autofocus: true,
            placeholder: 'vd 9:00',
            keyboardType: TextInputType.datetime,
          ),
        ),
        actions: [
          CupertinoDialogAction(
              onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
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
            style: const TextStyle(color: _ink),
            controller: ctrl,
            obscureText: true,
            autofocus: true,
            placeholder: 'Mật khẩu',
          ),
        ),
        actions: [
          CupertinoDialogAction(
              onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('OK')),
        ],
      ),
    );
  }

  Future<bool> _confirm(String title, String message,
      {String confirmLabel = 'Xóa', bool destructive = true}) async {
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
              isDestructiveAction: destructive,
              isDefaultAction: !destructive,
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(confirmLabel)),
        ],
      ),
    );
    return ok == true;
  }

  // Đăng nhập 3 vai trò bằng Ctrl+H: nhập mật khẩu 1 lần, kiểm tra mật
  // khẩu tổng TRƯỚC (đúng -> admin), rồi mới kiểm tra mật khẩu chủ
  // (đúng -> chủ). Nhấn Ctrl+H lần nữa thì thoát về nhân viên.
  Future<void> _ownerLogin() async {
    if (_role != 'employee') {
      final wasAdmin = _isAdmin;
      setState(() {
        _role = 'employee';
        _tab = 0;
      });
      _snack(wasAdmin
          ? 'Đã thoát chế độ admin.'
          : 'Đã thoát chế độ chủ cửa hàng.');
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
    final pw = await _askPassword('Nhập mật khẩu');
    if (pw == null) return;
    final role = _s.resolveLoginRole(pw);
    if (role == null) {
      _snack('Mật khẩu không đúng.');
      return;
    }
    setState(() {
      _role = role;
      _tab = 2;
    });
    _snack(role == 'admin'
        ? 'Đã vào chế độ admin.'
        : 'Đã vào chế độ chủ cửa hàng.');
  }

  // Đổi mật khẩu chủ: hỏi mật khẩu hiện tại trước — chấp nhận mật khẩu
  // chủ cũ HOẶC mật khẩu tổng (để admin đổi được mà không cần biết
  // mật khẩu chủ cũ) — rồi mới nhập mật khẩu mới 2 lần.
  Future<void> _changeOwnerPassword() async {
    final current = await _askPassword('Mật khẩu hiện tại');
    if (current == null) return;
    if (_s.resolveLoginRole(current) == null) {
      _snack('Mật khẩu hiện tại không đúng.');
      return;
    }
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

  // --- Mật khẩu tổng (admin) -------------------------------------------
  // Đặt lần đầu (chưa có mật khẩu tổng): nhập mới 2 lần.
  Future<void> _setMasterPassword() async {
    final pw = await _askPassword('Đặt mật khẩu tổng');
    if (pw == null || pw.isEmpty) return;
    final pw2 = await _askPassword('Nhập lại mật khẩu tổng');
    if (pw != pw2) {
      _snack('Hai lần nhập không khớp.');
      return;
    }
    await _s.setMasterPassword(pw);
    setState(() {});
    _snack('Đã đặt mật khẩu tổng. Chỉ anh biết mật khẩu này.');
  }

  // Đổi mật khẩu tổng (chỉ admin): nhập mật khẩu tổng cũ + mới 2 lần.
  Future<void> _changeMasterPassword() async {
    final current = await _askPassword('Mật khẩu tổng hiện tại');
    if (current == null) return;
    if (!_s.checkMasterPassword(current)) {
      _snack('Mật khẩu tổng hiện tại không đúng.');
      return;
    }
    final pw = await _askPassword('Mật khẩu tổng mới');
    if (pw == null || pw.isEmpty) return;
    final pw2 = await _askPassword('Nhập lại mật khẩu tổng mới');
    if (pw != pw2) {
      _snack('Hai lần nhập không khớp.');
      return;
    }
    await _s.setMasterPassword(pw);
    _snack('Đã đổi mật khẩu tổng.');
  }

  // Admin đặt lại mật khẩu chủ mà không cần biết mật khẩu chủ cũ:
  // nhập mật khẩu tổng + mật khẩu chủ mới 2 lần.
  Future<void> _resetOwnerPassword() async {
    final master = await _askPassword('Mật khẩu tổng');
    if (master == null) return;
    if (!_s.checkMasterPassword(master)) {
      _snack('Mật khẩu tổng không đúng.');
      return;
    }
    final pw = await _askPassword('Mật khẩu chủ mới');
    if (pw == null || pw.isEmpty) return;
    final pw2 = await _askPassword('Nhập lại mật khẩu mới');
    if (pw != pw2) {
      _snack('Hai lần nhập không khớp.');
      return;
    }
    _s.setOwnerPassword(pw);
    await _save();
    _snack('Đã đặt lại mật khẩu chủ.');
  }

  // --- Sửa/thêm từng ngày (EntryEditor kiểu iOS) ---
  // Ngày hôm nay ai cũng sửa được; ca qua đêm kết thúc hôm nay cũng
  // sửa được trong buổi sáng hôm đó; ngày khác chỉ chủ mới sửa.
  Future<void> _showEntryEditor({Shift? shift, String? date}) async {
    final emp = _s.data.employees.where((e) => e.name == _employee).firstOrNull;
    if (emp == null) return;
    final day = shift?.date ?? date ?? _todayStr;
    final editable = shift != null
        ? canEmployeeEditShift(shift.date, shift.clockIn, shift.clockOut)
        : day == _todayStr;
    if (!editable && !_isOwner) {
      _snack(
          'Ngày đã qua bạn không có quyền sửa, hãy liên hệ chủ cửa hàng để được trợ giúp');
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
                  : ((durationMinutes(ci, co)! - breakMinutes)
                      .clamp(0, 24 * 60))
              : 0;
          return Dialog(
            backgroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
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
                              // Nhân viên thêm ngày chỉ được thêm đúng
                              // hôm nay nên không cho chọn ngày khác.
                              if (_isOwner)
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
                              onSelected: (_) => setState(() => status = s.$1),
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
                                    style: const TextStyle(color: _ink),
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
                                    style: const TextStyle(color: _ink),
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
                                style: TextStyle(fontSize: 15, color: _ink)),
                            const Spacer(),
                            CupertinoButton(
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              onPressed: breakMinutes <= 0
                                  ? null
                                  : () => setState(() => breakMinutes -= 5),
                              child: const Icon(Icons.remove_circle,
                                  color: _accent, size: 24),
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
                              child: const Icon(Icons.add_circle,
                                  color: _accent, size: 24),
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
                          style: const TextStyle(color: _ink),
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
                          // Nhân viên chỉ được xóa ca bắt đầu hôm nay;
                          // ca ngày đã qua (kể cả ca qua đêm vừa kết
                          // thúc sáng nay) chỉ chủ mới xóa được.
                          if (shift != null &&
                              (_isOwner || shift.date == _todayStr))
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
                                // Kiểm tra lại lúc lưu: nhân viên không
                                // được lưu ca ngày đã qua (kể cả khi đã
                                // đổi ngày trong hộp thoại Thêm ngày).
                                final allowed = _isOwner ||
                                    (shift != null
                                        ? canEmployeeEditShift(shift.date,
                                            shift.clockIn, shift.clockOut)
                                        : canEmployeeAddShift(dstr));
                                if (!allowed) {
                                  _snack(
                                      'Ngày đã qua bạn không có quyền sửa, hãy liên hệ chủ cửa hàng để được trợ giúp');
                                  return;
                                }
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
    final leaveCtrl =
        TextEditingController(text: emp.annualLeaveAllowance.toString());
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Sửa nhân viên'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          CupertinoTextField(
              style: const TextStyle(color: _ink),
              controller: nameCtrl,
              placeholder: 'Tên'),
          const SizedBox(height: 8),
          CupertinoTextField(
              style: const TextStyle(color: _ink),
              controller: rateCtrl,
              placeholder: 'Đơn giá/giờ (vd 160)',
              keyboardType: TextInputType.number),
          const SizedBox(height: 8),
          CupertinoTextField(
              style: const TextStyle(color: _ink),
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
    final leave =
        int.tryParse(leaveCtrl.text.trim()) ?? emp.annualLeaveAllowance;
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
    // Chọn cửa hàng khi thêm (chỉ chủ/admin, khi có >1 cửa hàng).
    // Mặc định là cửa hàng đang xem.
    final stores = {...cloudSync.storeIds, _s.data.storeName}.toList()..sort();
    final canPick = cloudSync.canPickStore && stores.length > 1;
    var targetStore = _s.data.storeName;
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => CupertinoAlertDialog(
          title: const Text('Thêm nhân viên'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 12),
            CupertinoTextField(
                style: const TextStyle(color: _ink),
                controller: nameCtrl,
                placeholder: 'Tên'),
            const SizedBox(height: 8),
            CupertinoTextField(
                style: const TextStyle(color: _ink),
                controller: rateCtrl,
                placeholder: 'Đơn giá/giờ (vd 160)',
                keyboardType: TextInputType.number),
            if (canPick) ...[
              const SizedBox(height: 12),
              Row(children: [
                const Text('Cửa hàng',
                    style: TextStyle(color: _muted, fontSize: 14)),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _line)),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: targetStore,
                        isExpanded: true,
                        items: stores
                            .map((id) => DropdownMenuItem(
                                value: id,
                                child: Text(id,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: _ink,
                                        fontSize: 14))))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setD(() => targetStore = v);
                        },
                      ),
                    ),
                  ),
                ),
              ]),
            ],
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
      ),
    );
    if (ok != true) return;
    final name = nameCtrl.text.trim();
    final rate = int.tryParse(rateCtrl.text.trim());
    if (name.isEmpty || rate == null) {
      _snack('Tên hoặc giá giờ không hợp lệ.');
      return;
    }
    if (targetStore == _s.data.storeName) {
      if (!_s.data.addEmployee(Employee(name, rate))) {
        _snack('Đã có nhân viên tên $name.');
        return;
      }
      setState(() => _employee = name);
      await _save();
      _snack('Đã thêm nhân viên.');
      return;
    }
    // Thêm vào cửa hàng khác trên cloud (không cần chuyển màn hình).
    setState(() => _cloudBusy = true);
    try {
      await cloudSync.addEmployeeToStore(targetStore, Employee(name, rate));
      _snack('Đã thêm $name vào cửa hàng $targetStore.');
    } on StateError catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('Thêm nhân viên lỗi: $e');
    } finally {
      if (mounted) setState(() => _cloudBusy = false);
    }
  }

  /// Chọn 1 cửa hàng trong danh sách (action sheet kiểu iOS).
  Future<String?> _pickStore(List<String> stores, String title) {
    return showCupertinoModalPopup<String>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(title),
        actions: [
          for (final s in stores)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(ctx, s),
              child: Text(s),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Hủy'),
        ),
      ),
    );
  }

  /// Nút ⇄ ở dòng nhân viên: chọn gán thêm vào cửa hàng khác (vẫn ở
  /// cửa hàng này — 1 nhân viên làm được 2 cửa hàng, giờ làm mỗi
  /// cửa hàng tính riêng) hay chuyển hẳn sang cửa hàng khác (xóa
  /// khỏi cửa hàng này, ca làm chuyển theo).
  Future<void> _employeeStoreAction(Employee emp) async {
    if (!cloudSync.canPickStore) {
      _snack('Chưa đăng nhập chủ cửa hàng.');
      return;
    }
    final choice = await showCupertinoModalPopup<String>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text('${emp.name} — cửa hàng'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(ctx, 'assign'),
            child: const Text('Gán thêm vào cửa hàng khác'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(ctx, 'move'),
            child: const Text('Chuyển sang cửa hàng khác'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Hủy'),
        ),
      ),
    );
    if (choice == null) return;
    await _assignEmployeeToStore(emp, move: choice == 'move');
  }

  /// Gán nhân viên sang cửa hàng khác: move=false thì chỉ thêm vào
  /// cửa hàng đích (vẫn ở cửa hàng này); move=true thì chuyển hẳn
  /// (xóa khỏi cửa hàng này, toàn bộ ca làm chuyển theo).
  Future<void> _assignEmployeeToStore(Employee emp,
      {required bool move}) async {
    if (!cloudSync.canPickStore) {
      _snack('Chưa đăng nhập chủ cửa hàng.');
      return;
    }
    if (move && _s.data.employees.length <= 1) {
      _snack('Cửa hàng phải còn ít nhất 1 nhân viên.');
      return;
    }
    final targets = {...cloudSync.storeIds, _s.data.storeName}.toList()
      ..sort()
      ..remove(_s.data.storeName);
    if (targets.isEmpty) {
      _snack('Chỉ có 1 cửa hàng, không gán/chuyển được.');
      return;
    }
    final target = await _pickStore(
        targets,
        move
            ? 'Chuyển ${emp.name} sang cửa hàng'
            : 'Gán ${emp.name} vào cửa hàng');
    if (target == null) return;
    final ok = await _confirm(
        move ? 'Chuyển cửa hàng' : 'Gán thêm cửa hàng',
        move
            ? 'Chuyển ${emp.name} cùng toàn bộ ca làm sang cửa hàng $target?'
            : 'Gán ${emp.name} thêm vào cửa hàng $target? Người này vẫn ở cửa hàng ${_s.data.storeName}, giờ làm mỗi cửa hàng tính riêng.',
        confirmLabel: move ? 'Chuyển' : 'Thêm',
        destructive: false);
    if (!ok) return;
    setState(() => _cloudBusy = true);
    try {
      final data = await cloudSync.fetchStoreData(target);
      if (data == null) {
        _snack(
            'Không tải được dữ liệu cửa hàng $target. Kiểm tra mạng rồi thử lại.');
        return;
      }
      if (!move) {
        // Gán thêm: chỉ thêm nhân viên vào cửa hàng đích, không đụng
        // tới ca làm ở cửa hàng hiện tại.
        if (!data.addEmployee(Employee(emp.name, emp.rate,
            annualLeaveAllowance: emp.annualLeaveAllowance))) {
          _snack('Cửa hàng $target đã có nhân viên ${emp.name}.');
          return;
        }
        await cloudSync.uploadStoreData(target, data);
        _snack('Đã gán ${emp.name} thêm vào cửa hàng $target.');
        return;
      }
      // Chuyển hẳn: chuyển trên bản sao trước, chỉ xóa ở cửa hàng
      // hiện tại sau khi đã đẩy được lên cửa hàng đích, để lỗi giữa
      // chừng không mất người.
      final copy = AppData.fromJson(_s.data.toJson());
      if (!copy.moveEmployeeTo(data, emp.name)) {
        _snack(
            'Cửa hàng $target đã có nhân viên ${emp.name}. Đổi tên trước rồi chuyển lại.');
        return;
      }
      await cloudSync.uploadStoreData(target, data);
      setState(() {
        _s.data.employees.removeWhere((e) => e.name == emp.name);
        _s.data.shifts.remove(emp.name);
        if (_employee == emp.name && _s.data.employees.isNotEmpty) {
          _employee = _s.data.employees.first.name;
        }
      });
      await _save();
      _snack('Đã chuyển ${emp.name} sang cửa hàng $target.');
    } on StateError catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack(move ? 'Chuyển cửa hàng lỗi: $e' : 'Gán cửa hàng lỗi: $e');
    } finally {
      if (mounted) setState(() => _cloudBusy = false);
    }
  }

  Future<void> _removeEmployee(Employee emp) async {
    if (_s.data.employees.length <= 1) {
      _snack('Phải còn ít nhất 1 nhân viên.');
      return;
    }
    final ok = await _confirm(
        'Xóa nhân viên', 'Xóa ${emp.name} cùng toàn bộ ca làm của người này?');
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
        // Nhân viên + đang ẩn tiền: PDF bỏ cột giờ công/tăng ca và
        // phần tổng kết tiền công; chủ/admin xuất đầy đủ như cũ.
        hideSensitive: _payHidden,
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
        _employee =
            _s.data.employees.isNotEmpty ? _s.data.employees.first.name : null;
        _tab = 0;
      });
      _snack('Đã khôi phục dữ liệu từ file sao lưu.');
    } catch (e) {
      _snack('Khôi phục lỗi: file không đúng định dạng sao lưu Gio-Lam. ($e)');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Chưa nhập mã PIN (Firebase bật mà chưa có tài khoản):
    // hiện màn hình nhập PIN thay cho các tab.
    if (_showCloudLogin) {
      return Scaffold(body: SafeArea(child: _cloudLoginScreen()));
    }
    final items = <BottomNavigationBarItem>[
      const BottomNavigationBarItem(
          icon: Icon(Icons.access_time_filled), label: 'Chấm công'),
      const BottomNavigationBarItem(
          icon: Icon(Icons.description), label: 'Báo cáo'),
      if (_isOwner)
        const BottomNavigationBarItem(
            icon: Icon(Icons.settings), label: 'Cài đặt'),
    ];
    final pages = <Widget>[
      _attendanceTab(),
      _reportTab(),
      if (_isOwner) _settingsTab(),
    ];
    // Phím tắt Ctrl+H mở đăng nhập chủ cửa hàng (không có nút hiện ngoài).
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.keyH, control: true): _OwnerIntent(),
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
    final todaySegments =
        _employee == null ? <Shift>[] : data.shiftsOn(_employee!, _todayStr);
    final todayClosed = todaySegments.where((s) => s.clockOut != null).toList();
    final todayTotal =
        _employee == null ? 0 : data.dayTotalMinutes(_employee!, _todayStr);
    final weekday =
        ['CN', 'T2', 'T3', 'T4', 'T5', 'T6', 'T7'][_now.weekday % 7];
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
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const IconTile(icon: Icons.work, tint: _teal),
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
              if (_role != 'employee') ...[
                _roleBadge(),
                const SizedBox(width: 6),
              ],
              _pulsingInfoButton(),
            ]),
            _storePicker(),
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
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: data.employees.map((e) {
                  final selected = e.name == _employee;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(_employeeChipLabel(e)),
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
                  icon: Icons.play_circle_fill,
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
                  icon: Icons.stop_circle,
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
                  icon: Icons.edit_note,
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
                  icon: Icons.edit_note,
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
                icon: Icons.calendar_month, title: 'Bảng công tháng'),
            const SizedBox(height: 8),
            MonthSwitcher(
              monthLabel: 'Tháng ${_month.month}/${_month.year}',
              onPrev: () => setState(
                  () => _month = DateTime(_month.year, _month.month - 1)),
              onNext: () => setState(
                  () => _month = DateTime(_month.year, _month.month + 1)),
            ),
            const SizedBox(height: 16),
            const AppSectionHeader(icon: Icons.bar_chart, title: 'Tổng quan'),
            const SizedBox(height: 8),
            GradientSummaryCard(metrics: [
              MetricData(
                  icon: Icons.calendar_month,
                  value: '${monthTotal.days}',
                  title: 'Ngày làm'),
              MetricData(
                  icon: Icons.access_time_filled,
                  value: fmtDuration(monthTotal.minutes),
                  title: 'Tổng giờ'),
              MetricData(
                  icon: Icons.bolt,
                  value: fmtDuration(monthOvertime),
                  title: 'Tăng ca'),
            ]),
            if (emp != null && !_payHidden) ...[
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
    final rows = emp == null
        ? <Shift>[]
        : data.monthShifts(emp.name, _month.year, _month.month);
    final overtime = emp == null
        ? 0
        : data.monthOvertime(emp.name, _month.year, _month.month);

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 48, 20, 24),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
                    label: Text(_employeeChipLabel(e)),
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
          const AppSectionHeader(icon: Icons.bar_chart, title: 'Tổng hợp'),
          const SizedBox(height: 8),
          GradientSummaryCard(metrics: [
            MetricData(
                icon: Icons.calendar_month,
                value: '${total.days}',
                title: 'Ngày làm'),
            MetricData(
                icon: Icons.access_time_filled,
                value: fmtDuration(total.minutes),
                title: 'Tổng giờ'),
            MetricData(
                icon: Icons.bolt,
                value: fmtDuration(overtime),
                title: 'Tăng ca'),
          ]),
          if (emp != null && !_payHidden) ...[
            const SizedBox(height: 12),
            _salaryCard(data, emp, total.minutes),
          ],
          const SizedBox(height: 20),
          const AppSectionHeader(
              icon: Icons.description, title: 'Xuất báo cáo'),
          const SizedBox(height: 8),
          _card(
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                IconTile(icon: Icons.description, tint: _accent),
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
                  icon: Icons.description,
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
                    icon: Icons.list, title: 'Dữ liệu trong báo cáo')),
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              onPressed: emp == null ? null : () => _showEntryEditor(),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.add_circle, size: 16),
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
            'Bấm vào ca trong danh sách để sửa (ngày đã qua chỉ chủ cửa hàng mới sửa được, trừ ca qua đêm vừa kết thúc sáng nay).',
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
          child: CupertinoTextField(
              style: const TextStyle(color: _ink),
              controller: ctrl,
              autofocus: true),
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
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Cài đặt',
              style: TextStyle(
                  fontSize: 34, fontWeight: FontWeight.bold, color: _ink)),
          const SizedBox(height: 4),
          const Text('Chỉ chủ cửa hàng mới xem và sửa được mục này.',
              style: TextStyle(color: _muted, fontSize: 14)),
          const SizedBox(height: 20),
          const AppSectionHeader(icon: Icons.work, title: 'Thông tin cửa hàng'),
          const SizedBox(height: 8),
          AppCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: const IconTile(icon: Icons.work, tint: _teal),
              title: const Text('Tên cửa hàng'),
              subtitle: Text(data.storeName,
                  style: const TextStyle(
                      color: _ink, fontWeight: FontWeight.w600)),
              trailing:
                  const Icon(Icons.chevron_right, size: 16, color: _muted),
              onTap: _editStoreName,
            ),
          ),
          const SizedBox(height: 20),
          const AppSectionHeader(icon: Icons.store, title: 'Cửa hàng'),
          const SizedBox(height: 8),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              if (!cloudSync.available) ...[
                const ListTile(
                  leading: IconTile(icon: Icons.cloud_off, tint: _muted),
                  title: Text('Chưa đăng nhập đồng bộ'),
                  subtitle: Text(
                      'Nhập mã PIN để đồng bộ rồi mới thêm/xóa cửa hàng được.'),
                ),
              ] else ...[
                for (final id in cloudSync.storeIds) ...[
                  ListTile(
                    leading: const IconTile(icon: Icons.store, tint: _teal),
                    title: Text(id,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, color: _ink)),
                    subtitle: Text(id == data.storeName
                        ? 'Đang xem cửa hàng này'
                        : 'Bấm để xem cửa hàng này'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        icon: const Icon(Icons.visibility, size: 18),
                        tooltip: 'Xem mã PIN',
                        onPressed: _cloudBusy ? null : () => _showStorePin(id),
                      ),
                      IconButton(
                        icon: const Icon(Icons.key, size: 18),
                        tooltip: 'Đổi mã PIN',
                        onPressed:
                            _cloudBusy ? null : () => _changeStorePin(id),
                      ),
                      IconButton(
                        icon:
                            const Icon(Icons.delete, size: 18, color: _danger),
                        onPressed: _cloudBusy ? null : () => _deleteStore(id),
                      ),
                    ]),
                    onTap: _cloudBusy ? null : () => _switchStore(id),
                  ),
                  const Divider(height: 1, color: _line),
                ],
                ListTile(
                  leading:
                      const IconTile(icon: Icons.add_circle, tint: _accent),
                  title: const Text('Thêm cửa hàng',
                      style: TextStyle(color: _accentDark)),
                  subtitle: const Text(
                      'Đặt tên + mã PIN, rồi gửi bộ cài app cho cửa hàng đó'),
                  onTap: _cloudBusy ? null : _addStore,
                ),
              ],
            ]),
          ),
          const SizedBox(height: 20),
          const AppSectionHeader(icon: Icons.palette, title: 'Giao diện'),
          const SizedBox(height: 8),
          _card(
            Column(children: [
              Row(children: [
                const IconTile(icon: Icons.text_fields, tint: _accent),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('Font chữ',
                      style: TextStyle(fontSize: 15, color: _ink)),
                ),
                CupertinoSegmentedControl<String>(
                  groupValue: data.fontFamily,
                  onValueChanged: (v) async {
                    setState(() => data.fontFamily = v);
                    await _save();
                    widget.onFontChanged?.call(v);
                  },
                  children: const {
                    'Lexend': Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('Lexend')),
                    'System': Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('Mặc định')),
                  },
                ),
              ]),
              const SizedBox(height: 8),
              const Text(
                'Lexend là font mới, rõ và hiện đại; "Mặc định" dùng font hệ thống của máy.',
                style: TextStyle(color: _muted, fontSize: 12),
              ),
            ]),
          ),
          const SizedBox(height: 20),
          const AppSectionHeader(icon: Icons.group, title: 'Nhân viên'),
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
                  leading:
                      const IconTile(icon: Icons.add_circle, tint: _accent),
                  title: const Text('Thêm nhân viên',
                      style: TextStyle(color: _accentDark)),
                  onTap: _addEmployee,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const AppSectionHeader(
              icon: Icons.access_time_filled, title: 'Giờ làm'),
          const SizedBox(height: 8),
          _card(
            Column(children: [
              Row(children: [
                const IconTile(icon: Icons.access_time_filled, tint: _accent),
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
                          setState(() => data.standardMinutesPerDay -= 30);
                          await _save();
                        },
                  child: const Icon(Icons.remove_circle, color: _accent),
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
                          setState(() => data.standardMinutesPerDay += 30);
                          await _save();
                        },
                  child: const Icon(Icons.add_circle, color: _accent),
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
          const AppSectionHeader(icon: Icons.paid, title: 'Lương'),
          const SizedBox(height: 8),
          _card(
            Column(children: [
              Row(children: [
                const IconTile(icon: Icons.paid, tint: _teal),
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
          const AppSectionHeader(icon: Icons.archive, title: 'Sao lưu dữ liệu'),
          const SizedBox(height: 8),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              ListTile(
                leading: const IconTile(icon: Icons.upload, tint: iosBlue),
                title: const Text('Xuất sao lưu (.json)'),
                subtitle:
                    const Text('Lưu toàn bộ dữ liệu + cài đặt ra file JSON'),
                trailing:
                    const Icon(Icons.chevron_right, size: 16, color: _muted),
                onTap: _exportBackup,
              ),
              const Divider(height: 1, color: _line),
              ListTile(
                leading: const IconTile(icon: Icons.download, tint: iosBlue),
                title: const Text('Khôi phục từ file'),
                subtitle:
                    const Text('Thay thế dữ liệu hiện tại bằng file sao lưu'),
                trailing:
                    const Icon(Icons.chevron_right, size: 16, color: _muted),
                onTap: _importBackup,
              ),
            ]),
          ),
          const SizedBox(height: 20),
          const AppSectionHeader(icon: Icons.cloud, title: 'Đồng bộ cloud'),
          const SizedBox(height: 8),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              ListTile(
                leading: const IconTile(icon: Icons.cloud, tint: _accent),
                // Dòng vai trò/quyền ("admin (xem được hết)") chỉ hiện
                // khi admin đăng nhập — chủ cửa hàng không thấy, để
                // chủ tưởng mình là cao nhất.
                title: Text(cloudSync.signedIn
                    ? _isAdmin
                        ? 'Đã vào bằng mã PIN: admin (xem được hết)'
                        : 'Đã vào bằng mã PIN'
                    : cloudSync.firebaseReady
                        ? 'Chưa nhập mã PIN'
                        : 'Chưa bật đồng bộ (mất mạng hoặc chưa cấu hình)'),
                subtitle: Text(cloudSync.signedIn
                    ? _isAdmin
                        ? 'Quyền: admin · xem được hết các cửa hàng'
                        : 'Đã đăng nhập đồng bộ.'
                    : 'Dữ liệu vẫn lưu local trên máy, có mạng nhập mã PIN lại để đồng bộ.'),
              ),
              if (cloudSync.lastSyncTime != null) ...[
                const Divider(height: 1, color: _line),
                ListTile(
                  leading: const IconTile(icon: Icons.sync, tint: _teal),
                  title: const Text('Đồng bộ lần cuối'),
                  subtitle: Text(
                      '${cloudSync.lastSyncTime!.day}/${cloudSync.lastSyncTime!.month}/${cloudSync.lastSyncTime!.year} ${cloudSync.lastSyncTime!.hour.toString().padLeft(2, '0')}:${cloudSync.lastSyncTime!.minute.toString().padLeft(2, '0')}'),
                ),
              ],
              const Divider(height: 1, color: _line),
              ListTile(
                leading: const IconTile(icon: Icons.sync, tint: _accent),
                title: const Text('Đồng bộ ngay'),
                subtitle: const Text(
                    'Tải về nếu cloud mới hơn, không thì đẩy dữ liệu local lên'),
                trailing: _cloudBusy
                    ? const CupertinoActivityIndicator()
                    : const Icon(Icons.chevron_right, size: 16, color: _muted),
                onTap: _cloudBusy ? null : _syncNow,
              ),
              if (cloudSync.signedIn) ...[
                const Divider(height: 1, color: _line),
                ListTile(
                  leading: const IconTile(icon: Icons.logout, tint: _danger),
                  title: const Text('Đăng xuất (nhập lại mã PIN)',
                      style: TextStyle(color: _danger)),
                  subtitle: const Text('Dữ liệu local trên máy vẫn giữ nguyên'),
                  onTap: _cloudSignOut,
                ),
              ],
            ]),
          ),
          const SizedBox(height: 20),
          const AppSectionHeader(icon: Icons.info, title: 'Giới thiệu'),
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
          const AppSectionHeader(icon: Icons.help, title: 'Hỗ trợ'),
          const SizedBox(height: 8),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              ListTile(
                leading: const IconTile(icon: Icons.menu_book, tint: iosBlue),
                title: const Text('Hướng dẫn sử dụng'),
                trailing:
                    const Icon(Icons.chevron_right, size: 16, color: _muted),
                onTap: _showGuideDialog,
              ),
            ]),
          ),
          const SizedBox(height: 20),
          const AppSectionHeader(icon: Icons.lock, title: 'Chủ cửa hàng'),
          const SizedBox(height: 8),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              ListTile(
                leading: const IconTile(icon: Icons.lock, tint: _accent),
                title: const Text('Đổi mật khẩu chủ'),
                trailing:
                    const Icon(Icons.chevron_right, size: 16, color: _muted),
                onTap: _changeOwnerPassword,
              ),
              const Divider(height: 1, color: _line),
              ListTile(
                leading: const IconTile(icon: Icons.lock_open, tint: _danger),
                title: Text(
                    _isAdmin
                        ? 'Thoát chế độ admin'
                        : 'Thoát chế độ chủ cửa hàng',
                    style: const TextStyle(color: _danger)),
                onTap: _ownerLogin,
              ),
            ]),
          ),
          // --- Mục Quản trị (admin) ---
          // Chưa có mật khẩu tổng: chủ đặt mật khẩu tổng ở đây.
          // Đã có mật khẩu tổng: mục này CHỈ hiện ở chế độ admin.
          if (!_s.hasMasterPassword) ...[
            const SizedBox(height: 20),
            const AppSectionHeader(
                icon: Icons.admin_panel_settings, title: 'Quản trị'),
            const SizedBox(height: 8),
            AppCard(
              padding: EdgeInsets.zero,
              child: ListTile(
                leading: const IconTile(
                    icon: Icons.admin_panel_settings, tint: _accent),
                title: const Text('Đặt mật khẩu tổng'),
                subtitle: const Text(
                    'Mật khẩu quyền cao nhất, luôn vào được dù mật khẩu chủ đã đổi'),
                trailing:
                    const Icon(Icons.chevron_right, size: 16, color: _muted),
                onTap: _setMasterPassword,
              ),
            ),
          ],
          if (_isAdmin && _s.hasMasterPassword) ...[
            const SizedBox(height: 20),
            const AppSectionHeader(
                icon: Icons.admin_panel_settings, title: 'Quản trị'),
            const SizedBox(height: 8),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                ListTile(
                  leading: const IconTile(
                      icon: Icons.admin_panel_settings, tint: _accent),
                  title: const Text('Đổi mật khẩu tổng'),
                  trailing:
                      const Icon(Icons.chevron_right, size: 16, color: _muted),
                  onTap: _changeMasterPassword,
                ),
                const Divider(height: 1, color: _line),
                ListTile(
                  leading:
                      const IconTile(icon: Icons.lock_reset, tint: _accent),
                  title: const Text('Đặt lại mật khẩu chủ'),
                  subtitle: const Text('Không cần biết mật khẩu chủ cũ'),
                  trailing:
                      const Icon(Icons.chevron_right, size: 16, color: _muted),
                  onTap: _resetOwnerPassword,
                ),
                const Divider(height: 1, color: _line),
                ListTile(
                  leading: const IconTile(icon: Icons.pin, tint: _accent),
                  title: const Text('Đặt/đổi mã PIN chủ'),
                  subtitle:
                      const Text('Mã PIN đăng nhập cloud của chủ cửa hàng'),
                  trailing:
                      const Icon(Icons.chevron_right, size: 16, color: _muted),
                  onTap: _cloudBusy ? null : () => _setRolePin('owner'),
                ),
                const Divider(height: 1, color: _line),
                ListTile(
                  leading: const IconTile(icon: Icons.pin, tint: _accent),
                  title: const Text('Đổi mã PIN admin'),
                  subtitle:
                      const Text('Đổi xong phải đăng nhập lại bằng mã PIN mới'),
                  trailing:
                      const Icon(Icons.chevron_right, size: 16, color: _muted),
                  onTap: _cloudBusy ? null : () => _setRolePin('admin'),
                ),
                const Divider(height: 1, color: _line),
                const ListTile(
                  leading: IconTile(icon: Icons.info, tint: _muted),
                  title: Text(
                      'Mã PIN cloud khác mật khẩu tổng local (Ctrl+H): PIN để vào app + đồng bộ, mật khẩu tổng để mở chế độ admin trên máy này kể cả khi mất mạng.'),
                  subtitle: Text(
                      'Đổi mã PIN cửa hàng chưa có ở bản này — chủ tạo lại cửa hàng mới rồi xóa cửa hàng cũ nếu cần đổi PIN.'),
                ),
                const Divider(height: 1, color: _line),
                ListTile(
                  leading:
                      const IconTile(icon: Icons.visibility_off, tint: _accent),
                  title: const Text('Ẩn tiền công với nhân viên'),
                  subtitle: const Text(
                      'Nhân viên chỉ thấy giờ làm, không thấy tiền công và đơn giá giờ'),
                  trailing: Switch(
                    value: data.hidePay,
                    activeThumbColor: _accent,
                    onChanged: (v) async {
                      setState(() => data.hidePay = v);
                      await _save();
                    },
                  ),
                ),
              ]),
            ),
          ],
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
        const IconTile(icon: Icons.paid, tint: _teal),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Tiền công tháng',
                style: TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w600, color: _ink)),
            const SizedBox(height: 3),
            Text('Theo ${emp.rate} ${data.currency}/giờ',
                style: const TextStyle(color: _muted, fontSize: 13)),
          ]),
        ),
        Text('${pay.toStringAsFixed(0)} ${data.currency}',
            style: const TextStyle(
                fontSize: 17, fontWeight: FontWeight.bold, color: _accentDark)),
      ]),
    );
  }

  Widget _card(Widget child) => AppCard(child: child);

  Widget _employeeRow(Employee e) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: _accent.withValues(alpha: 0.12),
        child: Text(e.name.isEmpty ? '?' : e.name[0].toUpperCase(),
            style:
                const TextStyle(color: _accent, fontWeight: FontWeight.bold)),
      ),
      title: Text(e.name,
          style: const TextStyle(fontWeight: FontWeight.w600, color: _ink)),
      subtitle: Text(
          '${e.rate} ${_s.data.currency}/giờ'
          '${e.annualLeaveAllowance > 0 ? ' · phép còn ${e.annualLeaveAllowance - _s.data.yearPaidLeaveUsed(e.name, DateTime.now().year)} ngày' : ''}',
          style: const TextStyle(color: _muted, fontSize: 13)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (cloudSync.canPickStore &&
            {...cloudSync.storeIds, _s.data.storeName}.length > 1)
          IconButton(
            icon: const Icon(Icons.swap_horiz, size: 18),
            tooltip: 'Gán / chuyển cửa hàng',
            onPressed: () => _employeeStoreAction(e),
          ),
        IconButton(
          icon: const Icon(Icons.edit, size: 18),
          onPressed: () => _editEmployee(e),
        ),
        IconButton(
          icon: const Icon(Icons.delete, size: 18, color: _danger),
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
                Icon(Icons.edit, size: 10, color: _amber),
                SizedBox(width: 3),
                Text('Đã sửa', style: TextStyle(fontSize: 11, color: _amber)),
              ]),
            ],
          ]),
        ]),
      ),
    );
  }
}
