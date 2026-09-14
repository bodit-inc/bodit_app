/// Google 로그인 + googleapis 용 인증 클라이언트.
///
/// ## 함정 ① — v7 은 인증(authentication)과 인가(authorization)가 분리됐다
///
/// v6 의 `signIn()` 하나로 끝나던 흐름이 없어졌다. v7 은:
///   1. `GoogleSignIn.instance` 싱글턴 (`GoogleSignIn()` 생성 불가)
///   2. `initialize()` 를 **딱 한 번** await
///   3. `authenticate()` 로 로그인 — 이건 "누구인가" 만 준다
///   4. 스코프 인가는 **따로** — `authorizationForScopes` / `authorizeScopes`
///
/// ## 함정 ①-b — `authorizationHeaders()` 로 직접 클라이언트를 만들지 마라
///
/// flutter/flutter#173407 이 정확히 그걸 하다가
/// `403 Method doesn't allow unregistered callers` 를 맞았고 "not planned" 로 닫혔다.
/// 공식 다리인 `extension_google_sign_in_as_googleapis_auth` 의 `authClient()` 를 쓴다.
///
/// ## 함정 ①-c — AuthClient 를 캐싱하지 마라  ★ 이게 제일 조용히 물린다
///
/// 다리 패키지 소스를 보면 만료 시각을 **임의로 365일 뒤**로 박고
/// refresh token 은 `null` 로 둔다 (SDK 가 둘 다 안 알려줘서 어쩔 수 없다).
/// 즉 이 클라이언트는 **토큰이 만료돼도 스스로 갱신하지 않고, 만료된 줄도 모른다.**
/// 오래 들고 있으면 어느 순간부터 조용히 401 이 난다.
/// → 매 작업마다 `authorizedClient` 를 새로 얻는다.
library;

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis_auth/googleapis_auth.dart' as gapis;


/// 앱이 요구하는 스코프.
///
/// `drive.file` 은 **앱이 만든 파일만** 접근한다 — 남의 증빙을 읽거나 지우는 게
/// 원천적으로 불가능하다. 넓히지 않는다(ADR Decision 5).
const googleScopes = <String>[
  'https://www.googleapis.com/auth/drive.file',
  'https://www.googleapis.com/auth/spreadsheets',
];

class GoogleAuthService {
  GoogleSignInAccount? _account;
  bool _initialized = false;

  GoogleSignInAccount? get account => _account;
  bool get isSignedIn => _account != null;

  /// 앱 시작 시 한 번. 두 번 부르면 플러그인이 예외를 던진다.
  Future<void> ensureInitialized() async {
    if (_initialized) return;
    await GoogleSignIn.instance.initialize(
      // 사내 계정만 계정 선택기에 뜨게 한다.
      hostedDomain: 'bodit.co',
      // TODO(james): iOS 는 clientId, Android 는 serverClientId 를 콘솔에서 발급 후 주입.
      //   envied 로 컴파일 타임 주입 예정 — 지금은 플랫폼 설정 파일에서 읽힌다.
    );
    _initialized = true;
  }

  /// 조용한 로그인 시도. 앱 재시작 시 먼저 부른다 — 계정 선택기를 안 띄운다.
  Future<GoogleSignInAccount?> restore() async {
    await ensureInitialized();
    // 반환 타입이 `Future<GoogleSignInAccount?>?` 다 — Future 자체가 널일 수 있다.
    // (플랫폼이 이 기능을 지원하지 않으면 null 을 준다.)
    return _account =
        await GoogleSignIn.instance.attemptLightweightAuthentication();
  }

  /// 사용자가 로그인 버튼을 눌렀을 때. 계정 선택기를 띄운다.
  Future<GoogleSignInAccount> signIn() async {
    await ensureInitialized();
    _account = await GoogleSignIn.instance.authenticate(
      // 힌트일 뿐이다 — 플랫폼에 따라 무시된다. 인가는 따로 받아야 한다.
      scopeHint: googleScopes,
    );
    return _account!;
  }

  Future<void> signOut() async {
    await GoogleSignIn.instance.signOut();
    _account = null;
  }

  /// Sheets·Drive 호출 직전에 부른다. **결과를 필드에 저장하지 마라** (함정 ①-c).
  ///
  /// [interactive] 가 false 면 이미 인가된 경우에만 클라이언트를 준다.
  /// 백그라운드 갱신처럼 사용자 제스처가 없는 자리에서 쓴다.
  Future<gapis.AuthClient?> authorizedClient({bool interactive = true}) async {
    final acc = _account;
    if (acc == null) return null;

    final client = acc.authorizationClient;
    final authz = await client.authorizationForScopes(googleScopes);

    if (authz != null) return authz.authClient(scopes: googleScopes);

    // 아직 인가를 안 받았으면 여기서 동의 화면이 뜬다.
    // 반드시 **사용자 조작 핸들러 안**에서 불러야 한다.
    if (!interactive) return null;
    final granted = await client.authorizeScopes(googleScopes);
    return granted.authClient(scopes: googleScopes);
  }
}
