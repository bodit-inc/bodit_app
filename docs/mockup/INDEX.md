# bodit app 화면 시안

`build.py` 로 생성한다. 디자인 확정본이 아니라 **동작 흐름 공유용**이다.

| # | 파일 | 화면 |
|---|---|---|
| 1 | `01-login.png` | 회사 Google 계정으로 로그인 (@bodit.co 만) |
| 2 | `02-home.png` | 홈 — 촬영 / 파일 선택, 전송 대기 큐, Sheets·Drive 바로가기 |
| 3 | `03-capture.png` | 촬영 — 프레임 가이드 |
| 4 | `04-analyzing.png` | OCR — 이미지에서 항목을 추출하고 과거 이력을 조회 |
| 5 | `05-review-top.png` | 검토 폼 ① — 프리필된 값. 확신이 낮은 항목만 노란색 |
| 6 | `06-suggest.png` | 검토 폼 ② — 비목·분류코드는 과거 이력으로 추천 + 근거 표시 |
| 7 | `07-picker.png` | 비목 선택 — 추천·최근순으로 정렬된 검색 목록 |
| 8 | `08-amount.png` | 검토 폼 ③ — 금액. 부가세는 자동 계산하지 않고 물어본다 |
| 9 | `09-submitting.png` | 제출 — 세 곳에 동시에 올라간다 |
| 10 | `10-done.png` | 완료 — Slack 에 올라간 모습까지 확인 |
| 11 | `11-list.png` | 내 제출 목록 — 부분 실패(Slack 만 실패)가 여기서 보인다 |
| 12 | `12-offline.png` | 오프라인 — 로컬에 쌓아두고 연결되면 자동 전송 (해외 출장) |

재생성: `python3 docs/mockup/build.py`
