# Gio-Lam — App chấm công (Flutter, Windows)

App chấm công cho máy tính, thay bản Python tkinter (bản đó mở lên là tắt luôn
cmd vì máy không có Python/tkinter).

## Giao diện

App có 3 tab kiểu iOS ở thanh dưới cùng: **Chấm công** (bấm giờ trực tiếp,
đồng hồ đếm giờ), **Báo cáo** (tổng hợp tháng + xuất PDF), **Cài đặt**
— tab Cài đặt chỉ hiện khi chủ cửa hàng đăng nhập bằng mật khẩu (bấm nút
khóa "Chủ cửa hàng" ở đầu tab Chấm công). Nhân viên không thấy nút Cài đặt.

## Tính năng

- **Vào ca / Tan ca**: bấm nút, app ghi giờ máy tính.
- **Nhập tay trong ngày**: nhân viên đến trước khi bật máy thì nhập tay giờ
  vào/ra, giờ nhập tay được ghi chú rõ "nhập tay".
- **Ca đêm 20:00 → 05:00**: tính 9h00, tính vào ngày bắt đầu ca. Sáng hôm sau
  bấm Tan ca là đóng ca hôm qua.
- **Ngày đã qua không sửa được**: nhân viên không sửa được ca ngày cũ; chỉ
  chủ cửa hàng (bấm "Chủ cửa hàng", nhập mật khẩu đặt ở lần đầu) mới sửa.
- **Tổng tháng + tiền công**: theo từng nhân viên, giá giờ riêng
  (mặc định cửa hàng Rybna: Hieu 160/giờ, Hoan 170/giờ).
- **Xuất PDF tháng**: nút "Xuất PDF" xuất báo cáo tháng của nhân viên đang
  chọn theo mẫu của app iOS ChamCongHieuIT — tiêu đề "BẢNG CHẤM CÔNG",
  bảng Ngày/Thứ/Vào/Ra/Giờ công/Tăng ca (tăng ca tính theo ngày, vượt 8h),
  tổng kết + tiền công. File lưu vào thư mục Documents rồi tự mở lên.
- Dữ liệu lưu trong file `gio-lam.json` ở thư mục Documents của máy.

## Chạy / build trên máy Windows

Cần cài Flutter SDK trước (https://docs.flutter.dev/get-started/install/windows),
rồi trong thư mục này:

```bat
flutter pub get
flutter run -d windows
```

Build file .exe để dùng, không cần mở cmd:

```bat
flutter build windows --release
```

File chạy nằm ở `build\windows\x64\runner\Release\gio_lam.exe` — copy cả thư
mục `Release` đi đâu cũng chạy được, đúp chuột là mở (không cần Python, không
cần cmd).

## Kiểm thử

```bat
flutter test
```

Test kiểm tra: ca đêm 20:00→05:00 = 9h00, chưa tan ca thì không vào ca mới
được, nhập tay ngày cũ bị chặn.
