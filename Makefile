# 환경(flavor)별 실행·빌드를 한 줄로 묶어둔다.
#
# ## 왜 Makefile 인가
#
# 환경 하나를 고르는 데 플래그가 **둘** 필요하다:
#
#   --flavor dev              네이티브 쪽(번들 ID·앱 이름·아이콘)
#   --dart-define=FLAVOR=dev  Dart 쪽(시트·드라이브·Slack 설정)
#
# 둘을 손으로 적으면 **엇갈릴 수 있다** — `--flavor dev` 로 깔면서
# `FLAVOR=prod` 를 넘기면 "Bodit_dev" 라고 적힌 앱이 운영 시트에 append 한다.
# Sheets 는 append-only 라 그 행은 앱으로 못 지운다.
#
# 그래서 둘을 항상 같이 넘기는 타깃만 둔다. 손으로 flutter 를 부르지 않는다.
#
# ## 개발은 debug 전용이다
#
# 개발 빌드는 배포하지 않는다 — 내 기기에서 돌려보는 용도다. 그래서
# release·ipa 타깃을 두지 않는다. 운영 빌드만 스토어로 나간다.
#
# fvm 을 쓴다 — `.fvmrc` 의 핀을 벗어나지 않게.

FLUTTER := fvm flutter
DART := fvm dart

.PHONY: help gen clean-gen icons run-dev run-prod apk-prod ipa-prod \
        deploy deploy-android deploy-ios testflight-notes \
        test analyze check-prod-env

help:
	@echo "gen         생성 코드 만들기 (envied · freezed · drift · riverpod)"
	@echo "icons       개발용 앱 아이콘 다시 만들기 (운영 아이콘이 바뀌었을 때)"
	@echo "run-dev     개발 환경으로 실행 (debug · 내 기기 전용)"
	@echo "run-prod    운영 환경으로 실행 — 운영 시트에 실제로 들어간다"
	@echo "apk-prod    운영 APK (release) — 올리지는 않는다"
	@echo "ipa-prod    운영 IPA (release) — 올리지는 않는다"
	@echo ""
	@echo "deploy-android   APK 빌드 → Firebase App Distribution"
	@echo "deploy-ios       IPA 빌드 → TestFlight"
	@echo "deploy           둘 다 (빌드 번호는 한 번만 올라간다)"
	@echo "testflight-notes 처리가 끝난 TestFlight 빌드에 What to Test 붙이기"
	@echo "analyze     flutter analyze"
	@echo "test        flutter test"

# 두 환경을 **같이** 생성한다. 환경마다 돌리는 구조가 아니다 —
# `.env.dev`·`.env.prod` 가 각각 EnvDev·EnvProd 로 구워지고, 고르는 일은
# 런타임이 아니라 `--dart-define` 이 한다(lib/core/flavor.dart).
gen:
	$(DART) run build_runner build --delete-conflicting-outputs

clean-gen:
	$(DART) run build_runner clean
	$(MAKE) gen

# 운영 아이콘을 입력으로 개발 아이콘을 다시 만든다. 운영 아이콘이 바뀌었을
# 때만 돌리면 된다 — 산출물은 커밋돼 있다.
icons:
	python3 tool/make_dev_icons.py

run-dev:
	$(FLUTTER) run --debug --flavor dev --dart-define=FLAVOR=dev

run-prod: check-prod-env
	$(FLUTTER) run --flavor prod --dart-define=FLAVOR=prod

apk-prod: check-prod-env
	$(FLUTTER) build apk --release --flavor prod --dart-define=FLAVOR=prod

ipa-prod: check-prod-env
	$(FLUTTER) build ipa --release --flavor prod --dart-define=FLAVOR=prod

# 사내 배포. 빌드 번호 올리기 · 생성 코드 굽기 · 빌드 · 업로드 · 공지 안내를
# 한 줄로 묶는다. 순서와 이유는 `tool/deploy.sh` 머리말에 적혀 있다.
#
# `apk-prod`·`ipa-prod` 는 그대로 둔다 — **올리지 않고 빌드만** 해보는 길이
# 하나는 있어야 한다(서명이 되는지, 빌드가 깨지지 않는지).
deploy-android: check-prod-env
	tool/deploy.sh android

deploy-ios: check-prod-env
	tool/deploy.sh ios

deploy: check-prod-env
	tool/deploy.sh all

# 업로드와 따로인 이유: Apple 쪽 처리(5~30분)가 끝나야 노트를 붙일 빌드가
# 생긴다. 처리 중이면 그렇다고 말하고 멈춘다.
testflight-notes:
	python3 tool/testflight_notes.py

# 운영으로 나가기 전에 `.env.prod` 가 자리값인지 본다.
#
# 앱에도 같은 검사가 있지만(`Config.ensureConfigured`) 그건 **앱을 켠 뒤**다.
# 자리값으로 구운 운영 빌드를 올린 다음 알게 되는 것보다, 빌드를 거부하는
# 쪽이 싸다. 생성 코드는 `.env.prod` 가 아니라 이미 구워진 것을 쓰므로
# 파일을 직접 본다.
check-prod-env:
	@test -f .env.prod || { \
	  echo ".env.prod 가 없습니다. cp .env.prod.example .env.prod 후 값을 채우세요."; \
	  exit 1; }
	@! grep -q 'REPLACE_ME' .env.prod || { \
	  echo ".env.prod 에 REPLACE_ME 가 남아 있습니다:"; \
	  grep -n 'REPLACE_ME' .env.prod; \
	  echo "값을 채우고 make gen 을 다시 돌리세요."; \
	  exit 1; }

analyze:
	$(FLUTTER) analyze

test:
	$(FLUTTER) test
