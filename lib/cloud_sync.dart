// Đồng bộ cloud Firebase (Firestore + Auth) cho app Gio-Lam.
//
// Thiết kế:
// - Dữ liệu local (JSON + ký HMAC) vẫn là nguồn chính khi offline.
//   Mọi thay đổi lưu local xong mới đẩy lên cloud (tốt nhất có thể);
//   mất mạng thì lần lưu sau / lần mở app sau tự đẩy lại.
// - Mỗi cửa hàng là 1 doc trong collection `stores`, doc id = tên cửa
//   hàng (vd "Rybna"), chứa toàn bộ AppData.toJson + updatedAt.
//   Quy tắc "bản mới thắng": chỉ tải cloud về khi updatedAt trên cloud
//   mới hơn mốc cloudUpdatedAt đã lưu trong JSON local.
// - Đăng nhập bằng tài khoản Firebase Auth (email/mật khẩu, admin tạo
//   trong Console). Quyền xem map qua doc `users/{uid}`:
//   {storeId, role: 'store' | 'owner' | 'admin'}; storeId '*' = xem
//   được tất cả cửa hàng. Chưa có doc users/{uid} thì mặc định chỉ
//   xem cửa hàng local hiện tại (không chặn app, chỉ là chưa đồng bộ).
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';
import 'store.dart';

/// Mốc thời gian chờ tối đa cho 1 lần gọi Firestore (tránh kẹt khi
/// mạng yếu). Lỗi/timeout đều được nuốt ở tầng gọi, app vẫn chạy
/// offline bình thường.
const _cloudTimeout = Duration(seconds: 10);

/// Có nên tải bản cloud về không — chỉ tải khi bản cloud mới hơn mốc
/// đồng bộ local gần nhất (tránh ghi đè giờ nhập offline chưa đẩy lên).
bool shouldApplyRemote(int remoteUpdatedAt, int localCloudUpdatedAt) =>
    remoteUpdatedAt > localCloudUpdatedAt;

class CloudSync {
  bool firebaseReady = false;
  // Quyền cloud của tài khoản đang đăng nhập: 'store' | 'owner' |
  // 'admin'. null = chưa tải được (chưa đăng nhập / chưa có doc).
  String? cloudRole;
  // Cửa hàng tài khoản này được xem: tên cửa hàng hoặc '*' (tất cả).
  String? cloudStoreId;
  // Danh sách id các doc trong collection `stores` (để chọn cửa hàng).
  List<String> storeIds = [];
  // Lần đồng bộ thành công gần nhất (để hiện ở Cài đặt).
  DateTime? lastSyncTime;
  // Lỗi đồng bộ gần nhất (nếu có), để hiện ở Cài đặt.
  String? lastSyncError;

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  String? get currentEmail => FirebaseAuth.instance.currentUser?.email;

  bool get signedIn =>
      firebaseReady && FirebaseAuth.instance.currentUser != null;

  /// Sẵn sàng đồng bộ: Firebase đã khởi tạo + đã đăng nhập.
  bool get available => signedIn;

  /// Chủ cửa hàng (quản lý) và admin tổng được chọn xem hết các cửa hàng.
  bool get canPickStore => cloudRole == 'owner' || cloudRole == 'admin';

  /// Khởi tạo Firebase. Lỗi (không mạng, chưa cấu hình...) thì app vẫn
  /// chạy offline hoàn toàn — chỉ là không đồng bộ được.
  Future<void> initFirebase() async {
    try {
      await Firebase.initializeApp(
              options: DefaultFirebaseOptions.currentPlatform)
          .timeout(_cloudTimeout);
      firebaseReady = true;
    } catch (_) {
      firebaseReady = false;
    }
  }

  Future<void> signIn(String email, String password) async {
    await FirebaseAuth.instance
        .signInWithEmailAndPassword(email: email, password: password)
        .timeout(_cloudTimeout);
  }

  Future<void> signOut() async {
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
    cloudRole = null;
    cloudStoreId = null;
    storeIds = [];
  }

  /// Tải doc users/{uid} để biết tài khoản này là ai (store/owner/admin)
  /// và được xem cửa hàng nào. Chưa có doc thì mặc định 'store' với
  /// đúng cửa hàng local hiện tại — không chặn app.
  Future<void> loadUserProfile(String localStoreName) async {
    cloudRole = 'store';
    cloudStoreId = localStoreName;
    if (!signedIn) return;
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final doc = await _db
          .collection('users')
          .doc(uid)
          .get()
          .timeout(_cloudTimeout);
      final d = doc.data();
      if (d != null) {
        final role = d['role'] as String?;
        if (role == 'store' || role == 'owner' || role == 'admin') {
          cloudRole = role;
        }
        final sid = d['storeId'] as String?;
        if (sid != null && sid.isNotEmpty) cloudStoreId = sid;
      }
    } catch (e) {
      lastSyncError = '$e';
    }
  }

  /// Liệt kê các cửa hàng đã có trên cloud (để hiện ô chọn cửa hàng).
  /// Tài khoản 'store' chỉ thấy cửa hàng của mình (theo Rules).
  Future<void> fetchStoreIds() async {
    if (!available) return;
    try {
      final snap =
          await _db.collection('stores').get().timeout(_cloudTimeout);
      storeIds = snap.docs.map((d) => d.id).toList()..sort();
    } catch (e) {
      lastSyncError = '$e';
    }
  }

  String _updatedBy() {
    final email = currentEmail;
    final role = cloudRole ?? 'store';
    return email == null ? 'local ($role)' : '$email ($role)';
  }

  /// Đẩy dữ liệu local hiện tại lên cloud (doc stores/{storeName}).
  /// Ghi mốc cloudUpdatedAt vào JSON local rồi mới upload, để lần sau
  /// không tải lại chính dữ liệu mình vừa đẩy. Lỗi mạng thì ném ra cho
  /// tầng gọi nuốt — không hiện lỗi chặn người dùng.
  Future<void> uploadCurrent(DataStore s) async {
    if (!available) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    s.data.cloudUpdatedAt = now;
    await s.save();
    await _db.collection('stores').doc(s.data.storeName).set({
      'data': s.data.toJson(),
      'updatedAt': now,
      'updatedBy': _updatedBy(),
    }, SetOptions(merge: true)).timeout(_cloudTimeout);
    lastSyncTime = DateTime.now();
    lastSyncError = null;
  }

  /// Đẩy lên cloud nếu được, lỗi thì nuốt (thử lại lần lưu sau).
  /// Dùng sau mỗi lần lưu local trong HomePage._save(). Các lần đẩy
  /// được xếp hàng nối tiếp nhau (không đẩy chồng nhau để khỏi ghi
  /// đè bản mới bằng bản cũ khi 2 lần lưu sát nhau).
  bool _uploading = false;
  bool _uploadQueued = false;

  Future<void> uploadBestEffort(DataStore s) async {
    if (_uploading) {
      _uploadQueued = true;
      return;
    }
    _uploading = true;
    try {
      while (true) {
        _uploadQueued = false;
        try {
          await uploadCurrent(s);
        } catch (_) {}
        if (!_uploadQueued) break;
      }
    } finally {
      _uploading = false;
    }
  }

  /// Tải dữ liệu cloud về nếu bản cloud mới hơn mốc local. Trả về true
  /// nếu đã thay dữ liệu local (bên gọi setState lại giao diện).
  Future<bool> downloadIfNewer(DataStore s) async {
    if (!available) return false;
    try {
      final doc = await _db
          .collection('stores')
          .doc(s.data.storeName)
          .get()
          .timeout(_cloudTimeout);
      if (!doc.exists) return false;
      final d = doc.data();
      if (d == null) return false;
      final remoteAt = (d['updatedAt'] as num?)?.toInt() ?? 0;
      final remoteData = d['data'];
      if (remoteData is! Map) return false;
      if (!shouldApplyRemote(remoteAt, s.data.cloudUpdatedAt)) {
        return false;
      }
      s.data =
          AppData.fromJson(Map<String, dynamic>.from(remoteData));
      s.data.cloudUpdatedAt = remoteAt;
      await s.save();
      lastSyncTime = DateTime.now();
      lastSyncError = null;
      return true;
    } catch (e) {
      lastSyncError = '$e';
      return false;
    }
  }

  /// Đồng bộ lúc mở app: cloud chưa có doc thì đẩy local lên; có doc
  /// mới hơn thì tải về. Trả về true nếu dữ liệu local đã thay đổi.
  Future<bool> syncOnStartup(DataStore s) async {
    if (!available) return false;
    return syncNow(s);
  }

  /// Đồng bộ tay (nút "Đồng bộ ngay" trong Cài đặt): tải về nếu cloud
  /// mới hơn, không thì đẩy local lên. Trả về true nếu dữ liệu local
  /// đã thay đổi (tải về).
  Future<bool> syncNow(DataStore s) async {
    if (!available) return false;
    try {
      final changed = await downloadIfNewer(s);
      if (changed) return true;
      await uploadCurrent(s);
      return false;
    } catch (e) {
      lastSyncError = '$e';
      return false;
    }
  }

  /// Đổi sang xem cửa hàng khác (chỉ chủ/admin). Đẩy dữ liệu cửa hàng
  /// hiện tại lên trước, rồi tải doc cửa hàng mới về. Trả về false nếu
  /// mất mạng hoặc cửa hàng đó chưa có dữ liệu trên cloud.
  Future<bool> switchStore(DataStore s, String storeId) async {
    if (!available) return false;
    try {
      await uploadCurrent(s);
      final doc = await _db
          .collection('stores')
          .doc(storeId)
          .get()
          .timeout(_cloudTimeout);
      if (!doc.exists) return false;
      final d = doc.data();
      if (d == null) return false;
      final remoteData = d['data'];
      if (remoteData is! Map) return false;
      s.data =
          AppData.fromJson(Map<String, dynamic>.from(remoteData));
      s.data.cloudUpdatedAt =
          (d['updatedAt'] as num?)?.toInt() ?? 0;
      await s.save();
      lastSyncTime = DateTime.now();
      lastSyncError = null;
      return true;
    } catch (e) {
      lastSyncError = '$e';
      return false;
    }
  }
}

/// Một instance dùng chung cho cả app (main tạo, HomePage dùng).
final cloudSync = CloudSync();
