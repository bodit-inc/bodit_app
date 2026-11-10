/// 새 버전이 있으면 **한 번 물어본다.** 쓰는 것은 막지 않는다.
///
/// ## 왜 홈에 두나
///
/// 다이얼로그는 `Navigator` 아래에서만 띄울 수 있다. 차단 화면이 있는
/// `MaterialApp.builder` 자리는 라우터보다 **위**라 거기서는 못 띄운다.
///
/// 자리를 옮길 이유도 있다 — 로그인 화면 위에 "업데이트하세요" 를 띄우면
/// 사용자는 로그인이 막힌 줄 안다. 일을 시작하는 자리(홈)에서 묻는 쪽이 맞다.
///
/// ## 그려지는 것이 없는 위젯이다
///
/// 화면을 차지하지 않고(`SizedBox.shrink`) 다이얼로그만 띄운다. 홈 코드에
/// 섞어두면 `build` 안에 조회·저장·다이얼로그가 같이 들어가 길어지므로
/// 여기로 뺐다 — 홈은 `const UpdateNotice()` 한 줄만 안다.
///
/// ## 같은 버전은 하루에 한 번만
///
/// 켤 때마다 뜨면 [나중에] 를 반사적으로 누르게 되고, 그러면 정작 중요한
/// 안내도 같이 지나간다. 버전과 날짜를 적어두고 둘 중 하나가 바뀌었을 때만
/// 묻는다 — 새 버전이 또 올라오면 같은 날에도 다시 묻는다.
library;

import 'dart:async';

import 'package:bodit_app/core/log.dart';
import 'package:bodit_app/core/widgets/app_widgets.dart';
import 'package:bodit_app/data/providers.dart';
import 'package:bodit_app/features/update/update_prompt.dart';
import 'package:bodit_app/models/app_update.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 마지막으로 물어본 버전과 날짜. `1.0.1+6|2026-11-10` 꼴.
///
/// 한 칸에 둘을 넣는다 — 따로 두면 한쪽만 쓰이고 남는 경우가 생긴다.
const _askedKey = 'update_notice_asked';

class UpdateNotice extends ConsumerStatefulWidget {
  const UpdateNotice({super.key});

  @override
  ConsumerState<UpdateNotice> createState() => _UpdateNoticeState();
}

class _UpdateNoticeState extends ConsumerState<UpdateNotice> {
  /// 이 화면에 머무는 동안 두 번 묻지 않는다. 조회 결과가 다시 흐르거나
  /// 위젯이 리빌드돼도 다이얼로그가 겹쳐 뜨면 안 된다.
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    // 이미 끝난 조회면 바로 받고(`fireImmediately`), 아직이면 끝날 때 받는다.
    ref.listenManual(appUpdateProvider, (_, next) {
      final update = next.value;
      if (update != null) unawaited(_ask(update));
    }, fireImmediately: true);
  }

  Future<void> _ask(AppUpdate update) async {
    if (_handled || update.urgency != UpdateUrgency.optional) return;
    _handled = true;

    // 이 `await` 이 프레임 밖으로 나가는 역할도 한다 — `initState` 에서
    // 바로 다이얼로그를 띄우면 "빌드 중에 띄웠다" 고 프레임워크가 던진다.
    if (!await _shouldAsk(update)) return;
    if (!mounted) return;

    final go = await confirmUpdate(
      context,
      title: '새 버전이 있습니다',
      message: Text(
        [
          if (update.message != null) update.message!,
          updateVersionLine(update),
        ].where((s) => s.isNotEmpty).join('\n\n'),
      ),
    );
    if (!go || !mounted) return;
    await openUpdateLink(context, update);
  }

  /// 물어봐도 되는지. **실패하면 묻는 쪽으로 기운다** — 저장소를 못 읽었다고
  /// 안내를 삼키면, 정작 올려야 할 버전을 아무도 모른다.
  Future<bool> _shouldAsk(AppUpdate update) async {
    final mark = '${update.latest}|${_today()}';
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_askedKey) == mark) return false;
      await prefs.setString(_askedKey, mark);
      return true;
    } on Object catch (e, st) {
      log.w('업데이트 안내 기록을 읽지 못했습니다.', error: e, stackTrace: st);
      return true;
    }
  }

  /// `2026-11-10`. 날짜만 쓰므로 포맷을 따로 들여오지 않는다.
  String _today() {
    final now = DateTime.now();
    return '${now.year}-${now.month}-${now.day}';
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
