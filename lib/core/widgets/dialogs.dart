/// 다이얼로그.
///
/// 확인 창과 입력 창이 화면마다 손으로 조립돼 있었다. 버튼 순서·색·문구가
/// 조금씩 달라지면 **위험한 동작인지 아닌지가 화면마다 다르게 읽힌다.**
/// 여기로 모아 한 가지로 보이게 한다.
library;

import 'package:bodit_app/core/widgets/buttons.dart';
import 'package:flutter/material.dart';

/// 되돌릴 수 없는 동작을 확인받는다.
///
/// 확인 버튼이 **빨갛다**. 취소가 왼쪽이고, 다이얼로그 밖을 눌러도 취소다 —
/// 실수로 지우는 쪽보다 실수로 취소하는 쪽이 낫다.
///
/// [message] 에는 **무엇이 지워지고 무엇이 안 지워지는지** 적는다.
/// "정말 삭제하시겠습니까?" 만으로는 판단할 수 없다.
Future<bool> confirmDestructive(
  BuildContext context, {
  required String title,
  required Widget message,
  String confirmLabel = '지우기',
  String cancelLabel = '취소',
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: message,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(cancelLabel),
        ),
        DangerTextButton(
          onPressed: () => Navigator.pop(ctx, true),
          label: confirmLabel,
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// 새 버전이 있다고 알리고, 받으러 갈지 묻는다. 가겠다고 하면 true.
///
/// [confirmDestructive] 와 **버튼 성격이 반대다** — 되돌릴 수 없는 동작이
/// 아니라 권하는 동작이라, 확인이 빨간 글자가 아니라 강조 버튼이다.
/// 창 밖을 눌러도 닫힌다: 여기서 닫는 것은 "나중에" 와 같은 뜻이고,
/// 꼭 받아야 하는 버전은 다이얼로그가 아니라 **화면으로** 막는다
/// (`features/update/update_required_screen.dart`).
///
/// 화면에서 `showDialog` 를 직접 쓰지 않기로 했으므로(`test/architecture_test.dart`)
/// 업데이트 안내도 여기 둔다. 내용은 부르는 쪽이 [message] 로 넘긴다 —
/// `core` 는 버전 비교 규칙을 모른다.
Future<bool> confirmUpdate(
  BuildContext context, {
  required String title,
  required Widget message,
  String updateLabel = '업데이트',
  String laterLabel = '나중에',
}) async {
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: message,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(laterLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(updateLabel),
        ),
      ],
    ),
  );
  return go ?? false;
}

/// 값 하나를 고쳐 받는다. 취소하면 null.
///

/// 긴 글을 읽기만 하는 창. 전송 실패 사유처럼 복사해 갈 수 있어야 하는 것.
Future<void> showDetailDialog(
  BuildContext context, {
  required String title,
  required String detail,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(child: SelectableText(detail)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('확인'),
        ),
      ],
    ),
  );
}

/// 쓰던 내용을 버리고 화면을 벗어날지 확인받는다.
///
/// [confirmDestructive] 와 모양은 같지만 **제목이 없다.** 지우는 대상을
/// 지목할 것이 없어서다 — 사라지는 것은 "지금 화면에 있는 전부" 고,
/// 그 말이 곧 본문이다. 제목에 한 번 더 적으면 같은 말이 두 줄이 된다.
///
/// 머무는 쪽이 왼쪽이고, 창 밖을 눌러도 머문다 —
/// 실수로 버리는 쪽보다 실수로 취소하는 쪽이 낫다.
///
/// 벗어나겠다고 하면 true.
Future<bool> confirmLeave(
  BuildContext context, {
  String message = '화면을 벗어나면 현재 내용이 모두 사라집니다.',
  String stayLabel = '계속 작성하기',
  String leaveLabel = '뒤로가기',
}) async {
  final leave = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(stayLabel),
        ),
        DangerTextButton(
          onPressed: () => Navigator.pop(ctx, true),
          label: leaveLabel,
        ),
      ],
    ),
  );
  return leave ?? false;
}
