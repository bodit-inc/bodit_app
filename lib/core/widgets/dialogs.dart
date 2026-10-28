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
