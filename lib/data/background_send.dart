/// 제출을 누른 뒤의 전송을 **화면 밖에서** 돌린다.
///
/// ## 왜 기다리지 않나
///
/// 한 건을 보내는 데 수십 초가 걸린다 — Drive 업로드 + 시트 append + Slack
/// 파일 업로드가 전부 네트워크 왕복이고, 사진이 크면 더 길다. 그동안 검토
/// 화면은 잠겨 있었다(`AbsorbPointer`). 사용자는 다음 영수증을 찍지도,
/// 목록을 보지도 못하고 스피너만 봤다.
///
/// 그래서 **큐에 넣는 것까지만 기다린다**(로컬 쓰기라 즉시 끝난다). 전송은
/// 여기로 넘기고 화면은 홈으로 돌아간다. 진행은 상단 배너(`SendingBanner`)가
/// 보여주고, 끝나면 앱 전체가 보는 스낵바가 결과를 말한다.
///
/// ## ADR 12a 를 깨지 않는다 — 재전송은 여전히 수동이다
///
/// 여기가 돌리는 것은 **사용자가 버튼을 눌러 시작한** 전송뿐이다:
/// [BackgroundSendController.start] 는 [제출], [BackgroundSendController.startPending]
/// 은 홈의 [전송 시도] 가 부른다. connectivity 리스너도, 주기적으로 깨는
/// 워커도 없다. 앱이 죽으면 전송도 멈추고 건은 큐에 남는다 —
/// 다시 켜서 [전송 시도] 를 누르면 된다.
///
/// ## 한 번에 한 건씩만 보낸다
///
/// 전송줄(`inFlight`)을 하나 두고 순서대로 비운다. 동시에 여러 건을 보내면
/// 같은 날짜의 Drive 폴더를 둘이 같이 만들어 폴더가 두 개 생기고
/// (`DriveFolderIndex` 가 막는 그 상황이다), 사진 업로드가 겹쳐 느려진다.
///
/// 이미 전송줄에 있는 id 는 다시 올리지 않는다 — **같은 행을 두 번 보내면
/// 시트에 같은 행이 두 번 들어간다**(append only 라 지울 수 없다).
library;

import 'dart:async';

import 'package:bodit_app/core/log.dart';
import 'package:bodit_app/data/providers.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 한 묶음(전송줄이 빌 때까지)의 결과. 스낵바가 이걸로 문구를 만든다.
class SendReport {
  const SendReport({required this.total, required this.sent, this.failedWhere});

  final int total;

  /// 세 목적지 전부 성공한 건수.
  final int sent;

  /// 실패한 목적지 이름만 짧게 — `드라이브·슬랙`. 예외 원문은 목록의
  /// [실패 사유 보기] 가 맡는다(스낵바는 접을 수 없는 자리다).
  final String? failedWhere;

  int get failed => total - sent;
  bool get allSent => failed == 0;
}

class BackgroundSendState {
  const BackgroundSendState({this.inFlight = const [], this.report});

  /// 전송 중이거나 차례를 기다리는 큐 행 id. **id 가 큰 것(최근 제출)이 앞**이다.
  ///
  /// 보여줄 때와 보낼 때의 순서가 반대다 — 배너는 최근 제출을 가리켜야
  /// 하지만(방금 누른 그것이다), 전송은 들어온 순서대로 한다.
  final List<int> inFlight;

  /// 마지막으로 비운 묶음의 결과. 화면이 한 번 읽고
  /// [BackgroundSendController.consumeReport] 로 지운다 — 안 지우면 화면이
  /// 다시 그려질 때마다 같은 스낵바가 뜬다.
  final SendReport? report;

  bool get isSending => inFlight.isNotEmpty;

  int get count => inFlight.length;

  /// 배너를 눌렀을 때 데려갈 건 — 가장 최근에 제출한 것.
  int? get newestId => inFlight.isEmpty ? null : inFlight.first;
}

/// 전송줄에 올릴 목록을 만든다.
///
/// **중복을 걷어내는 것이 핵심이다** — 이미 전송줄에 있는 id 를 다시 올리면
/// 같은 행을 두 번 보내고, 시트는 append only 라 생긴 중복 행을 앱으로
/// 지울 수 없다.
///
/// 순서는 **id 내림차순**(최근 제출이 앞)으로 세운다. 호출부가 어떤 순서로
/// 주든 배너가 가리키는 건(앞)과 전송 순서(뒤에서부터)가 달라지지 않는다.
@visibleForTesting
List<int> mergeQueue(List<int> current, Iterable<int> added) {
  return <int>{...current, ...added}.toList()..sort((a, b) => b.compareTo(a));
}

class BackgroundSendController extends Notifier<BackgroundSendState> {
  @override
  BackgroundSendState build() => const BackgroundSendState();

  /// 전송줄을 비우는 루프가 돌고 있는지. 두 개가 같이 돌면 같은 건을
  /// 두 번 보낼 수 있다.
  bool _draining = false;

  /// 방금 큐에 넣은 건들을 전송줄에 올린다. **기다리지 않는다.**
  void start(Iterable<int> ids) {
    final next = mergeQueue(state.inFlight, ids);
    // 늘어난 게 없으면 이미 전송 중인 건들이다 — 다시 보내지 않는다.
    if (next.length == state.inFlight.length) return;

    state = BackgroundSendState(inFlight: next, report: state.report);
    if (!_draining) unawaited(_drain());
  }

  /// 큐에 남아 있는 것 전부. 홈의 [전송 시도] 가 부른다.
  ///
  /// 이미 전송 중인 건은 [start] 가 걸러낸다 — 배너가 "전송 중" 인 동안
  /// 버튼을 눌러도 같은 행이 두 번 나가지 않는다.
  Future<void> startPending() async {
    final rows = await ref.read(queueDbProvider).pending();
    start(rows.map((r) => r.id));
  }

  /// 결과를 읽었다고 알린다. 안 지우면 같은 스낵바가 반복해서 뜬다.
  void consumeReport() {
    if (state.report == null) return;
    state = BackgroundSendState(inFlight: state.inFlight);
  }

  /// 전송줄이 빌 때까지 한 건씩 보낸다.
  Future<void> _drain() async {
    _draining = true;
    final db = ref.read(queueDbProvider);
    final sender = ref.read(submissionSenderProvider);

    var total = 0;
    var sent = 0;
    String? failedWhere;

    try {
      while (state.inFlight.isNotEmpty) {
        // 오래된 것부터 보낸다. 목록은 최근순으로 보여주지만 전송은 들어온
        // 순서대로 — `SubmissionSender.sendPending` 과 같은 규칙이다.
        final id = state.inFlight.last;
        try {
          final row = await db.byId(id);
          // 보내기 전에 사용자가 목록에서 지웠을 수 있다. 그건 실패가 아니다.
          if (row != null) {
            total++;
            final outcome = await sender.sendOne(row);
            if (outcome.allDone) {
              sent++;
            } else {
              failedWhere ??= outcome.failedWhere;
            }
          }
        } on Object catch (e) {
          // `sendOne` 은 목적지마다 따로 try 하므로 여기까지 오는 것은 큐
          // 읽기나 인가처럼 **목적지 바깥**에서 터진 것이다.
          //
          // 그 사유를 행에 적어둔다. 안 적으면 목록에는 "대기" 로만 남아
          // 왜 안 갔는지 아무도 모른다 — 조용히 실패하면 안 된다.
          log.e('백그라운드 전송이 예상 못 한 곳에서 실패했다 (id=$id): $e');
          final row = await db.byId(id);
          if (row != null) {
            await db.updateRow(
              row.copyWith(
                lastError: Value('$e'),
                lastTriedAt: Value(DateTime.now()),
              ),
            );
          }
        } finally {
          // 성공이든 실패든 전송줄에서는 빠진다. 재시도는 수동이다(ADR 12a).
          state = BackgroundSendState(
            inFlight: [
              for (final other in state.inFlight)
                if (other != id) other,
            ],
            report: state.report,
          );
        }
      }
    } finally {
      _draining = false;
      // 전송줄이 비었다 = 묶음이 끝났다. 결과를 내놓는다.
      //
      // 도중에 사용자가 또 제출하면 그 건도 같은 묶음에 섞인다 — 그러면
      // 스낵바가 둘을 합쳐 말한다. 묶음을 따로 세어 두 번 띄우는 것보다
      // 낫다(두 번째 스낵바가 첫 번째를 밀어내 아무도 못 읽는다).
      state = BackgroundSendState(
        report: SendReport(total: total, sent: sent, failedWhere: failedWhere),
      );
    }
  }
}

/// 홈·검토·목록이 같이 본다. **autoDispose 가 아니다** — 화면이 사라져도
/// 전송은 계속돼야 한다. 그게 이 provider 의 존재 이유다.
final backgroundSendProvider =
    NotifierProvider<BackgroundSendController, BackgroundSendState>(
      BackgroundSendController.new,
    );
