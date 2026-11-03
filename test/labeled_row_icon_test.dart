/// `LabeledRow` 가 줄 끝에 **무엇을 달지** 고정한다.
///
/// 규칙이 셋인데 셋 다 눈으로만 확인하던 것이다:
///   - 값을 고치는 줄   → 연필
///   - 다른 화면으로 가는 줄 → `›`
///   - 고칠 길이 없는 줄 → 아무것도 없음
///
/// 세 번째가 실제로 깨져 있었다. 지출날짜에 `onTap: () {}` 가 달려 있어서
/// `›` 가 뜨는데 눌러도 아무 일이 없었다 — 고장난 줄로 보인다.
library;

import 'package:bodit_app/core/widgets/app_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required bool editable,
    VoidCallback? onTap,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: LabeledRow(
          label: '소속날짜',
          value: '2026-08-05',
          editable: editable,
          onTap: onTap,
        ),
      ),
    ),
  );

  final pencil = find.byIcon(Icons.edit_outlined);
  final chevron = find.byIcon(Icons.chevron_right);

  testWidgets('고치는 줄은 연필이다 — 달력·바텀시트로 고르는 줄도 마찬가지다', (tester) async {
    await pump(tester, editable: true, onTap: () {});
    expect(pencil, findsOneWidget);
    expect(chevron, findsNothing);
  });

  testWidgets('다른 화면으로 가는 줄은 › 다', (tester) async {
    await pump(tester, editable: false, onTap: () {});
    expect(chevron, findsOneWidget);
    expect(pencil, findsNothing);
  });

  testWidgets('고칠 길이 없으면 아무것도 안 붙는다 — 지출날짜가 그랬다', (tester) async {
    await pump(tester, editable: false);
    expect(chevron, findsNothing);
    expect(pencil, findsNothing);
  });
}
