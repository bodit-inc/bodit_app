import 'package:bodit_app/core/utils/currency.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final usd = currencyOf('USD');
  final jpy = currencyOf('JPY');

  group('소수점 없는 통화(원)는 기존과 똑같다', () {
    test('정수 그대로 보인다', () => expect(krw.format(8000), '8,000'));
    test('시트 값도 정수', () => expect(krw.toSheetValue(8000), 8000));
    test('표시는 원이 뒤에 붙는다', () {
      expect(krw.formatWithCode(19000), '19,000원');
    });
  });

  group('소수점 있는 통화는 최소 단위로 들고 있다', () {
    test('1299 센트 → 12.99', () => expect(usd.format(1299), '12.99'));
    test('5 센트 → 0.05', () => expect(usd.format(5), '0.05'));
    test('100000 센트 → 1,000.00', () => expect(usd.format(100000), '1,000.00'));
    test('시트에는 나눈 값이 들어간다 — 회계가 보는 칸이다', () {
      expect(usd.toSheetValue(1299), 12.99);
    });
    test('코드는 뒤에 붙는다', () {
      expect(usd.formatWithCode(1299), '12.99 USD');
    });
  });

  test('엔·동은 소수점이 없다', () {
    expect(jpy.decimals, 0);
    expect(jpy.format(12000), '12,000');
    expect(currencyOf('VND').decimals, 0);
  });

  test('모르는 코드는 원화로 떨어진다 — 앱이 멈추면 안 된다', () {
    expect(currencyOf('XXX').code, 'KRW');
    expect(currencyOf('').code, 'KRW');
  });

  test('음수', () => expect(usd.format(-1299), '-12.99'));
}
