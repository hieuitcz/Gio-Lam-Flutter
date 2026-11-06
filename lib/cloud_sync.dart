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
// - Đăng nhập bằng MÃ PIN (thay cho email/mật khẩu): mỗi cửa hàng 1
//   PIN riêng, chủ/admin cũng có PIN riêng. PIN suy ra tài khoản
//   Firebase Auth của đối tượng đó (email + mật khẩu suy ra từ PIN,
//   xem logic.dart). Hash PIN lưu công khai trong doc `pins/config`
//   để app kiểm tra PIN khi đăng nhập (xem firestore.rules).
//   Quyền xem map qua doc `users/{uid}`:
//   {storeId, role: 'store' | 'owner' | 'admin'}; storeId '*' = xem
//   được tất cả cửa hàng. Chưa có doc users/{uid} thì mặc định chỉ
//   xem cửa hàng local hiện tại (không chặn app, chỉ là chưa đồng bộ).
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';
import 'logic.dart';
import 'store.dart';

/// Mốc thời gian chờ tối đa cho 1 lần gọi Firestore (tránh kẹt khi
/// mạng yếu). Lỗi/timeout đều được nuốt ở tầng gọi, app vẫn chạy
/// offline bình thường.
const _cloudTimeout = Duration(seconds: 10);

/// Có nên tải bản cloud về không — chỉ tải khi bản cloud mới hơn mốc
/// đồng bộ local gần nhất (tránh ghi đè giờ nhập offline chưa đẩy lên).
bool shouldApplyRemote(int remoteUpdatedAt, int localCloudUpdatedAt) =>
    remoteUpdatedAt > localCloudUpdatedAt;

/// Cấu hình mã PIN lưu trong doc `pins/config` trên Firestore:
/// `stores` = map tên cửa hàng -> hash SHA-256 của PIN cửa hàng đó;
/// `ownerPinHash` / `adminPinHash` = hash PIN của chủ / admin.
class PinConfig {
  final Map<String, String> storePins;
  final String? ownerPinHash;
  final String? adminPinHash;
  PinConfig({required this.storePins, this.ownerPinHash, this.adminPinHash});

  factory PinConfig.fromDoc(Map<String, dynamic>? d) {
    final stores = <String, String>{};
    final m = d?['stores'];
    if (m is Map) {
      m.forEach((k, v) {
        if (v is String) stores[k.toString()] = v;
      });
    }
    return PinConfig(
      storePins: stores,
      ownerPinHash: d?['ownerPinHash'] as String?,
      adminPinHash: d?['adminPinHash'] as String?,
    );
  }
}

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
  // Cấu hình mã PIN đã tải (null = doc pins/config chưa tồn tại).
  PinConfig? pinConfig;
  // Lần tải pins/config gần nhất bị lỗi mạng (để màn hình PIN phân
  // biệt "chưa có PIN nào" với "mất mạng, không kiểm tra được PIN").
  bool pinFetchFailed = false;

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

  Future<void> signOut() async {
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
    cloudRole = null;
    cloudStoreId = null;
    storeIds = [];
  }

  // --- Mã PIN ----------------------------------------------------------
  // Tải doc pins/config (đọc công khai theo Rules, không cần đăng
  // nhập). Thử đăng nhập ẩn danh trước cho đúng luồng, nhưng nếu
  // Anonymous chưa bật trong Console thì vẫn đọc được vì Rules cho
  // đọc công khai — lỗi đăng nhập ẩn danh được bỏ qua. Trả về null
  // khi doc chưa tồn tại (chưa ai đặt mã PIN) hoặc khi tải lỗi
  // (pinFetchFailed = true để màn hình PIN phân biệt 2 trường hợp).
  Future<PinConfig?> fetchPinConfig() async {
    pinFetchFailed = false;
    if (!firebaseReady) {
      pinFetchFailed = true;
      return null;
    }
    try {
      if (FirebaseAuth.instance.currentUser == null) {
        try {
          await FirebaseAuth.instance
              .signInAnonymously()
              .timeout(_cloudTimeout);
        } catch (_) {
          // Anonymous chưa bật trong Console: vẫn đọc công khai được.
        }
      }
      final doc = await _db
          .collection('pins')
          .doc('config')
          .get()
          .timeout(_cloudTimeout);
      if (!doc.exists) {
        pinConfig = null;
        return null;
      }
      pinConfig = PinConfig.fromDoc(doc.data());
      return pinConfig;
    } catch (_) {
      pinFetchFailed = true;
      return null;
    }
  }

  /// Đăng nhập bằng mã PIN: khớp hash trong pins/config thì đăng nhập
  /// bằng tài khoản Firebase Auth suy ra từ PIN (email + mật khẩu đều
  /// suy ra từ PIN, xem logic.dart). Sai PIN -> StateError
  /// 'Mã PIN không đúng.' (không nói rõ PIN nào sai). Tài khoản chưa
  /// được tạo (chủ tạo cửa hàng dở dang) thì tạo tài khoản rồi vào;
  /// quyền xem mặc định theo cửa hàng local, chủ tạo lại cửa hàng thì
  /// quyền sẽ đúng.
  Future<void> signInWithPin(String pin) async {
    final cfg = pinConfig ?? await fetchPinConfig();
    if (cfg == null) {
      if (pinFetchFailed) {
        throw StateError('Mất mạng, không kiểm tra được mã PIN.');
      }
      throw StateError('Chưa có mã PIN nào. Nhờ admin đặt mã PIN trước.');
    }
    final resolved =
        resolvePinRole(cfg.storePins, cfg.ownerPinHash, cfg.adminPinHash, pin);
    if (resolved == null) throw StateError('Mã PIN không đúng.');
    final email = accountEmail(resolved.role, resolved.storeId);
    final pw = accountPassword(resolved.role, resolved.storeId, pin);
    try {
      await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: pw)
          .timeout(_cloudTimeout);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        await FirebaseAuth.instance
            .createUserWithEmailAndPassword(email: email, password: pw)
            .timeout(_cloudTimeout);
      } else if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        throw StateError('Mã PIN không đúng.');
      } else {
        rethrow;
      }
    }
  }

  /// Đặt mã PIN admin lần đầu (chưa có pins/config): người mở app đầu
  /// tiên làm việc này. THỨ TỰ QUAN TRỌNG (theo luật bootstrap trong
  /// firestore.rules): tạo tài khoản admin -> tạo doc users (lúc này
  /// pins/config chưa tồn tại nên được phép) -> ghi pins/config.
  /// Tài khoản admin đã tồn tại (đặt dở lần trước) thì đăng nhập lại
  /// bằng PIN đó rồi làm tiếp, không báo lỗi.
  Future<void> setupAdminPin(String pin) async {
    final email = accountEmail('admin', '*');
    final pw = accountPassword('admin', '*', pin);
    UserCredential cred;
    try {
      cred = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: pw)
          .timeout(_cloudTimeout);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        try {
          cred = await FirebaseAuth.instance
              .signInWithEmailAndPassword(email: email, password: pw)
              .timeout(_cloudTimeout);
        } on FirebaseAuthException catch (e2) {
          // Tài khoản admin đã tồn tại với 1 mã PIN khác (lần đặt
          // trước dở dang): không đoán được PIN cũ nên báo rõ để
          // admin đặt lại từ Console, thay vì báo mất mạng chung chung.
          if (e2.code == 'wrong-password' || e2.code == 'invalid-credential') {
            throw StateError(
                'Tài khoản admin đã tồn tại với mã PIN khác. Xóa tài khoản admin@gio-lam.local và doc pins/config trên Firebase Console rồi đặt lại mã PIN.');
          }
          rethrow;
        }
      } else {
        rethrow;
      }
    }
    final uid = cred.user!.uid;
    await _db
        .collection('users')
        .doc(uid)
        .set({'storeId': '*', 'role': 'admin'}).timeout(_cloudTimeout);
    final hash = pinHash(pin);
    await _db.collection('pins').doc('config').set({
      'stores': <String, String>{},
      'adminPinHash': hash,
    }).timeout(_cloudTimeout);
    pinConfig = PinConfig(storePins: {}, adminPinHash: hash);
  }

  /// Tìm UID của 1 doc users theo storeId (và role nếu có), để dùng
  /// lại khi tài khoản Auth đã tồn tại mà doc users bị thiếu (tạo dở
  /// lần trước). Chỉ query theo 1 field rồi lọc field còn lại bằng
  /// code để không cần composite index trên Firestore.
  Future<String?> _findUserUid({String? storeId, String? role}) async {
    try {
      Query<Map<String, dynamic>> q = _db.collection('users');
      if (storeId != null) {
        q = q.where('storeId', isEqualTo: storeId);
      } else if (role != null) {
        q = q.where('role', isEqualTo: role);
      }
      final snap = await q.limit(10).get().timeout(_cloudTimeout);
      for (final d in snap.docs) {
        final data = d.data();
        if (role != null && data['role'] != role) continue;
        if (storeId != null && data['storeId'] != storeId) continue;
        return d.id;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Tạo tài khoản Firebase Auth bằng app phụ (để không đăng xuất
  /// phiên chủ/admin hiện tại — createUser trên app chính sẽ đổi
  /// phiên đăng nhập) rồi tạo doc users/{uid} cho tài khoản đó.
  /// Tài khoản đã tồn tại thì dùng lại UID cũ (tìm qua users doc,
  /// hoặc đăng nhập thử bằng mật khẩu mới trên app phụ). Trả về UID
  /// và cờ created (true = vừa tạo mới, false = tài khoản đã có sẵn
  /// — khi đó mật khẩu tài khoản vẫn là mật khẩu cũ, bên gọi phải tự
  /// đổi mật khẩu nếu PIN thay đổi).
  Future<({String uid, bool created})> _provisionAccount({
    required String email,
    required String password,
    required String storeId,
    required String role,
  }) async {
    FirebaseApp? secondary;
    try {
      try {
        secondary = Firebase.app('provisioner');
      } catch (_) {
        secondary = await Firebase.initializeApp(
                name: 'provisioner',
                options: DefaultFirebaseOptions.currentPlatform)
            .timeout(_cloudTimeout);
      }
      final auth = FirebaseAuth.instanceFor(app: secondary);
      String uid;
      bool created;
      try {
        final cred = await auth
            .createUserWithEmailAndPassword(email: email, password: password)
            .timeout(_cloudTimeout);
        uid = cred.user!.uid;
        created = true;
      } on FirebaseAuthException catch (e) {
        if (e.code != 'email-already-in-use') rethrow;
        // Tài khoản đã có: tìm UID qua users doc, không có thì đăng
        // nhập thử bằng mật khẩu mới (trường hợp tạo dở lần trước
        // với đúng PIN này).
        final found = await _findUserUid(storeId: storeId, role: role);
        if (found != null) {
          uid = found;
        } else {
          try {
            final cred = await auth
                .signInWithEmailAndPassword(email: email, password: password)
                .timeout(_cloudTimeout);
            uid = cred.user!.uid;
          } catch (_) {
            throw StateError(
                'Tài khoản $email đã tồn tại, nhờ admin kiểm tra.');
          }
        }
        created = false;
      }
      await _db
          .collection('users')
          .doc(uid)
          .set({'storeId': storeId, 'role': role}).timeout(_cloudTimeout);
      return (uid: uid, created: created);
    } finally {
      try {
        await secondary?.delete();
      } catch (_) {}
    }
  }

  /// Đổi mật khẩu 1 tài khoản Auth: đăng nhập bằng mật khẩu cũ trên
  /// app phụ rồi gọi updatePassword (phiên vừa đăng nhập nên còn mới).
  /// Sai mật khẩu cũ -> StateError để app báo rõ, không báo mất mạng.
  Future<void> _updateAccountPassword({
    required String email,
    required String oldPassword,
    required String newPassword,
  }) async {
    FirebaseApp? secondary;
    try {
      try {
        secondary = Firebase.app('provisioner');
      } catch (_) {
        secondary = await Firebase.initializeApp(
                name: 'provisioner',
                options: DefaultFirebaseOptions.currentPlatform)
            .timeout(_cloudTimeout);
      }
      final auth = FirebaseAuth.instanceFor(app: secondary);
      final cred = await auth
          .signInWithEmailAndPassword(email: email, password: oldPassword)
          .timeout(_cloudTimeout);
      await cred.user!.updatePassword(newPassword).timeout(_cloudTimeout);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        throw StateError('Mã PIN hiện tại không đúng.');
      }
      rethrow;
    } finally {
      try {
        await secondary?.delete();
      } catch (_) {}
    }
  }

  /// Chủ/admin THÊM 1 cửa hàng: tạo tài khoản Auth + doc users +
  /// doc stores/{tên} (dữ liệu seed, chưa có nhân viên) + thêm PIN
  /// vào pins/config. Tên cửa hàng không được chứa '.' hay '/' (vì
  /// tên dùng làm field path khi cập nhật map PIN + làm doc id).
  /// Trả về mã PIN vừa tạo (để chủ báo cho cửa hàng, chỉ hiện 1 lần).
  Future<String> createStore(String storeName, String pin) async {
    if (!available || !canPickStore) {
      throw StateError('Chưa đăng nhập chủ/admin.');
    }
    final name = storeName.trim();
    if (name.isEmpty || name.contains('.') || name.contains('/')) {
      throw StateError('Tên cửa hàng không được trống, chứa . hay /.');
    }
    if (storeIds.contains(name)) {
      throw StateError('Cửa hàng $name đã có rồi.');
    }
    final email = accountEmail('store', name);
    final pw = accountPassword('store', name, pin);
    await _provisionAccount(
        email: email, password: pw, storeId: name, role: 'store');
    final seed = AppData(storeName: name, employees: []);
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.collection('stores').doc(name).set({
      'data': seed.toJson(),
      'updatedAt': now,
      'updatedBy': _updatedBy(),
    }, SetOptions(merge: true)).timeout(_cloudTimeout);
    final hash = pinHash(pin);
    try {
      await _db
          .collection('pins')
          .doc('config')
          .update({'stores.$name': hash}).timeout(_cloudTimeout);
    } catch (_) {
      // pins/config chưa tồn tại (trường hợp hiếm): tạo mới kèm map.
      await _db.collection('pins').doc('config').set({
        'stores': {name: hash}
      }, SetOptions(merge: true)).timeout(_cloudTimeout);
    }
    pinConfig?.storePins[name] = hash;
    await fetchStoreIds();
    return pin;
  }

  /// Chủ/admin XÓA 1 cửa hàng: xóa doc stores + doc users của cửa
  /// hàng + mục PIN. Tài khoản Auth cũ vẫn còn (client không xóa
  /// được tài khoản Auth) nhưng mất quyền vì không còn doc users.
  Future<void> deleteStore(String storeName) async {
    if (!available || !canPickStore) {
      throw StateError('Chưa đăng nhập chủ/admin.');
    }
    await _db
        .collection('stores')
        .doc(storeName)
        .delete()
        .timeout(_cloudTimeout);
    try {
      final q = await _db
          .collection('users')
          .where('storeId', isEqualTo: storeName)
          .get()
          .timeout(_cloudTimeout);
      for (final d in q.docs) {
        try {
          await d.reference.delete().timeout(_cloudTimeout);
        } catch (_) {}
      }
    } catch (_) {}
    try {
      await _db.collection('pins').doc('config').update(
          {'stores.$storeName': FieldValue.delete()}).timeout(_cloudTimeout);
    } catch (_) {}
    pinConfig?.storePins.remove(storeName);
    await fetchStoreIds();
  }

  /// Admin ĐẶT/ĐỔI mã PIN chủ hoặc mã PIN admin: tạo tài khoản Auth
  /// mới (mật khẩu suy ra từ PIN mới) + doc users mới, xóa doc users
  /// cũ của vai trò đó (tài khoản Auth cũ mất quyền), cập nhật hash
  /// trong pins/config. Đổi mã PIN admin xong thì phiên admin hiện
  /// tại mất quyền (doc users của nó vừa bị xóa) nên bên gọi phải
  /// đăng xuất rồi đăng nhập lại bằng PIN mới.
  /// Đặt/đổi mã PIN chủ/admin. Mật khẩu tài khoản Firebase Auth suy ra
  /// từ PIN (xem logic.dart) nên ĐỔI PIN PHẢI ĐỔI CẢ MẬT KHẨU tài
  /// khoản — bản trước chỉ đổi hash trong pins/config nên PIN mới
  /// không đăng nhập được (sai mật khẩu) mà PIN cũ cũng không khớp
  /// hash nữa, thành ra khóa luôn tài khoản. Đổi PIN cần mã PIN hiện
  /// tại để đăng nhập vào app phụ rồi đổi mật khẩu; đặt lần đầu (tài
  /// khoản chưa có) thì không cần mã hiện tại.
  Future<void> setRolePin(String kind, String pin, {String? currentPin}) async {
    if (!available || cloudRole != 'admin') {
      throw StateError('Chỉ admin mới đặt mã PIN.');
    }
    if (kind != 'owner' && kind != 'admin') {
      throw StateError('Vai trò không hợp lệ.');
    }
    final email = accountEmail(kind, '*');
    final pw = accountPassword(kind, '*', pin);
    final provisioned = await _provisionAccount(
        email: email, password: pw, storeId: '*', role: kind);
    final uid = provisioned.uid;
    // Tài khoản đã tồn tại (đổi PIN): đổi mật khẩu tài khoản thành
    // mật khẩu suy ra từ PIN mới, đăng nhập bằng PIN cũ trước.
    if (!provisioned.created) {
      if (currentPin == null || currentPin.isEmpty) {
        throw StateError('Đổi mã PIN cần nhập mã PIN hiện tại.');
      }
      await _updateAccountPassword(
          email: email,
          oldPassword: accountPassword(kind, '*', currentPin),
          newPassword: pw);
    }
    // Xóa doc users cũ của vai trò này (trừ doc vừa tạo).
    try {
      final q = await _db
          .collection('users')
          .where('role', isEqualTo: kind)
          .get()
          .timeout(_cloudTimeout);
      for (final d in q.docs) {
        if (d.id != uid && (d.data()['storeId'] as String?) == '*') {
          try {
            await d.reference.delete().timeout(_cloudTimeout);
          } catch (_) {}
        }
      }
    } catch (_) {}
    final hash = pinHash(pin);
    final field = kind == 'owner' ? 'ownerPinHash' : 'adminPinHash';
    try {
      await _db
          .collection('pins')
          .doc('config')
          .update({field: hash}).timeout(_cloudTimeout);
    } catch (_) {
      await _db
          .collection('pins')
          .doc('config')
          .set({field: hash}, SetOptions(merge: true)).timeout(_cloudTimeout);
    }
    if (pinConfig != null) {
      pinConfig = PinConfig(
        storePins: pinConfig!.storePins,
        ownerPinHash: kind == 'owner' ? hash : pinConfig!.ownerPinHash,
        adminPinHash: kind == 'admin' ? hash : pinConfig!.adminPinHash,
      );
    }
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
      final doc =
          await _db.collection('users').doc(uid).get().timeout(_cloudTimeout);
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
      final snap = await _db.collection('stores').get().timeout(_cloudTimeout);
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
      s.data = AppData.fromJson(Map<String, dynamic>.from(remoteData));
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
      s.data = AppData.fromJson(Map<String, dynamic>.from(remoteData));
      s.data.cloudUpdatedAt = (d['updatedAt'] as num?)?.toInt() ?? 0;
      await s.save();
      lastSyncTime = DateTime.now();
      lastSyncError = null;
      return true;
    } catch (e) {
      lastSyncError = '$e';
      return false;
    }
  }

  /// Tải dữ liệu 1 cửa hàng về mà KHÔNG đổi dữ liệu local hiện tại.
  /// Trả về null nếu chưa có doc hoặc mất mạng. Dùng khi thêm/chuyển
  /// nhân viên sang cửa hàng khác mà không cần chuyển màn hình sang đó.
  Future<AppData?> fetchStoreData(String storeId) async {
    if (!available) return null;
    try {
      final doc = await _db
          .collection('stores')
          .doc(storeId)
          .get()
          .timeout(_cloudTimeout);
      if (!doc.exists) return null;
      final d = doc.data();
      if (d == null) return null;
      final remoteData = d['data'];
      if (remoteData is! Map) return null;
      final data = AppData.fromJson(Map<String, dynamic>.from(remoteData));
      data.cloudUpdatedAt = (d['updatedAt'] as num?)?.toInt() ?? 0;
      return data;
    } catch (_) {
      return null;
    }
  }

  /// Đẩy 1 AppData (không phải dữ liệu local hiện tại) lên doc của
  /// cửa hàng đó. Không chạm gì tới dữ liệu local trên máy.
  Future<void> uploadStoreData(String storeId, AppData data) async {
    if (!available) throw StateError('Chưa đăng nhập cloud.');
    final now = DateTime.now().millisecondsSinceEpoch;
    data.cloudUpdatedAt = now;
    await _db.collection('stores').doc(storeId).set({
      'data': data.toJson(),
      'updatedAt': now,
      'updatedBy': _updatedBy(),
    }, SetOptions(merge: true)).timeout(_cloudTimeout);
    lastSyncTime = DateTime.now();
    lastSyncError = null;
  }

  /// Thêm nhân viên mới vào 1 cửa hàng khác (không phải cửa hàng đang
  /// xem). Ném StateError nếu trùng tên hoặc không tải được dữ liệu.
  Future<void> addEmployeeToStore(String storeId, Employee emp) async {
    if (!available || !canPickStore) {
      throw StateError('Chưa đăng nhập chủ/admin.');
    }
    final target = await fetchStoreData(storeId);
    if (target == null) {
      throw StateError('Không tải được dữ liệu cửa hàng $storeId.');
    }
    if (!target.addEmployee(emp)) {
      throw StateError('Cửa hàng $storeId đã có nhân viên ${emp.name}.');
    }
    await uploadStoreData(storeId, target);
  }
}

/// Một instance dùng chung cho cả app (main tạo, HomePage dùng).
final cloudSync = CloudSync();
