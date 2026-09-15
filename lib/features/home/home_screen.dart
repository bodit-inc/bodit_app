import 'dart:async';

import 'package:bodit_app/core/config.dart';
import 'package:bodit_app/core/links.dart';
import 'package:bodit_app/core/theme/tokens.dart';
import 'package:bodit_app/core/widgets/app_widgets.dart';
import 'package:bodit_app/data/providers.dart';
import 'package:bodit_app/features/auth/auth_controller.dart';
import 'package:bodit_app/features/capture/capture_service.dart';
import 'package:bodit_app/features/review/review_controller.dart';
import 'package:bodit_app/features/submissions/submission_row.dart';
import 'package:bodit_app/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

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
    final pending =
        queue.value
            ?.where((s) => !s.slackDone || !s.sheetsDone || !s.driveDone)
            .toList() ??
        const [];

    return Scaffold(
      appBar: AppBar(title: const Text('매입내역'), actions: [_AccountMenu()]),
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
            Row(
              children: [
                Expanded(
                  child: SectionHeader('전송 대기 ${pending.length}건 · 최근순'),
                ),
                TextButton(
                  onPressed: () => _clearAll(context),
                  child: const Text('전체 삭제'),
                ),
              ],
            ),
            AppCard(
              // `내 제출` 과 같은 위젯이다 — 목적지별 성패도, 전송 전 건
              // 편집도 여기서 그대로 된다.
              children: [for (final s in pending.take(3)) SubmissionRow(s)],
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
              '제출할 때 보내지 못한 건입니다. 기기에 보관돼 있으니 '
              '인터넷 연결이 원활해지면 전송 시도해주세요.',
            ),
          ],
          const SectionHeader('바로가기'),
          AppCard(
            children: [
              _ShortcutRow(
                label: '스프레드시트',
                value: '매입내역',
                id: Config.spreadsheetId,
                url: spreadsheetUrl,
              ),
              _ShortcutRow(
                label: '드라이브',
                value: '증빙 폴더',
                id: Config.driveFolderId,
                url: driveFolderUrl,
              ),
              _ShortcutRow(
                label: 'Slack',
                value: '#purchase',
                id: Config.slackChannelId,
                url: slackChannelUrl,
              ),
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

  Future<void> _clearAll(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final n = await confirmClearAll(context, ref);
    if (n == null || !mounted) return;
    messenger.showSnackBar(SnackBar(content: Text('$n건을 지웠습니다.')));
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

/// 앱바의 계정 메뉴 — 누가 로그인했는지 + 로그아웃.
///
/// ## 로그아웃이 왜 필요한가
///
/// "쓸 일 없는 기능" 처럼 보이지만 아니다. google_sign_in 7.x 는 인증과 인가가
/// 별개라서, **인가 동의를 거부했거나 스코프가 늘어나면 다시 로그인하는 것이
/// 유일한 복구 경로**다. 버튼이 없으면 앱 데이터를 지우는 수밖에 없다.
///
/// 등록자(`createdBy`)로 시트에 박히는 계정이라 누구로 로그인했는지도 보여준다.
class _AccountMenu extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final email = ref.watch(authControllerProvider).value?.email;

    return PopupMenuButton<String>(
      icon: const Icon(Icons.account_circle_outlined),
      tooltip: '계정',
      onSelected: (v) {
        if (v == 'signOut') {
          unawaited(ref.read(authControllerProvider.notifier).signOut());
        }
      },
      itemBuilder: (_) => [
        if (email != null)
          PopupMenuItem<String>(
            enabled: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('등록자', style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(height: 2),
                Text(email, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'signOut',
          child: Row(
            children: [
              Icon(Icons.logout, size: 18),
              SizedBox(width: Gap.sm),
              Text('로그아웃'),
            ],
          ),
        ),
      ],
    );
  }
}

/// 원본으로 가는 바로가기 한 줄.
///
/// 설정값이 비어 있으면 **누를 수 없게** 하고 왜 그런지 말한다.
/// 눌렀는데 아무 일도 안 일어나면 앱이 고장 난 줄 안다.
class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({
    required this.label,
    required this.value,
    required this.id,
    required this.url,
  });

  final String label;
  final String value;
  final String id;
  final String Function(String) url;

  @override
  Widget build(BuildContext context) {
    final configured = id.isNotEmpty;

    return LabeledRow(
      label: label,
      value: configured ? value : null,
      placeholder: '설정 안 됨',
      subtitle: configured ? null : '.env 에 값을 넣고 build_runner 를 다시 돌리세요',
      onTap: configured ? () => _open(context) : null,
    );
  }

  Future<void> _open(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri.parse(url(id));
    // 외부 앱(시트·드라이브·Slack)이 깔려 있으면 그쪽이 받아간다.
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      messenger.showSnackBar(SnackBar(content: Text('$label 을(를) 열지 못했습니다.')));
    }
  }
}
