// Cấu hình Firebase cho app Gio-Lam — viết tay theo firebaseConfig
// của project "gio-lam" (anh chủ tạo trên Firebase Console).
// Đây là key client công khai theo chuẩn Firebase (bảo mật thật nằm ở
// Firestore Rules + Auth), nên để trong code app là bình thường.
import 'package:firebase_core/firebase_core.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get windows => const FirebaseOptions(
        apiKey: 'AIzaSyCuGZlsiHnnJwaR7t9SaISRnEsMvCcrqKY',
        appId: '1:1039514283001:web:016265e83e30d0940e6b28',
        messagingSenderId: '1039514283001',
        projectId: 'gio-lam',
        authDomain: 'gio-lam.firebaseapp.com',
        storageBucket: 'gio-lam.firebasestorage.app',
      );

  // App chỉ chạy trên Windows; các nền tảng khác dùng chung cấu hình
  // Windows (không build thật trên đó).
  static FirebaseOptions get currentPlatform => windows;
}
