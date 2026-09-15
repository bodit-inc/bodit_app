/// 큐에 쌓인 건을 세 목적지로 보낸다.
///
/// ## 순서가 정해져 있다: Drive → Sheets → Slack
///
/// Sheets 행의 `증빙링크` 컬럼과 Slack 메시지가 **Drive URL 을 참조**하기 때문이다.
/// Drive 가 실패하면 나머지 둘은 시도하지 않는다.
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
import 'package:bodit_app/models/purchase_entry.dart';
import 'package:bodit_app/models/sheet_row.dart';
import 'package:drift/drift.dart' show Value;

/// 한 건의 전송 결과.
class SendOutcome {
  const SendOutcome({required this.id, required this.allDone, this.error});

  final int id;
  final bool allDone;

  /// 사용자에게 그대로 보여준다 — 조용히 실패하면 안 된다.
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

  /// 한 건을 보낸다. 이미 끝난 목적지는 건너뛴다.
  Future<SendOutcome> sendOne(Submission row) async {
    // AuthClient 를 캐싱하지 않는다 — 다리 패키지가 만료를 임의로 365일 뒤로
    // 박아두고 refresh token 을 안 넣어서, 오래 들고 있으면 조용히 401 이 난다.
    final client = await auth.authorizedClient();
    if (client == null) {
      return await _fail(row, 'Google 인가가 없습니다. 다시 로그인해 주세요.');
    }

    final entry = _decode(row);
    final file = File(row.evidencePath);
    if (!file.existsSync()) {
      return await _fail(row, '증빙 원본을 찾을 수 없습니다: ${row.evidencePath}');
    }

    var current = row;

    try {
      // ── 1. Drive ────────────────────────────────────────────────
      if (!current.driveDone) {
        final url = await drive.upload(
          client: client,
          source: file,
          filename: current.filename,
          belongDate: entry.belongDate,
        );
        current = current.copyWith(
          driveDone: true,
          driveUrl: Value(url),
          lastError: const Value(null),
        );
        await db.updateRow(current);
      }

      final driveUrl = current.driveUrl ?? '';

      // ── 2. Sheets ───────────────────────────────────────────────
      if (!current.sheetsDone) {
        await sheets.appendRow(
          client: client,
          row: entry.copyWith(evidenceUrl: driveUrl),
        );
        current = current.copyWith(
          sheetsDone: true,
          lastError: const Value(null),
        );
        await db.updateRow(current);
      }

      // ── 3. Slack ────────────────────────────────────────────────
      if (!current.slackDone) {
        await slack.postEvidence(
          image: file,
          filename: current.filename,
          belongDate: entry.belongDate,
          vendor: entry.vendor,
          description: entry.description,
          totalAmount: entry.totalAmount,
          currency: entry.currency,
          className: entry.className,
          submittedBy: entry.createdBy,
          driveUrl: driveUrl,
        );
        current = current.copyWith(
          slackDone: true,
          lastError: const Value(null),
        );
        await db.updateRow(current);
      }

      await db.updateRow(current.copyWith(lastTriedAt: Value(DateTime.now())));
      return SendOutcome(id: current.id, allDone: true);
    } on Object catch (e) {
      // 여기까지 성공한 목적지는 이미 DB 에 기록됐다 — 재시도하면 그 지점부터 간다.
      return await _fail(current, '$e');
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

  Future<SendOutcome> _fail(Submission row, String message) async {
    await db.updateRow(
      row.copyWith(
        lastError: Value(message),
        lastTriedAt: Value(DateTime.now()),
      ),
    );
    return SendOutcome(id: row.id, allDone: false, error: message);
  }
}
