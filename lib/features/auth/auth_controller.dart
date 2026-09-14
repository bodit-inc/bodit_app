import 'package:bodit_app/data/providers.dart';
import 'package:bodit_app/data/remote/google_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// 로그인 상태. null 이면 로그아웃.
///
/// `GoogleAuthService` 자체는 `data` 계층 소유다(`googleAuthProvider`).
/// 저장소들이 전부 그걸 쓰므로 화면 기능에 두면 의존 방향이 거꾸로 된다.
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
