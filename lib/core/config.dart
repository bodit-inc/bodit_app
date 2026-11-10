/// 외부 자원 ID 와 자격증명. **환경(flavor)에 따라 두 벌 중 하나를 고른다.**
///
/// ## 왜 두 벌인가
///
/// 제출은 Sheets 에 **append 만** 하고 수정·삭제하지 않는다(ADR). 그래서
/// 운영 시트에 들어간 잘못된 행은 앱으로 못 지운다 — "동작하는지 확인" 하는
/// 일이 곧 운영 데이터를 더럽히는 일이었다. Slack·드라이브도 같다.
/// 확인용으로 쓸 **별도의 시트·폴더·Slack 앱**이 필요하다.
///
/// ## 구조
///
/// 값 자체는 `core/env/env_dev.dart` · `env_prod.dart` 가 각각 `.env.dev` ·
/// `.env.prod` 에서 굽는다. 이 클래스는 **그중 하나를 고르는 창구**다.
/// 호출하는 쪽은 환경을 모른다 — `Config.spreadsheetId` 하나만 읽는다.
///
/// 어느 쪽을 고르는지는 `core/flavor.dart` 가 컴파일 상수로 정한다.
/// 두 바이너리에 두 벌이 **같이 들어간다** — 아래 "보안이 아니다" 참고.
///
/// ## 여기 들어가는 값은 보안이 아니다
///
/// `envied` 는 상수를 난독화해서 apk 를 unzip 하고 `strings` 를 돌려도 안 나오게
/// 할 뿐이다. **런타임에는 평문으로 헤더에 실려 나가므로 프록시로 잡힌다.**
/// ADR 에서 이미 알고 감수한 사항이고(전 직원 배포 = APK 추출 가능),
/// 실질 방어선은 다음 둘이다:
///
///   - Anthropic: **콘솔 지출 한도**
///   - Slack: scope 를 `chat:write` · `files:write` · `files:read` 로만 좁히기
///
/// 두 벌이 **한 바이너리에 같이 들어간다** — 운영 빌드 안에 개발 토큰이,
/// 개발 빌드 안에 운영 토큰이 있다. 새로운 노출은 아니다: 개발 빌드는
/// 배포하지 않고 내 기기에서만 돌고, 운영 빌드에 더 들어가는 것은 개발용
/// 토큰뿐이다(그 토큰으로 닿을 수 있는 곳이 개발 시트·채널이다).
///
/// 환경별로 바이너리에서 빼내려면 빌드마다 build_runner 를 다시 돌려 `.env` 를
/// 갈아끼워야 하는데, 그러면 "지금 뭐가 구워져 있는지" 를 아무도 모르게 된다.
///
/// ## 빌드 방법
///
/// ```sh
/// cp .env.dev.example .env.dev && cp .env.prod.example .env.prod  # 값 채우기
/// make gen        # build_runner — 두 환경을 같이 생성한다
/// make run-dev    # 개발 환경으로 실행
/// ```
library;

import 'package:bodit_app/core/env/env_dev.dart';
import 'package:bodit_app/core/env/env_prod.dart';
import 'package:bodit_app/core/flavor.dart';

/// 환경에 맞는 설정값. 호출부는 환경을 몰라도 된다.
abstract final class Config {
  /// OCR 전용. 다른 용도는 없다.
  ///
  /// 개발·운영을 **다른 키로** 두면 콘솔에서 지출이 갈려 보인다 — 테스트하다
  /// 한도를 태워도 운영이 멈추지 않는다. 같은 키를 양쪽에 넣어도 동작은 한다.
  static String get anthropicApiKey =>
      _pick(EnvDev.anthropicApiKey, EnvProd.anthropicApiKey);

  /// scope 는 `chat:write` · `files:write` · `files:read` 셋만. 넓히지 않는다.
  /// (`files:read` 는 제출 목록에서 그 메시지로 보내는 permalink 용이다.)
  ///
  /// **개발용은 별도의 Slack 앱이다.** 같은 앱의 토큰으로 채널만 바꾸면
  /// 운영 채널에 쓸 권한이 그대로 남아, 채널 ID 한 글자 실수로 운영에 글이 간다.
  static String get slackBotToken =>
      _pick(EnvDev.slackBotToken, EnvProd.slackBotToken);

  static String get slackChannelId =>
      _pick(EnvDev.slackChannelId, EnvProd.slackChannelId);

  /// 이메일 → Slack user id. `email:ID` 를 쉼표로 잇는다.
  ///
  /// **왜 API 조회가 아닌가** — `users.lookupByEmail` 은 Slack 계정에 적힌
  /// 이메일로만 찾는데, 회사 이메일과 다른 사람이 실제로 있다(개인 Gmail 로
  /// 가입). 그 사람은 조회로는 영원히 못 찾고 이메일 글자로 떨어진다.
  /// 사내 매핑은 사람이 연결해둔 것이라 그 경우를 덮는다.
  ///
  /// **왜 코드가 아닌 `.env` 인가** — 이 레포는 공개돼 있다. 코드에 박으면
  /// 사내 전원의 이메일과 Slack ID 명단이 그대로 공개된다.
  ///
  /// 비어 있어도 빌드된다(멘션 없이 이메일 글자가 들어간다).
  ///
  /// user id 는 **워크스페이스 단위**라 Slack 앱을 새로 만들어도 그대로다 —
  /// 개발·운영에 같은 값을 넣으면 된다.
  static String get slackUserIds =>
      _pick(EnvDev.slackUserIds, EnvProd.slackUserIds);

  /// 매입내역 스프레드시트.
  ///
  /// 개발용은 운영 시트의 **사본**이어야 한다 — 수식 컬럼(해당년도·해당월·
  /// 분류명)과 `_비목마스터`·`_분류마스터` 탭이 없으면 앱이 거기서 멈춘다.
  static String get spreadsheetId =>
      _pick(EnvDev.spreadsheetId, EnvProd.spreadsheetId);

  /// 카드보유내역 스프레드시트. **매입내역과 다른 파일이다** —
  /// 운영팀이 따로 관리하고 우리 계정으로는 보기 전용이다.
  ///
  /// 스코프를 넓힐 필요는 없다. `spreadsheets` 는 특정 파일이 아니라
  /// **사용자가 열 수 있는 모든 스프레드시트**에 걸리므로 이미 덮는다.
  ///
  /// 앱이 **읽기만** 하므로 개발에서도 운영과 같은 파일을 써도 된다. 사본을
  /// 두면 카드가 추가될 때 한쪽만 갱신돼 "개발에서는 분류가 안 잡힌다" 가 된다.
  static String get cardSheetId =>
      _pick(EnvDev.cardSheetId, EnvProd.cardSheetId);

  /// 증빙을 모아두는 공유 드라이브 폴더.
  /// `drive.file` scope 로는 폴더를 검색할 수 없어서 ID 를 박아둔다.
  static String get driveFolderId =>
      _pick(EnvDev.driveFolderId, EnvProd.driveFolderId);

  /// iOS 용 OAuth 클라이언트. **번들 ID 로 매칭되므로 환경마다 다르다** —
  /// 개발 빌드는 `co.bodit.boditApp.dev` 로 깔리니 그 번들 ID 로 만든
  /// 클라이언트가 따로 필요하다.
  static String get googleIosClientId =>
      _pick(EnvDev.googleIosClientId, EnvProd.googleIosClientId);

  /// Android 가 Credential Manager 에 넘기는 **웹** 클라이언트 ID.
  ///
  /// 이건 패키지명과 무관해서 개발·운영이 같은 값을 써도 된다. 다만 GCP 에
  /// Android 클라이언트(`co.bodit.bodit_app.dev` + SHA-1)를 **따로 등록**해야
  /// 개발 빌드에서 로그인이 통과한다.
  static String get googleServerClientId =>
      _pick(EnvDev.googleServerClientId, EnvProd.googleServerClientId);

  // ── Firebase (Remote Config 전용) ──────────────────────────────────
  //
  // **용도가 하나다** — 새 버전이 올라왔는지 묻는 것(`AppUpdateService`).
  // Analytics·Crashlytics·푸시를 붙이는 일이 생기면 이 줄부터 고친다.
  // Anthropic 키의 "셋째 용도를 늘리지 않는다" 와 같은 규칙이다.
  //
  // ## 왜 `google-services.json`·`GoogleService-Info.plist` 가 아닌가
  //
  // 그 두 파일은 `.gitignore` 에 걸려 있다(이 레포는 공개돼 있다). 그러면
  // 받은 사람 쪽에서 빌드가 깨지고, flavor 마다 다른 파일을 Xcode 빌드
  // 단계에서 골라 복사하는 장치를 하나 더 만들어야 한다.
  //
  // 대신 Dart 에서 `Firebase.initializeApp(options:)` 로 넘긴다 — 두 파일에
  // 적힌 값과 같은 것이고, Remote Config 는 그걸로 충분하다. 환경 분리도
  // 이미 있는 장치(`.env.dev`·`.env.prod`)를 그대로 쓴다.
  //
  // ## 왜 `ensureConfigured()` 가 막지 않나
  //
  // 비어 있으면 **업데이트 안내만 안 뜨고 앱은 돈다**(`AppUpdateService` 가
  // 조용히 건너뛴다). 시트·Slack 설정이 비면 제출이 깨지니 앱을 세우는 게
  // 맞지만, 이건 보여주는 기능이다 — 못 물어봤다고 앱을 못 쓰게 만들 이유가
  // 없다. `AppInfo.load()` 가 실패해도 안 던지는 것과 같은 이유다.

  /// Firebase 프로젝트 ID. 콘솔 → 프로젝트 설정 → 일반.
  static String get firebaseProjectId =>
      _pick(EnvDev.firebaseProjectId, EnvProd.firebaseProjectId);

  /// 프로젝트 번호(= `messagingSenderId`). 같은 프로젝트면 개발·운영이 같다.
  static String get firebaseProjectNumber =>
      _pick(EnvDev.firebaseProjectNumber, EnvProd.firebaseProjectNumber);

  /// iOS 앱의 API 키. **플랫폼마다 다른 키가 자동으로 만들어진다** —
  /// 콘솔이 내려주는 `GoogleService-Info.plist` 의 `API_KEY` 다.
  static String get firebaseApiKeyIos =>
      _pick(EnvDev.firebaseApiKeyIos, EnvProd.firebaseApiKeyIos);

  /// iOS 앱 ID(`1:123...:ios:abc`). 번들 ID 로 등록된 그 앱이다 —
  /// 개발은 `co.bodit.boditApp.dev` 로 **따로 등록**해야 한다.
  static String get firebaseAppIdIos =>
      _pick(EnvDev.firebaseAppIdIos, EnvProd.firebaseAppIdIos);

  /// Android 앱의 API 키. `google-services.json` 의 `current_key` 다.
  static String get firebaseApiKeyAndroid =>
      _pick(EnvDev.firebaseApiKeyAndroid, EnvProd.firebaseApiKeyAndroid);

  /// Android 앱 ID(`1:123...:android:abc`).
  /// 개발은 패키지명 `co.bodit.bodit_app.dev` 로 따로 등록한다.
  static String get firebaseAppIdAndroid =>
      _pick(EnvDev.firebaseAppIdAndroid, EnvProd.firebaseAppIdAndroid);

  /// 환경에 맞는 쪽을 고른다. 분기를 한 군데로 모아 빠뜨릴 수 없게 한다.
  static String _pick(String dev, String prod) => switch (flavor) {
    AppFlavor.dev => dev,
    AppFlavor.prod => prod,
  };

  /// `.env.*.example` 의 자리값이 그대로 남아 있는지 본다.
  ///
  /// ## 왜 필요한가
  ///
  /// `envied` 는 값이 **비어 있으면** 빌드를 거부하지만, `REPLACE_ME` 처럼
  /// 뭐라도 적혀 있으면 그대로 굽는다. 그러면 빌드는 통과하고 앱도 뜨는데
  /// 첫 API 호출에서 404·401 이 난다 — 설정을 안 채운 것인지 권한 문제인지
  /// 화면에서는 구분이 안 된다.
  ///
  /// 그래서 `main()` 에서 한 번 보고 **왜 안 되는지 말하고 죽는다.**
  /// (운영 빌드는 `make build-prod` 가 `.env.prod` 를 미리 한 번 더 막는다.)
  static void ensureConfigured() {
    // 선택값은 뺀다 — `slackUserIds` 는 비어도 동작하고(멘션 없이 이메일 글자),
    // google 클라이언트 ID 는 플랫폼별이라 `GoogleAuthService` 가 따로 본다.
    final missing = <String>[
      if (_isPlaceholder(anthropicApiKey)) 'ANTHROPIC_API_KEY',
      if (_isPlaceholder(slackBotToken)) 'SLACK_BOT_TOKEN',
      if (_isPlaceholder(slackChannelId)) 'SLACK_CHANNEL_ID',
      if (_isPlaceholder(spreadsheetId)) 'SPREADSHEET_ID',
      if (_isPlaceholder(cardSheetId)) 'CARD_SHEET_ID',
      if (_isPlaceholder(driveFolderId)) 'DRIVE_FOLDER_ID',
    ];
    if (missing.isEmpty) return;
    final file = switch (flavor) {
      AppFlavor.dev => '.env.dev',
      AppFlavor.prod => '.env.prod',
    };
    throw StateError(
      '$file 에 아직 채우지 않은 값이 있습니다 (${flavor.label} 환경):\n'
      '  ${missing.join(', ')}\n'
      '값을 넣고 `make gen` 을 다시 돌리세요.',
    );
  }

  static bool _isPlaceholder(String v) => v.isEmpty || v == placeholder;

  /// 예제 파일이 쓰는 자리값. `Makefile` 의 검사와 같은 글자를 쓴다.
  static const placeholder = 'REPLACE_ME';
}
