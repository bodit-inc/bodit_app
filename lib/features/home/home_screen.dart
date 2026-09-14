import 'dart:async';

import 'package:bodit_app/core/theme/tokens.dart';
import 'package:bodit_app/core/widgets/app_widgets.dart';
import 'package:bodit_app/data/providers.dart';
import 'package:bodit_app/features/capture/capture_service.dart';
import 'package:bodit_app/features/review/review_controller.dart';
import 'package:bodit_app/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 시안 ②·⑬ — 촬영/파일 선택 + 전송 대기 큐 + 원본 바로가기.
///
/// 오프라인일 때도 같은 화면이다. **재전송이 수동이라**(ADR 12a) 자동 전송
/// 문구를 쓰지 않고 [전송 시도] 버튼을 둔다.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _sending = false;

  @override
  Widget build(BuildContext context) {
    final queue = ref.watch(pendingSubmissionsProvider);
    final pending = queue.value?.where((s) => !s.slackDone || !s.sheetsDone || !s.driveDone).toList() ??
        const [];

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
                  onTap: _capture,
                ),
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: BigActionCard(
                  icon: Icons.image_outlined,
                  title: '파일 선택',
                  subtitle: 'PDF·JPG·PNG',
                  onTap: _pickFiles,
                ),
              ),
            ],
          ),
          if (pending.isNotEmpty) ...[
            SectionHeader('전송 대기 ${pending.length}건 · 최근순'),
            AppCard(
              children: [
                for (final s in pending.take(3))
                  LabeledRow(
                    label: '',
                    value: s.filename,
                    trailing: StatusPill(
                      s.lastError == null ? '대기' : '실패',
                      tone: s.lastError == null
                          ? PillTone.waiting
                          : PillTone.error,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: Gap.md),
            FilledButton(
              onPressed: _sending ? null : _sendPending,
              child: _sending
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('전송 시도'),
            ),
            const NoteText(
              '지금 등록한 건은 기기에 임시저장합니다. '
              '인터넷 연결이 원활해지면 전송 시도해주세요.',
            ),
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

  Future<void> _capture() async {
    final shot = await ref.read(captureServiceProvider).fromCamera();
    if (shot == null) return;
    await _openReview(<CapturedEvidence>[shot]);
  }

  Future<void> _pickFiles() async {
    final files = await ref.read(captureServiceProvider).fromFiles();
    if (files.isEmpty) return;
    await _openReview(files);
  }

  /// 검토 화면으로 넘기고 OCR 을 시작한다.
  /// OCR 을 기다리지 않고 먼저 화면을 띄운다 — 진행 상태는 검토 화면이 보여준다.
  Future<void> _openReview(List<CapturedEvidence> evidence) async {
    if (!mounted) return;
    unawaited(ref.read(reviewControllerProvider.notifier).load(evidence));
    await context.push(Routes.review);
  }

  Future<void> _sendPending() async {
    setState(() => _sending = true);
    try {
      final results = await ref.read(submissionSenderProvider).sendPending();
      if (!mounted) return;

      final failed = results.where((r) => !r.allDone).toList();
      final message = failed.isEmpty
          ? '${results.length}건을 모두 보냈습니다.'
          : '${results.length - failed.length}건 성공, '
              '${failed.length}건 실패 — ${failed.first.error}';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}
