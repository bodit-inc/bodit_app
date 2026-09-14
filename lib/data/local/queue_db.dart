import 'package:bodit_app/models/purchase_entry.dart' show PurchaseEntry;
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

  /// [PurchaseEntry] 를 JSON 으로 직렬화해 둔 것.
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
  int get schemaVersion => 1;

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
