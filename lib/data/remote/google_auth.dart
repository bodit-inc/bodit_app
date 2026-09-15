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

import 'dart:io';

import 'package:bodit_app/core/config.dart';
import 'package:bodit_app/core/log.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis_auth/googleapis_auth.dart' as gapis;

/// 앱이 요구하는 스코프.
///
/// `drive.file` 은 **앱이 만든 파일만** 접근한다 — 남의 증빙을 읽거나 지우는 게
/// 원천적으로 불가능하다. 넓히지 않는다(ADR Decision 5).
const googleScopes = <String>['https://www.googleapis.com/auth/drive.file', 'https://www.googleapis.com/auth/spreadsheets'];

class GoogleAuthService {
  GoogleSignInAccount? _account;
  bool _initialized = false;

  GoogleSignInAccount? get account => _account;
  bool get isSignedIn => _account != null;

  /// 앱 시작 시 한 번. 두 번 부르면 플러그인이 예외를 던진다.
  Future<void> ensureInitialized() async {
    if (_initialized) return;
    // Android 는 Credential Manager 를 쓰는데, 거기서 **serverClientId 가 필수**다.
    // 없으면 `clientConfigurationError: serverClientId must be provided on Android`.f
    //
    // 주의: serverClientId 는 Android 클라이언트 ID 가 **아니다.**
    // GCP 콘솔에서 만든 **웹 애플리케이션** 유형 클라이언트 ID 다.
    // Android 클라이언트(패키지명 + SHA-1)는 따로 등록해두되 코드에 넣지 않는다 —
    // 서명으로 매칭되므로 전달할 필요가 없다.
    final serverClientId = Config.googleServerClientId;
    final iosClientId = Config.googleIosClientId;
    if (Platform.isAndroid && serverClientId.isEmpty) {
      throw StateError(
        'GOOGLE_SERVER_CLIENT_ID 가 비어 있습니다.\n'
        'GCP 콘솔에서 "웹 애플리케이션" 유형 OAuth 클라이언트를 만들고 '
        '.env 에 넣은 뒤 build_runner 를 다시 돌리세요.',
      );
    }
    if (Platform.isIOS && iosClientId.isEmpty) {
      throw StateError(
        'GOOGLE_IOS_CLIENT_ID 가 비어 있습니다.\n'
        'GCP 콘솔에서 "iOS" 유형 OAuth 클라이언트(번들 ID co.bodit.boditApp)를 '
        '만들어 .env 에 넣고 build_runner 를 다시 돌리세요.\n'
        '그리고 ios/Runner/Info.plist 의 REPLACE_ME 를 '
        '뒤집은 클라이언트 ID 로 바꿔야 로그인 후 앱으로 돌아옵니다.',
      );
    }

    await GoogleSignIn.instance.initialize(
      // iOS 전용. Android 에서는 무시된다.
      clientId: iosClientId.isEmpty ? null : iosClientId,
      serverClientId: serverClientId.isEmpty ? null : serverClientId,
      // 사내 계정만 계정 선택기에 뜨게 한다. Android 도 지원한다.
      hostedDomain: 'bodit.co',
    );
    _initialized = true;
  }

  /// 조용한 로그인 시도. 앱 재시작 시 먼저 부른다 — 계정 선택기를 안 띄운다.
  ///
  /// **실패는 정상 경로다.** 처음 켠 사용자, 로그아웃한 사용자, 클라이언트 ID 가
  /// 아직 설정되지 않은 상태 모두 여기서 실패한다. 그래서 던지지 않고 null 을
  /// 돌려준다 — 아무도 시도하지 않은 실패를 화면에 띄우면 안 된다.
  ///
  /// 원인은 로그에만 남긴다. 조용히 넘어가되 흔적은 남긴다.
  Future<GoogleSignInAccount?> restore() async {
    try {
      // 타임아웃이 없으면 플랫폼 채널이 안 돌아올 때 인증 상태가 영영 안 정해지고,
      // 그러면 스플래시가 걷히지 않는다. 못 끝내면 로그인 화면으로 보낸다.
      return await _restore().timeout(const Duration(seconds: 8));
    } on Object catch (e) {
      log.i('조용한 로그인 복구 실패 (로그인 화면으로 간다): $e');
      return _account = null;
    }
  }

  Future<GoogleSignInAccount?> _restore() async {
    await ensureInitialized();
    // 반환 타입이 `Future<GoogleSignInAccount?>?` 다 — Future 자체가 널일 수 있다.
    // (플랫폼이 이 기능을 지원하지 않으면 null 을 준다.)
    return _account =
        await GoogleSignIn.instance.attemptLightweightAuthentication();
  }

  /// 사용자가 로그인 버튼을 눌렀을 때. 계정 선택기 → **스코프 동의**까지 한 번에.
  ///
  /// ## 인증(authentication)과 인가(authorization)는 별개다
  ///
  /// v7 에서 갈라진 부분이고, 이걸 놓치면 증상이 아주 헷갈린다.
  ///
  ///   - `authenticate()` = **누구인지**. 이메일과 신원만 준다
  ///   - `authorizeScopes()` = **무엇을 할 수 있는지**. Sheets·Drive 접근권
  ///
  /// `scopeHint` 는 말 그대로 힌트라 플랫폼이 무시할 수 있다. 로그인에 성공해도
  /// 인가는 여전히 없을 수 있고, 그러면 시트 읽기가 조용히 null 을 돌려준다.
  ///
  /// 그래서 **로그인 버튼 안에서 인가까지 받아둔다.** 여기가 사용자 조작
  /// 핸들러라 동의 화면을 띄울 수 있는 자리이기도 하다. 나중에 비목 목록을
  /// 불러오다가 갑자기 동의 화면이 뜨는 것보다 낫다.
  Future<GoogleSignInAccount> signIn() async {
    await ensureInitialized();
    _account = await GoogleSignIn.instance.authenticate(
      scopeHint: googleScopes,
    );

    // 인가는 실패해도 로그인 자체는 살린다 — 사용자가 동의를 거부했을 수 있다.
    // 그때는 시트를 쓰는 시점에 다시 요청한다.
    try {
      await authorizedClient();
    } on Object catch (e) {
      log.w('로그인은 됐지만 스코프 인가를 못 받았다: $e');
    }
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
