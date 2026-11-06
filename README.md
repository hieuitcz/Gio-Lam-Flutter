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

Bộ cài đặt: cài Inno Setup 6 rồi chạy `iscc installer.iss` trong thư mục
repo — file cài ra ở `installer-output\ChamCongHTHSHOP-Setup.exe`, tạo
shortcut ngoài desktop tên "Chấm Công HTHSHOP". CI cũng build sẵn bộ cài
này trong mỗi Release trên GitHub.

## Đồng bộ cloud (Firebase)

App đồng bộ dữ liệu chấm công lên cloud để máy ở cửa hàng, máy chủ
cửa hàng và máy admin tổng đều thấy số liệu mới nhất. Project Firebase
là **gio-lam** (gói miễn phí Spark). Dữ liệu local (JSON + ký HMAC)
vẫn là nguồn chính khi offline: mất mạng vẫn chấm công bình thường, có
mạng lại tự đẩy lên; mở app thì tải bản mới nhất trên cloud về nếu có.

- **Luật xem**: mỗi cửa hàng chỉ hiện cửa hàng của mình. Chủ cửa hàng
  (quản lý) và admin tổng nhập mã PIN xong thì có ô chọn cửa hàng
  ở đầu tab Chấm công, xem được hết các cửa hàng.
- **Cách đồng bộ**: mỗi cửa hàng là 1 doc trong collection `stores`
  (doc id = tên cửa hàng, vd `Rybna`), chứa toàn bộ dữ liệu + mốc
  `updatedAt`. Lưu local xong app tự đẩy lên cloud (chạy nền, lỗi mạng
  thì lần sau đẩy lại). Mở app hoặc bấm "Đồng bộ ngay" trong Cài đặt:
  tải về nếu bản cloud mới hơn mốc đã đồng bộ, không thì đẩy local lên.
  Mốc đồng bộ lưu trong chính file JSON local (`cloudUpdatedAt`) nên
  không tải đè lên giờ công nhập offline chưa kịp đẩy.

### Đăng nhập bằng mã PIN (thay cho email/mật khẩu)

Mở app nhập mã PIN là vào luôn, không cần email/mật khẩu:

- **Cửa hàng**: nhập mã PIN của cửa hàng (do chủ cấp, 4-6 chữ số)
  thì chỉ hiện đúng cửa hàng đó + nhân viên của nó.
- **Chủ cửa hàng**: nhập mã PIN chủ thì xem được hết các cửa hàng
  (có ô chọn cửa hàng), quản lý được cửa hàng + nhân viên.
- **Admin**: nhập mã PIN admin thì xem được tất cả, quyền cao hơn chủ
  (mục Quản trị riêng trong Cài đặt).
- **Chưa có mã PIN nào** (app mới cập nhật / project mới): người mở
  app đầu tiên đặt mã PIN admin (nhập 2 lần) rồi vào luôn với vai trò
  admin. Máy nào đang đăng nhập bằng email từ bản cũ thì cũng được
  coi như admin để đặt PIN luôn.
- Mất mạng thì bấm "Dùng offline" vẫn chấm công bình thường, có mạng
  nhập PIN lại để đồng bộ.
- **Đổi mã PIN chủ/admin**: trong Cài đặt > Quản trị, app hỏi thêm mã
  PIN hiện tại — vì mật khẩu tài khoản suy ra từ PIN nên đổi PIN phải
  đổi cả mật khẩu tài khoản, nếu không PIN mới sẽ không đăng nhập được.
  Quên mã PIN hiện tại thì không đổi được trong app: xóa tài khoản
  tương ứng (`admin@` / `owner@gio-lam.local`) trong Firebase Console
  > Authentication và xóa field hash tương ứng trong doc `pins/config`
  rồi đặt lại từ đầu (mất mã PIN cửa hàng thì chủ tạo lại cửa hàng).

Kỹ thuật: hash mã PIN lưu công khai trong doc `pins/config`
(collection `pins`, field `stores` là map tên cửa hàng -> hash PIN,
cộng `ownerPinHash` / `adminPinHash`). App kiểm tra hash rồi đăng
nhập bằng tài khoản Firebase Auth suy ra từ PIN (email dạng
`store-<slug>@gio-lam.local` / `owner@gio-lam.local` /
`admin@gio-lam.local`, mật khẩu suy ra từ PIN). Tài khoản và doc
`users/{uid}` do chủ/admin tạo ngay trong app khi thêm cửa hàng hoặc
đặt mã PIN — không cần tạo tay trong Console nữa.

**GIỚI HẠN TRUNG THỰC**: mã PIN ngắn (4-6 số) + hash lưu công khai
nên PIN chỉ ngăn người tò mò xem nhầm cửa hàng, không chống được
người cố tình dò (4-6 số thì dò hết cũng nhanh). Đừng dùng PIN làm
mật khẩu cho dữ liệu nhạy cảm khác. Mã PIN cloud khác mật khẩu tổng
local (file `gio-lam.json.master`, bấm Ctrl+H): PIN để vào app +
đồng bộ, mật khẩu tổng để mở chế độ admin trên máy này kể cả khi
mất mạng.

### Chủ tự thêm cửa hàng + nhân viên

Chủ (hoặc admin) vào **Cài đặt > Cửa hàng** (cần nhập mã PIN
chủ/admin trước):

1. Bấm **Thêm cửa hàng** → nhập tên cửa hàng + mã PIN (4-6 số, nhập
   2 lần). App tự tạo dữ liệu cửa hàng mới trên cloud + tài khoản +
   mã PIN. Mã PIN hiện **1 lần duy nhất** sau khi tạo — chủ báo mã
   này cho cửa hàng, sau này không xem lại được.
2. Thêm nhân viên cho cửa hàng đang xem ở **Cài đặt > Nhân viên**
   (nhân viên thêm/sửa/xóa luôn ghi vào đúng cửa hàng đang chọn
   trong ô chọn ở đầu tab Chấm công). Khi thêm nhân viên mới có ô
   chọn **Cửa hàng** — chọn luôn cửa hàng muốn gán, không cần chuyển
   màn hình sang đó trước. Muốn chuyển 1 nhân viên đã có sang cửa
   hàng khác (vd sang tháng sau đổi cửa hàng): bấm nút ⇄ ở dòng
   nhân viên đó, chọn cửa hàng đích — toàn bộ ca làm của người đó
   chuyển theo. Không chuyển được nếu cửa hàng đích đã có nhân viên
   trùng tên, hoặc cửa hàng nguồn chỉ còn 1 nhân viên.
3. Gửi **bộ cài app** (file `ChamCongHTHSHOP-Setup-windows-N.exe`
   trong Release trên GitHub) cho cửa hàng đó. Cửa hàng cài xong,
   mở app nhập mã PIN là vào đúng cửa hàng của mình.
4. Xóa cửa hàng: bấm nút xóa ở dòng cửa hàng đó (không xóa được cửa
   hàng đang xem — đổi sang cửa hàng khác trước). Xóa xong thì tài
   khoản của cửa hàng đó mất quyền xem (doc users bị xóa).

Chưa có ở bản này: **đổi mã PIN cửa hàng** — muốn đổi thì chủ tạo
lại cửa hàng mới (tên khác hoặc xóa cửa hàng cũ rồi tạo lại) và báo
mã PIN mới cho cửa hàng.

### Admin làm 1 lần trên Firebase Console (console.firebase.google.com)

1. **Firestore**: vào Build > Firestore Database, tạo database nếu chưa
   có. Vào Firestore > Rules, dán toàn bộ file `firestore.rules` trong
   repo này rồi bấm Publish. **LƯU Ý: bản rules đã đổi sau bản đồng bộ
   đầu (thêm collection `pins` + cho chủ/admin tạo doc users) — nếu
   đã dán bản rules cũ thì dán lại bản mới này.**
2. Không cần tạo tài khoản tay trong Console nữa: tài khoản + doc
   `users/{uid}` được tạo tự động trong app khi chủ thêm cửa hàng
   hoặc admin đặt mã PIN. Không cần bật Anonymous hay App Check
   (App Check không hỗ trợ Windows — bật ép buộc sẽ chặn hết đồng bộ).

## Bộ cài đặt (Chấm Công HTHSHOP)

App đóng gói thành bộ cài đặt Windows bằng Inno Setup (file
`installer.iss` ở root repo). CI build xong sẽ đăng cả 2 file lên
Release: file zip cũ (`gio-lam-windows.zip`) và bộ cài
(`ChamCongHTHSHOP-Setup-windows-N.exe`). Chạy bộ cài thì app được
cài vào thư mục Programs của user, tạo shortcut ngoài desktop tên
**Chấm Công HTHSHOP** (+ shortcut Start Menu), có gỡ cài đặt.
Không cần quyền admin để cài. Tên cửa sổ trong app vẫn là
"Chấm công by Hiếu Lê", chỉ tên chương trình cài đặt + shortcut là
"Chấm Công HTHSHOP".

## Kiểm thử

```bat
flutter test
```

Test kiểm tra: ca đêm 20:00→05:00 = 9h00, chưa tan ca thì không vào ca mới
được, nhập tay ngày cũ bị chặn.
