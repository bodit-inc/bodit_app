/// 통화.
///
/// ## 금액 int 의 의미는 "그 통화의 최소 단위" 다
///
/// 원화는 소수점이 없어서 `8000` = 8,000원 그대로다. 달러는 소수점 2자리라
/// `1299` = $12.99 다. 즉 **저장은 언제나 정수**이고, 화면에 보일 때만 나눈다.
///
/// 이렇게 하면 두 가지가 해결된다:
///   - 돈을 double 로 다루지 않는다. 0.1 + 0.2 문제가 회계에 들어오면 안 된다
///   - 키패드에 소수점 키가 필요 없다. POS 처럼 **오른쪽부터 채우면** 된다
///     (달러에서 1·2·9·9 를 누르면 12.99)
///
/// 원화만 쓰던 기존 데이터는 소수점이 0 이라 의미가 바뀌지 않는다.
library;

class Currency {
  const Currency(this.code, this.symbol, this.name, this.decimals);

  /// ISO 4217 코드. 시트·파일명에 쓰는 것은 이 값이다.
  final String code;
  final String symbol;

  /// 선택 목록에 보일 한국어 이름.
  final String name;

  /// 소수점 자리수(ISO 4217 exponent). 원·엔·동은 0 이다.
  final int decimals;

  /// 최소 단위 정수를 사람이 읽는 문자열로. `1299`(USD) → `12.99`
  String format(int minor) {
    final neg = minor < 0;
    final v = minor.abs();
    final unit = _pow10(decimals);
    final major = _comma((v ~/ unit).toString());
    final body = decimals == 0
        ? major
        : '$major.${(v % unit).toString().padLeft(decimals, '0')}';
    return neg ? '-$body' : body;
  }

  /// 금액에 통화 표시를 붙인 것. 목록·메시지에 쓴다.
  String formatWithCode(int minor) =>
      code == 'KRW' ? '${format(minor)}원' : '${format(minor)} $code';

  /// 시트에 넣을 값. 정수 통화는 int, 소수 통화는 double 이다 —
  /// 회계 담당자가 보는 칸이라 `1299` 가 아니라 `12.99` 여야 한다.
  num toSheetValue(int minor) =>
      decimals == 0 ? minor : minor / _pow10(decimals);

  static int _pow10(int n) {
    var r = 1;
    for (var i = 0; i < n; i++) {
      r *= 10;
    }
    return r;
  }

  static String _comma(String digits) => digits.replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+$)'),
        (m) => '${m[1]},',
      );
}

/// 기본값. 대부분의 증빙이 원화다.
const krw = Currency('KRW', '₩', '대한민국 원', 0);

/// 고를 수 있는 통화.
///
/// 전 세계를 다 넣지 않는다 — 목록이 길면 고르는 게 일이 된다.
/// 실제로 쓸 만한 것만 두고, 필요하면 여기에 추가한다.
const currencies = <Currency>[
  krw,
  Currency('USD', r'$', '미국 달러', 2),
  Currency('JPY', '¥', '일본 엔', 0),
  Currency('EUR', '€', '유로', 2),
  Currency('CNY', '¥', '중국 위안', 2),
  Currency('GBP', '£', '영국 파운드', 2),
  Currency('HKD', r'HK$', '홍콩 달러', 2),
  Currency('TWD', r'NT$', '대만 달러', 2),
  Currency('SGD', r'S$', '싱가포르 달러', 2),
  Currency('VND', '₫', '베트남 동', 0),
  Currency('THB', '฿', '태국 바트', 2),
  Currency('AUD', r'A$', '호주 달러', 2),
  Currency('CAD', r'C$', '캐나다 달러', 2),
  Currency('CHF', 'Fr', '스위스 프랑', 2),
  Currency('INR', '₹', '인도 루피', 2),
  Currency('IDR', 'Rp', '인도네시아 루피아', 2),
  Currency('MYR', 'RM', '말레이시아 링깃', 2),
  Currency('PHP', '₱', '필리핀 페소', 2),
  Currency('AED', 'د.إ', '아랍에미리트 디르함', 2),
];

/// 코드로 찾는다. 모르는 코드는 원화로 본다 — 저장된 값이 깨져도
/// 앱이 멈추지는 않아야 한다.
Currency currencyOf(String code) =>
    currencies.firstWhere((c) => c.code == code, orElse: () => krw);
