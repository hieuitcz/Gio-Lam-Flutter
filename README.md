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

## Đồng bộ cloud (Firebase)

App đồng bộ dữ liệu chấm công lên cloud để máy ở cửa hàng, máy chủ
cửa hàng và máy admin tổng đều thấy số liệu mới nhất. Project Firebase
là **gio-lam** (gói miễn phí Spark). Dữ liệu local (JSON + ký HMAC)
vẫn là nguồn chính khi offline: mất mạng vẫn chấm công bình thường, có
mạng lại tự đẩy lên; mở app thì tải bản mới nhất trên cloud về nếu có.

- **Luật xem**: mỗi cửa hàng chỉ hiện cửa hàng của mình. Chủ cửa hàng
  (quản lý) và admin tổng đăng nhập cloud xong thì có ô chọn cửa hàng
  ở đầu tab Chấm công, xem được hết các cửa hàng.
- **Cách đồng bộ**: mỗi cửa hàng là 1 doc trong collection `stores`
  (doc id = tên cửa hàng, vd `Rybna`), chứa toàn bộ dữ liệu + mốc
  `updatedAt`. Lưu local xong app tự đẩy lên cloud (chạy nền, lỗi mạng
  thì lần sau đẩy lại). Mở app hoặc bấm "Đồng bộ ngay" trong Cài đặt:
  tải về nếu bản cloud mới hơn mốc đã đồng bộ, không thì đẩy local lên.
  Mốc đồng bộ lưu trong chính file JSON local (`cloudUpdatedAt`) nên
  không tải đè lên giờ công nhập offline chưa kịp đẩy.

### Admin làm 1 lần trên Firebase Console (console.firebase.google.com)

1. **Firestore**: vào Build > Firestore Database, tạo database nếu chưa
   có. Vào Firestore > Rules, dán toàn bộ file `firestore.rules` trong
   repo này rồi bấm Publish.
2. **Tài khoản đăng nhập**: vào Build > Authentication > Users > Add
   user, tạo 1 tài khoản (email + mật khẩu) cho mỗi cửa hàng, cộng 1
   tài khoản admin. Mật khẩu này là mật khẩu đăng nhập đồng bộ trên app,
   khác với mật khẩu chủ / mật khẩu tổng bấm Ctrl+H trong app.
3. **Quyền xem**: vào Firestore > Data, tạo collection `users`, thêm 1
   doc cho mỗi tài khoản — doc id = UID của tài khoản đó (xem trong
   Authentication > Users, bấm vào tài khoản để copy UID), field:
   `storeId` (tên cửa hàng, vd `Rybna`; tài khoản admin/chủ xem hết thì
   ghi `*`) và `role` (`store` cho máy cửa hàng, `owner` cho chủ cửa
   hàng, `admin` cho admin tổng).
4. Mỗi máy mở app lần đầu: nhập email + mật khẩu đồng bộ của máy đó.
   Máy cửa hàng tự nhận đúng cửa hàng của tài khoản; máy admin/chủ thì
   chọn cửa hàng ở ô phía trên tab Chấm công. Chưa có doc `users/{uid}`
   thì tài khoản đó không đồng bộ được (app vẫn chạy offline) — admin
   tạo doc xong thì đăng xuất rồi đăng nhập lại trên máy đó.

## Kiểm thử

```bat
flutter test
```

Test kiểm tra: ca đêm 20:00→05:00 = 9h00, chưa tan ca thì không vào ca mới
được, nhập tay ngày cũ bị chặn.
