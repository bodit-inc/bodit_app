#!/usr/bin/env python3
"""TestFlight 의 "What to Test" 를 App Store Connect API 로 채운다.

## 왜 업로드와 따로인가

`xcrun altool --upload-app` 이 성공해도 그 빌드는 아직 없는 것이나 같다 —
Apple 쪽 처리(보통 5~30분)가 끝나야 빌드가 조회되고, 그 전에는 노트를
붙일 대상이 없다. 그래서 업로드 스크립트가 끝까지 기다리는 대신
(기다리는 동안 맥을 못 쓴다) 이 타깃을 따로 뒀다.

처리 중이면 그렇다고 말하고 멈춘다. 조금 뒤에 다시 돌리면 된다.

## 왜 altool 이 아니라 직접 호출인가

altool 은 바이너리를 올리는 도구고, 빌드 메타데이터(What to Test)는
건드리지 못한다. fastlane 의 pilot 이 하는 일인데, 그거 하나 때문에
루비 체인을 들이는 대신 필요한 REST 호출 셋만 적었다.

쓰는 법:

    make testflight-notes                 pubspec 의 현재 빌드 번호로
    tool/testflight_notes.py --build 8    번호를 직접 지정
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, utils as asym_utils

API = "https://api.appstoreconnect.apple.com"
# 번들 ID 는 비밀이 아니고 Xcode 프로젝트에 박혀 있는 값이다.
# 운영 쪽은 바꾸지 않는다(CLAUDE.md "환경 분리" 1).
BUNDLE_ID = os.environ.get("ASC_BUNDLE_ID", "co.bodit.boditApp")

# 화면에는 "What to Test" 로 나오지만 API 필드는 `whatsNew` 다. `whatsToTest`
# 로 보내면 409 로 거절한다("unknown attribute"). UI 라벨을 그대로 필드
# 이름으로 짐작하지 않는다 — 실제 GET 응답의 키가 이것이다.
WHATS_NEW = "whatsNew"


def die(message: str) -> None:
    print(f"\n\033[31m오류: {message}\033[0m", file=sys.stderr)
    sys.exit(1)


def step(message: str) -> None:
    print(f"\n\033[1m==> {message}\033[0m")


# ------------------------------------------------------------------ 설정

def read_env(path: Path) -> dict[str, str]:
    """`.env` 형식에서 키=값을 읽는다. 주석과 빈 줄은 버린다."""
    values: dict[str, str] = {}
    if not path.exists():
        return values
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        values[key.strip()] = value.strip()
    return values


# ------------------------------------------------------------------ 인증

def make_token(key_id: str, issuer_id: str, key_file: Path) -> str:
    """ES256 으로 서명한 ASC 토큰. 유효기간은 Apple 이 20분까지만 받는다."""
    private_key = serialization.load_pem_private_key(key_file.read_bytes(), password=None)
    if not isinstance(private_key, ec.EllipticCurvePrivateKey):
        die(f"EC 키가 아니다: {key_file}")

    now = int(time.time())
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    payload = {
        "iss": issuer_id,
        "iat": now,
        "exp": now + 20 * 60,
        "aud": "appstoreconnect-v1",
    }

    import base64

    def b64(raw: bytes) -> bytes:
        return base64.urlsafe_b64encode(raw).rstrip(b"=")

    signing_input = (
        b64(json.dumps(header, separators=(",", ":")).encode())
        + b"."
        + b64(json.dumps(payload, separators=(",", ":")).encode())
    )

    # cryptography 는 DER(ASN.1) 서명을 돌려주는데 JWT 는 r||s 64바이트를
    # 요구한다. 그대로 넘기면 401 로 떨어진다.
    der = private_key.sign(signing_input, ec.ECDSA(hashes.SHA256()))
    r, s = asym_utils.decode_dss_signature(der)
    raw = r.to_bytes(32, "big") + s.to_bytes(32, "big")

    return (signing_input + b"." + b64(raw)).decode()


def call(token: str, method: str, path: str, body: dict | None = None) -> dict:
    url = path if path.startswith("http") else f"{API}{path}"
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(url, data=data, method=method)
    request.add_header("Authorization", f"Bearer {token}")
    if data is not None:
        request.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(request) as response:
            raw = response.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as error:
        detail = error.read().decode(errors="replace")
        try:
            errors = json.loads(detail).get("errors", [])
            detail = "\n".join(
                f"{e.get('title', '')}: {e.get('detail', '')}" for e in errors
            ) or detail
        except json.JSONDecodeError:
            pass
        die(f"{method} {path} → {error.code}\n{detail}")
        raise  # 닿지 않는다. 타입 체커용.


# ------------------------------------------------------------------ 본문

def main() -> None:
    root = Path(subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        capture_output=True, text=True, check=True,
    ).stdout.strip())
    os.chdir(root)

    parser = argparse.ArgumentParser(description="TestFlight What to Test 채우기")
    parser.add_argument("--build", help="빌드 번호 (기본: pubspec.yaml 의 +N)")
    parser.add_argument("--notes", default="release_notes.md", help="출시 노트 파일")
    args = parser.parse_args()

    config = read_env(root / ".env.deploy")
    key_id = config.get("ASC_KEY_ID", "")
    issuer_id = config.get("ASC_ISSUER_ID", "")
    locale = config.get("TESTFLIGHT_LOCALE") or "ko"
    key_file = config.get("ASC_KEY_FILE") or f"~/.appstoreconnect/private_keys/AuthKey_{key_id}.p8"

    if not key_id or not issuer_id:
        die(".env.deploy 의 ASC_KEY_ID · ASC_ISSUER_ID 가 비어 있다.")
    key_path = Path(key_file).expanduser()
    if not key_path.exists():
        die(f"ASC 키 파일이 없다: {key_path}")

    notes_path = root / args.notes
    if not notes_path.exists():
        die(f"{args.notes} 가 없다.")
    notes = notes_path.read_text().strip()
    if not notes:
        die(f"{args.notes} 가 비어 있다.")

    build_number = args.build
    if not build_number:
        match = re.search(r"^version:\s*(\S+)\+(\S+)\s*$", (root / "pubspec.yaml").read_text(), re.M)
        if not match:
            die("pubspec.yaml 에서 version 을 읽지 못했다.")
        build_number = match.group(2)

    token = make_token(key_id, issuer_id, key_path)

    step(f"빌드 {build_number} 찾기 ({BUNDLE_ID})")
    apps = call(token, "GET", f"/v1/apps?filter[bundleId]={BUNDLE_ID}")["data"]
    if not apps:
        die(f"App Store Connect 에 {BUNDLE_ID} 가 없다. 키 권한을 봐라.")
    app_id = apps[0]["id"]

    builds = call(
        token, "GET",
        f"/v1/builds?filter[app]={app_id}&filter[version]={build_number}&limit=1",
    )["data"]
    if not builds:
        die(
            f"빌드 {build_number} 이 아직 안 보인다.\n"
            "    업로드 직후면 Apple 쪽 처리(5~30분)가 끝나지 않은 것이다 — 조금 뒤에 다시 돌려라."
        )

    build = builds[0]
    state = build["attributes"].get("processingState")
    if state == "PROCESSING":
        die("아직 처리 중(PROCESSING)이다. 조금 뒤에 다시 돌려라.")
    if state != "VALID":
        die(f"빌드 상태가 {state} 다. App Store Connect 에서 이유를 봐라.")

    build_id = build["id"]
    print(f"    빌드 {build_number} · {state}")

    step(f"What to Test 쓰기 ({locale})")
    existing = call(token, "GET", f"/v1/builds/{build_id}/betaBuildLocalizations")["data"]
    mine = next((x for x in existing if x["attributes"].get("locale") == locale), None)

    if mine:
        # 이미 있으면 덮어쓴다 — 노트를 고쳐서 다시 돌리는 경우다.
        call(token, "PATCH", f"/v1/betaBuildLocalizations/{mine['id']}", {
            "data": {
                "type": "betaBuildLocalizations",
                "id": mine["id"],
                "attributes": {WHATS_NEW: notes},
            }
        })
    else:
        call(token, "POST", "/v1/betaBuildLocalizations", {
            "data": {
                "type": "betaBuildLocalizations",
                "attributes": {"locale": locale, WHATS_NEW: notes},
                "relationships": {
                    "build": {"data": {"type": "builds", "id": build_id}}
                },
            }
        })

    print(f"\n    붙였다:\n")
    for line in notes.splitlines():
        print(f"      {line}")
    print()


if __name__ == "__main__":
    main()
