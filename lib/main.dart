import 'package:bodit_app/app.dart';
import 'package:bodit_app/core/app_info.dart';
import 'package:bodit_app/core/config.dart';
import 'package:bodit_app/core/flavor.dart';
import 'package:bodit_app/core/log.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // **화면이 뜨기 전에** 환경을 확정한다. 둘 다 여기서 던질 수 있다:
  //
  //   - `flavor`        — `--dart-define=FLAVOR` 를 빼먹었다
  //   - `ensureConfigured()` — `.env.*` 에 자리값이 남아 있다
  //
  // 뒤로 미루면 "로그인까지 되고 제출에서만 실패하는" 빌드가 돌아다닌다.
  // 운영 시트는 append-only 라 잘못 들어간 행을 앱으로 되돌릴 수 없으므로,
  // 설정이 수상한 빌드는 아예 시작하지 않는 쪽이 싸다.
  final active = flavor;
  Config.ensureConfigured();
  log.i('환경: ${active.label} (${active.name})');

  // 계정 메뉴에 띄울 버전. 환경 검사 **뒤에** 둔다 — 위 둘은 빌드가 수상하면
  // 앱을 세우는 검사라 먼저 터져야 하고, 이건 실패해도 안 던진다.
  await AppInfo.load();

  runApp(const ProviderScope(child: BoditApp()));
}
