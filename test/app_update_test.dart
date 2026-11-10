/// 원격 값 → 판정. **"막는다" 가 잘못 나오면 전원이 앱을 못 쓴다.**
///
/// 네트워크는 건드리지 않는다 — `AppUpdateService.read` 가 문자열만 받는
/// 순수 함수로 갈라져 있는 이유다.
library;

import 'package:bodit_app/core/version.dart';
import 'package:bodit_app/data/remote/app_update_service.dart';
import 'package:bodit_app/models/app_update.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = AppVersion.tryParse('1.0.0+5')!;

  AppUpdate read({String latest = '', String minimum = '', String url = ''}) {
    return AppUpdateService.read(
      current: now,
      latest: latest,
      minimum: minimum,
      url: url,
    );
  }

  group('안내', () {
    test('원격 값이 비면 아무것도 하지 않는다 — 기본이 조용함이다', () {
      // 조회 실패·키 이름 오타·아직 안 채운 콘솔이 전부 이 경우로 떨어진다.
      expect(read().urgency, UpdateUrgency.none);
    });

    test('최신이 더 높으면 안내한다', () {
      final u = read(latest: '1.0.1');
      expect(u.urgency, UpdateUrgency.optional);
      expect(u.current, now);
      expect(u.latest.toString(), '1.0.1');
    });

    test('빌드 번호만 올라도 안내한다', () {
      expect(read(latest: '1.0.0+6').urgency, UpdateUrgency.optional);
    });

    test('같거나 낮으면 안내하지 않는다', () {
      expect(read(latest: '1.0.0+5').urgency, UpdateUrgency.none);
      expect(read(latest: '1.0.0+4').urgency, UpdateUrgency.none);
      expect(read(latest: '0.9.9').urgency, UpdateUrgency.none);
    });
  });

  group('차단', () {
    test('최소 버전에 못 미치면 막는다', () {
      expect(read(minimum: '1.0.0+6').urgency, UpdateUrgency.blocked);
    });

    test('최소 버전을 채우면 안내보다 차단이 이긴다', () {
      final u = read(latest: '1.1.0', minimum: '1.0.0+6');
      expect(u.urgency, UpdateUrgency.blocked);
      // 받아야 할 버전은 최신 쪽이다 — 최소 버전만 받고 또 막히면 안 된다.
      expect(u.latest.toString(), '1.1.0');
    });

    test('최소 버전만 있으면 그게 받아야 할 버전이다', () {
      // 화면에 적을 숫자가 없으면 "업데이트하세요" 만 남는다.
      expect(read(minimum: '1.0.0+6').latest.toString(), '1.0.0+6');
    });

    test('읽을 수 없는 최소 버전으로는 막지 않는다', () {
      // 콘솔 오타 하나로 전원이 막히는 쪽이 훨씬 나쁘다.
      for (final bad in ['최신', '1.0.0-rc1', 'v', '  ']) {
        expect(
          read(minimum: bad).urgency,
          UpdateUrgency.none,
          reason: bad,
        );
      }
    });

    test('최소 버전이 비어 있으면 아무도 막히지 않는다 — 평소 상태다', () {
      expect(read(latest: '2.0.0').urgency, UpdateUrgency.optional);
    });
  });

  group('링크', () {
    test('공백만 있으면 없는 것으로 친다', () {
      expect(read(latest: '1.0.1', url: '   ').url, isNull);
    });

    test('앞뒤 공백을 떼고 들고 있는다 — 콘솔에서 붙여넣은 값이다', () {
      expect(
        read(latest: '1.0.1', url: ' https://testflight.apple.com/x ').url,
        'https://testflight.apple.com/x',
      );
    });
  });
}
