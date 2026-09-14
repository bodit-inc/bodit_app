import 'dart:async';

import 'package:bodit_app/core/router/app_router.dart';
import 'package:bodit_app/core/theme/tokens.dart';
import 'package:bodit_app/core/widgets/app_widgets.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 시안 ②·⑬ — 촬영/파일 선택 + 전송 대기 큐 + 원본 바로가기.
///
/// 오프라인일 때도 같은 화면이다. 배너와 [전송 시도] 버튼만 더 붙는다
/// — 재전송이 수동이라(ADR 12a) 자동 전송 문구를 쓰지 않는다.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // TODO(james): QueueDb.pending() 을 watch 해서 실제 건수로 바꾼다.
    const pendingCount = 0;

    return Scaffold(
      appBar: AppBar(title: const Text('매입내역')),
      body: ListView(
        padding: screenPadding,
        children: [
          Row(
            children: [
              Expanded(
                child: BigActionCard(
                  icon: Icons.photo_camera_outlined,
                  title: '증빙 촬영',
                  subtitle: '영수증·전표',
                  onTap: () => context.push(Routes.review),
                ),
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: BigActionCard(
                  icon: Icons.image_outlined,
                  title: '파일 선택',
                  subtitle: 'PDF·JPG·PNG',
                  onTap: () => context.push(Routes.review),
                ),
              ),
            ],
          ),
          if (pendingCount > 0) ...[
            const SectionHeader('전송 대기'),
            AppCard(
              children: [
                LabeledRow(
                  label: '대기',
                  value: '$pendingCount건',
                  onTap: () => context.push(Routes.submissions),
                ),
              ],
            ),
            const NoteText('전송 시도를 누르면 보냅니다. 자동으로 보내지 않습니다.'),
          ],
          const SectionHeader('바로가기'),
          AppCard(
            children: [
              // TODO(james): url_launcher 로 실제 Sheets·Drive·Slack URL 을 연다.
              LabeledRow(label: '스프레드시트', value: '매입내역', onTap: () {}),
              LabeledRow(label: '드라이브', value: '증빙 폴더', onTap: () {}),
              LabeledRow(label: 'Slack', value: '#purchase', onTap: () {}),
            ],
          ),
          const NoteText('조회는 앱에서 다시 만들지 않고 원본으로 연결합니다.'),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        onDestinationSelected: (i) {
          if (i == 1) unawaited(context.push(Routes.submissions));
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: '홈'),
          NavigationDestination(icon: Icon(Icons.list_alt), label: '내 제출'),
        ],
      ),
    );
  }
}
