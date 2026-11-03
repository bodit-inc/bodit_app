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
/// 들어가면 그 칸은 비어서 나간다. 그래도 이쪽을 골랐다: 회계가 보는 매입내역
/// 행이 아예 안 들어가는 쪽이 더 나쁘다. 링크가 빈 행은 채울 수 있지만,
/// 없는 행은 아무도 모른다.
///
/// ### 나중에 Drive 가 성공하면 그 칸을 채운다
///
/// 전에는 못 채웠다 — 시트는 append 만 하고(ADR Decision 2) 키 컬럼도 없어서
/// (Decision 14) 그 행을 지목할 방법이 없었다. 그래서 재시도로 Drive 가
/// 성공해도 증빙링크는 영원히 빈 칸이었고, 사람이 Drive 에서 파일을 찾아
/// 손으로 붙이고 있었다. **앱은 그 URL 을 이미 알고 있는데** 말이다.
///
/// 그래서 append 가 돌려주는 **들어간 자리**(`Submission.sheetsRange`)를
/// 적어두고, Drive 가 나중에 성공하면 그 행의 **증빙링크 칸만** 채운다
/// (`SheetsRepository.fillEvidenceLink`). 쓰기 전에 그 행이 여전히 우리
/// 행인지 확인한다 — 회계 담당자가 위쪽 행을 지우면 번호가 밀리고, 밀린 줄
/// 모르고 쓰면 남의 행에 적는다.
///
/// 확인에 걸려 못 채웠으면 그 사실을 `followUpNote` 에 적는다. 조용히 넘기면
/// 사용자는 채워진 줄 안다.
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

import 'package:bodit_app/core/utils/retry.dart';
import 'package:bodit_app/data/local/queue_db.dart';
import 'package:bodit_app/data/remote/drive_repository.dart';
import 'package:bodit_app/data/remote/google_auth.dart';
import 'package:bodit_app/data/remote/sheets_repository.dart';
import 'package:bodit_app/data/remote/slack_repository.dart';
import 'package:bodit_app/data/send_status.dart';
import 'package:bodit_app/models/purchase_entry.dart';
import 'package:bodit_app/models/sheet_row.dart';
import 'package:drift/drift.dart' show Value;
import 'package:googleapis_auth/googleapis_auth.dart' as gapis;

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

    // 들어올 때 **시트 행이 이미 들어가 있었는지** 기억한다.
    //
    // 이번 호출에서 Drive 가 성공했을 때 "나중에 성공한 것" 인지 가리는 기준이다.
    // 같은 호출에서 Drive → Sheets 로 이어지면 append 가 링크를 이미 들고
    // 가므로 채울 것이 없다. 반대로 지난번에 Drive 만 실패했던 건이면 시트에는
    // 증빙링크가 빈 행이 이미 있고, 그 칸을 채우러 가야 한다.
    final sheetsWasAlreadyIn = row.sheetsDone;

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
      // 세 곳 다 성공해도 **사람이 손 볼 일**이 남을 수 있다. 실패 사유와
      // 섞지 않고 여기 모아 `followUpNote` 로 보낸다(아래 두 군데서 담는다).
      final followUps = <String>[];
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

        // 시트 행이 **먼저** 들어갔다면 그 행의 증빙링크가 비어 있다.
        // 이제 링크가 생겼으니 그 칸만 채운다 — append-only 의 유일한 예외다
        // (`SheetsRepository.fillEvidenceLink`).
        if (sheetsWasAlreadyIn) {
          final note = await _fillEvidenceLink(
            client,
            row: current,
            entry: entry,
            url: url,
          );
          if (note != null) followUps.add(note);
        }
      } on Object catch (e) {
        current = current.copyWith(driveError: Value('$e'));
      }

      // 폴더 기록 실패는 업로드 성공과 **같이** 올 수 있다 — 폴더는 만들었고
      // 올리기도 됐는데 그 ID 만 시트에 못 적은 경우다. 실패 사유가 아니라
      // 뒷일이므로 이쪽으로 간다.
      final folderWarning = drive.folders.takeRecordWarning();
      if (folderWarning != null) followUps.add(folderWarning);

      current = current.copyWith(
        // 이번 시도의 결과로 **다시 쓴다.** 지난번 "직접 붙여주세요" 가
        // 이번에 채워졌으면 그 문구는 사라져야 한다.
        followUpNote: Value(followUps.isEmpty ? null : followUps.join('\n\n')),
      );
      await db.updateRow(current);
    }

    // ── 2. Sheets ───────────────────────────────────────────────
    //    Drive 가 실패했으면 `증빙링크` 가 빈 채로 들어간다. append-only 라
    //    나중에 못 채운다 — 알고 감수한 쪽이다(위 설명 참조).
    if (!current.sheetsDone) {
      try {
        final range = await sheets.appendRow(
          client: client,
          row: entry.copyWith(evidenceUrl: current.driveUrl ?? ''),
        );
        current = current.copyWith(
          sheetsDone: true,
          sheetsError: const Value(null),
          // 들어간 자리를 적어둔다. Drive 가 실패한 건이면 나중에 그 행의
          // 증빙링크를 채우러 돌아와야 한다 — 그때 유일한 단서다.
          sheetsRange: Value(range),
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

  /// 시트 행이 먼저 들어간 뒤에 Drive 가 성공했을 때, 그 행의 증빙링크를 채운다.
  ///
  /// ## 왜 여기만 시트를 고치는가
  ///
  /// Drive 가 실패하면 시트 행은 증빙링크가 빈 채로 들어간다(ADR Decision 4 —
  /// 세 목적지는 독립이고, 앞이 실패해도 뒤를 건너뛰지 않는다). 그 대가를
  /// "링크 빈 행은 사람이 붙인다" 로 감수해왔는데, 실제로 운영에서 한 건
  /// 생기고 나니 **앱은 Drive URL 을 알고 있는데** 사람이 그걸 찾아 옮기고
  /// 있었다. 아는 걸 안 쓰는 셈이다.
  ///
  /// 그래서 **그 칸 하나만** 채운다. 금액·비목 같은 다른 칸은 영원히 안 고친다.
  ///
  /// 돌려주는 값: 사람이 손 볼 일이 남으면 그 문구, 깔끔히 끝났으면 null.
  /// **실패해도 던지지 않는다** — 업로드는 이미 성공했고, 그걸 실패로 되돌리면
  /// 다음 재시도가 같은 파일을 또 올린다.
  Future<String?> _fillEvidenceLink(
    gapis.AuthClient client, {
    required Submission row,
    required PurchaseEntry entry,
    required String url,
  }) async {
    final range = row.sheetsRange;
    if (range == null) {
      // `sheetsRange` 컬럼이 생기기 전에 시트에 들어간 행이다 — 몇 번째 줄인지
      // 알 방법이 없다(키 컬럼이 없다). 예전과 같은 결과지만 말은 해준다.
      return '증빙링크가 빈 채로 시트에 들어간 건입니다.\n'
          '시트의 증빙링크 칸에 직접 붙여주세요:\n$url';
    }

    try {
      final filled = await retryTransient(
        () => sheets.fillEvidenceLink(
          client: client,
          appendedRange: range,
          url: url,
          // 그 행이 여전히 우리 행인지 확인할 재료다.
          expectVendor: entry.vendor,
          expectDescription: entry.description,
        ),
        what: '증빙링크 채우기',
      );
      if (filled) return null;

      // 쓰지 않기로 **판단한** 경우다. 행이 밀렸거나 다른 값이 들어 있다 —
      // 남의 행에 쓰는 것보다 사람에게 넘기는 쪽이 낫다.
      return '시트에서 그 행을 찾지 못해 증빙링크를 채우지 못했습니다.\n'
          '행이 밀렸거나 이미 다른 값이 들어 있습니다. 직접 붙여주세요:\n$url';
    } on Object catch (e) {
      return '증빙링크를 시트에 채우지 못했습니다. 직접 붙여주세요:\n$url\n\n$e';
    }
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
