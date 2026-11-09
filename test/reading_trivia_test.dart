/// 로딩 중에 띄우는 소 상식의 **분량과 형식**을 고정한다.
///
/// 글을 늘리는 일은 쉽고 즐거워서, 다음에 추가하는 사람은 세 문장을 쓴다.
/// 그런데 로딩은 5초쯤에 끝나므로 길어지면 **매번 중간에 끊긴다** —
/// 끊기는 글은 없는 것보다 답답하다. 사람이 지킬 규칙 대신 테스트로 둔다.
library;

import 'dart:math';

import 'package:bodit_app/features/review/reading_trivia.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('목록이 비어 있지 않다 — 비면 로딩 화면에서 터진다', () {
    // 화면이 `_trivia[_index]` 로 바로 꺼낸다. 폴백을 두지 않은 이유가
    // 이 테스트다 — 비는 경우를 코드로 감싸는 대신 비지 않게 막는다.
    expect(cowTrivia, isNotEmpty);
  });

  test('한 꼭지는 로딩 시간 안에 읽히는 길이다', () {
    for (final t in cowTrivia) {
      expect(
        t.length,
        lessThanOrEqualTo(triviaMaxLength),
        reason:
            '너무 길다 (${t.length}자): $t\n'
            '로딩은 5초쯤에 끝난다. 두 문장으로 줄이거나 두 꼭지로 쪼개세요.',
      );
    }
  });

  test('같은 글이 두 번 들어 있지 않다', () {
    expect(cowTrivia.toSet().length, cowTrivia.length);
  });

  test('꼭지는 존댓말로 끝난다 — 화면에서 사용자에게 하는 말이다', () {
    // 주석·문서는 평어체지만 화면 문구는 앱 전체가 존댓말이다. 한 화면에서
    // 말투가 갈리면 상식 쪽이 남이 쓴 글처럼 읽힌다.
    //
    // **`-니다.` 만 보면 좁다.** "조심히 다뤄주십시오." 처럼 권하는 말도
    // 존댓말인데 어미가 다르다 — 실제로 그 문장 때문에 한 번 걸렸다.
    // 그래서 어미 하나가 아니라 **존댓말 종결 목록**으로 본다.
    const endings = ['니다.', '십시오.', '세요.', '죠?', '까요?'];
    for (final t in cowTrivia) {
      expect(
        endings.any(t.endsWith),
        isTrue,
        reason:
            '존댓말로 끝나지 않는다: $t\n'
            '허용하는 끝맺음: ${endings.join(" · ")}',
      );
    }
  });

  test('섞어도 모든 꼭지가 한 번씩 들어 있고 원본은 그대로다', () {
    // 섞은 사본을 순서대로 쓰는 것이 "같은 글이 연달아 나오지 않는다" 의
    // 근거다. 사본이 원본을 건드리면 const 목록이 깨진다.
    final before = [...cowTrivia];
    final shuffled = shuffledTrivia(Random(42));

    expect(shuffled.length, cowTrivia.length);
    expect(shuffled.toSet(), cowTrivia.toSet());
    expect(cowTrivia, before);
  });
}
