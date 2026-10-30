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

**`.env.prod` 도 있어야 빌드가 된다.** 운영 값이 없는 사람은 예제의
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
| 설정 | `.env.dev` | `.env.prod` — 지금까지 쓰던 값 그대로 |
| iOS 번들 ID | `co.bodit.boditApp.dev` | `co.bodit.boditApp` (변경 없음) |
| Android applicationId | `co.bodit.bodit_app.dev` | `co.bodit.bodit_app` (변경 없음) |
| 앱 이름 | `Bodit_dev` | `Bodit App` / `bodit_app` (변경 없음) |
| 아이콘 | 가운데 주황 `dev` 띠 | 변경 없음 |
| 화면 | 우상단 `DEV` 리본 + 홈 안내 배너 | 변경 없음 |

운영 쪽은 **번들 ID·이름·아이콘·설정 무엇도 바뀌지 않았다.** 개발만 덧붙였다.
`--flavor` 없이 빌드하던 기존 경로(Xcode 의 `Runner` 스킴)도 그대로 동작한다.

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

## .env 값 9개가 어디서 오는가

값은 여기 적지 않는다 — **이 repo 는 공개되어 있다.** 받는 곳만 적는다.
개발·운영이 **같아도 되는 값**과 **달라야 하는 값**이 갈린다.

| 키 | 어디서 | 개발 ↔ 운영 |
|---|---|---|
| `ANTHROPIC_API_KEY` | Anthropic 콘솔 | 같아도 됨. **용도는 OCR 하나뿐** — 지출 한도 없이 발급하지 않는다 (#4). 나누면 콘솔에서 지출이 갈려 보인다 |
| `SLACK_BOT_TOKEN` | Slack 앱 | **달라야 함.** 개발용 앱을 따로 만든다 — 같은 토큰이면 채널 ID 한 글자 실수로 운영 채널에 글이 간다. scope 는 `chat:write` · `files:write` · `files:read` 셋만 |
| `SLACK_CHANNEL_ID` | 게시할 채널 | **달라야 함.** 개발용 채널을 하나 파고 봇을 초대한다 |
| `SLACK_USER_IDS` | 사내 Slack 매핑 | 같아도 됨 — user id 는 워크스페이스 단위라 앱을 새로 만들어도 그대로다. `email:ID` 를 쉼표로 |
| `SPREADSHEET_ID` | 매입내역 스프레드시트 | **달라야 함.** 개발용은 운영 시트의 **사본** — 수식 컬럼과 `_비목마스터`·`_분류마스터` 탭이 같이 복사돼야 한다 |
| `CARD_SHEET_ID` | 카드보유내역 스프레드시트 | 같아도 됨 — 앱이 **읽기만** 한다. 사본을 두면 카드가 늘 때 한쪽만 낡는다 |
| `DRIVE_FOLDER_ID` | 증빙 공유 드라이브 폴더 | **달라야 함.** 섞이면 회계 담당자가 테스트 파일을 보게 된다 |
| `GOOGLE_IOS_CLIENT_ID` | Google Cloud OAuth 클라이언트 | **달라야 함** — 클라이언트는 번들 ID 로 매칭되고 개발은 `co.bodit.boditApp.dev` 다. 뒤집은 값을 [`ios/Flutter/Dev.xcconfig`](ios/Flutter/Dev.xcconfig) 에도 넣는다 |
| `GOOGLE_SERVER_CLIENT_ID` | Google Cloud OAuth 클라이언트 | 같아도 됨(웹 클라이언트라 패키지명과 무관). 단 GCP 에 Android 클라이언트 `co.bodit.bodit_app.dev` + SHA-1 을 따로 등록해야 개발 빌드에서 로그인이 통과한다 |

`envied` 는 **난독화일 뿐 보안이 아니다.** 런타임에는 평문으로 헤더에 실려 나간다.
실질 방어선은 Anthropic 지출 한도와 Slack 의 좁은 scope 두 개다
([`lib/core/config.dart`](lib/core/config.dart) 주석).

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
금액·통화(`currency_test` · `korean_amount_test`), 카드 뒤 4자리 매칭
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
