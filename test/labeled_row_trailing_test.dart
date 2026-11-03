/// **상태 알약은 라벨 쪽이 길어도 보인다**(`LabeledRow.trailing`).
///
/// 제출 목록에서 왼쪽(일자 + 보조 문구)이 길면 알약이 화면 밖으로 밀려
/// 통째로 안 보였다 — 그 줄이 전송 중인지 실패인지 알 수 없었다.
/// `Row` 가 flex 아닌 자식(라벨 쪽)에게 폭을 무한으로 주기 때문이라,
/// 라벨 쪽에 상한을 걸어 값·알약 자리를 남긴다.
library;

import 'package:bodit_app/core/widgets/app_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 테스트 폰트는 글자 하나가 `fontSize` 만큼의 정사각형이라 실제보다 넓다.
  // 여기서 보는 것은 절대 폭이 아니라 **왼쪽이 길 때 알약이 남는지**다.
  const width = 300.0;
  const long = '전송하고 있습니다 — 끝나면 결과가 표시됩니다';

  Future<void> pump(WidgetTester tester, {required String subtitle}) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                child: LabeledRow(
                  label: '5일',
                  value: '영풍문고_8월 도서 구입_영수증_19,000',
                  subtitle: subtitle,
                  maxLines: 2,
                  trailing: const StatusPill('전송 중', tone: PillTone.waiting),
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      );

  testWidgets('왼쪽이 길어도 알약은 줄 안에 있다', (tester) async {
    await pump(tester, subtitle: long);
    expect(tester.takeException(), isNull, reason: '넘치면 안 된다');

    final row = tester.getRect(find.byType(SizedBox).first);
    final pill = tester.getRect(find.byType(StatusPill));
    expect(pill.width, greaterThan(0));
    // 왼쪽으로 밀려 잘리지도, 오른쪽으로 빠져나가지도 않는다.
    expect(pill.left, greaterThanOrEqualTo(row.left));
    expect(pill.right, lessThanOrEqualTo(row.right));
  });

  testWidgets('그 대신 라벨 쪽이 줄의 절반까지만 쓴다', (tester) async {
    // 위 테스트가 무엇 때문에 통과하는지 못 박는다 — 왼쪽이 접히지 않으면
    // 알약 자리가 남을 이유가 없다.
    await pump(tester, subtitle: long);
    expect(
      tester.getRect(find.text(long)).width,
      lessThanOrEqualTo(width / 2),
      reason: '보조 문구가 줄 절반을 넘으면 값·알약 자리가 사라진다',
    );
  });

  testWidgets('짧으면 예전처럼 값이 남은 폭을 다 받는다', (tester) async {
    // 상한이지 반칼이 아니다. 왼쪽이 짧은 줄은 좁아지지 않아야 한다.
    await pump(tester, subtitle: '전송중');
    final roomy = tester.getRect(find.textContaining('영풍문고')).width;

    await pump(tester, subtitle: long);
    expect(
      tester.getRect(find.textContaining('영풍문고')).width,
      lessThan(roomy),
      reason: '왼쪽이 길면 값이 줄어든다 — 짧을 때는 그만큼 넓었다는 뜻',
    );
  });
}
