import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Penyimpanan sesi (token) di Keystore/Keychain perangkat.
class SessionStore {
  SessionStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _kAccess = 'access_token';
  static const _kRefresh = 'refresh_token';
  static const _kUserId = 'user_id';
  static const _kUserName = 'user_name';
  static const _kUserEmail = 'user_email';
  static const _kUserPhoto = 'user_profile_photo';
  static const _kDeviceId = 'device_id';
  static const _kBaseUrl = 'base_url';
  static const _kSavedEmail = 'saved_login_email';
  static const _kSavedPassword = 'saved_login_password';
  static const _kRememberMe = 'remember_me_enabled';

  /// Alamat server lokal. Di HP/emulator gunakan `adb reverse tcp:4000 tcp:4000`
  /// agar `127.0.0.1:4000` di perangkat mengarah ke laptop. Untuk server
  /// produksi, ubah lewat Lainnya → Alamat server.
  static String get defaultBaseUrl =>
      kIsWeb ? 'http://127.0.0.1:4000' : 'https://dailypilot.solusiit.id';

  Future<String> baseUrl() async {
    final stored = await _storage.read(key: _kBaseUrl);
    if (stored == null ||
        stored.isEmpty ||
        (!kIsWeb && (stored.contains('127.0.0.1') || stored.contains('77.37.44.232') || stored.contains('10.0.2.2')))) {
      if (!kIsWeb) {
        await setBaseUrl('https://dailypilot.solusiit.id');
        return 'https://dailypilot.solusiit.id';
      }
      return defaultBaseUrl;
    }
    return stored;
  }

  Future<void> setBaseUrl(String url) => _storage.write(key: _kBaseUrl, value: url.trim());

  Future<String?> accessToken() => _storage.read(key: _kAccess);
  Future<String?> refreshToken() => _storage.read(key: _kRefresh);
  Future<String?> userId() => _storage.read(key: _kUserId);
  Future<String?> userName() => _storage.read(key: _kUserName);
  Future<String?> userEmail() => _storage.read(key: _kUserEmail);
  Future<String?> userPhoto() => _storage.read(key: _kUserPhoto);
  Future<String?> deviceId() => _storage.read(key: _kDeviceId);

  Future<void> writeUserName(String name) => _storage.write(key: _kUserName, value: name.trim());
  Future<void> saveUserProfilePhoto(String photo) => _storage.write(key: _kUserPhoto, value: photo);

  Future<String?> savedEmail() => _storage.read(key: _kSavedEmail);
  Future<String?> savedPassword() => _storage.read(key: _kSavedPassword);
  Future<bool> isRememberMe() async {
    final val = await _storage.read(key: _kRememberMe);
    return val != 'false'; // Default true for user convenience
  }

  Future<void> saveCredentials({required String email, required String password, bool remember = true}) async {
    await _storage.write(key: _kRememberMe, value: remember.toString());
    if (remember) {
      await _storage.write(key: _kSavedEmail, value: email.trim());
      await _storage.write(key: _kSavedPassword, value: password);
    } else {
      await _storage.delete(key: _kSavedEmail);
      await _storage.delete(key: _kSavedPassword);
    }
  }

  Future<void> saveSession({
    required String accessToken,
    required String refreshToken,
    required String userId,
    required String userName,
    required String userEmail,
    String? deviceId,
  }) async {
    await _storage.write(key: _kAccess, value: accessToken);
    await _storage.write(key: _kRefresh, value: refreshToken);
    await _storage.write(key: _kUserId, value: userId);
    await _storage.write(key: _kUserName, value: userName);
    await _storage.write(key: _kUserEmail, value: userEmail);
    if (deviceId != null) await _storage.write(key: _kDeviceId, value: deviceId);
  }

  Future<void> saveTokens({required String accessToken, required String refreshToken}) async {
    await _storage.write(key: _kAccess, value: accessToken);
    await _storage.write(key: _kRefresh, value: refreshToken);
  }

  Future<bool> hasSession() async {
    final token = await _storage.read(key: _kRefresh);
    return token != null && token.isNotEmpty;
  }

  Future<void> clear() async {
    await _storage.delete(key: _kAccess);
    await _storage.delete(key: _kRefresh);
    await _storage.delete(key: _kUserId);
    await _storage.delete(key: _kUserName);
    await _storage.delete(key: _kUserEmail);
    await _storage.delete(key: _kDeviceId);
  }
}
