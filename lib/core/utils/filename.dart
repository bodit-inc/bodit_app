/// Drive 에 저장할 증빙 파일명을 만든다.
///
/// 규칙의 단일 원천은 위키다:
///   ~/llm-wiki-template/wiki/projects/bodit-app/sheet-schema.md
///
///   소속일자_[업체명]_[내역]_증빙자료명_총금액
///   예: 260805_[영풍문고]_[8월 도서]_영수증_19,000
///
/// 업체명·내역을 대괄호로 감싸는 이유: 값 안에 `_` 가 들어가도 필드 경계가
/// 안 무너진다. 다만 이건 가독성용이다 — 시트에 `증빙링크` 컬럼이 있으므로
/// 파일명을 되파싱할 일은 없다.
///
/// 주의: 사용자가 검토 화면에서 이 파일명을 직접 고칠 수 있다(ADR Decision 12c).
/// 그래서 `sanitizeSegment` 는 자동 생성 경로뿐 아니라 **사용자 입력에도 반드시** 적용한다.
library;

/// 파일시스템이 거부하는 문자들.
///
/// Drive API 자체는 `/` 를 받아주지만, Drive for Desktop 으로 동기화하거나
/// 내려받는 순간 깨진다. 회계 담당자가 로컬로 받아 정리하므로 반드시 막는다.
const _forbidden = r'<>:"/\|?*';

/// 대괄호 구분자를 깨뜨리는 문자.
const _closingBracket = ']';

/// 파일명 한 조각을 안전하게 만든다.
///
/// 금지문자만 바꾸고 나머지는 그대로 통과시킨다 — 공백·한글·`_`·`-`·`,`·괄호 모두 허용.
/// 실무에서 실제로 걸리는 건 사실상 `/` 하나다 (예: "A/S 비용" → "A-S 비용").
String sanitizeSegment(String raw) {
  final buf = StringBuffer();
  for (final rune in raw.runes) {
    final ch = String.fromCharCode(rune);
    if (rune < 0x20 || rune == 0x7F) continue; // 제어문자는 버린다
    if (_forbidden.contains(ch)) {
      buf.write('-');
    } else if (ch == _closingBracket) {
      buf.write(')');
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
    '[${sanitizeSegment(vendor)}]',
    '[${sanitizeSegment(description)}]',
    sanitizeSegment(evidenceType),
    formatAmountForFilename(amount),
  ];
  return parts.join('_');
}
