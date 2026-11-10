/// 쓰면 안 되는 버전을 **라우터 바깥에서** 막는다.
///
/// ## 왜 라우터 바깥인가
///
/// 라우트마다 검사를 붙이면 새 화면이 생길 때 한 군데를 빠뜨린다. 그러면
/// 막힌 줄 알았던 버전이 그 화면으로 들어가 제출까지 한다 — 시트는
/// append-only 라 그 행은 앱으로 못 지운다.
///
/// `app.dart` 의 `MaterialApp.builder` 에 끼우면 **라우터가 무엇을 그리든**
/// 그 위에 있다. 개발 빌드의 `DEV` 리본을 거기 둔 것과 같은 이유다.
///
/// ## 조회 중에는 막지 않는다
///
/// 답이 오기 전까지는 앱을 그대로 쓴다. 여기서 또 스플래시를 띄우면 켤 때마다
/// 네트워크를 기다리게 되고, 비행기 모드에서는 10초를 기다린 끝에 아무 일도
/// 안 일어난다. 대신 **답이 늦게 와도 그때 막힌다** — 쓰던 중에 화면이
/// 덮일 수 있다는 뜻인데, 그건 "쓰면 안 되는 버전" 이라서 맞는 동작이다.
library;

import 'package:bodit_app/data/providers.dart';
import 'package:bodit_app/features/update/update_required_screen.dart';
import 'package:bodit_app/models/app_update.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class UpdateGate extends ConsumerWidget {
  const UpdateGate({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 조회가 실패하면 `AppUpdateService` 가 `AppUpdate.none` 을 돌려준다 —
    // 여기서 에러를 따로 다루지 않는 이유다(막지 않는 쪽이 기본값).
    final update = ref.watch(appUpdateProvider).value;
    if (update != null && update.urgency == UpdateUrgency.blocked) {
      return UpdateRequiredScreen(update);
    }
    return child;
  }
}
