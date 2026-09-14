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
  TextColumn get entryKind =>
      text().withDefault(const Constant('purchase'))();

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
  int get schemaVersion => 2;

  /// v1 → v2: `entryKind` 추가.
  ///
  /// 실사용 데이터가 없는 시점에 넣어서 백필이 필요 없다. 기존 행이 있더라도
  /// 1차에는 매입내역밖에 없었으므로 기본값 `purchase` 가 정답이다.
  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) await m.addColumn(submissions, submissions.entryKind);
        },
      );

  /// 아직 세 곳 다 못 보낸 건. **최근순** — 시안 ⑬번의 정렬 규칙이다.
  Future<List<Submission>> pending() {
    return (select(submissions)
          ..where((t) => t.sheetsDone.not() | t.driveDone.not() | t.slackDone.not())
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
    return (select(submissions)
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  Future<int> enqueue(SubmissionsCompanion row) =>
      into(submissions).insert(row);

  Future<bool> updateRow(Submission row) => update(submissions).replace(row);

  Future<int> remove(int id) =>
      (delete(submissions)..where((t) => t.id.equals(id))).go();
}
