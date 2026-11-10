/// 이 버전으로는 더 못 쓴다고 말하는 화면.
///
/// ## 왜 다이얼로그가 아닌가
///
/// 다이얼로그는 닫을 수 있고, 닫으면 그대로 쓰게 된다. 여기는 **쓰면 안 되는
/// 버전**이라 그걸 허용할 수 없다 — 제출이 Sheets 에 append-only 로 들어가서
/// 잘못 들어간 행을 앱으로 되돌릴 수 없다(ADR). 그래서 화면을 통째로 덮고,
/// 뒤로 갈 길도 두지 않는다.
///
/// `minimum_version` 을 콘솔에서 비워두면 아무도 여기 오지 않는다. 평소에는
/// 비어 있는 것이 정상이다.
library;

import 'package:bodit_app/core/app_info.dart';
import 'package:bodit_app/core/theme/tokens.dart';
import 'package:bodit_app/core/widgets/app_widgets.dart';
import 'package:bodit_app/features/update/update_prompt.dart';
import 'package:bodit_app/models/app_update.dart';
import 'package:flutter/material.dart';

class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen(this.update, {super.key});

  final AppUpdate update;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final versions = updateVersionLine(update);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: screenPadding,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.system_update,
                size: 56,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: Gap.lg),
              Text('업데이트가 필요합니다', style: text.titleLarge),
              const SizedBox(height: Gap.md),
              Text(
                // **왜 막혔는지** 적는다. "업데이트하세요" 만으로는 사용자가
                // 자기 앱이 고장난 줄 안다.
                update.message ??
                    '이 버전으로는 매입내역을 올릴 수 없습니다. '
                        '최신 버전을 받은 뒤 다시 열어주세요.',
                style: text.bodyMedium,
                textAlign: TextAlign.center,
              ),
              if (versions.isNotEmpty) ...[
                const SizedBox(height: Gap.sm),
                Text(
                  versions,
                  style: text.labelSmall?.copyWith(
                    color: AppColors.neutralFg,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
              const SizedBox(height: Gap.xl),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => openUpdateLink(context, update),
                  child: const Text('업데이트 받기'),
                ),
              ),
              // 받는 곳을 못 찾았을 때 물어볼 상대가 있어야 한다. 버전은
              // 계정 메뉴에도 있지만 여기서는 그 메뉴에 닿을 수 없다.
              const SizedBox(height: Gap.lg),
              if (AppInfo.version.isNotEmpty)
                NoteText('지금 버전 ${AppInfo.version}'),
            ],
          ),
        ),
      ),
    );
  }
}
