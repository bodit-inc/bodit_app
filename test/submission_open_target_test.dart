/// 제출 목록에서 행을 탭했을 때 **어디로 가는가**.
///
/// 네 갈래가 조용히 뒤바뀌면 사용자는 왜 다른 곳으로 가는지 모른다. 특히
/// `slackUrl` 이 없는 과거 건을 "아무 데도 안 나갔다" 로 떨어뜨리면 이미
/// 올라간 건을 안 올라갔다고 말하는 셈이다.
library;

import 'package:bodit_app/data/local/queue_db.dart';
import 'package:bodit_app/features/submissions/submission_row.dart';
import 'package:flutter_test/flutter_test.dart';

/// 전송 상태만 다르게 주는 큐 행.
Submission row({
  bool sheetsDone = false,
  bool driveDone = false,
  bool slackDone = false,
  String? driveUrl,
  String? slackUrl,
}) {
  return Submission(
    id: 1,
    localId: 'local-1',
    entryKind: 'purchase',
    entryJson: '{}',
    evidencePath: '/tmp/a.jpg',
    filename: '260805_영풍문고_8월 도서_영수증_19,000',
    sheetsDone: sheetsDone,
    driveDone: driveDone,
    slackDone: slackDone,
    driveUrl: driveUrl,
    slackUrl: slackUrl,
    createdAt: DateTime(2026, 8, 5),
  );
}

void main() {
  group('탭했을 때 갈 곳', () {
    test('링크가 있으면 그 파일로 간다', () {
      final r = row(
        sheetsDone: true,
        driveDone: true,
        slackDone: true,
        driveUrl: 'https://drive.example/f',
        slackUrl: 'https://slack.example/files/x',
      );
      expect(SubmissionRow.targetOf(r), OpenTarget.slackMessage);
    });

    test('올라갔는데 링크가 없으면 채널로 간다', () {
      // `slackUrl` 컬럼이 생기기 전에 보낸 건이다. 백필할 방법이 없다 —
      // 그렇다고 "안 올라갔다" 고 하면 거짓말이다.
      final r = row(
        sheetsDone: true,
        driveDone: true,
        slackDone: true,
        driveUrl: 'https://drive.example/f',
      );
      expect(SubmissionRow.targetOf(r), OpenTarget.slackChannel);
    });

    test('Slack 전이고 Drive 에 있으면 증빙 파일로 간다', () {
      // 부분 실패 — 무엇을 올렸는지는 확인할 수 있다.
      final r = row(driveDone: true, driveUrl: 'https://drive.example/f');
      expect(SubmissionRow.targetOf(r), OpenTarget.drive);
    });

    test('아무 데도 안 나갔으면 갈 곳이 없다', () {
      expect(SubmissionRow.targetOf(row()), OpenTarget.nothing);
    });

    test('Drive 부터 실패하면 Slack 링크가 있을 수 없다', () {
      // 전송은 Drive → Sheets → Slack 순서라 앞이 실패하면 뒤는 시도하지
      // 않는다. 그 상태에서도 갈 곳을 말할 수 있어야 한다.
      expect(SubmissionRow.targetOf(row(sheetsDone: true)), OpenTarget.nothing);
    });

    test('Slack 만 완료된 이상한 상태에서도 링크를 따른다', () {
      // 순서상 생기지 않지만, 생겼다면 링크가 가장 정확한 정보다.
      final r = row(slackDone: true, slackUrl: 'https://slack.example/files/x');
      expect(SubmissionRow.targetOf(r), OpenTarget.slackMessage);
    });
  });
}
