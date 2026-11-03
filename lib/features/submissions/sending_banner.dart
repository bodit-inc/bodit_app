/// 백그라운드 전송 진행 띠. **홈과 `내 제출` 이 같은 위젯을 쓴다** —
/// 두 곳에 비슷한 코드를 두면 한쪽만 고치게 된다(`SubmissionRow` 와 같은 이유).
library;

import 'dart:async';

import 'package:bodit_app/core/widgets/app_widgets.dart';
import 'package:bodit_app/data/background_send.dart';
import 'package:bodit_app/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class SendingBanner extends ConsumerWidget {
  const SendingBanner({super.key, this.onTap});

  /// 눌렀을 때 할 일을 화면이 가로챈다.
  ///
  /// `내 제출` 은 이미 그 목록이라 화면을 또 띄울 이유가 없다 — 그 자리에서
  /// 스크롤만 한다. 주지 않으면 목록 화면을 열고 그 건으로 데려간다.
  final void Function(int id)? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sending = ref.watch(backgroundSendProvider);
    final id = sending.newestId;
    // 전송 중이 아니면 자리를 차지하지 않는다.
    if (id == null) return const SizedBox.shrink();

    return ProgressBanner(
      text: sending.count == 1
          ? '제출한 건을 전송하고 있습니다 · 눌러서 보기'
          : '${sending.count}건을 전송하고 있습니다 · 눌러서 보기',
      onTap: () {
        final handler = onTap;
        if (handler != null) {
          handler(id);
          return;
        }
        // 가장 최근에 제출한 건으로 데려간다. 배너를 누른 사용자가 보려는
        // 것은 "방금 누른 그것이 어디까지 갔나" 다.
        unawaited(context.push(Routes.submissionsFocus(id)));
      },
    );
  }
}
