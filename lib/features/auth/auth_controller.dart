import 'package:bodit_app/data/remote/google_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

final googleAuthProvider = Provider<GoogleAuthService>((ref) {
  return GoogleAuthService();
});

/// 로그인 상태. null 이면 로그아웃.
class AuthController extends AsyncNotifier<GoogleSignInAccount?> {
  GoogleAuthService get _svc => ref.read(googleAuthProvider);

  @override
  Future<GoogleSignInAccount?> build() async {
    // 앱 시작 시 계정 선택기를 띄우지 않고 조용히 복구를 시도한다.
    return await _svc.restore();
  }

  Future<void> signIn() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_svc.signIn);
  }

  Future<void> signOut() async {
    await _svc.signOut();
    state = const AsyncData(null);
  }
}

final authControllerProvider =
    AsyncNotifierProvider<AuthController, GoogleSignInAccount?>(
  AuthController.new,
);
