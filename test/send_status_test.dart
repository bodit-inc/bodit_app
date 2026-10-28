/// 목적지별 상태 계산.
///
/// 세 곳을 **독립으로** 보내기 시작하면서 "앞이 실패하면 뒤는 미시도" 규칙이
/// 사라졌다. 그 규칙이 되살아나면 드라이브만 실패한 건이 시트·슬랙까지
/// 실패로 보이고, 사용자는 멀쩡히 올라간 것을 다시 보내려 한다.
library;

import 'package:bodit_app/data/send_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('legStatuses', () {
    test('앞이 실패해도 뒤는 각자의 결과로 칠한다', () {
      final legs = legStatuses(
        driveDone: false,
        driveError: '403 Insufficient permissions for the specified parent.',
        sheetsDone: true,
        slackDone: true,
      );

      expect(legs.map((l) => l.state), [
        LegState.failed,
        LegState.done,
        LegState.done,
      ]);
    });

    test('아직 안 나갔고 사유도 없으면 대기다', () {
      final legs = legStatuses(
        driveDone: false,
        sheetsDone: false,
        slackDone: false,
      );

      expect(legs.every((l) => l.state == LegState.pending), isTrue);
    });

    test('성공이 지난 사유를 이긴다', () {
      final legs = legStatuses(
        driveDone: true,
        driveError: '지난번 실패',
        sheetsDone: false,
        slackDone: false,
      );

      expect(legs.first.state, LegState.done);
    });
  });

  group('failureDetail', () {
    test('동시에 실패한 둘을 모두 담는다', () {
      final detail = failureDetail(
        legStatuses(
          driveDone: false,
          driveError: '403 parent',
          sheetsDone: true,
          slackDone: false,
          slackError: 'network',
        ),
      );

      expect(detail, contains('드라이브: 403 parent'));
      expect(detail, contains('슬랙: network'));
      // 성공한 곳은 적지 않는다.
      expect(detail, isNot(contains('스프레드시트')));
    });

    test('목적지를 가리지 않는 사유가 맨 앞에 온다', () {
      final detail = failureDetail(
        legStatuses(
          driveDone: false,
          driveError: '403 parent',
          sheetsDone: false,
          slackDone: false,
        ),
        blocked: 'Google 인가가 없습니다. 다시 로그인해 주세요.',
      );

      expect(detail, startsWith('Google 인가가 없습니다'));
    });

    test('실패가 없으면 null — 멀쩡한 건에 사유 보기가 붙으면 안 된다', () {
      final detail = failureDetail(
        legStatuses(driveDone: true, sheetsDone: true, slackDone: true),
      );

      expect(detail, isNull);
    });
  });
}
