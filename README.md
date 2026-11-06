# Gio-Lam — App chấm công (Flutter, Windows)

App chấm công cho máy tính, thay bản Python tkinter (bản đó mở lên là tắt luôn
cmd vì máy không có Python/tkinter).

## Giao diện

App có 3 tab kiểu iOS ở thanh dưới cùng: **Chấm công** (bấm giờ trực tiếp,
đồng hồ đếm giờ), **Báo cáo** (tổng hợp tháng + xuất PDF), **Cài đặt**
— tab Cài đặt chỉ hiện khi chủ cửa hàng hoặc admin đăng nhập bằng mật khẩu
(Ctrl+H, không có nút hiện ra ngoài). Nhân viên không thấy tab Cài đặt.

## Vai trò (nhân viên / chủ / admin)

- **Nhân viên** (mặc định khi mở app, không cần PIN): chỉ thấy giờ làm của
  mình (giờ vào/ra, tổng giờ, tăng ca). Không thấy tiền công, đơn giá giờ,
  không thấy giờ của người khác. Xuất PDF được nhưng PDF của nhân viên bỏ
  cột "Giờ công"/"Tăng ca" và phần tổng kết tiền công (khi đang bật ẩn tiền).
- **Chủ cửa hàng** (tài khoản quản lý): thấy đầy đủ app — tất cả nhân viên,
  tiền công, cài đặt, sửa ngày đã qua. Đổi được mật khẩu chủ của mình.
- **Admin** (quyền cao nhất): đầy đủ như chủ, cộng thêm mục **Quản trị**
  trong Cài đặt: đặt/đổi mật khẩu tổng, đặt lại mật khẩu chủ, công tắc
  "Ẩn tiền công với nhân viên" (mặc định bật). Đăng nhập bằng mật khẩu tổng
  (Ctrl+H) thì luôn vào được, kể cả khi mật khẩu chủ đã bị đổi. Mật khẩu
  tổng lưu SHA-256 trong file riêng `gio-lam.json.master` bên cạnh file dữ
  liệu, không nằm trong JSON đã ký nên khôi phục dữ liệu cũng không mất.
  Huy hiệu "CHỦ" (indigo) / "ADMIN" (teal) hiện ở đầu tab Chấm công.

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
