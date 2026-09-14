import 'package:bodit_app/core/theme/tokens.dart';
import 'package:bodit_app/core/widgets/app_widgets.dart';
import 'package:bodit_app/data/local/queue_db.dart';
import 'package:bodit_app/data/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 시안 ⑫ — 내 제출 목록. **부분 실패가 여기서 보인다.**
///
/// 목적지가 3곳이라 Slack 만 실패하는 경우가 생긴다. 어디까지 갔는지를
/// 그대로 보여준다 — 조용히 실패하면 안 된다.
class SubmissionsScreen extends ConsumerWidget {
  const SubmissionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(pendingSubmissionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('내 제출')),
      body: rows.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('목록을 불러오지 못했습니다.\n$e')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: Text('아직 제출한 건이 없습니다.'));
          }
          return ListView(
            padding: screenPadding,
            children: [
              AppCard(
                children: [for (final s in list) _SubmissionRow(s)],
              ),
              const NoteText(
                '목적지가 3곳이라 하나만 실패할 수 있습니다. '
                '실패한 곳만 다시 보내므로 시트에 같은 행이 두 번 들어가지 않습니다.',
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SubmissionRow extends StatelessWidget {
  const _SubmissionRow(this.row);

  final Submission row;

  bool get _allDone => row.driveDone && row.sheetsDone && row.slackDone;

  /// 어디까지 갔는지 한 줄로. 실패했으면 사유를 그대로 보여준다.
  String get _detail {
    if (_allDone) return '완료 · ${_time(row.createdAt)}';
    final done = <String>[
      if (row.driveDone) 'Drive',
      if (row.sheetsDone) 'Sheets',
      if (row.slackDone) 'Slack',
    ];
    final err = row.lastError;
    if (err != null) {
      final prefix = done.isEmpty ? '' : '${done.join('·')} 완료 / ';
      return '$prefix실패 — $err';
    }
    return done.isEmpty
        ? '전송 대기 · ${_time(row.createdAt)}'
        : '${done.join('·')} 완료 / 나머지 대기';
  }

  @override
  Widget build(BuildContext context) {
    final (label, tone) = _allDone
        ? ('완료', PillTone.ok)
        : row.lastError != null
            ? ('재시도', PillTone.error)
            : ('대기', PillTone.waiting);

    return Container(
      decoration: row.lastError != null && !_allDone
          ? const BoxDecoration(
              border: Border(
                left: BorderSide(color: AppColors.danger, width: 3),
              ),
            )
          : null,
      child: LabeledRow(
        label: '',
        value: row.filename,
        trailing: StatusPill(label, tone: tone),
        subtitle: _detail,
      ),
    );
  }

  static String _time(DateTime d) =>
      '${d.month}/${d.day} ${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';
}
