/// 소속날짜가 **한 줄에 다 보여야 한다**(`LabeledRow.valueOnOneLine`).
///
/// 좁은 화면에서 라벨 쪽 설명("계산서 발행일자 또는 카드 결제일자")이 날짜를
/// 밀어내 `2026-` / `11-03` 두 줄로 갈렸다 — 한 값이 둘로 보인다.
/// 줄여도 되는 쪽은 설명이다: 앞부분만 읽어도 뜻이 통하지만 반 토막 난
/// 날짜는 못 읽는다.
library;

import 'package:bodit_app/core/widgets/app_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const date = '2026-11-03';
  const subtitle = '계산서 발행일자 또는 카드 결제일자';

  /// [width] 만큼의 폭에 한 줄을 그린다.
  ///
  /// **폭은 실제 기기 값이 아니다.** 테스트 폰트는 글자 하나가 `fontSize`
  /// 만큼의 정사각형이라 같은 글자가 실제보다 넓게 그려진다. 여기서 보는
  /// 것은 절대 폭이 아니라 **좁을 때와 넉넉할 때의 차이**다.
  Future<void> pump(
    WidgetTester tester, {
    required double width,
    required bool oneLine,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: LabeledRow(
              label: '소속날짜',
              value: date,
              subtitle: subtitle,
              editable: true,
              valueOnOneLine: oneLine,
              onTap: () {},
            ),
          ),
        ),
      ),
    ),
  );

  double heightOf(WidgetTester tester, String text) =>
      tester.renderObject<RenderBox>(find.text(text)).size.height;

  testWidgets('좁아도 날짜는 한 줄이다 — 넉넉할 때와 높이가 같다', (tester) async {
    await pump(tester, width: 600, oneLine: true);
    final roomy = heightOf(tester, date);

    await pump(tester, width: 300, oneLine: true);
    expect(tester.takeException(), isNull, reason: '넘치면 안 된다');
    expect(heightOf(tester, date), roomy, reason: '두 줄로 갈라지면 높이가 늘어난다');
  });

  testWidgets('대신 설명이 … 으로 줄어든다', (tester) async {
    await pump(tester, width: 300, oneLine: true);
    final p = tester.renderObject<RenderParagraph>(find.text(subtitle));
    expect(p.didExceedMaxLines, isTrue, reason: '줄어드는 쪽은 설명이다');
  });

  testWidgets('플래그가 없으면 예전처럼 날짜가 갈린다 — 이 테스트가 그걸 잡는다', (tester) async {
    // 위 테스트가 실제로 무언가를 지키고 있는지 확인한다. 이 줄이 통과하지
    // 않으면 그 폭이 좁지 않다는 뜻이고, 첫 테스트는 아무것도 안 막는다.
    await pump(tester, width: 600, oneLine: false);
    final roomy = heightOf(tester, date);

    await pump(tester, width: 300, oneLine: false);
    expect(heightOf(tester, date), greaterThan(roomy));
  });
}
