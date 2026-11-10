/// 차단이 **맞는 때에만** 걸리는지 본다.
///
/// 이 판정이 틀리면 둘 중 하나다 — 쓸 수 있는 버전이 막히거나(전원이 앱을
/// 못 쓴다), 쓰면 안 되는 버전이 통과한다(막은 의미가 없다).
library;

import 'dart:async';

import 'package:bodit_app/core/version.dart';
import 'package:bodit_app/data/providers.dart';
import 'package:bodit_app/features/update/update_gate.dart';
import 'package:bodit_app/models/app_update.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, AsyncValue<AppUpdate> state) {
    return tester.pumpWidget(
      ProviderScope(
        overrides: [appUpdateProvider.overrideWith((ref) => state.value!)],
        child: const MaterialApp(
          home: UpdateGate(child: Text('앱 화면')),
        ),
      ),
    );
  }

  AppUpdate update(UpdateUrgency urgency) => AppUpdate(
    urgency: urgency,
    current: AppVersion.tryParse('1.0.0+5'),
    latest: AppVersion.tryParse('1.0.1'),
  );

  testWidgets('평소에는 아무것도 하지 않고 앱 화면을 그대로 보여준다', (tester) async {
    await pump(tester, const AsyncData(AppUpdate.none));
    await tester.pumpAndSettle();
    expect(find.text('앱 화면'), findsOne);
  });

  testWidgets('안내만 할 때는 막지 않는다 — 쓰는 것을 멈추지 않는다', (tester) async {
    await pump(tester, AsyncData(update(UpdateUrgency.optional)));
    await tester.pumpAndSettle();
    expect(find.text('앱 화면'), findsOne);
    expect(find.text('업데이트가 필요합니다'), findsNothing);
  });

  testWidgets('최소 버전에 못 미치면 화면을 통째로 덮는다', (tester) async {
    await pump(tester, AsyncData(update(UpdateUrgency.blocked)));
    await tester.pumpAndSettle();
    // 아래 화면이 **남아 있지 않아야** 한다 — 뒤로 가거나 가려진 버튼을
    // 눌러서 빠져나갈 길이 없어야 막은 것이다.
    expect(find.text('앱 화면'), findsNothing);
    expect(find.text('업데이트가 필요합니다'), findsOne);
    expect(find.text('업데이트 받기'), findsOne);
    // 몇에서 몇으로 가는지 적어준다.
    expect(find.text('1.0.0+5 → 1.0.1'), findsOne);
  });

  testWidgets('조회가 아직 안 끝났으면 막지 않는다 — 켤 때마다 기다리게 할 수 없다', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // 영원히 안 끝나는 조회. 비행기 모드에서 10초 기다리는 경우다.
          appUpdateProvider.overrideWith((ref) => Completer<AppUpdate>().future),
        ],
        child: const MaterialApp(
          home: UpdateGate(child: Text('앱 화면')),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('앱 화면'), findsOne);
  });
}
