/// 비목 화면이 **고르고 눌러야 넘어가는지** 본다.
///
/// 이 화면의 값은 한 번 적히면 되돌릴 수 없다 — 비목은 폼에서 고칠 수 있지만
/// 사용자는 이 화면을 지나면 그 칸을 다시 안 본다. 그래서 세 가지를 테스트로
/// 고정한다:
///
///   - 칩을 눌러도 **넘어가지 않는다**(고르는 것과 넘어가는 것이 다르다)
///   - 버튼 글자가 **무엇이 일어날지** 말한다(`비목없이 다음` / `다음`)
///   - [다음] 을 누르면 그 건에만 적히고 대기열이 한 칸 준다
library;

import 'package:bodit_app/core/theme/tokens.dart';
import 'package:bodit_app/core/widgets/app_widgets.dart';
import 'package:bodit_app/data/providers.dart';
import 'package:bodit_app/features/review/category_screen.dart';
import 'package:bodit_app/features/review/review_controller.dart';
import 'package:bodit_app/models/category_tally.dart';
import 'package:bodit_app/models/entry_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 상태를 심어둔 컨트롤러. `load()` 는 OCR·시트를 타므로 테스트에서 못 부른다.
/// 그 뒤의 상태만 흉내내고 **`answerCategory` 는 실제 코드를 돈다.**
class _SeededController extends ReviewController {
  _SeededController(this._seed);

  final ReviewState _seed;

  @override
  ReviewState build() => _seed;
}

const _master = <String>['도서인쇄비', '복리후생비', '여비교통비', '장비구입비', '사무용품비'];

void main() {
  /// 두 건 중 둘 다 비목이 빈 상태. 첫 건에는 추측 칩이 있다.
  ReviewState seed() => const ReviewState(
    drafts: <EntryDraft>[
      EntryDraft(
        evidencePath: '/tmp/a.jpg',
        vendor: '영풍문고 종로점',
        description: '9월 도서',
        categoryGuesses: <CategoryTally>[
          CategoryTally(category: '도서인쇄비', count: 2),
          CategoryTally(category: '복리후생비', count: 1),
        ],
        categoryGuessReason: '업체명이 비슷한 과거 3건에서 쓴 비목입니다.',
        categoryHints: <String>['장비구입비', '사무용품비'],
        categoryHintReason: '멀티탭은 사무실 비품이다.',
      ),
      EntryDraft(evidencePath: '/tmp/b.jpg', vendor: 'GS25'),
    ],
    categoryQueue: <int>[0, 1],
  );

  Future<ProviderContainer> pump(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        reviewControllerProvider.overrideWith(() => _SeededController(seed())),
        expenseCategoriesProvider.overrideWith((ref) async => _master),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: CategoryScreen(index: 0)),
      ),
    );
    // 마스터 읽기(override 지만 Future 다)가 끝나야 목록이 뜬다.
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('추측 칩과 근거, 그리고 어느 건인지를 보여준다', (tester) async {
    await pump(tester);

    expect(find.text('비목'), findsOneWidget);
    // 여러 건이면 몇 번째 건인지 같이 적는다 — 아니면 지금 무엇의 비목을
    // 고르는지 알 수 없다.
    expect(find.textContaining('1/2번째 건'), findsOneWidget);
    expect(find.textContaining('영풍문고 종로점'), findsOneWidget);
    expect(find.text('도서인쇄비 2건'), findsOneWidget);
    expect(find.text('업체명이 비슷한 과거 3건에서 쓴 비목입니다.'), findsOneWidget);
    // 전체 목록도 같이 있다 — 추측이 틀렸을 때 찾아갈 곳이 있어야 한다.
    expect(find.text('여비교통비'), findsOneWidget);
  });

  testWidgets('아무것도 안 골랐으면 버튼이 `비목없이 다음` 이다', (tester) async {
    final container = await pump(tester);

    expect(find.text('비목없이 다음'), findsOneWidget);
    await tester.tap(find.text('비목없이 다음'));
    await tester.pump();

    final state = container.read(reviewControllerProvider);
    // 안 골랐으면 **아무것도 쓰지 않는다.** 그래도 대기열은 줄어든다.
    expect(state.drafts[0].expenseCategory, isNull);
    expect(state.categoryQueue, <int>[1]);
  });

  testWidgets('칩을 눌러도 넘어가지 않는다 — 넘어가는 것은 하단 버튼이다', (tester) async {
    final container = await pump(tester);

    await tester.tap(find.text('도서인쇄비 2건'));
    await tester.pump();

    // 아직 대기열 그대로. 칩은 고르기만 한다.
    expect(container.read(reviewControllerProvider).categoryQueue, <int>[0, 1]);
    expect(find.text('다음'), findsOneWidget);
    expect(find.text('비목없이 다음'), findsNothing);

    await tester.tap(find.text('다음'));
    await tester.pump();

    final state = container.read(reviewControllerProvider);
    expect(state.drafts[0].expenseCategory, '도서인쇄비');
    // 다른 건은 건드리지 않는다.
    expect(state.drafts[1].expenseCategory, isNull);
    expect(state.categoryQueue, <int>[1]);
  });

  testWidgets('같은 것을 다시 누르면 선택이 풀린다 — 잘못 눌렀을 때 비목 없이 넘어갈 길', (tester) async {
    await pump(tester);

    await tester.tap(find.text('복리후생비 1건'));
    await tester.pump();
    expect(find.text('다음'), findsOneWidget);

    await tester.tap(find.text('복리후생비 1건'));
    await tester.pump();
    expect(find.text('비목없이 다음'), findsOneWidget);
  });

  testWidgets('목록에서 고른 것도 버튼을 눌러야 적힌다', (tester) async {
    final container = await pump(tester);

    await tester.tap(find.text('여비교통비'));
    await tester.pump();
    expect(container.read(reviewControllerProvider).categoryQueue, <int>[0, 1]);

    await tester.tap(find.text('다음'));
    await tester.pump();
    expect(
      container.read(reviewControllerProvider).drafts[0].expenseCategory,
      '여비교통비',
    );
  });

  testWidgets('품목으로 짐작한 비목은 **줄을 따로** 쓰고 출처를 밝힌다', (tester) async {
    final container = await pump(tester);

    // 과거 기록 칩은 건수가 붙고, 짐작 칩은 이름만 붙는다 — 셀 것이 없다.
    expect(find.text('도서인쇄비 2건'), findsOneWidget);
    // 짐작 칩의 이름은 아래 전체 목록에도 같은 글자로 있다. 칩 쪽만 집는다.
    final chip = find.descendant(
      of: find.byType(SuggestChip),
      matching: find.text('장비구입비'),
    );
    expect(chip, findsOneWidget);
    // **어디서 온 값인지 말한다.** 이 말이 없으면 사용자는 이것도 과거
    // 기록인 줄 안다.
    expect(
      find.text('영수증 품목으로 짐작했습니다 — 멀티탭은 사무실 비품이다.'),
      findsOneWidget,
    );

    await tester.tap(chip);
    await tester.pump();
    await tester.tap(find.text('다음'));
    await tester.pump();

    expect(
      container.read(reviewControllerProvider).drafts[0].expenseCategory,
      '장비구입비',
    );
  });

  testWidgets('고른 줄은 체크가 아니라 **줄 전체의 색**으로 표시한다', (tester) async {
    await pump(tester);

    await tester.tap(find.text('여비교통비'));
    await tester.pump();

    final tile = tester.widget<ListTile>(
      find.ancestor(
        of: find.text('여비교통비'),
        matching: find.byType(ListTile),
      ),
    );
    expect(tile.tileColor, AppColors.suggestBg);
    // 오른쪽 끝의 작은 표시는 글자와 반대쪽 끝에 있어서 눈이 두 번 움직인다.
    expect(tile.trailing, isNull);
    expect(find.byIcon(Icons.check), findsNothing);

    // 안 고른 줄은 물들지 않는다 — 전부 같은 색이면 표시가 아니다.
    final other = tester.widget<ListTile>(
      find.ancestor(
        of: find.text('복리후생비'),
        matching: find.byType(ListTile),
      ),
    );
    expect(other.tileColor, isNull);
  });

  testWidgets('마스터를 못 읽어도 막지 않는다 — 추측 칩과 [다음] 은 그대로 쓴다', (tester) async {
    final container = ProviderContainer(
      overrides: [
        reviewControllerProvider.overrideWith(() => _SeededController(seed())),
        expenseCategoriesProvider.overrideWith(
          (ref) async => throw StateError('탭이 비어 있습니다.'),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: CategoryScreen(index: 0)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('비목 목록을 불러오지 못했습니다.'), findsOneWidget);
    // 과거 행에서 온 칩은 마스터와 무관하게 쓸 수 있다.
    await tester.tap(find.text('도서인쇄비 2건'));
    await tester.pump();
    await tester.tap(find.text('다음'));
    await tester.pump();

    expect(
      container.read(reviewControllerProvider).drafts[0].expenseCategory,
      '도서인쇄비',
    );
  });
}
