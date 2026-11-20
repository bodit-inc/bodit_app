#!/usr/bin/env bash
#
# 사내 배포를 한 줄로 묶는다 — Android 는 Firebase App Distribution,
# iOS 는 TestFlight. 스토어 심사로 나가는 길이 아니다.
#
# ## 왜 스크립트인가
#
# 배포 한 번에 손이 가는 일이 여섯이다: 출시 노트 쓰기 · 빌드 번호 올리기 ·
# 생성 코드 다시 굽기 · 빌드 · 업로드 · Remote Config 공지. 하나라도 빠지면
# 조용히 틀린다:
#
#   - 빌드 번호를 안 올리면 **TestFlight 가 통째로 거부한다**(같은 번호는 못 올린다).
#     Android 는 거부하지 않고 그냥 올라가서 더 나쁘다 — 받는 사람이 자기가
#     새 빌드를 받았는지 알 수 없다.
#   - `make gen` 을 건너뛰면 `.env.prod` 를 고친 것이 빌드에 안 들어간다.
#     envied 는 **굽는 시점**의 값을 쓰기 때문이다.
#   - 공지를 안 하면 올린 쪽만 알고 깔린 쪽은 모른다(README "업데이트 알림").
#
# 그래서 순서를 사람이 아니라 여기에 적어둔다.
#
# ## 쓰는 법
#
#   make deploy-android     Android 만
#   make deploy-ios         iOS 만
#   make deploy             둘 다 (빌드 번호는 **한 번만** 올라간다)
#
# 실패해서 다시 돌릴 때는 `--no-bump` 를 붙인다 — 안 그러면 빌드 번호가
# 한 번 더 올라가서 실제로 나간 적 없는 번호가 생긴다.
#
#   tool/deploy.sh ios --no-bump
#
# ## 출시 노트
#
# `release_notes.md` 를 읽는다(gitignore 됨 — 건마다 갈아 쓰는 파일이다).
# 비어 있으면 **빌드하지 않고 멈춘다.** 같은 글이 세 곳으로 간다:
# App Distribution 출시 노트 · 버전 커밋 본문 · (iOS 는 업로드 후
# `make testflight-notes` 로 What to Test).

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

NOTES_FILE="release_notes.md"
NOTES_PLACEHOLDER="여기에 출시 노트를 적는다 (이 줄을 지우고)."

# 색 없는 로그. 단계가 길어서 어디까지 갔는지 보여야 한다.
step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
info() { printf '    %s\n' "$*"; }
die()  { printf '\n\033[31m오류: %s\033[0m\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- 인자

do_android=0
do_ios=0
bump=1

for arg in "$@"; do
  case "$arg" in
    android)   do_android=1 ;;
    ios)       do_ios=1 ;;
    all|both)  do_android=1; do_ios=1 ;;
    --no-bump) bump=0 ;;
    *) die "모르는 인자: $arg (android | ios | all | --no-bump)" ;;
  esac
done

[ "$do_android" = 1 ] || [ "$do_ios" = 1 ] || die "배포 대상을 적어라 (android | ios | all)"

# ---------------------------------------------------------------- 설정 읽기

# `.env` 형식에서 키 하나를 꺼낸다. 값에 `=` 가 들어 있어도 자르지 않는다.
env_value() {
  local file="$1" key="$2"
  [ -f "$file" ] || return 0
  sed -n "s/^${key}=//p" "$file" | head -1
}

# 배포에 쓰는 자격증명은 `.env.prod` 와 **다른 파일**에 둔다.
# `.env.prod` 는 envied 가 **앱 바이너리에 굽는** 값이다 — 업로드용 키를
# 거기 적으면 전 직원 기기에 App Store Connect 키가 들어간다.
DEPLOY_ENV=".env.deploy"
[ -f "$DEPLOY_ENV" ] || die "$DEPLOY_ENV 가 없다. cp .env.deploy.example $DEPLOY_ENV 후 값을 채워라."

FIREBASE_PROJECT_ID="$(env_value .env.prod FIREBASE_PROJECT_ID)"
FIREBASE_APP_ID_ANDROID="$(env_value .env.prod FIREBASE_APP_ID_ANDROID)"
APPDIST_GROUP="$(env_value "$DEPLOY_ENV" APPDIST_GROUP)"
ASC_KEY_ID="$(env_value "$DEPLOY_ENV" ASC_KEY_ID)"
ASC_ISSUER_ID="$(env_value "$DEPLOY_ENV" ASC_ISSUER_ID)"
ASC_KEY_FILE="$(env_value "$DEPLOY_ENV" ASC_KEY_FILE)"

# 대상에 **필요한 값만** 본다 — Android 만 올리는데 ASC 키를 요구하지 않는다.
if [ "$do_android" = 1 ]; then
  [ -n "$FIREBASE_APP_ID_ANDROID" ] || die ".env.prod 의 FIREBASE_APP_ID_ANDROID 가 비어 있다."
  [ -n "$APPDIST_GROUP" ] || die "$DEPLOY_ENV 의 APPDIST_GROUP 이 비어 있다."
  command -v firebase >/dev/null || die "firebase CLI 가 없다. npm i -g firebase-tools"
fi

if [ "$do_ios" = 1 ]; then
  [ -n "$ASC_KEY_ID" ] || die "$DEPLOY_ENV 의 ASC_KEY_ID 가 비어 있다."
  [ -n "$ASC_ISSUER_ID" ] || die "$DEPLOY_ENV 의 ASC_ISSUER_ID 가 비어 있다."
  [ -n "$ASC_KEY_FILE" ] || ASC_KEY_FILE="$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"
  ASC_KEY_FILE="${ASC_KEY_FILE/#\~/$HOME}"
  [ -f "$ASC_KEY_FILE" ] || die "ASC 키 파일이 없다: $ASC_KEY_FILE"
  # altool 은 키를 **파일 경로**로 받지 않는다 — 디렉토리에서 이름으로 찾는다.
  export API_PRIVATE_KEYS_DIR="$(cd "$(dirname "$ASC_KEY_FILE")" && pwd)"
fi

# ---------------------------------------------------------------- 가드

step "출시 노트 확인"
if [ ! -f "$NOTES_FILE" ]; then
  printf '%s\n' "$NOTES_PLACEHOLDER" > "$NOTES_FILE"
  die "$NOTES_FILE 을 만들어뒀다. 내용을 적고 다시 돌려라."
fi
if ! grep -qv '^\s*$' "$NOTES_FILE"; then
  die "$NOTES_FILE 이 비어 있다. 받는 사람이 무엇이 바뀌었는지 알 길이 없다."
fi
if grep -qF "$NOTES_PLACEHOLDER" "$NOTES_FILE"; then
  die "$NOTES_FILE 에 자리값이 그대로 있다. 내용을 적고 다시 돌려라."
fi
info "$(head -3 "$NOTES_FILE")"

# 작업 트리가 더러우면 **막지는 않는다** — 막으면 급할 때 스크립트를 안 쓰고
# 손으로 빌드하게 된다. 대신 올라간 바이너리가 어느 커밋도 아니라는 것은
# 알려준다. 커밋은 끝에 pubspec.yaml 만 담는다(제약: 남의 변경을 끌어가지 않는다).
dirty="$(git status --porcelain -- . ':!pubspec.yaml')"
if [ -n "$dirty" ]; then
  step "커밋하지 않은 변경이 있다"
  printf '%s\n' "$dirty"
  info "이 상태 그대로 빌드된다. 올라간 빌드와 같은 커밋이 레포에 없게 된다."
  read -r -p "    계속할까? [y/N] " answer
  [ "$answer" = "y" ] || [ "$answer" = "Y" ] || die "중단했다."
fi

# ---------------------------------------------------------------- 버전

version_line="$(grep -m1 '^version:' pubspec.yaml)" || die "pubspec.yaml 에 version 이 없다."
current="${version_line#version: }"
name="${current%+*}"
build="${current#*+}"

if [ "$bump" = 1 ]; then
  build=$((build + 1))
  new="${name}+${build}"
  step "빌드 번호 ${current} → ${new}"
  # 있던 줄을 **그 줄 그대로** 찾아 바꾼다 — 다른 version 비슷한 줄을 건드리지 않게.
  sed -i '' "s|^version: ${current}$|version: ${new}|" pubspec.yaml
  grep -q "^version: ${new}$" pubspec.yaml || die "pubspec.yaml 의 version 을 바꾸지 못했다."
else
  new="$current"
  step "빌드 번호 ${new} (--no-bump)"
fi

# ---------------------------------------------------------------- 빌드

step "생성 코드 다시 굽기 (make gen)"
# `.env.prod` 를 고쳐두고 gen 을 안 돌린 채 배포하는 사고를 막는다.
# make 안에서 불릴 때는 MAKE 가 내려온다 — 재귀 호출을 그쪽에 맡긴다.
"${MAKE:-make}" gen

if [ "$do_android" = 1 ]; then
  step "Android APK 빌드 (prod · release)"
  fvm flutter build apk --release --flavor prod --dart-define=FLAVOR=prod
  APK="build/app/outputs/flutter-apk/app-prod-release.apk"
  [ -f "$APK" ] || die "APK 가 없다: $APK"

  step "Firebase App Distribution 업로드 → 그룹 '${APPDIST_GROUP}'"
  firebase appdistribution:distribute "$APK" \
    --project "$FIREBASE_PROJECT_ID" \
    --app "$FIREBASE_APP_ID_ANDROID" \
    --groups "$APPDIST_GROUP" \
    --release-notes-file "$NOTES_FILE"
fi

if [ "$do_ios" = 1 ]; then
  step "iOS IPA 빌드 (prod · release · app-store)"
  fvm flutter build ipa --release --flavor prod --dart-define=FLAVOR=prod
  IPA="$(ls -t build/ios/ipa/*.ipa 2>/dev/null | head -1)" || true
  [ -n "${IPA:-}" ] || die "IPA 가 없다. Xcode 에서 배포 인증서(Apple Distribution)가 만들어졌는지 봐라."

  step "TestFlight 업로드 ($(basename "$IPA"))"
  # altool 이 성공해도 **바로 테스트 가능해지지 않는다** — Apple 쪽 처리가
  # 5~30분 걸린다. What to Test 는 처리가 끝난 뒤에야 붙일 수 있어서
  # 별도 타깃(make testflight-notes)으로 뺐다.
  xcrun altool --upload-app -f "$IPA" -t ios \
    --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
fi

# ---------------------------------------------------------------- 커밋

# 빌드·업로드가 **다 끝난 뒤에** 커밋한다. 먼저 커밋하면 빌드가 깨졌을 때
# 나간 적 없는 번호가 역사에 남는다.
if ! git diff --quiet -- pubspec.yaml; then
  step "버전 커밋"
  # 본문은 출시 노트 그대로다. `release_notes.md` 는 다음 배포 때 갈아쓰는
  # 파일이라 여기 적어두지 않으면 "그 빌드가 뭐였는지" 가 남지 않는다.
  git commit --only pubspec.yaml -F - <<COMMIT
chore: [Version] ${new}

$(cat "$NOTES_FILE")
COMMIT
fi

# ---------------------------------------------------------------- 공지

step "남은 일 — Remote Config 공지"
cat <<GUIDE
    올린 쪽은 알지만 깔린 쪽은 모른다. 콘솔에서 한 줄 고쳐야 전원에게 간다.

      Firebase 콘솔 → Remote Config → ${FIREBASE_PROJECT_ID}
        latest_version  = ${new}
        update_message  = (무엇이 바뀌었는지 한 줄)
        minimum_version = 그대로 비워둔다 — 전원을 막아야 할 때만 건드린다

    강제로 할지 · 문구를 뭘로 할지는 Claude 에게 "배포했다, 공지하자" 고
    말하면 묻고 만들어준다.
GUIDE

if [ "$do_ios" = 1 ]; then
  cat <<GUIDE

    iOS 는 Apple 쪽 처리(5~30분)가 끝난 뒤 한 번 더:

      make testflight-notes

    처리 중이면 그렇다고 말하고 멈춘다 — 조금 뒤에 다시 돌리면 된다.
GUIDE
fi
