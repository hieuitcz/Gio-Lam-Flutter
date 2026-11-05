import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'logic.dart';
import 'store.dart';

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
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
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
      _snack(okMsg);
    } on StateError catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('Lỗi: $e');
    }
  }

  Future<String?> _askTime(String title, String hint) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(hintText: hint, labelText: 'Giờ (vd 9:00)'),
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

  Future<String?> _askPassword(String title) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(controller: ctrl, obscureText: true, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('OK')),
        ],
      ),
    );
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

  Future<void> _addEmployee() async {
    final nameCtrl = TextEditingController();
    final rateCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Thêm nhân viên'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Tên')),
          TextField(
              controller: rateCtrl,
              decoration: const InputDecoration(labelText: 'Đơn giá/giờ (vd 160)'),
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
    final total = emp == null ? (days: 0, minutes: 0) : data.monthTotal(emp.name, _month.year, _month.month);
    final rows = emp == null ? <Shift>[] : data.monthShifts(emp.name, _month.year, _month.month);

    return Scaffold(
      appBar: AppBar(
        title: Text('Gio-Lam — ${data.storeName}'),
        actions: [
          TextButton(
            onPressed: _owner,
            child: Text(_ownerMode ? 'Thoát chủ cửa hàng' : 'Chủ cửa hàng',
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('Nhân viên: '),
            DropdownButton<String>(
              value: _employee,
              items: data.employees
                  .map((e) => DropdownMenuItem(value: e.name, child: Text('${e.name} — ${e.rate}/giờ')))
                  .toList(),
              onChanged: (v) => setState(() => _employee = v),
            ),
            const SizedBox(width: 12),
            if (_ownerMode)
              OutlinedButton(onPressed: _addEmployee, child: const Text('Thêm nhân viên')),
          ]),
          const SizedBox(height: 8),
          Text(
            '${_now.day}/${_now.month}/${_now.year}  ${_now.hour.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}:${_now.second.toString().padLeft(2, '0')}',
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            open != null
                ? 'Đang làm từ ${fmtHhmm(open.clockIn!)} ngày ${open.date}'
                    '${open.date != _todayStr ? ' (ca đêm từ hôm qua)' : ''} — bấm Tan ca để về.'
                : todayShift != null && todayShift.clockOut != null
                    ? 'Hôm nay đã tan ca: ${fmtHhmm(todayShift.clockIn!)}–${fmtHhmm(todayShift.clockOut!)} (${fmtDuration(todayShift.total)}).'
                    : 'Chưa vào ca hôm nay.',
            style: const TextStyle(fontSize: 15),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            FilledButton(
              onPressed: open != null || emp == null
                  ? null
                  : () => _act(() async => _s.clockIn(emp.name),
                      'Đã ghi giờ vào lúc ${_now.hour}:${_now.minute.toString().padLeft(2, '0')}.'),
              child: const Text('Vào ca'),
            ),
            FilledButton(
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
              child: const Text('Tan ca'),
            ),
            OutlinedButton(
              onPressed: emp == null
                  ? null
                  : () async {
                      final v = await _askTime('Nhập tay giờ vào', '9:00');
                      if (v != null) {
                        await _act(() async => _s.manualIn(emp.name, v), 'Đã ghi giờ vào (nhập tay).');
                      }
                    },
              child: const Text('Nhập tay giờ vào'),
            ),
            OutlinedButton(
              onPressed: emp == null
                  ? null
                  : () async {
                      final v = await _askTime('Nhập tay giờ ra', '20:00');
                      if (v != null) {
                        await _act(() async => _s.manualOut(emp.name, v), 'Đã ghi giờ ra (nhập tay).');
                      }
                    },
              child: const Text('Nhập tay giờ ra'),
            ),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)),
            ),
            Text('Tháng ${_month.month}/${_month.year}',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: () => setState(() => _month = DateTime(_month.year, _month.month + 1)),
            ),
            const SizedBox(width: 12),
            if (emp != null)
              Text(
                  '${total.days} ngày làm, tổng ${fmtDuration(total.minutes)}, '
                  'tiền công ${(total.minutes / 60 * emp.rate).toStringAsFixed(0)} (giá ${emp.rate}/giờ)',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: rows.length,
              itemBuilder: (ctx, i) {
                final s = rows[i];
                final notes = <String>[];
                if (s.inManual) notes.add('vào: nhập tay');
                if (s.outManual) notes.add('ra: nhập tay');
                if (s.clockOut == null) notes.add('chưa tan ca');
                return ListTile(
                  title: Text(
                      '${s.date}   ${s.clockIn == null ? '' : fmtHhmm(s.clockIn!)} – ${s.clockOut == null ? '' : fmtHhmm(s.clockOut!)}   ${fmtDuration(s.total)}'),
                  subtitle: notes.isEmpty ? null : Text(notes.join(', ')),
                  onTap: () => _editShift(s),
                );
              },
            ),
          ),
          const Text(
            'Nhập tay chỉ được trong đúng ngày hôm đó, giờ nhập tay được ghi chú rõ. '
            'Ngày đã qua chỉ chủ cửa hàng mới sửa được.',
            style: TextStyle(color: Colors.grey),
          ),
        ]),
      ),
    );
  }
}
