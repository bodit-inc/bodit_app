/// 한 건이 **목적지별로** 어디까지 갔는지.
///
/// ## 왜 따로 떼어냈나
///
/// 같은 판단을 두 곳이 한다 — 목록의 칩(`SubmissionRow`)과 전송 결과 문구
/// (`SubmissionSender`). 한쪽에만 고치면 화면은 "드라이브 실패" 라고 하는데
/// 스낵바는 다른 말을 하는 일이 생긴다.
///
/// ## 순서가 상태를 정하지 않는다
///
/// 예전에는 "앞이 실패하면 뒤는 미시도" 로 칩을 칠했다. 지금은 세 곳을 서로
/// **독립으로** 보낸다(ADR Decision 7 — 목적지가 셋이고 부분 실패가 가능하다).
/// 드라이브가 실패해도 시트·슬랙은 시도되고 결과도 각자 적히므로, 상태는
/// 그 목적지 자신의 `done` 과 `error` 만 보고 정한다.
library;

import 'package:bodit_app/data/local/queue_db.dart';

/// 제출이 나가는 세 곳. 화면에 적는 이름도 여기서 온다.
enum Destination {
  drive('드라이브'),
  sheets('스프레드시트'),
  slack('슬랙');

  Destination(this.label);

  final String label;
}

/// 목적지 하나의 상태.
enum LegState {
  done('완료'),
  failed('실패'),

  /// 아직 안 나갔는데 실패 사유도 없다 — 시도조차 못 했다는 뜻이다.
  /// (제출 직후이거나, 인가가 없어서 세 곳 다 건너뛴 경우)
  pending('대기');

  LegState(this.label);

  final String label;
}

/// 목적지 하나의 결과.
class LegStatus {
  const LegStatus(this.destination, this.state, {this.error});

  final Destination destination;
  final LegState state;

  /// 예외 원문. **사람이 읽을 문구를 여기서 만들지 않는다** —
  /// 그건 화면(`ErrorDisclosure`)이 붙인다.
  final String? error;

  bool get failed => state == LegState.failed;
}

/// 목적지별 상태를 Drive → Sheets → Slack 순서로 돌려준다.
///
/// 순서는 **보여주는 순서**일 뿐이다. 전송 순서가 상태를 좌우하지 않는다.
List<LegStatus> legStatuses({
  required bool driveDone,
  required bool sheetsDone,
  required bool slackDone,
  String? driveError,
  String? sheetsError,
  String? slackError,
}) {
  LegStatus leg(Destination d, {required bool done, String? error}) {
    // 성공이 사유를 이긴다 — 재시도해서 성공한 뒤에도 지난 사유가 남아 있으면
    // 지우는 쪽을 빠뜨린 것이고, 그때 "완료인데 실패" 로 보이면 안 된다.
    if (done) return LegStatus(d, LegState.done);
    if (error != null) return LegStatus(d, LegState.failed, error: error);
    return LegStatus(d, LegState.pending);
  }

  return [
    leg(Destination.drive, done: driveDone, error: driveError),
    leg(Destination.sheets, done: sheetsDone, error: sheetsError),
    leg(Destination.slack, done: slackDone, error: slackError),
  ];
}

/// 큐에 든 행 하나를 그대로 읽는다.
List<LegStatus> legStatusesOf(Submission row) => legStatuses(
  driveDone: row.driveDone,
  sheetsDone: row.sheetsDone,
  slackDone: row.slackDone,
  driveError: row.driveError,
  sheetsError: row.sheetsError,
  slackError: row.slackError,
);

/// 실패한 목적지들의 사유를 한 덩어리로 잇는다. 하나도 없으면 null.
///
/// **둘 이상 실패할 수 있다.** 세 곳을 독립으로 보내기 때문에 첫 실패만
/// 보여주면 나머지는 조용히 사라진다.
///
/// [blocked] 는 목적지를 가리지 않는 사유(`Submission.lastError`)다.
/// 있으면 맨 앞에 둔다 — 그게 원인이고 나머지는 결과다.
String? failureDetail(List<LegStatus> legs, {String? blocked}) {
  final parts = <String>[
    ?blocked,
    for (final leg in legs)
      if (leg.failed) '${leg.destination.label}: ${leg.error}',
  ];
  return parts.isEmpty ? null : parts.join('\n\n');
}

/// 실패한 목적지 이름만 짧게 — `드라이브·슬랙`. 하나도 없으면 null.
///
/// 스낵바처럼 **접을 수 없는 자리**에 쓴다. 거기에 예외 원문을 그대로 깔면
/// 여러 목적지가 동시에 실패했을 때 화면 절반이 영문 덩어리가 된다 —
/// 원문은 목록의 [실패 사유 보기] 가 맡는다.
String? failedLabels(List<LegStatus> legs) {
  final names = [
    for (final leg in legs)
      if (leg.failed) leg.destination.label,
  ];
  return names.isEmpty ? null : names.join('·');
}
