/// `confirmLeave` — 쓰던 내용을 버리고 나갈지 묻는 창.
///
/// 문구와 **버튼 순서**를 테스트로 고정한다. 검토 화면의 값은 어디에도
/// 저장돼 있지 않아서, 두 버튼이 뒤바뀌면 한 번의 오탭으로 OCR 결과와 손으로
/// 고친 값이 전부 사라진다 — 되살릴 길은 다시 찍는 것뿐이다.
/// "머무는 쪽이 왼쪽" 은 눈으로 보고 넘길 규칙이 아니다.
library;

import 'package:bodit_app/core/widgets/app_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// 버튼을 눌러 창을 닫고, 창이 돌려준 값을 본다.
  Future<bool?> tapAndGet(WidgetTester tester, {String? label}) async {
    bool? answer;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => answer = await confirmLeave(context),
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();

    if (label != null) {
      await tester.tap(find.text(label));
    } else {
      // 창 밖 — 가장 왼쪽 위를 누른다.
      await tester.tapAt(const Offset(10, 10));
    }
    await tester.pumpAndSettle();
    return answer;
  }

  testWidgets('"뒤로가기" 를 누르면 벗어난다', (tester) async {
    expect(await tapAndGet(tester, label: '뒤로가기'), isTrue);
  });

  testWidgets('"계속 작성하기" 를 누르면 머문다', (tester) async {
    expect(await tapAndGet(tester, label: '계속 작성하기'), isFalse);
  });

  testWidgets('창 밖을 눌러도 머문다 — 실수로 버리는 쪽보다 취소되는 쪽이 낫다', (tester) async {
    expect(await tapAndGet(tester), isFalse);
  });

  testWidgets('무엇이 사라지는지 적는다. 머무는 버튼이 왼쪽이다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => confirmLeave(context),
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();

    expect(find.text('화면을 벗어나면 현재 내용이 모두 사라집니다.'), findsOneWidget);

    final stay = tester.getCenter(find.text('계속 작성하기'));
    final leave = tester.getCenter(find.text('뒤로가기'));
    expect(
      stay.dx,
      lessThan(leave.dx),
      reason: '머무는 쪽이 왼쪽이어야 한다 — 오탭이 버리는 쪽으로 가면 안 된다.',
    );
  });
}
