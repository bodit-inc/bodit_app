/// 큐에 쌓인 건을 세 목적지로 보낸다.
///
/// ## 세 곳은 서로 독립이다: 하나가 실패해도 나머지를 보낸다
///
/// 순서는 Drive → Sheets → Slack 이지만 **의존이 아니라 순서일 뿐이다.**
/// 예전에는 Drive 가 실패하면 나머지 둘을 아예 시도하지 않았다. 그러면
/// Drive 폴더 권한 하나 때문에 시트 행도, 팀이 보는 Slack 글도 안 나간다 —
/// 실제로 다른 계정으로 테스트하다 403(`Insufficient permissions for the
/// specified parent`)에 걸려 세 곳 다 멈췄다.
///
/// 그래서 지금은 목적지마다 따로 try 한다. 실패 사유도 목적지별로 적는다
/// (`driveError`·`sheetsError`·`slackError`) — 둘이 동시에 실패할 수 있는데
/// 한 칸에 덮어쓰면 하나가 조용히 사라진다.
///
/// ### 대가: 증빙링크가 빈 시트 행이 생길 수 있다
///
/// 시트의 `증빙링크` 는 Drive URL 이다. Drive 가 실패한 채로 시트 행이
/// 들어가면 그 칸은 비어서 나간다. **시트는 append 만 한다**(ADR Decision 2·14)
/// — 나중에 Drive 재시도가 성공해도 그 행을 찾아가 채울 수 없다. 행에 키
/// 컬럼이 없으니 지목할 방법도 없다.
///
/// 그래도 이쪽을 골랐다: 회계가 보는 매입내역 행이 아예 안 들어가는 쪽이 더
/// 나쁘다. 링크가 빈 행은 사람이 Drive 에서 파일을 찾아 붙이면 되지만,
/// 없는 행은 아무도 모른다. 링크를 꼭 붙여야 하면 Drive 권한을 고친 뒤
/// 그 건을 **전송 전에** 다시 만드는 게 맞다.
///
/// ## 부분 실패
///
/// 목적지별 완료 여부를 큐에 따로 들고 있어서, 재시도할 때 **이미 끝난 곳은
/// 건너뛴다.** 이게 없으면 Slack 만 실패한 건을 재시도할 때 시트에 같은 행이
/// 두 번 들어간다.
///
/// ## 전송은 수동이다
///
/// 사용자가 [전송 시도] 를 눌러야 이 코드가 돈다(ADR Decision 12a).
/// 백그라운드 워커도 connectivity 리스너도 없다.
library;

import 'dart:convert';
import 'dart:io';

import 'package:bodit_app/data/local/queue_db.dart';
import 'package:bodit_app/data/remote/drive_repository.dart';
import 'package:bodit_app/data/remote/google_auth.dart';
import 'package:bodit_app/data/remote/sheets_repository.dart';
import 'package:bodit_app/data/remote/slack_repository.dart';
import 'package:bodit_app/data/send_status.dart';
import 'package:bodit_app/models/purchase_entry.dart';
import 'package:bodit_app/models/sheet_row.dart';
import 'package:drift/drift.dart' show Value;

/// 한 건의 전송 결과.
class SendOutcome {
  const SendOutcome({
    required this.id,
    required this.allDone,
    this.error,
    this.failedWhere,
  });

  final int id;
  final bool allDone;

  /// 실패한 목적지 이름만 짧게 — `드라이브·슬랙`. 스낵바처럼 **접을 수 없는
  /// 자리**가 쓴다. 예외 원문은 [error] 쪽이다.
  final String? failedWhere;

  /// 사용자에게 그대로 보여준다 — 조용히 실패하면 안 된다.
  ///
  /// **여러 목적지가 한꺼번에 실패할 수 있다.** 그래서 첫 사유 하나가 아니라
  /// 실패한 목적지를 전부 담은 덩어리다(`failureDetail`).
  final String? error;
}

class SubmissionSender {
  const SubmissionSender({
    required this.db,
    required this.auth,
    required this.drive,
    required this.sheets,
    required this.slack,
  });

  final QueueDb db;
  final GoogleAuthService auth;
  final DriveRepository drive;
  final SheetsRepository sheets;
  final SlackRepository slack;

  /// 대기 중인 걸 순서대로 보낸다. 한 건이 실패해도 다음 건을 계속 시도한다.
  Future<List<SendOutcome>> sendPending() async {
    final rows = await db.pending();
    final out = <SendOutcome>[];
    // 오래된 것부터 보낸다 — 목록은 최근순으로 보여주지만 전송은 들어온 순서대로.
    for (final row in rows.reversed) {
      out.add(await sendOne(row));
    }
    return out;
  }

  /// 한 건을 보낸다. 이미 끝난 목적지는 건너뛰고, 실패한 목적지는 **다음
  /// 목적지를 막지 않는다.**
  Future<SendOutcome> sendOne(Submission row) async {
    // AuthClient 를 캐싱하지 않는다 — 다리 패키지가 만료를 임의로 365일 뒤로
    // 박아두고 refresh token 을 안 넣어서, 오래 들고 있으면 조용히 401 이 난다.
    final client = await auth.authorizedClient();
    if (client == null) {
      return await _blocked(row, 'Google 인가가 없습니다. 다시 로그인해 주세요.');
    }

    final entry = _decode(row);
    final file = File(row.evidencePath);
    if (!file.existsSync()) {
      // 증빙 원본이 없으면 세 곳 다 보낼 수 없다 — Slack 도 사진을 올린다.
      return await _blocked(row, '증빙 원본을 찾을 수 없습니다: ${row.evidencePath}');
    }

    // 여기까지 왔으면 목적지를 가리지 않는 장애물은 없다. 지난 사유를 지운다.
    var current = row.copyWith(lastError: const Value(null));

    // ── 1. Drive ────────────────────────────────────────────────
    //    가장 먼저 보낸다 — 성공하면 그 URL 이 시트 행의 `증빙링크` 가 된다.
    //    실패해도 여기서 멈추지 않는다(위 설명 참조).
    if (!current.driveDone) {
      try {
        final url = await drive.upload(
          client: client,
          source: file,
          filename: current.filename,
          // 날짜 폴더를 정하는 날짜다. 파일명 접두와 **같은 소속일자**를
          // 넘긴다 — 둘을 따로 계산하면 `260805` 폴더에 `260806_…` 이 들어간다.
          belongDate: entry.belongDate,
        );
        current = current.copyWith(
          driveDone: true,
          driveUrl: Value(url),
          driveError: const Value(null),
        );
      } on Object catch (e) {
        current = current.copyWith(driveError: Value('$e'));
      }
      await db.updateRow(current);
    }

    // ── 2. Sheets ───────────────────────────────────────────────
    //    Drive 가 실패했으면 `증빙링크` 가 빈 채로 들어간다. append-only 라
    //    나중에 못 채운다 — 알고 감수한 쪽이다(위 설명 참조).
    if (!current.sheetsDone) {
      try {
        await sheets.appendRow(
          client: client,
          row: entry.copyWith(evidenceUrl: current.driveUrl ?? ''),
        );
        current = current.copyWith(
          sheetsDone: true,
          sheetsError: const Value(null),
        );
      } on Object catch (e) {
        current = current.copyWith(sheetsError: Value('$e'));
      }
      await db.updateRow(current);
    }

    // ── 3. Slack ────────────────────────────────────────────────
    //    사진을 직접 올리므로 Drive URL 이 없어도 그대로 나간다.
    if (!current.slackDone) {
      try {
        final slackUrl = await slack.postEvidence(
          image: file,
          filename: current.filename,
          belongDate: entry.belongDate,
          vendor: entry.vendor,
          description: entry.description,
          totalAmount: entry.totalAmount,
          currency: entry.currency,
          className: entry.className,
          submittedBy: entry.createdBy,
        );
        current = current.copyWith(
          slackDone: true,
          // 목록에서 탭하면 이 링크로 간다. null 이면 화면이 채널까지만 보낸다.
          slackUrl: Value(slackUrl),
          slackError: const Value(null),
        );
      } on Object catch (e) {
        current = current.copyWith(slackError: Value('$e'));
      }
      await db.updateRow(current);
    }

    current = current.copyWith(lastTriedAt: Value(DateTime.now()));
    await db.updateRow(current);

    final allDone =
        current.driveDone && current.sheetsDone && current.slackDone;
    final legs = legStatusesOf(current);
    return SendOutcome(
      id: current.id,
      allDone: allDone,
      // 실패한 목적지를 전부 적는다 — 화면의 칩과 같은 문구를 쓴다.
      error: failureDetail(legs),
      failedWhere: failedLabels(legs),
    );
  }

  /// 큐에 저장된 JSON 을 원래 타입으로 되살린다.
  ///
  /// 2차 사업비가 생기면 여기 `case` 하나만 추가한다.
  /// switch 가 exhaustive 라 새 종류를 빠뜨리면 **컴파일이 막아준다.**
  PurchaseEntry _decode(Submission row) {
    final json = jsonDecode(row.entryJson) as Map<String, dynamic>;
    return switch (EntryKind.fromWire(row.entryKind)) {
      EntryKind.purchase => PurchaseEntry.fromJson(json),
    };
  }

  /// 목적지를 가리지 않는 실패 — 세 곳 다 시도조차 못 했다.
  ///
  /// 목적지별 사유는 **건드리지 않는다.** 지난번 드라이브 403 이 남아 있다면
  /// 그건 여전히 사실이고, 여기서 지우면 사용자가 보던 설명이 사라진다.
  Future<SendOutcome> _blocked(Submission row, String message) async {
    final updated = row.copyWith(
      lastError: Value(message),
      lastTriedAt: Value(DateTime.now()),
    );
    await db.updateRow(updated);
    return SendOutcome(
      id: row.id,
      allDone: false,
      error: failureDetail(legStatusesOf(updated), blocked: message),
      // `failedWhere` 는 비워둔다 — 특정 목적지의 문제가 아니다.
    );
  }
}
