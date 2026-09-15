/// 금액을 한글로 읽는다. `10005` → `만 오 원`
///
/// ## 왜 필요한가
///
/// 금액은 **0 하나 틀리면 10배**가 된다. 숫자만 보면 `80000` 과 `8000` 이 비슷해
/// 보이지만 "팔만 원" 과 "팔천 원" 은 헷갈릴 수가 없다. 입력할 때와 검토할 때
/// 둘 다 보여준다.
library;

const _digits = <String>['', '일', '이', '삼', '사', '오', '육', '칠', '팔', '구'];

/// 네 자리 안에서 쓰는 단위.
const _small = <String>['', '십', '백', '천'];

/// 네 자리씩 끊어 올라가는 단위.
const _big = <String>['', '만', '억', '조', '경'];

const _pow = <int>[1, 10, 100, 1000];

/// 금액의 한글 표현. 뒤에 `원` 이 붙는다.
///
/// 규칙:
///   - 0 인 자리는 읽지 않는다 (`10005` → 만 오)
///   - 십·백·천 앞의 1 은 읽지 않는다 (`10` → 십, `일십` 아님)
///   - **만 앞의 1 도 읽지 않는다** (`10000` → 만). 다만 억·조는 읽는다
///     (`100000000` → 일억). 우리말이 그렇게 쓴다
String readKoreanAmount(int amount) {
  if (amount == 0) return '영 원';

  final negative = amount < 0;
  var rest = amount.abs();
  final parts = <String>[];

  for (var bigIndex = 0; rest > 0; bigIndex++) {
    final group = rest % 10000;
    rest ~/= 10000;
    if (group == 0) continue;

    var text = _readGroup(group);
    final unit = _big[bigIndex];
    if (unit.isNotEmpty) {
      // 만 은 "일만" 이라 하지 않는다. 억·조는 "일억"·"일조" 라고 한다.
      if (group == 1 && bigIndex == 1) text = '';
      text = '$text$unit';
    }
    parts.add(text);
  }

  final body = parts.reversed.join(' ');
  return '${negative ? '마이너스 ' : ''}$body 원';
}

/// 네 자리 한 덩어리를 읽는다. 덩어리 안에서는 띄어쓰지 않는다.
String _readGroup(int group) {
  final out = StringBuffer();
  for (var pos = 3; pos >= 0; pos--) {
    final digit = (group ~/ _pow[pos]) % 10;
    if (digit == 0) continue;
    // 십·백·천 앞의 1 은 생략한다. 일의 자리는 그대로 읽는다.
    if (digit != 1 || pos == 0) out.write(_digits[digit]);
    out.write(_small[pos]);
  }
  return out.toString();
}

/// 천 단위 쉼표. `8000` → `8,000`
String formatWon(int amount) => amount.toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'),
      (m) => '${m[1]},',
    );
