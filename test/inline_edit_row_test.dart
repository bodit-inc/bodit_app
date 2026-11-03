/// `InlineEditRow` 가 **탭하면 실제로 입력칸이 되는지** 본다.
///
/// 단위 테스트만 있는 레포에 위젯 테스트가 하나 끼어 있는 이유가 있다.
/// `LabeledRow` 의 값 칸이 Row 의 flex 아닌 자식이 된 적이 있는데, Row 는
/// 그런 자식에게 폭을 무한으로 준다. 그러면 `InputDecorator` 가 레이아웃에서
/// 던지고(`cannot have an unbounded width`) 그 예외가
/// `EditableText._openInputConnection` 의 크기 계산까지 끌고 가서
/// **키보드가 아예 안 올라왔다.** 컴파일도 분석도 통과하고, 탭해도 아무 일이
/// 없는 것처럼만 보여서 사람 눈으로는 원인을 못 짚는다.
library;

import 'package:bodit_app/core/widgets/app_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// 실제 화면처럼 스크롤 안에 넣는다 — `_begin` 이 `Scrollable.ensureVisible`
  /// 을 부르므로 스크롤이 없으면 그 경로를 안 타게 된다.
  Future<void> pumpRow(WidgetTester tester, {String? value}) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: InlineEditRow(
                label: '업체명',
                value: value,
                placeholder: '직접 입력',
                onSubmit: (_) {},
              ),
            ),
          ),
        ),
      );

  testWidgets('탭하면 입력칸이 열리고 포커스가 간다 — 키보드가 올라오는 조건이다', (tester) async {
    await pumpRow(tester, value: '영풍문고');
    await tester.tap(find.text('영풍문고'));
    await tester.pump();

    // **레이아웃 예외가 하나라도 있으면 키보드가 안 올라온다.**
    expect(tester.takeException(), isNull);

    final field = find.byType(TextField);
    expect(field, findsOneWidget);
    expect(tester.widget<TextField>(field).focusNode?.hasFocus, isTrue);
  });

  testWidgets('빈 칸도 열린다 — 값이 없을 때가 오히려 흔하다', (tester) async {
    await pumpRow(tester);
    await tester.tap(find.text('직접 입력'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(TextField), findsOneWidget);
  });
}
