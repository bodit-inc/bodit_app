import 'package:bodit_app/core/theme/tokens.dart';
import 'package:bodit_app/core/widgets/app_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 시안 ⑫ — 내 제출 목록. **부분 실패가 여기서 보인다.**
///
/// 목적지가 3곳이라 Slack 만 실패하는 경우가 생긴다. 실패한 곳만 다시 보내므로
/// 시트에 같은 행이 두 번 들어가지 않는다(큐가 목적지별 완료 여부를 들고 있다).
class SubmissionsScreen extends ConsumerWidget {
  const SubmissionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // TODO(james): QueueDb.watchAll() 로 바꾼다.
    return Scaffold(
      appBar: AppBar(title: const Text('내 제출')),
      body: ListView(
        padding: screenPadding,
        children: const [
          SectionHeader('오늘'),
          AppCard(
            children: [
              LabeledRow(
                label: '영풍문고',
                value: '19,000',
                trailing: StatusPill('완료', tone: PillTone.ok),
              ),
              LabeledRow(
                label: '스타벅스',
                value: '12,400',
                trailing: StatusPill('재시도', tone: PillTone.error),
              ),
              LabeledRow(
                label: 'GS칼텍스',
                value: '80,000',
                trailing: StatusPill('대기', tone: PillTone.waiting),
              ),
            ],
          ),
          NoteText(
            '목적지가 3곳이라 하나만 실패할 수 있습니다. '
            '실패한 곳만 다시 보내므로 시트에 같은 행이 두 번 들어가지 않습니다.',
          ),
        ],
      ),
    );
  }
}
