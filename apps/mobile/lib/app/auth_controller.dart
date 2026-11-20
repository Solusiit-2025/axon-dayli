import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/remote/api_client.dart';
import 'providers.dart';

enum AuthStatus { loading, signedOut, signedIn }

class AuthState {
  const AuthState({
    this.status = AuthStatus.loading,
    this.name,
    this.email,
    this.userPhoto,
    this.busy = false,
    this.error,
  });

  final AuthStatus status;
  final String? name;
  final String? email;
  final String? userPhoto;
  final bool busy;
  final String? error;

  AuthState copyWith({
    AuthStatus? status,
    String? name,
    String? email,
    String? userPhoto,
    bool? busy,
    String? error,
    bool clearError = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      name: name ?? this.name,
      email: email ?? this.email,
      userPhoto: userPhoto ?? this.userPhoto,
      busy: busy ?? this.busy,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class AuthController extends StateNotifier<AuthState> {
  AuthController(this.ref) : super(const AuthState()) {
    _bootstrap();
  }

  final Ref ref;

  Future<void> _bootstrap() async {
    final store = ref.read(sessionStoreProvider);

    if (!await store.hasSession()) {
      state = const AuthState(status: AuthStatus.signedOut);
      return;
    }

    final cachedName = await store.userName();
    final cachedEmail = await store.userEmail();
    final cachedPhoto = await store.userPhoto();

    try {
      final me = await ref.read(apiClientProvider).get('/auth/me');
      await _applyPayload(me);
      state = AuthState(status: AuthStatus.signedIn, name: cachedName, email: cachedEmail, userPhoto: cachedPhoto);
      _afterSignIn();
    } on ApiException catch (e) {
      if (e.isUnauthorized) {
        await store.clear();
        state = const AuthState(status: AuthStatus.signedOut);
      } else if (cachedEmail != null) {
        // Offline: tetap masuk memakai data lokal.
        state = AuthState(
          status: AuthStatus.signedIn,
          name: cachedName,
          email: cachedEmail,
          userPhoto: cachedPhoto,
        );
        _afterSignIn(immediate: false);
      } else {
        state = AuthState(status: AuthStatus.signedOut, error: e.message);
      }
    } catch (_) {
      if (cachedEmail != null) {
        state = AuthState(status: AuthStatus.signedIn, name: cachedName, email: cachedEmail, userPhoto: cachedPhoto);
        _afterSignIn(immediate: false);
      } else {
        state = const AuthState(status: AuthStatus.signedOut);
      }
    }
  }

  Future<void> login(String email, String password) async {
    state = state.copyWith(busy: true, clearError: true);
    try {
      final res = await ref.read(apiClientProvider).post('/auth/login', {
        'email': email.trim(),
        'password': password,
        'deviceName': 'Android',
      });
      await _persistSession(res);
      await _applyPayload(res);
      final user = (res['user'] as Map?) ?? const {};
      state = AuthState(
        status: AuthStatus.signedIn,
        name: user['name']?.toString(),
        email: user['email']?.toString(),
      );
      _afterSignIn();
    } on ApiException catch (e) {
      state = AuthState(status: AuthStatus.signedOut, error: e.message);
    } catch (e) {
      state = AuthState(status: AuthStatus.signedOut, error: 'Gagal masuk: $e');
    }
  }

  Future<void> register(String name, String email, String password) async {
    state = state.copyWith(busy: true, clearError: true);
    try {
      final res = await ref.read(apiClientProvider).post('/auth/register', {
        'name': name.trim(),
        'email': email.trim(),
        'password': password,
        'deviceName': 'Android',
      });
      await _persistSession(res);
      await _applyPayload(res);
      final user = (res['user'] as Map?) ?? const {};
      state = AuthState(
        status: AuthStatus.signedIn,
        name: user['name']?.toString(),
        email: user['email']?.toString(),
      );
      _afterSignIn();
    } on ApiException catch (e) {
      state = AuthState(status: AuthStatus.signedOut, error: e.message);
    } catch (e) {
      state = AuthState(status: AuthStatus.signedOut, error: 'Gagal mendaftar: $e');
    }
  }

  Future<void> logout() async {
    final store = ref.read(sessionStoreProvider);
    final refresh = await store.refreshToken();
    if (refresh != null) {
      try {
        await ref.read(apiClientProvider).post('/auth/logout', {'refreshToken': refresh});
      } catch (_) {
        // Tetap keluar secara lokal meski server tidak terjangkau.
      }
    }
    await _signOutLocal();
  }

  Future<void> updateProfileName(String newName) async {
    final store = ref.read(sessionStoreProvider);
    await store.writeUserName(newName.trim());
    state = state.copyWith(name: newName.trim());
  }

  Future<void> updateProfilePhoto(String photoDataUrl) async {
    final store = ref.read(sessionStoreProvider);
    await store.saveUserProfilePhoto(photoDataUrl);
    state = state.copyWith(userPhoto: photoDataUrl);
  }

  Future<void> forceSignOut() => _signOutLocal();

  Future<void> _signOutLocal() async {
    await ref.read(sessionStoreProvider).clear();
    await ref.read(databaseProvider).wipeLocalData();
    state = const AuthState(status: AuthStatus.signedOut);
  }

  Future<void> _persistSession(Map<String, dynamic> res) async {
    final user = (res['user'] as Map?) ?? const {};
    await ref.read(sessionStoreProvider).saveSession(
          accessToken: res['accessToken'] as String,
          refreshToken: res['refreshToken'] as String,
          userId: user['id']?.toString() ?? '',
          userName: user['name']?.toString() ?? '',
          userEmail: user['email']?.toString() ?? '',
          deviceId: res['deviceId']?.toString(),
        );
  }

  Future<void> _applyPayload(Map<String, dynamic> res) async {
    final db = ref.read(databaseProvider);
    final workspaces = (res['workspaces'] as List?)?.cast<Map>() ?? const [];

    await db.deviceId();

    for (final raw in workspaces) {
      final ws = Map<String, dynamic>.from(raw);
      await db.upsertWorkspaceFromServer(ws);
    }

    final categories = (res['categories'] as List?)?.cast<Map>() ?? const [];
    for (final raw in categories) {
      await db.upsertCategoryFromServer(Map<String, dynamic>.from(raw));
    }

    final wallets = (res['wallets'] as List?)?.cast<Map>() ?? const [];
    for (final raw in wallets) {
      await db.upsertWalletFromServer(Map<String, dynamic>.from(raw));
    }

    if (workspaces.isNotEmpty) {
      ref.invalidate(activeWorkspaceIdProvider);
    }
  }

  void _afterSignIn({bool immediate = true}) {
    final scheduler = ref.read(syncSchedulerProvider);
    if (immediate) {
      scheduler.schedule(delay: const Duration(milliseconds: 300));
    }
  }
}
