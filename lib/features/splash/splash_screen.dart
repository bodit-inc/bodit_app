import 'package:bodit_app/core/theme/tokens.dart';
import 'package:flutter/material.dart';

/// 앱을 켜고 **조용한 로그인 복구가 끝날 때까지** 보이는 화면.
///
/// ## 왜 네이티브 스플래시를 붙잡지 않았나
///
/// `flutter_native_splash` 의 `preserve()` 로 네이티브 스플래시를 유지해봤는데
/// **Android 12 에서 로고 없는 흰 화면**이 됐다. Android 12 부터 스플래시가 OS
/// 소관이라, OS 가 아이콘을 잠깐 띄우고 내린 뒤에는 `windowBackground` 단색만
/// 남는다. 붙잡아 봐야 흰 화면을 오래 보는 것뿐이다.
///
/// Flutter 로 그리면 Android 버전과 iOS 에서 **같은 화면**이 나오고 언제 넘어갈지도
/// 우리가 정한다. 네이티브 스플래시는 첫 프레임까지의 짧은 구간만 맡고(기본 동작),
/// 그 뒤를 이 화면이 이어받는다 — 배경색과 로고가 같아 바뀌는 티가 안 난다.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 네이티브 스플래시와 같은 이미지다.
            SizedBox(
              width: 220,
              child: Image(
                image: AssetImage('assets/brand/logo-primary.png'),
                fit: BoxFit.contain,
              ),
            ),
            SizedBox(height: Gap.xxl),
            SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ),
      ),
    );
  }
}
