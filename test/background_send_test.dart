/// 전송줄의 **중복 방지**를 고정한다.
///
/// 제출을 누르면 전송이 백그라운드로 돌고, 그동안 홈의 [전송 시도] 도 누를
/// 수 있다. 같은 행이 두 번 전송줄에 올라가면 **시트에 같은 행이 두 번**
/// 들어가고, append only 라 앱으로 지울 수 없다(ADR Decision 2).
/// 그래서 순서보다 먼저 이걸 테스트로 막는다.
library;

import 'package:bodit_app/data/background_send.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('mergeQueue', () {
    test('이미 전송 중인 id 는 다시 올라가지 않는다', () {
      expect(mergeQueue([3, 2], [2]), [3, 2]);
      // 늘어난 게 없으면 호출부가 전송을 다시 시작하지 않는다 —
      // `start` 가 길이를 보고 판단한다.
      expect(mergeQueue([3, 2], [2, 3]).length, 2);
    });

    test('최근 제출(id 큰 것)이 앞에 온다 — 배너가 그걸 가리킨다', () {
      // 호출부가 어떤 순서로 주든 결과는 같다.
      expect(mergeQueue([], [1, 2, 3]), [3, 2, 1]);
      expect(mergeQueue([], [3, 1, 2]), [3, 2, 1]);
    });

    test('전송 중인 것과 새로 낸 것이 한 줄로 합쳐진다', () {
      expect(mergeQueue([5], [6, 7]), [7, 6, 5]);
    });

    test('빈 입력은 줄을 바꾸지 않는다', () {
      expect(mergeQueue([], []), isEmpty);
      expect(mergeQueue([9], []), [9]);
    });
  });

  group('SendReport', () {
    test('전부 성공하면 실패가 0 이다', () {
      const r = SendReport(total: 3, sent: 3);
      expect(r.failed, 0);
      expect(r.allSent, isTrue);
    });

    test('일부만 성공하면 나머지는 실패로 센다 — 조용히 넘기지 않는다', () {
      const r = SendReport(total: 3, sent: 1, failedWhere: '드라이브');
      expect(r.failed, 2);
      expect(r.allSent, isFalse);
      expect(r.failedWhere, '드라이브');
    });
  });
}
