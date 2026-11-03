/// 금액 키패드의 **배치**를 잰다.
///
/// 눈으로 보면 "비슷해 보인다" 로 넘어가는 것들이다. 예전엔 마지막 줄만
/// `C`·`00`·`0`·`⌫` 네 칸이라 가장 자주 누르는 `00`·`0` 이 가장 좁은 키였다.
/// 비우기를 통화 버튼 아래로 올려 네 줄 모두 세 칸이 됐는데, 그게 유지되는지는
/// 폭을 재야 안다.
library;

import 'package:bodit_app/core/widgets/amount_keypad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// 키패드를 띄운다. 실제처럼 **전화기 크기**로 띄운다 —
  /// 기본 테스트 화면(800x600)은 가로로 넓어서 좁은 화면의 넘침을 놓친다.
  Future<void> pumpKeypad(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1170, 2532)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showAmountKeypad(context, title: '총금액'),
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
  }

  /// 두 버튼은 같은 타입이라 글자로 가린다.
  final currencyButton = find.ancestor(
    of: find.text('KRW'),
    matching: find.byType(OutlinedButton),
  );
  final clearButton = find.ancestor(
    of: find.text('Clear'),
    matching: find.byType(OutlinedButton),
  );

  /// 키 하나가 차지하는 칸. `_Key` 안쪽의 `Center` 가 그 칸 전체다.
  Size keySize(WidgetTester tester, String label) => tester.getSize(
    find.ancestor(of: find.text(label), matching: find.byType(Center)).first,
  );

  testWidgets('00 · 0 · 삭제도 숫자 키와 같은 폭이다', (tester) async {
    await pumpKeypad(tester);

    final seven = keySize(tester, '7').width;
    for (final label in <String>['00', '0', '⌫']) {
      // 소수점 오차는 받아준다 — Expanded 가 남은 폭을 나눌 때 생긴다.
      expect(
        keySize(tester, label).width,
        closeTo(seven, 0.5),
        reason: '$label 이 숫자 키와 폭이 다르다',
      );
    }
  });

  testWidgets('Clear 는 키패드가 아니라 통화 버튼 아래에 있다', (tester) async {
    await pumpKeypad(tester);

    // **버튼을 재지, 글자를 재지 않는다** — 통화 버튼의 `KRW` 는 옆에 붙은
    // 꺾쇠 아이콘 때문에 버튼 가운데가 아니다.
    final currency = tester.getRect(currencyButton);
    final clear = tester.getRect(clearButton);

    // 아래에 있고, 같은 기둥이라 양쪽 끝이 맞는다.
    expect(clear.top, greaterThan(currency.bottom));
    expect(clear.left, closeTo(currency.left, 0.5));
    expect(clear.right, closeTo(currency.right, 0.5));

    // 숫자 `7` 보다 위다 — 키패드에서 빠져나왔다는 뜻이다.
    expect(clear.bottom, lessThan(tester.getRect(find.text('7')).top));

    // 그리고 키패드 마지막 줄은 세 칸이다 — 비우기가 거기 남아 있지 않다.
    expect(find.text('Clear'), findsOneWidget);
  });

  testWidgets('Clear 는 통화 버튼과 같은 버튼이다 — 색·테두리를 흉내내지 않는다', (tester) async {
    await pumpKeypad(tester);

    // 같은 `ButtonStyle` 인스턴스를 쓴다. 모양을 따로 적어두면 한쪽만 바뀐다.
    expect(
      tester.widget<OutlinedButton>(clearButton).style,
      same(tester.widget<OutlinedButton>(currencyButton).style),
    );
    // 같은 기둥이라 폭·높이도 같다.
    expect(tester.getSize(clearButton), tester.getSize(currencyButton));
  });

  testWidgets('좁은 화면에서도 넘치지 않는다', (tester) async {
    await pumpKeypad(tester);
    expect(tester.takeException(), isNull);
  });
}
