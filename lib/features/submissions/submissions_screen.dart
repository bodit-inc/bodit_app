import 'package:bodit_app/core/theme/tokens.dart';
import 'package:bodit_app/core/widgets/app_widgets.dart';
import 'package:bodit_app/data/providers.dart';
import 'package:bodit_app/features/submissions/submission_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 시안 ⑫ — 내 제출 목록. **부분 실패가 여기서 보인다.**
///
/// 목적지가 3곳이라 Slack 만 실패하는 경우가 생긴다. 어디까지 갔는지를
/// 목적지별로 그대로 보여준다 — 조용히 실패하면 안 된다.
class SubmissionsScreen extends ConsumerWidget {
  const SubmissionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(pendingSubmissionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('내 제출'),
        actions: [
          TextButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final n = await confirmClearAll(context, ref);
              if (n == null) return;
              messenger.showSnackBar(SnackBar(content: Text('$n건을 지웠습니다.')));
            },
            child: const Text('전체 삭제'),
          ),
        ],
      ),
      body: rows.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: screenPadding,
            child: ErrorDisclosure('목록을 불러오지 못했습니다.', detail: '$e'),
          ),
        ),
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: Text('아직 제출한 건이 없습니다.'));
          }
          return ListView(
            padding: screenPadding,
            children: [
              AppCard(children: [for (final s in list) SubmissionRow(s)]),
              const NoteText(
                '목적지가 3곳이라 하나만 실패할 수 있습니다. '
                '실패한 곳만 다시 보내므로 시트에 같은 행이 두 번 들어가지 않습니다.\n'
                '행을 왼쪽으로 밀면 목록에서 지울 수 있습니다 — '
                '이미 올라간 파일과 시트 행은 지워지지 않습니다.',
              ),
            ],
          );
        },
      ),
    );
  }
}
