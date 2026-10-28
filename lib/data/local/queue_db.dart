import 'dart:io';

import 'package:bodit_app/core/log.dart';
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'queue_db.g.dart';

/// 전송 대기 큐.
///
/// 오프라인 재전송은 **수동**이다(ADR Decision 12a) — 사용자가 [전송 시도] 를
/// 눌러야 보낸다. 그래서 백그라운드 워커도 connectivity 리스너도 없다.
/// 이 DB 는 "기기에 임시저장" 그 자체다.
///
/// 목적지가 3곳(Sheets·Drive·Slack)이라 **하나만 실패**할 수 있다.
/// 그래서 완료 여부를 목적지별로 따로 들고, 재시도할 때 이미 끝난 곳은 건너뛴다.
/// 이게 없으면 재시도 때 시트에 같은 행이 두 번 들어간다.
class Submissions extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 로컬 식별자. 시트에는 안 들어간다(ADR Decision 14) — 여기서만 쓴다.
  TextColumn get localId => text()();

  /// 항목의 종류(`EntryKind.wireName`). 지금은 `purchase` 하나뿐이다.
  ///
  /// **꺼낼 때 어떤 타입으로 되살릴지** 알려면 이게 필요하다.
  /// 2차 사업비가 오면 값 하나만 늘리면 된다 — 지금 넣어두는 이유가 그거다.
  TextColumn get entryKind => text().withDefault(const Constant('purchase'))();

  /// 항목을 JSON 으로 직렬화해 둔 것. 되살리는 방법은 [entryKind] 가 정한다.
  TextColumn get entryJson => text()();

  /// 기기에 보관 중인 증빙 원본 경로.
  TextColumn get evidencePath => text()();

  /// 업로드할 파일명. 사용자가 검토 화면에서 고쳤을 수 있다.
  TextColumn get filename => text()();

  // ── 목적지별 완료 여부 ───────────────────────────────────────────
  BoolColumn get sheetsDone => boolean().withDefault(const Constant(false))();
  BoolColumn get driveDone => boolean().withDefault(const Constant(false))();
  BoolColumn get slackDone => boolean().withDefault(const Constant(false))();

  /// Drive 업로드 성공 시 채워진다. Sheets 행과 Slack 메시지가 이걸 참조한다
  /// → **Drive 를 가장 먼저 보낸다.**
  TextColumn get driveUrl => text().nullable()();

  /// Slack 에 올라간 파일(과 그 파일이 붙은 메시지)로 가는 링크.
  ///
  /// **없을 수 있다.** 이 컬럼이 생기기 전에 올라간 건이 있고, 링크를 받는
  /// 호출(`files.info`)이 실패해도 전송은 성공으로 둔다 — 링크를 못 받은
  /// 것 때문에 재시도하면 **사진이 두 번 올라간다.**
  TextColumn get slackUrl => text().nullable()();

  /// 마지막 실패 사유. 사용자에게 그대로 보여준다 — 조용히 실패하면 안 된다.
  TextColumn get lastError => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get lastTriedAt => dateTime().nullable()();
}

@DriftDatabase(tables: [Submissions])
class QueueDb extends _$QueueDb {
  QueueDb([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'bodit_queue'));

  @override
  int get schemaVersion => 3;

  /// v1 → v2: `entryKind` 추가.
  ///
  /// 실사용 데이터가 없는 시점에 넣어서 백필이 필요 없다. 기존 행이 있더라도
  /// 1차에는 매입내역밖에 없었으므로 기본값 `purchase` 가 정답이다.
  ///
  /// v2 → v3: `slackUrl` 추가.
  ///
  /// **백필할 수 없다.** 이미 올라간 건의 링크는 Slack 에 물어봐야 알 수 있고,
  /// 그러려면 파일 id 를 들고 있어야 하는데 그것도 저장하지 않았다. 그래서
  /// 기존 행은 null 로 남고, 화면이 그 경우 채널까지만 보낸다.
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) await m.addColumn(submissions, submissions.entryKind);
      if (from < 3) await m.addColumn(submissions, submissions.slackUrl);
    },
  );

  /// 아직 세 곳 다 못 보낸 건. **최근순** — 시안 ⑬번의 정렬 규칙이다.
  Future<List<Submission>> pending() {
    return (select(submissions)
          ..where(
            (t) => t.sheetsDone.not() | t.driveDone.not() | t.slackDone.not(),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  /// 세 곳 다 끝난 건. 내 제출 목록에서 보여준다.
  Future<List<Submission>> completed({int limit = 50}) {
    return (select(submissions)
          ..where((t) => t.sheetsDone & t.driveDone & t.slackDone)
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(limit))
        .get();
  }

  Stream<List<Submission>> watchAll() {
    return (select(
      submissions,
    )..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).watch();
  }

  Future<int> enqueue(SubmissionsCompanion row) =>
      into(submissions).insert(row);

  Future<bool> updateRow(Submission row) => update(submissions).replace(row);

  /// 방금 넣은 건을 바로 전송하려고 꺼낼 때 쓴다.
  Future<Submission?> byId(int id) =>
      (select(submissions)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// 한 건을 큐에서 지우고 **기기에 복사해 둔 증빙 원본도 같이 지운다.**
  ///
  /// 행만 지우면 앱 디렉토리에 증빙 파일이 영영 남는다 — 아무도 참조하지 않는데
  /// 용량만 먹는다(`CaptureService` 가 촬영마다 한 장씩 복사해 둔다).
  ///
  /// **이미 전송된 것은 되돌리지 않는다.** Drive 에 올라간 파일도, 시트에 들어간
  /// 행도 그대로 남는다. 앱은 append 만 하고 원격을 지우지 않는다(ADR Decision 2).
  /// 여기서 지우는 건 "보낼 목록" 에서 빼는 것뿐이다.
  Future<void> discard(Submission row) async {
    await remove(row.id);
    try {
      final f = File(row.evidencePath);
      if (f.existsSync()) await f.delete();
    } on Object catch (e) {
      // 파일이 안 지워져도 행은 이미 빠졌다. 여기서 던지면 사용자는 "삭제
      // 실패" 로 보는데 목록에서는 사라져 있어 더 헷갈린다.
      log.w('증빙 파일을 지우지 못했다 (행은 삭제됨): $e');
    }
  }

  /// 큐를 비운다. 완료된 건까지 전부.
  Future<int> discardAll() async {
    final rows = await select(submissions).get();
    for (final r in rows) {
      await discard(r);
    }
    return rows.length;
  }

  Future<int> remove(int id) =>
      (delete(submissions)..where((t) => t.id.equals(id))).go();
}
