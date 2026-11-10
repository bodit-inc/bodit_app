/// 버전 비교. **문자열로 비교하면 틀리는 자리들**을 고정한다.
library;

import 'package:bodit_app/core/version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  AppVersion v(String raw) => AppVersion.tryParse(raw)!;

  group('읽기', () {
    test('빌드 번호까지 읽는다', () {
      expect(v('1.0.0+5').name, [1, 0, 0]);
      expect(v('1.0.0+5').build, 5);
    });

    test('빌드 번호가 없으면 null 이다 — 0 이 아니다', () {
      // 0 으로 치면 "안 적었다" 와 "0번 빌드다" 가 같아진다.
      expect(v('1.0.0').build, isNull);
    });

    test('앞뒤 공백과 v 접두는 흘려보낸다 — 콘솔에서 사람이 적는 값이다', () {
      expect(v(' v1.2.3+4 '), v('1.2.3+4'));
    });

    test('AppInfo 의 화면 표기도 받아준다', () {
      // `1.0.0 (5)` 는 계정 메뉴에 보여주는 표기다. 그 문자열이 흘러들 수 있다.
      expect(v('1.0.0 (5)'), v('1.0.0+5'));
    });

    test('읽을 수 없으면 null — 던지지 않는다', () {
      // 원격 값에 오타가 하나 들어갔다고 앱이 죽으면 안 된다.
      for (final bad in ['', '  ', 'latest', '1.0.0-beta', '1.0.0+x', '1..0', '1.0.0+1+2', null]) {
        expect(AppVersion.tryParse(bad), isNull, reason: '$bad');
      }
    });
  });

  group('비교', () {
    test('사전순이 아니라 숫자로 비교한다', () {
      // 문자열 비교로는 '1.0.10' < '1.0.9' 다. 이 테스트가 그걸 막는다.
      expect(v('1.0.9').isOlderThan(v('1.0.10')), isTrue);
      expect(v('1.0.10').isOlderThan(v('1.0.9')), isFalse);
    });

    test('빠진 자리는 0 이다', () {
      expect(v('1.0'), v('1.0.0'));
      expect(v('1.0').isOlderThan(v('1.0.1')), isTrue);
    });

    test('이름이 같으면 빌드 번호로 가른다 — 가장 흔한 경우다', () {
      // TestFlight 는 버전 이름을 두고 빌드만 올린다.
      expect(v('1.0.0+5').isOlderThan(v('1.0.0+6')), isTrue);
      expect(v('1.0.0+6').isOlderThan(v('1.0.0+5')), isFalse);
    });

    test('한쪽에 빌드 번호가 없으면 빌드로 가르지 않는다', () {
      // 원격에 `1.0.0` 만 적힌 경우. 빈자리를 0 으로 치면 `1.0.0+5` 를 쓰는
      // 사람이 "더 낮다" 가 되거나 그 반대가 된다 — 모르는 것은 비교하지 않는다.
      expect(v('1.0.0+5').isOlderThan(v('1.0.0')), isFalse);
      expect(v('1.0.0').isOlderThan(v('1.0.0+5')), isFalse);
    });

    test('이름이 다르면 빌드 번호는 보지 않는다', () {
      // 새 버전 이름의 빌드 1번이, 이전 이름의 빌드 99번보다 새것이다.
      expect(v('1.0.0+99').isOlderThan(v('1.0.1+1')), isTrue);
    });

    test('표기는 입력과 같은 모양으로 돌아온다', () {
      expect(v('1.0.0+5').toString(), '1.0.0+5');
      expect(v('1.0.0').toString(), '1.0.0');
    });
  });
}
