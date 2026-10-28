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

# 3. 환경 변수 — 값은 아래 표를 보고 채운다
cp .env.example .env && $EDITOR .env

# 4. 생성 코드 (envied · freezed · drift · riverpod)
fvm dart run build_runner build --delete-conflicting-outputs

# 5. 실행
fvm flutter run
```

`.env` 를 고친 뒤 `wrote 0 outputs` 가 나오면 [`build.yaml`](build.yaml) 주석을 읽는다 —
envied 가 `.env` 를 build_runner 그래프 밖에서 읽기 때문에 생기는 함정이고, 거기
대처가 적혀 있다.

## .env 값 8개가 어디서 오는가

값은 여기 적지 않는다 — **이 repo 는 공개되어 있다.** 받는 곳만 적는다.

| 키 | 어디서 | 메모 |
|---|---|---|
| `ANTHROPIC_API_KEY` | Anthropic 콘솔 | **용도는 OCR 하나뿐.** 지출 한도 없이 발급하지 않는다 (#4) |
| `SLACK_BOT_TOKEN` | Slack 앱 | scope 는 `chat:write` · `files:write` 만 (#5) — 게시 방식이 #1 에서 갈린다 |
| `SLACK_CHANNEL_ID` | 게시할 채널 | 사람이 손으로 증빙을 던지던 그 채널 |
| `SPREADSHEET_ID` | 매입내역 스프레드시트 | 회계 담당자가 정산할 때 읽는 원천. 앱은 **append 만** 한다 |
| `CARD_SHEET_ID` | 카드보유내역 스프레드시트 | **매입내역과 다른 파일이다.** 운영팀 관리 · 우리는 보기 전용 |
| `DRIVE_FOLDER_ID` | 증빙 공유 드라이브 폴더 | `drive.file` scope 로는 폴더를 검색할 수 없어 ID 를 박는다 (#6) |
| `GOOGLE_IOS_CLIENT_ID` | Google Cloud OAuth 클라이언트 | 비워도 빌드는 된다(기본값 `''`) |
| `GOOGLE_SERVER_CLIENT_ID` | Google Cloud OAuth 클라이언트 | 같음 |

`envied` 는 **난독화일 뿐 보안이 아니다.** 런타임에는 평문으로 헤더에 실려 나간다.
실질 방어선은 Anthropic 지출 한도와 Slack 의 좁은 scope 두 개다
([`lib/core/config.dart`](lib/core/config.dart) 주석).

## 테스트

```bash
fvm flutter analyze
fvm flutter test
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
