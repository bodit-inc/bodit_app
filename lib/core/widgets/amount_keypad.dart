/// 금액 전용 입력 키패드.
///
/// ## 왜 기본 키보드를 안 쓰나
///
/// 시스템 숫자 키보드는 기기·IME 마다 배열이 다르고, 한글 자판이 튀어나오거나
/// 소수점·마이너스가 섞여 들어온다. 금액은 **정수 원화 하나**만 받으면 되므로
/// 필요한 키만 두는 쪽이 빠르고 틀릴 여지도 없다.
///
/// 배열은 계산기와 같다(위가 7·8·9). 금액을 다루는 사람에게 익숙한 배열이다.
/// 전화기 배열(위가 1·2·3)과 섞이면 오입력이 난다.
library;

import 'dart:async';

import 'package:bodit_app/core/theme/tokens.dart';
import 'package:bodit_app/core/utils/currency.dart';
import 'package:bodit_app/core/utils/korean_amount.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 키패드가 돌려주는 것. 금액과 **어느 통화인지**를 같이 준다.
class AmountResult {
  const AmountResult(this.minor, this.currencyCode);

  /// 통화의 최소 단위 정수. 원화는 원, 달러는 센트.
  final int minor;
  final String currencyCode;
}

/// 금액 입력 시트를 띄우고 확정된 값을 돌려준다. 취소하면 null.
Future<AmountResult?> showAmountKeypad(
  BuildContext context, {
  required String title,
  int? initial,
  String currencyCode = 'KRW',
}) {
  return showModalBottomSheet<AmountResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _AmountKeypadSheet(
      title: title,
      initial: initial,
      currencyCode: currencyCode,
    ),
  );
}

class _AmountKeypadSheet extends StatefulWidget {
  const _AmountKeypadSheet({
    required this.title,
    required this.currencyCode,
    this.initial,
  });

  final String title;
  final int? initial;
  final String currencyCode;

  @override
  State<_AmountKeypadSheet> createState() => _AmountKeypadSheetState();
}

class _AmountKeypadSheetState extends State<_AmountKeypadSheet> {
  late int _value = widget.initial ?? 0;
  late Currency _currency = currencyOf(widget.currencyCode);

  /// 원 단위 정수라 자리수 상한을 둔다. 조 단위를 넘길 일은 없고,
  /// 넘기면 int 연산과 화면이 같이 깨진다.
  static const _maxDigits = 12;

  void _push(String digits) {
    final next = '$_value$digits';
    if (next.replaceFirst(RegExp('^0+'), '').length > _maxDigits) return;
    setState(() => _value = int.parse(next));
    unawaited(HapticFeedback.selectionClick());
  }

  void _backspace() {
    setState(() => _value = _value ~/ 10);
    unawaited(HapticFeedback.selectionClick());
  }

  void _clear() {
    setState(() => _value = 0);
    unawaited(HapticFeedback.mediumImpact());
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: Gap.md),

            // 입력값. 길게 눌러 지울 수 있다.
            GestureDetector(
              onLongPress: _clear,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  // 통화 선택. 해외 증빙이 있어서 원화 고정으로 둘 수 없다.
                  _CurrencyButton(
                    currency: _currency,
                    onChanged: (c) => setState(() => _currency = c),
                  ),
                  Expanded(
                    child: Text(
                      _currency.format(_value),
                      textAlign: TextAlign.end,
                      style: Theme.of(context)
                          .textTheme
                          .displayMedium
                          ?.copyWith(letterSpacing: -1),
                    ),
                  ),
                ],
              ),
            ),

            // 0 하나 틀리면 10배다. 숫자만 보면 안 걸리는 실수가 여기서 걸린다.
            // **원화일 때만** 보여준다 — 외화를 한글로 읽어주면 오히려 헷갈린다.
            if (_currency.code == 'KRW') ...[
              const SizedBox(height: Gap.xs),
              Text(
                readKoreanAmount(_value),
                textAlign: TextAlign.end,
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: AppColors.suggestFg),
              ),
            ],
            // 소수점 통화는 오른쪽부터 채워진다. 처음 보면 헷갈려서 알려준다.
            if (_currency.decimals > 0) ...[
              const SizedBox(height: Gap.xs),
              Text(
                '뒤에서부터 채워집니다 — 1·2·9·9 를 누르면 12.99',
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.neutralFg,
                      fontWeight: FontWeight.w400,
                    ),
              ),
            ],

            const SizedBox(height: Gap.lg),
            _Keypad(onDigits: _push, onBackspace: _backspace),
            const SizedBox(height: Gap.md),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(context, AmountResult(_value, _currency.code)),
              child: const Text('확인'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({required this.onDigits, required this.onBackspace});

  final void Function(String) onDigits;
  final VoidCallback onBackspace;

  @override
  Widget build(BuildContext context) {
    // 계산기 배열. 마지막 줄의 `00` 은 금액 입력에서 가장 자주 쓰는 키다.
    const rows = <List<String>>[
      ['7', '8', '9'],
      ['4', '5', '6'],
      ['1', '2', '3'],
      ['00', '0', '⌫'],
    ];

    return Column(
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: Gap.sm),
            child: Row(
              children: [
                for (final key in row)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Gap.xs),
                      child: _Key(
                        label: key,
                        onTap: key == '⌫' ? onBackspace : () => onDigits(key),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  bool get _isDelete => label == '⌫';

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _isDelete ? AppColors.neutralBg : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.button),
        side: const BorderSide(color: Color(0xFFE3E3E8)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.button),
        // 손가락으로 빠르게 누르는 키다. 작으면 오입력이 난다.
        child: SizedBox(
          height: 52,
          child: Center(
            child: Text(
              label,
              // 숫자 키는 titleMedium, 지우기는 한 단계 작게.
              style: _isDelete
                  ? Theme.of(context).textTheme.titleSmall
                  : Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ),
      ),
    );
  }
}


/// 통화 선택 버튼. 누르면 목록이 뜬다.
class _CurrencyButton extends StatelessWidget {
  const _CurrencyButton({required this.currency, required this.onChanged});

  final Currency currency;
  final ValueChanged<Currency> onChanged;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: () async {
        final picked = await showModalBottomSheet<Currency>(
          context: context,
          showDragHandle: true,
          builder: (_) => _CurrencyPicker(selected: currency),
        );
        if (picked != null) onChanged(picked);
      },
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: Gap.md),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            currency.code,
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const Icon(Icons.expand_more, size: 18),
        ],
      ),
    );
  }
}

class _CurrencyPicker extends StatelessWidget {
  const _CurrencyPicker({required this.selected});

  final Currency selected;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      builder: (_, controller) => ListView.builder(
        controller: controller,
        itemCount: currencies.length + 1,
        itemBuilder: (_, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.sm),
              child: Text(
                '통화 선택',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            );
          }
          final c = currencies[i - 1];
          return ListTile(
            dense: true,
            leading: SizedBox(
              width: 46,
              child: Text(
                c.code,
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(fontFamily: 'monospace'),
              ),
            ),
            title: Text(c.name),
            trailing: c.code == selected.code
                ? const Icon(Icons.check, size: 18)
                : null,
            onTap: () => Navigator.pop(context, c),
          );
        },
      ),
    );
  }
}
