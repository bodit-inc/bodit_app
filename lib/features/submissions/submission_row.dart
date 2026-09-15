/// 전송 대기·제출 목록의 한 행.
///
/// **홈과 `내 제출` 이 같은 위젯을 쓴다.** 두 곳에 비슷한 코드를 두면 한쪽만
/// 고치게 된다 — 실제로 목적지별 표시를 `내 제출` 에만 넣었다가 홈에서는
/// 여전히 "실패" 한 덩어리로 보이는 일이 있었다.
library;

import 'dart:async';

import 'package:bodit_app/core/theme/tokens.dart';
import 'package:bodit_app/core/widgets/app_widgets.dart';
import 'package:bodit_app/data/local/queue_db.dart';
import 'package:bodit_app/features/review/review_controller.dart';
import 'package:bodit_app/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 목적지 하나의 상태.
enum _Leg {
  done('완료'),
  failed('실패'),
  pending('대기');

  _Leg(this.label);
  final String label;
}

class SubmissionRow extends ConsumerWidget {
  const SubmissionRow(this.row, {super.key});

  final Submission row;

  bool get _allDone => row.driveDone && row.sheetsDone && row.slackDone;
  bool get _hasError => row.lastError != null && !_allDone;

  /// 아직 **어느 목적지에도 안 나간** 건만 고칠 수 있다.
  ///
  /// Drive 에 이미 올라간 건을 고치면 올라간 파일명과 시트에 들어갈 내용이
  /// 어긋난다. 그래서 진행이 조금이라도 된 건은 잠근다.
  bool get _editable => !row.driveDone && !row.sheetsDone && !row.slackDone;

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
            label: '',
            value: row.filename,
            trailing: StatusPill(label, tone: tone),
            subtitle: _allDone
                ? '완료 · ${_time(row.createdAt)}'
                : _editable
                    ? '눌러서 내용을 고칠 수 있습니다'
                    : null,
            onTap: _editable ? () => _edit(context, ref) : null,
          ),
          // 완료된 건은 목적지를 나열할 이유가 없다.
          if (!_allDone)
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.md),
              child: Wrap(
                spacing: Gap.sm,
                runSpacing: Gap.xs,
                children: [for (final (name, leg) in _legs) _LegChip(name, leg)],
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
            style: TextStyle(fontSize: 11, color: fg, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
