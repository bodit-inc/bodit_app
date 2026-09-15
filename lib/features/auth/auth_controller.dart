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
  // Riverpod 3 은 실패한 provider 를 기본으로 자동 재시도한다
  // (200ms 부터 2배씩, 최대 10회 · 6.4초). 그런데 여기서 나는 실패는
  // 설정 누락이나 로그인 거부라 **재시도해도 절대 성공하지 않는다.**
  // 켜두면 로그인 화면이 몇 초 동안 스피너를 돌리다 버튼을 보여준다.
  retry: (retryCount, error) => null,
);
