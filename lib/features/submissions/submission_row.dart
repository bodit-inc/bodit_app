/// 전송 대기·제출 목록의 한 행.
///
/// **홈과 `내 제출` 이 같은 위젯을 쓴다.** 두 곳에 비슷한 코드를 두면 한쪽만
/// 고치게 된다 — 실제로 목적지별 표시를 `내 제출` 에만 넣었다가 홈에서는
/// 여전히 "실패" 한 덩어리로 보이는 일이 있었다.
library;

import 'dart:async';
import 'dart:convert';

import 'package:bodit_app/core/config.dart';
import 'package:bodit_app/core/links.dart';
import 'package:bodit_app/core/theme/tokens.dart';
import 'package:bodit_app/core/utils/filename.dart';
import 'package:bodit_app/core/widgets/app_widgets.dart';
import 'package:bodit_app/data/local/queue_db.dart';
import 'package:bodit_app/data/providers.dart';
import 'package:bodit_app/features/review/review_controller.dart';
import 'package:bodit_app/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

/// 큐에 저장된 JSON 에서 **소속날짜**만 꺼낸다.
///
/// `PurchaseEntry` 로 통째로 되살리지 않는 이유: 2차 사업비처럼 **다른 타입**이
/// 들어와도 `belongDate` 만 있으면 쓸 수 있어야 한다. 타입을 맞춰 되살리면
/// 종류가 늘어날 때마다 여기도 같이 고쳐야 한다.
///
/// **행의 일자와 목록의 묶음이 같은 기준을 써야 한다.** 행에는 `5일` 이라고
/// 적혀 있는데 8월 묶음에 들어가 있으면 사용자는 어느 쪽이 맞는지 모른다.
/// 그래서 `submissions_screen` 도 이 함수를 쓴다.
DateTime? belongDateOf(Submission row) {
  try {
    final m = jsonDecode(row.entryJson) as Map<String, dynamic>;
    final v = m['belongDate'];
    return v is String ? DateTime.tryParse(v) : null;
  } on Object {
    // 묶음이 깨지는 것뿐이라 조용히 넘어간다 — 호출부가 제출일로 떨어뜨린다.
    return null;
  }
}

/// 행을 탭했을 때 갈 곳.
///
/// **순서가 규칙이다.** 전송이 어디까지 갔는지에 따라 갈 수 있는 곳이 다르고,
/// 아무 일도 안 하는 대신 왜 못 가는지 말해야 한다.
enum OpenTarget {
  /// Slack 에 올라간 그 파일(과 붙은 메시지).
  slackMessage,

  /// 올라갔는데 링크가 없다 — `slackUrl` 컬럼이 생기기 전에 보낸 건이다.
  /// 채널까지는 보낼 수 있다.
  slackChannel,

  /// Slack 에는 아직 없고 Drive 에는 있다. "무엇을 올렸나" 는 확인할 수 있다.
  drive,

  /// 아무 데도 안 나갔다.
  nothing,
}

/// 목적지 하나의 상태.
enum _Leg {
  done('완료'),
  failed('실패'),
  pending('대기');

  _Leg(this.label);
  final String label;
}

class SubmissionRow extends ConsumerWidget {
  const SubmissionRow(this.row, {super.key, this.dayOnly = false});

  final Submission row;

  /// 날짜를 **일자만** 보여준다.
  ///
  /// 월별로 묶인 `내 제출` 목록에서 참이다 — 묶음 헤더가 `2026년 8월` 을
  /// 말하므로 행에서 또 보여주면 연월이 두 번 찍힌다.
  ///
  /// 홈의 전송 대기 큐는 묶음이 없고 **몇 달 지난 영수증이 섞일 수 있다**
  /// (뒤늦게 올리는 일은 흔하다). 거기서 일자만 적으면 어느 달 건인지 알 수
  /// 없으므로 월까지 보여준다.
  final bool dayOnly;

  bool get _allDone => row.driveDone && row.sheetsDone && row.slackDone;
  bool get _hasError => row.lastError != null && !_allDone;

  /// 아직 **어느 목적지에도 안 나간** 건만 고칠 수 있다.
  ///
  /// Drive 에 이미 올라간 건을 고치면 올라간 파일명과 시트에 들어갈 내용이
  /// 어긋난다. 그래서 진행이 조금이라도 된 건은 잠근다.
  bool get _editable => !row.driveDone && !row.sheetsDone && !row.slackDone;

  /// 행 왼쪽에 적는 날짜. 예전엔 파일명 전체
  /// (`260805_영풍문고_8월 도서_영수증_19,000`)를 보여줘서 월별 묶음 안에서
  /// 연월이 두 번 찍혔다.
  ///
  /// 기준은 **소속날짜**다 — 목록을 묶는 기준과 같아야 한다. 행에 `5일` 이라고
  /// 적혀 있는데 8월 묶음에 들어가 있으면 어느 쪽이 맞는지 모른다.
  String get _date {
    final d = belongDateOf(row) ?? row.createdAt;
    return dayOnly ? '${d.day}일' : '${d.month}/${d.day}';
  }

  /// 목적지별 상태. 전송은 Drive → Sheets → Slack 순서라
  /// 앞이 실패하면 뒤는 **실패가 아니라 미시도**다. 그걸 구분해서 보여준다.
  List<(String, _Leg)> get _legs {
    var failedAlready = false;
    (String, _Leg) leg(String name, {required bool done}) {
      if (done) return (name, _Leg.done);
      if (_hasError && !failedAlready) {
        failedAlready = true;
        return (name, _Leg.failed);
      }
      return (name, _Leg.pending);
    }

    return [
      leg('드라이브', done: row.driveDone),
      leg('스프레드시트', done: row.sheetsDone),
      leg('슬랙', done: row.slackDone),
    ];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 왼쪽으로 밀어 삭제. 되돌릴 수 없으므로 반드시 확인을 받는다.
    return Dismissible(
      key: ValueKey('submission-${row.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: Gap.lg),
        color: AppColors.danger,
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      confirmDismiss: (_) => _confirmDelete(context),
      onDismissed: (_) async {
        await ref.read(queueDbProvider).discard(row);
      },
      child: _body(context, ref),
    );
  }

  /// 삭제 확인. **무엇이 지워지고 무엇이 안 지워지는지** 분명히 말한다.
  Future<bool> _confirmDelete(BuildContext context) async {
    final sent = <String>[
      if (row.driveDone) '드라이브',
      if (row.sheetsDone) '스프레드시트',
      if (row.slackDone) '슬랙',
    ];
    return await confirmDestructive(
      context,
      title: '이 건을 목록에서 지울까요?',
      message: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(row.filename, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: Gap.md),
          if (sent.isEmpty)
            const Text('아직 아무 곳에도 전송되지 않았습니다. 기기에서 완전히 지워집니다.')
          else
            Text(
              '이미 ${sent.join('·')}에 올라간 것은 그대로 남습니다.\n'
              '앱은 보낸 것을 되돌리지 않습니다 — 목록에서만 사라집니다.\n'
              '되돌리려면 시트와 드라이브에서 직접 지워야 합니다.',
            ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref) {
    final (label, tone) = _allDone
        ? ('완료', PillTone.ok)
        : _hasError
        ? ('실패', PillTone.error)
        : ('대기', PillTone.waiting);

    return Container(
      decoration: _hasError
          ? const BoxDecoration(
              border: Border(
                left: BorderSide(color: AppColors.danger, width: 3),
              ),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LabeledRow(
            label: _date,
            value: stripDatePrefix(row.filename),
            trailing: StatusPill(label, tone: tone),
            // 오른쪽 알약이 이미 "완료" 라고 말한다. 여기서 또 쓰면 같은 줄에
            // 완료가 두 번 찍힌다 — 실제로 그렇게 보였다.
            subtitle: _editable
                ? '눌러서 내용을 고칠 수 있습니다'
                : _allDone
                ? '${_time(row.createdAt)} · 눌러서 Slack 에서 보기'
                : null,
            // 고칠 수 있는 건은 고치는 쪽이 먼저다. 이미 나간 건은 고칠 수
            // 없으니(Drive 파일명과 시트 내용이 어긋난다) 원본으로 보낸다.
            onTap: _editable ? () => _edit(context, ref) : () => _open(context),
          ),
          // 완료된 건은 목적지를 나열할 이유가 없다.
          if (!_allDone)
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.md),
              child: Wrap(
                spacing: Gap.sm,
                runSpacing: Gap.xs,
                children: [
                  for (final (name, leg) in _legs) _LegChip(name, leg),
                ],
              ),
            ),
          if (_hasError)
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.md),
              child: ErrorDisclosure(
                '실패 사유 보기',
                detail: row.lastError!,
                align: MainAxisAlignment.start,
              ),
            ),
        ],
      ),
    );
  }

  /// 탭했을 때 갈 곳을 정한다. **순수 함수다** — 네 갈래가 조용히 뒤바뀌면
  /// 사용자는 왜 다른 곳으로 가는지 모른다.
  @visibleForTesting
  static OpenTarget targetOf(Submission row) {
    // 링크가 있으면 그 파일로. 가장 정확하다.
    if (row.slackDone && row.slackUrl != null) return OpenTarget.slackMessage;
    // 올라갔는데 링크가 없다 — 백필할 방법이 없으므로(파일 id 도 저장하지
    // 않았다) 채널까지만 보낸다. `#purchase` 는 흘러가는 채널이고 찾는 건은
    // 보통 최근 것이라 스크롤 몇 번이면 닿는다.
    if (row.slackDone) return OpenTarget.slackChannel;
    // Slack 에는 아직 없다. 증빙 파일이라도 있으면 거기로 — "무엇을 올렸나"
    // 를 확인하려는 것이 탭의 목적이다.
    if (row.driveUrl != null) return OpenTarget.drive;
    return OpenTarget.nothing;
  }

  /// 전송된 건을 **원본으로** 보낸다.
  ///
  /// 아무 일도 안 하는 대신 **왜 못 가는지 말한다** — 눌렀는데 반응이 없으면
  /// 사용자는 눌렀는지조차 모른다.
  Future<void> _open(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    switch (targetOf(row)) {
      case OpenTarget.slackMessage:
        await _launch(messenger, row.slackUrl!, 'Slack');
      case OpenTarget.slackChannel:
        // 왜 채널을 여는지 **먼저 말한다.** 메시지로 갈 줄 알고 눌렀는데
        // 채널 맨 위로 떨어지면 왜 그런지 모른다.
        messenger.showSnackBar(
          const SnackBar(content: Text('이 건은 전송 당시 링크를 저장하지 않아 채널만 엽니다.')),
        );
        await _launch(
          messenger,
          slackChannelUrl(Config.slackChannelId),
          'Slack',
        );
      case OpenTarget.drive:
        await _launch(messenger, row.driveUrl!, '드라이브');
      case OpenTarget.nothing:
        messenger.showSnackBar(
          const SnackBar(content: Text('아직 어디에도 올라가지 않았습니다.')),
        );
    }
  }

  Future<void> _launch(
    ScaffoldMessengerState messenger,
    String url,
    String what,
  ) async {
    try {
      // 외부 앱(Slack·드라이브)이 깔려 있으면 그쪽이 받아간다.
      final ok = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!ok) {
        messenger.showSnackBar(SnackBar(content: Text('$what 을(를) 열지 못했습니다.')));
      }
    } on Object catch (e) {
      // 조용히 실패하면 안 된다. 원문은 개발자용이지만 스낵바는 접을 대상이
      // 아니라 한 줄로 끝낸다.
      messenger.showSnackBar(
        SnackBar(content: Text('$what 을(를) 열지 못했습니다: $e')),
      );
    }
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    ref.read(reviewControllerProvider.notifier).loadForEdit(row);
    unawaited(context.push(Routes.review));
  }

  static String _time(DateTime d) =>
      '${d.month}/${d.day} ${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';
}

/// 목적지 하나를 나타내는 작은 칩.
class _LegChip extends StatelessWidget {
  const _LegChip(this.name, this.leg);

  final String name;
  final _Leg leg;

  @override
  Widget build(BuildContext context) {
    final (fg, icon) = switch (leg) {
      _Leg.done => (AppColors.success, Icons.check_circle),
      _Leg.failed => (AppColors.danger, Icons.cancel),
      _Leg.pending => (AppColors.neutralFg, Icons.schedule),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: 3),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 4),
          Text(
            '$name ${leg.label}',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: fg),
          ),
        ],
      ),
    );
  }
}

/// 큐 전체 비우기. 홈과 `내 제출` 이 같이 쓴다.
///
/// 지운 건수를 돌려준다. 취소하면 null.
Future<int?> confirmClearAll(BuildContext context, WidgetRef ref) async {
  final rows = await ref.read(queueDbProvider).pending();
  final total = rows.length;
  if (total == 0) return null;

  final anySent = rows.any((r) => r.driveDone || r.sheetsDone || r.slackDone);

  if (!context.mounted) return null;
  final ok = await confirmDestructive(
    context,
    title: '$total건을 전부 지울까요?',
    confirmLabel: '전부 지우기',
    message: Text(
      anySent
          ? '일부는 이미 전송됐습니다. 올라간 파일과 시트 행은 그대로 남고 '
                '목록에서만 사라집니다.\n\n되돌릴 수 없습니다.'
          : '아직 전송되지 않은 건들입니다. 기기에서 완전히 지워집니다.\n\n'
                '되돌릴 수 없습니다.',
    ),
  );
  if (!ok) return null;
  return await ref.read(queueDbProvider).discardAll();
}
