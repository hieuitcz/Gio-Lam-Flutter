import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import 'logic.dart';
import 'report_pdf.dart';
import 'store.dart';

// Bảng màu kiểu app chấm công iOS: nền sáng, thẻ trắng bo tròn, 1 màu chủ đạo.
const _ink = Color(0xFF0F172A);
const _muted = Color(0xFF64748B);
const _line = Color(0xFFE2E8F0);
const _bg = Color(0xFFF1F5F9);
const _accent = Color(0xFF0D9488);
const _accentDark = Color(0xFF0F766E);
const _danger = Color(0xFFDC2626);
const _amber = Color(0xFFB45309);
const _amberBg = Color(0xFFFEF3C7);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await getApplicationDocumentsDirectory();
  final store = DataStore(File('${dir.path}/gio-lam.json'));
  await store.load();
  runApp(GioLamApp(store: store));
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

  @override
  void initState() {
    super.initState();
    _employee = widget.store.data.employees.isNotEmpty
        ? widget.store.data.employees.first.name
        : null;
    _tick();
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
    final mins = nowMin - open.clockIn!;
    return fmtDuration(mins);
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

  Future<String?> _askTime(String title, String initial) async {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'vd 9:00',
            labelText: 'Giờ',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.datetime,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Ghi')),
        ],
      ),
    );
  }

  Future<String?> _askPassword(String title) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _owner() async {
    if (_ownerMode) {
      setState(() => _ownerMode = false);
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
      setState(() => _ownerMode = true);
      _snack('Đã vào chế độ chủ cửa hàng.');
    } else if (pw != null) {
      _snack('Mật khẩu không đúng.');
    }
  }

  Future<void> _editShift(Shift shift) async {
    if (!_ownerMode) {
      _snack('Ngày đã qua chỉ chủ cửa hàng mới sửa được. Bấm "Chủ cửa hàng" rồi nhập mật khẩu.');
      return;
    }
    final ci = await _askTime('Sửa giờ vào', shift.clockIn == null ? '' : fmtHhmm(shift.clockIn!));
    if (ci == null) return;
    final co = await _askTime('Sửa giờ ra', shift.clockOut == null ? '' : fmtHhmm(shift.clockOut!));
    if (co == null) return;
    await _act(() async {
      _s.ownerSetShift(_employee!, shift.date, ci.isEmpty ? null : ci, co.isEmpty ? null : co);
    }, 'Đã cập nhật ca.');
  }

  Future<void> _exportPdf() async {
    final emp = widget.store.data.employees
        .where((e) => e.name == _employee)
        .firstOrNull;
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
      _snack('Đã xuất PDF: ${file.path}');
      await OpenFilex.open(file.path);
    } catch (e) {
      _snack('Xuất PDF lỗi: $e');
    }
  }

  Future<void> _addEmployee() async {
    final nameCtrl = TextEditingController();
    final rateCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Thêm nhân viên'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                  labelText: 'Tên', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(
              controller: rateCtrl,
              decoration: const InputDecoration(
                  labelText: 'Đơn giá/giờ (vd 160)', border: OutlineInputBorder()),
              keyboardType: TextInputType.number),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Thêm')),
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

  @override
  Widget build(BuildContext context) {
    final data = _s.data;
    final emp = data.employees.where((e) => e.name == _employee).firstOrNull;
    final open = _employee == null ? null : data.openShift(_employee!);
    final todayShift = _employee == null ? null : data.shiftOn(_employee!, _todayStr);
    final total = emp == null
        ? (days: 0, minutes: 0)
        : data.monthTotal(emp.name, _month.year, _month.month);
    final rows = emp == null ? <Shift>[] : data.monthShifts(emp.name, _month.year, _month.month);
    final weekday = ['CN', 'T2', 'T3', 'T4', 'T5', 'T6', 'T7'][_now.weekday % 7];

    return Scaffold(
      body: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // --- Header đậm, kiểu iOS ---
          Container(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
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
                TextButton(
                  onPressed: _owner,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.white.withValues(alpha: 0.14),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  ),
                  child: Text(
                      _ownerMode ? 'Thoát chủ cửa hàng' : 'Chủ cửa hàng',
                      style: const TextStyle(fontSize: 12)),
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
                  child: Text('giờ hiện tại',
                      style: TextStyle(color: Colors.white60, fontSize: 13)),
                ),
              ]),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // --- Chọn nhân viên ---
              Row(children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: data.employees.map((e) {
                        final selected = e.name == _employee;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text('${e.name} · ${e.rate}/giờ'),
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
                ),
                if (_ownerMode)
                  IconButton(
                    onPressed: _addEmployee,
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                    tooltip: 'Thêm nhân viên',
                  ),
              ]),
              const SizedBox(height: 16),
              // --- Thẻ trạng thái ca ---
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
                            todayShift != null && todayShift.clockOut != null
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
                          todayShift != null && todayShift.clockOut != null
                              ? '${fmtHhmm(todayShift.clockIn!)} – ${fmtHhmm(todayShift.clockOut!)}'
                              : '--:--',
                          style: const TextStyle(
                              fontSize: 40, fontWeight: FontWeight.w200, color: _ink),
                        ),
                        Text(
                          todayShift != null && todayShift.clockOut != null
                              ? 'Hôm nay làm ${fmtDuration(todayShift.total)}'
                              : 'Bấm Vào ca để bắt đầu tính giờ.',
                          style: const TextStyle(color: _muted, fontSize: 14),
                        ),
                      ]),
              ),
              const SizedBox(height: 14),
              // --- Nút bấm giờ ---
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
              const SizedBox(height: 24),
              // --- Tổng tháng ---
              Row(children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left_rounded),
                  onPressed: () =>
                      setState(() => _month = DateTime(_month.year, _month.month - 1)),
                ),
                Text('Tháng ${_month.month}/${_month.year}',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold, color: _ink)),
                IconButton(
                  icon: const Icon(Icons.chevron_right_rounded),
                  onPressed: () =>
                      setState(() => _month = DateTime(_month.year, _month.month + 1)),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: emp == null ? null : _exportPdf,
                  icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                  label: const Text('Xuất PDF'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _ink,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                _statCard('${total.days}', 'ngày làm'),
                const SizedBox(width: 10),
                _statCard(fmtDuration(total.minutes), 'tổng giờ'),
                const SizedBox(width: 10),
                _statCard(
                  emp == null
                      ? '0'
                      : (total.minutes / 60 * emp.rate).toStringAsFixed(0),
                  'tiền công',
                  highlight: true,
                ),
              ]),
              const SizedBox(height: 20),
              const Text('Lịch sử chấm công',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold, color: _ink)),
              const SizedBox(height: 8),
              if (rows.isEmpty)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _line),
                  ),
                  child: const Text('Tháng này chưa có ca làm nào.',
                      style: TextStyle(color: _muted)),
                )
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
              const SizedBox(height: 16),
              const Text(
                'Nhập tay chỉ được trong đúng ngày hôm đó, giờ nhập tay được ghi chú rõ. '
                'Ngày đã qua chỉ chủ cửa hàng mới sửa được (bấm vào ca trong lịch sử).',
                style: TextStyle(color: _muted, fontSize: 12),
              ),
            ]),
          ),
        ]),
      ),
    );
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

  Widget _shiftRow(Shift s) {
    final d = DateTime.parse(s.date);
    final notes = <String>[];
    if (s.inManual) notes.add('vào: nhập tay');
    if (s.outManual) notes.add('ra: nhập tay');
    if (s.clockOut == null) notes.add('chưa tan ca');
    return InkWell(
      onTap: () => _editShift(s),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: s.clockOut == null ? _amberBg : _accent.withValues(alpha: 0.12),
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
                notes.isEmpty ? 'Ca làm bình thường' : notes.join(' · '),
                style: const TextStyle(color: _muted, fontSize: 12),
              ),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(
              '${s.clockIn == null ? '--:--' : fmtHhmm(s.clockIn!)} – ${s.clockOut == null ? '--:--' : fmtHhmm(s.clockOut!)}',
              style: const TextStyle(
                  fontWeight: FontWeight.w600, color: _ink, fontSize: 13),
            ),
            const SizedBox(height: 2),
            Text(fmtDuration(s.total),
                style: const TextStyle(color: _accentDark, fontSize: 13)),
          ]),
        ]),
      ),
    );
  }
}
