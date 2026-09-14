import 'package:bodit_app/core/theme/tokens.dart';
import 'package:flutter/material.dart';

/// 앱 테마. Material 3 기본값을 쓰고 토큰만 얹는다.
///
/// 시안의 iOS 풍 생김새를 흉내내지 않는다 — Android 에서 가짜 iOS UI 가 된다.
abstract final class AppTheme {
  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      // 브랜드 컬러가 정해지기 전까지 쓰는 중립 시드.
      // 확정되면 이 한 줄만 바꾸면 전체가 따라온다.
      seedColor: const Color(0xFF0064D2),
    );

    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFFF2F2F7),
      appBarTheme: const AppBarTheme(centerTitle: false, scrolledUnderElevation: 0),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.card),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.button),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.button),
          ),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.xs),
      ),
    );
  }
}
