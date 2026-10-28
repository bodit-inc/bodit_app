/// Drive 에 저장할 증빙 파일명을 만든다.
///
/// 규칙의 단일 원천은 위키다:
///   ~/llm-wiki-template/wiki/projects/bodit-app/sheet-schema.md
///
///   소속일자_업체명_내역_증빙자료명_총금액
///   예: 260805_영풍문고_8월 도서_영수증_19,000
///
/// ## 대괄호를 뺀 이유
///
/// 예전엔 업체명·내역을 `[]` 로 감쌌다. 값 안에 `_` 가 들어가도 필드 경계가
/// 안 무너진다는 이유였는데, **되파싱할 일이 없어서 그 안전장치가 쓸모가 없었다**
/// — 시트에 `증빙링크` 컬럼이 있으니 파일명에서 값을 다시 꺼낼 필요가 없다.
/// 회계 담당자가 Drive 에서 눈으로 읽는 이름이라 짧은 쪽이 낫다는 요청을 받았다.
///
/// 주의: 사용자가 검토 화면에서 이 파일명을 직접 고칠 수 있다(ADR Decision 12c).
/// 그래서 `sanitizeSegment` 는 자동 생성 경로뿐 아니라 **사용자 입력에도 반드시** 적용한다.
library;

/// 파일시스템이 거부하는 문자들.
///
/// Drive API 자체는 `/` 를 받아주지만, Drive for Desktop 으로 동기화하거나
/// 내려받는 순간 깨진다. 회계 담당자가 로컬로 받아 정리하므로 반드시 막는다.
const _forbidden = r'<>:"/\|?*';

/// 파일명 한 조각을 안전하게 만든다.
///
/// 금지문자만 바꾸고 나머지는 그대로 통과시킨다 — 공백·한글·`_`·`-`·`,`·괄호 모두 허용.
/// 대괄호도 이제 그냥 통과한다(구분자가 아니므로 깨질 게 없다).
/// 실무에서 실제로 걸리는 건 사실상 `/` 하나다 (예: "A/S 비용" → "A-S 비용").
String sanitizeSegment(String raw) {
  final buf = StringBuffer();
  for (final rune in raw.runes) {
    final ch = String.fromCharCode(rune);
    if (rune < 0x20 || rune == 0x7F) continue; // 제어문자는 버린다
    if (_forbidden.contains(ch)) {
      buf.write('-');
    } else {
      buf.write(ch);
    }
  }
  // 앞뒤 공백과 마침표는 Windows 에서 문제가 되므로 떨어낸다.
  return buf.toString().trim().replaceAll(RegExp(r'[.\s]+$'), '');
}

/// 금액을 파일명용 문자열로. `19000` → `19,000`
String formatAmountForFilename(int amount) {
  final s = amount.abs().toString();
  final buf = StringBuffer(amount < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}

/// 소속날짜를 `YYMMDD` 로. 2026-08-05 → `260805`
String formatDateForFilename(DateTime d) {
  final yy = (d.year % 100).toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  final dd = d.day.toString().padLeft(2, '0');
  return '$yy$mm$dd';
}

/// 증빙 파일명을 만든다. 확장자는 붙이지 않는다 — 업로드 시점에 원본 것을 쓴다.
///
/// `amount` 는 **이체확인증에 찍힌 실제 입금액**이다(ADR Decision 13).
/// 증빙 전체 금액이 아니다 — 선금/잔금은 집행 회차마다 파일이 따로 생긴다.
String buildEvidenceFilename({
  required DateTime belongDate,
  required String vendor,
  required String description,
  required String evidenceType,
  required int amount,
}) {
  final parts = [
    formatDateForFilename(belongDate),
    sanitizeSegment(vendor),
    sanitizeSegment(description),
    sanitizeSegment(evidenceType),
    formatAmountForFilename(amount),
  ];
  return parts.join('_');
}

/// 파일명에서 날짜 접두(`260805_`)를 뗀다.
///
/// 제출 목록이 **월로 묶여** 있어서 행마다 연월을 또 보여줄 이유가 없다.
/// 묶음 헤더가 `2026년 8월` 을 말하고 행은 일자만 적는다.
///
/// 접두가 **여섯 자리 숫자 + `_`** 인 경우에만 뗀다. 규칙은
/// `소속일자_업체명_내역_증빙자료명_총금액` 이지만 **사용자가 검토 화면에서
/// 파일명을 직접 고칠 수 있다**(CLAUDE.md). 규칙을 따른다고 가정해 앞을
/// 잘라내면 사용자가 적은 이름이 사라진다.
String stripDatePrefix(String filename) {
  final m = RegExp(r'^\d{6}_').firstMatch(filename);
  return m == null ? filename : filename.substring(m.end);
}
