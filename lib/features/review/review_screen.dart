import 'dart:async';

import 'package:bodit_app/core/theme/tokens.dart';
import 'package:bodit_app/core/utils/filename.dart';
import 'package:bodit_app/core/widgets/app_widgets.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 시안 ⑤⑥⑦⑧⑨ — 검토 폼.
///
/// 확신 낮은 필드를 표시하지 않는다(ADR Decision 11). 어차피 전부 훑어야 하는데
/// 특정 필드만 찍으면 나머지를 안 보게 된다.
///
/// 저장될 파일명을 여기서 보여주고 **직접 고칠 수 있다**(Decision 12c).
class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key});

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  // TODO(james): OCR 결과로 채운다. 지금은 시안과 같은 예시 값.
  final _belongDate = DateTime(2026, 8, 5);
  final _vendor = '영풍문고';
  final _description = '8월 도서';
  final _total = 19000;

  String? _filenameOverride;

  String get _filename =>
      _filenameOverride ??
      buildEvidenceFilename(
        belongDate: _belongDate,
        vendor: _vendor,
        description: _description,
        evidenceType: '영수증',
        amount: _total,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('검토'),
        actions: [
          TextButton(
            onPressed: () {}, // TODO(james): 큐에 넣고 전송
            child: const Text('제출'),
          ),
        ],
      ),
      body: ListView(
        padding: screenPadding,
        children: [
          const SectionHeader('기본'),
          AppCard(
            children: [
              LabeledRow(label: '소속날짜', value: _fmt(_belongDate), onTap: () {}),
              LabeledRow(label: '지출날짜', value: _fmt(_belongDate), onTap: () {}),
              LabeledRow(label: '업체명', value: _vendor, onTap: () {}),
              LabeledRow(label: '내역', value: _description, onTap: () {}),
            ],
          ),

          const SectionHeader('분류 — 영수증에 없는 항목'),
          AppCard(
            children: [
              Padding(
                padding: const EdgeInsets.all(Gap.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('비목', style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: Gap.sm),
                    Wrap(
                      spacing: Gap.sm,
                      children: [
                        SuggestChip('도서인쇄비', selected: true, onTap: () {}),
                        SuggestChip('사무용품비', onTap: () {}),
                        SuggestChip('직접 선택', onTap: _openCategoryPicker),
                      ],
                    ),
                    // 근거 없이 채워두면 사용자가 못 믿고 전부 다시 확인한다.
                    const SuggestReason('영풍문고는 지난 3건 모두 도서인쇄비였습니다'),
                  ],
                ),
              ),
            ],
          ),

          const SectionHeader('금액'),
          AppCard(
            children: [
              LabeledRow(label: '총금액', value: '19,000', onTap: () {}),
              LabeledRow(label: '공급가액', value: '19,000', onTap: () {}),
              LabeledRow(label: '부가세', value: '0', onTap: () {}),
            ],
          ),
          const SizedBox(height: Gap.md),
          NoticeBanner(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('부가세가 0원으로 읽혔습니다.\n'
                    '도서는 면세라 0원이 맞습니다. 과세 영수증인데 총액만 찍혀 '
                    '있다면 아래로 나눌 수 있습니다.'),
                const SizedBox(height: Gap.sm),
                OutlinedButton(
                  // TODO(james): splitVat(_total) 적용
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(horizontal: Gap.md),
                  ),
                  child: const Text('1.1로 나누기'),
                ),
              ],
            ),
          ),

          const SectionHeader('저장될 파일명'),
          AppCard(
            children: [
              Padding(
                padding: const EdgeInsets.all(Gap.lg),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _filename,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _editFilename,
                      child: const Text('수정'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const NoteText('위 항목을 고치면 파일명도 따라 바뀝니다. 직접 고칠 수도 있습니다.'),
        ],
      ),
    );
  }

  void _openCategoryPicker() {
    // 시안 ⑧ — 추천·최근순으로 정렬된 검색 목록.
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (_) => const _CategoryPickerSheet(),
      ),
    );
  }

  Future<void> _editFilename() async {
    final controller = TextEditingController(text: _filename);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('파일명 수정'),
        content: TextField(controller: controller, maxLines: 2),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('확인'),
          ),
        ],
      ),
    );
    if (result == null) return;
    // 사용자가 직접 친 값에도 치환 규칙을 반드시 적용한다 — `/` 하나로
    // Drive 동기화가 깨진다.
    setState(() => _filenameOverride = sanitizeSegment(result));
  }

  static String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

class _CategoryPickerSheet extends StatelessWidget {
  const _CategoryPickerSheet();

  @override
  Widget build(BuildContext context) {
    // TODO(james): `_비목마스터` 탭에서 읽어온 값으로 바꾼다. 하드코딩 금지.
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
      children: [
        Text('비목 선택', style: Theme.of(context).textTheme.titleMedium),
        const SectionHeader('추천'),
        const AppCard(
          children: [
            LabeledRow(
              label: '',
              value: '도서인쇄비',
              trailing: StatusPill('지난 3건', tone: PillTone.ok),
            ),
          ],
        ),
        const SectionHeader('최근 사용'),
        const AppCard(
          children: [
            LabeledRow(label: '', value: '사무용품비'),
            LabeledRow(label: '', value: '회의비'),
            LabeledRow(label: '', value: '여비교통비'),
          ],
        ),
        const SizedBox(height: Gap.xl),
      ],
    );
  }
}
