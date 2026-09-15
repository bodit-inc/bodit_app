/// 타이포그래피.
///
/// 크기·굵기는 `fh-front-app` 의 `FhTextStyleEnum` 과 **값이 동일하다** —
/// 사내 앱끼리 글자 인상을 맞춘다.
///
/// 다만 별도 enum 을 만들지 않고 Material 의 [TextTheme] 슬롯에 그대로 얹었다.
/// 이유가 두 가지다:
///
///   1. 그쪽 enum 의 이름(displayLarge … labelSmall)이 [TextTheme] 슬롯 이름과
///      **1:1로 같다.** 굳이 병렬 API 를 둘 이유가 없다.
///   2. 이 앱의 공통 위젯이 이미 전부 `Theme.of(context).textTheme.*` 를 쓴다.
///      여기에 얹으면 화면 코드를 한 줄도 안 고치고 폰트가 적용된다.
///
/// 그래서 호출부는 이렇게 쓴다:
///   `Theme.of(context).textTheme.bodyMedium`   (= FhTextStyleEnum.bodyMedium)
library;

import 'package:flutter/material.dart';

abstract final class AppTypography {
  static const fontFamily = 'Pretendard';

  /// fh-front-app 의 스케일과 동일. 값을 바꾸려면 저쪽과 같이 봐야 한다.
  static const textTheme = TextTheme(
    displayLarge: TextStyle(
      fontFamily: fontFamily, fontSize: 40, fontWeight: FontWeight.w600,
    ),
    displayMedium: TextStyle(
      fontFamily: fontFamily, fontSize: 36, fontWeight: FontWeight.w600,
    ),
    displaySmall: TextStyle(
      fontFamily: fontFamily, fontSize: 32, fontWeight: FontWeight.w600,
    ),
    headlineLarge: TextStyle(
      fontFamily: fontFamily, fontSize: 28, fontWeight: FontWeight.w600,
    ),
    headlineMedium: TextStyle(
      fontFamily: fontFamily, fontSize: 24, fontWeight: FontWeight.w600,
    ),
    headlineSmall: TextStyle(
      fontFamily: fontFamily, fontSize: 18, fontWeight: FontWeight.w600,
    ),
    titleLarge: TextStyle(
      fontFamily: fontFamily, fontSize: 24, fontWeight: FontWeight.w600,
    ),
    titleMedium: TextStyle(
      fontFamily: fontFamily, fontSize: 22, fontWeight: FontWeight.w600,
    ),
    titleSmall: TextStyle(
      fontFamily: fontFamily, fontSize: 20, fontWeight: FontWeight.w600,
    ),
    bodyLarge: TextStyle(
      fontFamily: fontFamily, fontSize: 18, fontWeight: FontWeight.w500,
    ),
    bodyMedium: TextStyle(
      fontFamily: fontFamily, fontSize: 17, fontWeight: FontWeight.w500,
    ),
    bodySmall: TextStyle(
      fontFamily: fontFamily, fontSize: 16, fontWeight: FontWeight.w400,
    ),
    labelLarge: TextStyle(
      fontFamily: fontFamily, fontSize: 18, fontWeight: FontWeight.w600,
    ),
    labelMedium: TextStyle(
      fontFamily: fontFamily, fontSize: 16, fontWeight: FontWeight.w600,
    ),
    labelSmall: TextStyle(
      fontFamily: fontFamily, fontSize: 14, fontWeight: FontWeight.w600,
    ),
  );
}
