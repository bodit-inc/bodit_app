# bodit_app

사내 매입내역 자동완성 앱 (Flutter · 모바일 전용)

증빙(영수증·카드 앱 캡처)을 올리면 OCR 과 과거 이력으로 매입내역 폼을 프리필하고,
제출하면 **세 곳에 동시에** 올린다 — Sheets(매입내역 행) · Drive(증빙 파일) ·
Slack(내용 + 사진). 백엔드가 없고 앱이 외부 API 를 직접 호출한다.

## 설계 문서는 이 repo 에 없다

**설계·결정·스키마의 단일 원천은 개인 LLM wiki 다.** 이 repo 는 코드만 갖는다 —
문서를 양쪽에 두면 두 벌이 갈라진다.

- 코드를 고칠 때 지켜야 하는 제약: [`CLAUDE.md`](CLAUDE.md)
- 구조 결정(ADR) · 시트 컬럼 계약 · 태스크: 위키 (`CLAUDE.md` 상단 표에 경로)
- 화면 시안 13장: [`docs/mockup/`](docs/mockup/) — `python3 docs/mockup/build.py` 로 재생성

`CLAUDE.md` 를 먼저 읽는 쪽이 빠르다. append-only 시트, 부가세 자동계산 금지,
`core/widgets` 조립 규약 같은 것들이 **테스트로 집행**되고 있어서, 모르고 고치면
`flutter test` 가 막는다.

## 받고 나서 빌드까지

생성 코드(`*.g.dart` · `*.freezed.dart`)를 커밋하지 않는다. 받은 뒤 한 번 만들어야 한다.

```bash
# 1. Flutter 버전 (.fvmrc 에 핀이 박혀 있다)
fvm install && fvm use

# 2. 의존성
fvm flutter pub get

# 3. 환경 변수 — 두 벌이다. 값은 아래 표를 보고 채운다
cp .env.dev.example .env.dev && $EDITOR .env.dev
cp .env.prod.example .env.prod && $EDITOR .env.prod

# 4. 생성 코드 (envied · freezed · drift · riverpod)
make gen

# 5. 실행 — 환경을 반드시 고른다
make run-dev     # 개발용 시트·드라이브·Slack
make run-prod    # 운영 (실제 매입내역이 올라간다)
```

**`.env.prod` 도 있어야 빌드가 된다.** 운영 값이 아직 없으면 예제의
`REPLACE_ME` 를 그대로 두면 된다 — 개발 빌드는 그대로 돌아가고, 운영 빌드는
`make` 가 거부한다.

`.env.*` 를 고친 뒤 `wrote 0 outputs` 가 나오면 [`build.yaml`](build.yaml) 주석을 읽는다 —
envied 가 `.env.*` 를 build_runner 그래프 밖에서 읽기 때문에 생기는 함정이고, 거기
대처가 적혀 있다.

## 개발 환경과 운영 환경

앱은 Sheets 에 **append 만** 한다 — 잘못 들어간 행을 앱으로 지울 수 없다.
그래서 "동작하는지 확인" 하는 일이 곧 운영 데이터를 더럽히는 일이었다.
확인은 개발 환경에서 한다.

|  | 개발(dev) | 운영(prod) |
|---|---|---|
| 쓰임 | 내 기기에서 debug 로만. **배포하지 않는다** | 스토어 · Firebase 에 등록된 그 앱 |
| 설정 | `.env.dev` — 원래 쓰던 시트·드라이브 + **새 Slack 앱** | `.env.prod` — **새 시트·드라이브** + 원래 쓰던 Slack 앱 |
| iOS 번들 ID | `co.bodit.boditApp.dev` | `co.bodit.boditApp` (변경 없음) |
| Android applicationId | `co.bodit.bodit_app.dev` | `co.bodit.bodit_app` (변경 없음) |
| 앱 이름 | `Bodit_dev` | `Bodit App` / `bodit_app` (변경 없음) |
| 아이콘 | 로고 아래 주황 `dev` 띠 | 변경 없음 |
| 화면 | 우상단 `DEV` 리본 + 홈 안내 배너 | 변경 없음 |

운영 쪽 **번들 ID·이름·아이콘은 바뀌지 않았다.** 개발만 덧붙였다.
`--flavor` 없이 빌드하던 기존 경로(Xcode 의 `Runner` 스킴)도 그대로 동작한다.

다만 **가리키는 곳은 자리를 바꿨다.** 원래 쓰던 매입내역 시트·증빙 폴더가
개발 쪽으로 가고, 운영은 새로 만든 것을 본다. 그래서 이미 배포된 빌드는 지금
개발 시트·폴더를 보고 있는 셈이다 — 새로 빌드해 올려야 갈라진다.

**Slack 만 반대다.** 원래 쓰던 앱이 운영에 남고 개발이 새 앱을 받는다.
시트·폴더는 사본을 떠도 그만이지만 Slack 앱은 워크스페이스에 설치하고 채널에
초대하는 과정이 따로 있다. 원래 앱을 개발로 내리면 **실제 제출이 가는 쪽이
한 번도 안 써본 새 앱**이 된다 — 검증된 쪽을 운영에 두는 게 맞다.

고르는 방법은 플래그 둘이다 — `--flavor` 는 네이티브(번들 ID·이름·아이콘),
`--dart-define=FLAVOR` 는 Dart(시트·드라이브·Slack). **둘이 엇갈리면
"Bodit_dev" 라고 적힌 앱이 운영 시트에 쓴다.** 그래서 손으로 적지 말고
[`Makefile`](Makefile) 의 타깃을 쓴다 (`make help`).

빠뜨렸을 때는 조용히 넘어가지 않는다:

- `--dart-define=FLAVOR` 가 없으면 `main()` 이 **앱을 띄우기 전에** 던진다
- `.env.*` 에 `REPLACE_ME` 가 남아 있으면 같은 자리에서 어느 키인지 말하고 던진다
- `make *-prod` 는 `.env.prod` 에 자리값이 남아 있으면 빌드를 거부한다

개발 아이콘은 운영 아이콘에서 만든다 — 운영 아이콘을 바꿨으면 `make icons`
([`tool/make_dev_icons.py`](tool/make_dev_icons.py)).

## .env 값 15개가 어디서 오는가

값은 여기 적지 않는다 — **이 repo 는 공개되어 있다.** 받는 곳만 적는다.
개발·운영이 **같아도 되는 값**과 **달라야 하는 값**이 갈린다.

| 키 | 어디서 | 개발 ↔ 운영 |
|---|---|---|
| `ANTHROPIC_API_KEY` | Anthropic 콘솔 | 같아도 됨. **용도는 OCR 하나뿐** — 지출 한도 없이 발급하지 않는다 (#4). 나누면 콘솔에서 지출이 갈려 보인다 |
| `SLACK_BOT_TOKEN` | Slack 앱 | **달라야 함.** 원래 앱이 운영, **새로 만든 앱이 개발** (시트·드라이브와 방향이 반대다). 같은 토큰이면 채널 ID 한 글자 실수로 실사용 채널에 글이 간다. scope 는 `chat:write` · `files:write` · `files:read` 셋만 |
| `SLACK_CHANNEL_ID` | 게시할 채널 | **달라야 함.** 개발은 테스트 채널, 운영은 실사용 채널. 각 환경의 봇이 그 채널에 들어가 있어야 한다 |
| `SLACK_USER_IDS` | 사내 Slack 매핑 | 같아도 됨 — user id 는 워크스페이스 단위라 앱을 새로 만들어도 그대로다. `email:ID` 를 쉼표로. **이건 바닥일 뿐이다** — 최신 명단은 Remote Config 에 있다(아래 "Slack 멘션 매핑"). 입사자 때문에 이 줄을 고칠 필요는 없다 |
| `SPREADSHEET_ID` | 매입내역 스프레드시트 | **달라야 함.** 원래 시트가 개발, **새 시트가 운영**. 새 시트에 과거 이력을 같이 옮긴다 — 비목 추천이 과거 행을 읽어서 나오므로 빈 시트로 시작하면 한동안 추천이 안 뜬다. 수식 컬럼과 `_비목마스터`·`_분류마스터` 탭도 같이 |
| `CARD_SHEET_ID` | 카드보유내역 스프레드시트 | 같아도 됨 — 앱이 **읽기만** 한다. 사본을 두면 카드가 늘 때 한쪽만 낡는다 |
| `DRIVE_FOLDER_ID` | 증빙 공유 드라이브 폴더 | **달라야 함.** 원래 폴더가 개발, **새 폴더가 운영**. 섞이면 회계 담당자가 테스트 파일을 보게 된다 |
| `GOOGLE_IOS_CLIENT_ID` | Google Cloud OAuth 클라이언트 | **달라야 함** — 클라이언트는 번들 ID 로 매칭되고 개발은 `co.bodit.boditApp.dev` 다. **배포 여부와 무관하다**: 내 기기 debug 빌드도 번들 ID 가 다르면 로그인이 거부된다. 뒤집은 값을 [`ios/Flutter/Dev.xcconfig`](ios/Flutter/Dev.xcconfig) 에도 넣는다 |
| `GOOGLE_SERVER_CLIENT_ID` | Google Cloud OAuth 클라이언트 | 같아도 됨(웹 클라이언트라 패키지명과 무관). 단 GCP 에 Android 클라이언트 `co.bodit.bodit_app.dev` + SHA-1 을 따로 등록해야 개발 빌드에서 로그인이 통과한다 |
| `FIREBASE_PROJECT_ID` · `FIREBASE_PROJECT_NUMBER` | Firebase 콘솔 → 프로젝트 설정 | 같아도 됨 — 개발·운영 앱이 **한 프로젝트** 안에 있다 |
| `FIREBASE_APP_ID_IOS` · `FIREBASE_APP_ID_ANDROID` | 그 프로젝트의 앱 (`GoogleService-Info.plist` 의 `GOOGLE_APP_ID` · `google-services.json` 의 `mobilesdk_app_id`) | **달라야 함** — 번들 ID·패키지명으로 등록되므로 개발(`.dev`)은 따로 등록한 앱이다. 구글 OAuth 클라이언트와 같은 이유다 |
| `FIREBASE_API_KEY_IOS` · `FIREBASE_API_KEY_ANDROID` | 같은 파일의 `API_KEY` · `current_key` | 같아도 됨 — **키는 앱이 아니라 플랫폼 단위**다. 개발 앱을 등록해도 같은 iOS/Android 키가 내려온다. 앱을 가르는 것은 앱 ID 쪽이다 |

**Firebase 값 6개는 비어 있어도 된다.** 그러면 업데이트 안내만 안 뜨고 앱은
그대로 돈다(`make *-prod` 도 막지 않는다). 용도는 **새 버전 알림 하나**다 —
아래 "업데이트 알림" 참조.

`envied` 는 **난독화일 뿐 보안이 아니다.** 런타임에는 평문으로 헤더에 실려 나간다.
실질 방어선은 Anthropic 지출 한도와 Slack 의 좁은 scope 두 개다
([`lib/core/config.dart`](lib/core/config.dart) 주석).

## 원격 설정 (Firebase Remote Config)

**콘솔에서 고치면 재배포 없이 바뀌는 값**이 여기 있다. 조회는 앱이 켜질 때
한 번이고([`remote_config.dart`](lib/data/remote/remote_config.dart)) 소비자가
둘이다 — 업데이트 안내와 **Slack 멘션 매핑**(아래 "입사자가 생겼을 때").

### 업데이트 알림

배포가 TestFlight(iOS)·Firebase App Distribution(Android)으로 나간다.
둘 다 **올린 쪽은 알지만 깔린 쪽은 모른다.** 그래서 앱이 켜질 때 Remote Config
에 "최신이 몇이냐" 를 묻고, 자기 버전(`pubspec.yaml` → `package_info_plus`)과
비교한다. 새 빌드를 올린 뒤 **콘솔에서 값 한 줄만 고치면** 전원에게 전달된다.

| 파라미터 | 값 | 없으면 |
|---|---|---|
| `latest_version` | `1.0.1+6` — 방금 올린 빌드 | 안내하지 않는다 |
| `minimum_version` | 이 밑은 **못 쓴다.** 평소에는 **비워둔다** | 아무도 막히지 않는다 |
| `update_message` | 안내에 같이 띄울 한 줄 (무엇이 바뀌었는지) | 기본 문구 |
| `update_url_ios` | 공개 링크가 있으면 그것 | **TestFlight 앱이 열린다**(`itms-beta://` 폴백) |
| `update_url_android` | App Distribution 링크 | 버튼이 "받는 곳 링크가 없다" 고 말한다 |

- 비교는 **빌드 번호까지** 본다 — `1.0.0+5` → `1.0.0+6` 도 새 버전이다
  ([`lib/core/version.dart`](lib/core/version.dart))
- `latest_version` 이 높으면 **홈에서 다이얼로그**를 띄운다. 같은 버전은 하루
  한 번만 묻는다 — 켤 때마다 뜨면 [나중에] 를 반사적으로 누르게 된다
- `minimum_version` 에 걸리면 **화면을 통째로 막는다**([`update_required_screen.dart`](lib/features/update/update_required_screen.dart)).
  시트가 append-only 라 잘못 쓰는 버전을 즉시 세울 길이 하나는 있어야 해서다.
  **쓸 일이 거의 없는 값이니 비워둔다**
- 읽을 수 없는 값(오타·`1.0.0-rc1`)은 **없는 것으로 친다** — 콘솔 오타 하나로
  전원이 막히는 쪽이 훨씬 나쁘다
- 조회가 실패하면(비행기 모드·`.env` 미입력) 조용히 넘어간다. 앱은 그대로 돈다
- **iOS 는 `update_url_ios` 를 비워둬도 된다** — TestFlight 앱이 열린다. 앱 안의
  우리 앱 페이지로 바로 가는 링크는 **외부 테스터 그룹의 공개 링크**뿐인데
  (빌드마다 베타 심사) 사내 배포는 내부 그룹이라 그게 없다. 나중에 생기면
  콘솔에 넣기만 하면 그쪽이 이긴다

**개발 빌드가 같이 막히는 것을 피하려면** 콘솔에서 `minimum_version` 에
"앱이 운영일 때" 조건을 건다 — 개발 앱이 Firebase 에 따로 등록돼 있어서
(`.dev` 번들·패키지) 조건으로 가를 수 있다.

### Slack 멘션 매핑

| 파라미터 | 값 | 없으면 |
|---|---|---|
| `slack_user_ids` | `email:ID` 를 쉼표로 이은 명단 | `.env` 에 구워진 명단을 쓴다 |

제출 글의 제출자 줄을 **멘션**으로 적는 데 쓴다. 매핑에 없는 사람은 이메일
글자로 떨어진다(알림이 안 가고 프로필로 못 간다).

- **명단이 두 겹이다.** `.env` 의 `SLACK_USER_IDS` 가 빌드에 구워진 바닥이고,
  `slack_user_ids` 가 그 위에 얹혀 **겹치면 이긴다.** 그래서 콘솔에는
  **달라진 사람만** 적으면 되고 전체 명단을 옮겨 적지 않아도 된다
- **지울 수는 없다** — 덧붙이는 것이라서다. 퇴사자는 `.env` 에서 지우고 다음
  배포를 기다린다(비활성 계정은 멘션이 회색 이름으로 뜰 뿐이라 급하지 않다)
- 운영은 캐시가 한 시간이다 — 콘솔에 적고 **앱을 다시 켠 뒤 최대 한 시간**
  안에 붙는다. 개발 빌드는 캐시가 없어 바로 보인다
- 로그에는 **명단을 찍지 않고 인원 수만** 남긴다. 사내 전원의 이메일과
  Slack ID 라 기기 로그로 흘릴 값이 아니다

## 입사자가 생겼을 때

앱이 요구하는 Google 스코프는 `drive.file` · `spreadsheets` **둘뿐**이고
([`google_auth.dart`](lib/data/remote/google_auth.dart)) 사람마다 승인하는 게
아니라 앱 단위다. 그래서 할 일은 **권한 공유와 명단**이다.

| 할 일 | 어디 | 안 하면 |
|---|---|---|
| bodit.co 구글 계정 | — | 계정 선택기에 안 뜬다(`hostedDomain`) |
| OAuth 동의 화면이 "외부 + 테스트 중" 이면 **테스트 사용자**에 추가 | GCP 콘솔 | 로그인이 거부된다 (내부면 할 일 없음) |
| 매입내역 시트 **편집** 권한 | `SPREADSHEET_ID` | 제출이 막힌다 |
| 카드보유내역 시트 **보기** 권한 | `CARD_SHEET_ID` | 분류 추천이 전부 "못 찾았다" 가 된다 |
| 증빙 폴더 **편집** 권한 | `DRIVE_FOLDER_ID` | Drive 업로드만 403 으로 실패한다 |
| `slack_user_ids` 에 `email:ID` 한 줄 | Remote Config 콘솔 | 제출자 줄이 멘션이 아니라 이메일 글자가 된다 |
| 테스터 등록 | TestFlight · App Distribution | 앱을 받을 수 없다 |

**재배포가 필요한 줄이 하나도 없다.** 멘션 매핑이 `.env` 에 있던 동안은
입사자마다 `make gen` + 빌드 + 배포였다 — 그게 원격으로 옮겨진 이유다.

## 테스트

```bash
make analyze
make test
```

[`test/architecture_test.dart`](test/architecture_test.dart) 가 규약을 집행한다 —
화면에서 `showDialog` · `TextField` · `styleFrom` 을 직접 쓰는 것, `fontSize:` 를
직접 적는 것을 막는다. 크기가 안 맞으면 새 값을 만들 게 아니라 `textTheme` 슬롯
선택이 틀린 것이다.

나머지는 깨지면 데이터가 상하는 자리들이다 — 파일명 치환(`filename_test`),
금액·통화(`currency_test` · `korean_amount_test`), 카드번호 매칭
(`card_directory_test`), 총금액 수정 시 공급가액·부가세 연동(`entry_draft_test`).

## 구조

```
lib/
  core/      theme(타이포 15슬롯·토큰) · widgets(화면이 조립하는 부품) · utils · config
  data/      local(drift 큐) · remote(Google · Anthropic · Slack) · submission_sender
  features/  auth · capture · home · review · submissions · splash
  models/    entry_draft(검토 중 상태) · purchase_entry(제출 단위) · sheet_row(시트 계약)
```

화면은 배럴 하나(`core/widgets/app_widgets.dart`)만 import 한다.
