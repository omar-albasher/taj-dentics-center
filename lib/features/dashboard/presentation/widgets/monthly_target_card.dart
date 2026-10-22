import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/responsive.dart';
import '../../data/monthly_target_repository.dart';

class MonthlyTargetCard extends ConsumerWidget {
  const MonthlyTargetCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progressAsync = ref.watch(monthlyTargetProgressProvider);
    final isDesktop = Responsive.isDesktop(context);

    return progressAsync.when(
      loading: () => Container(
        height: 140,
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
        ),
        child: const Center(
          child: CircularProgressIndicator(color: AppColors.gold, strokeWidth: 2),
        ),
      ),
      error: (e, _) => const SizedBox.shrink(),
      data: (data) {
        final monthKey = (data['month_key'] ?? '').toString();
        final hasTarget = (data['has_target'] as bool?) ?? false;

        final targetSyp = (data['target_syp'] as num?)?.toDouble() ?? 0.0;
        final collectedSyp = (data['collected_syp'] as num?)?.toDouble() ?? 0.0;
        final progressSyp = (data['progress_syp'] as num?)?.toDouble() ?? 0.0;

        final targetUsd = (data['target_usd'] as num?)?.toDouble() ?? 0.0;
        final collectedUsd = (data['collected_usd'] as num?)?.toDouble() ?? 0.0;
        final progressUsd = (data['progress_usd'] as num?)?.toDouble() ?? 0.0;

        final fmt = NumberFormat('#,###');

        return Container(
          padding: EdgeInsets.all(Responsive.spacing(context, 20)),
          decoration: BoxDecoration(
            color: AppColors.cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.gold.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.track_changes, color: AppColors.gold, size: 20),
                  ),
                  SizedBox(width: Responsive.spacing(context, 10)),
                  Text(
                    'الهدف المالي للشهر ($monthKey)',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.w800,
                      fontSize: Responsive.fontSize(context, 16),
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: hasTarget ? 'تعديل الهدف المالي' : 'تحديد الهدف المالي',
                    icon: Icon(
                      hasTarget ? Icons.edit_outlined : Icons.add_circle_outline,
                      color: AppColors.gold,
                      size: 20,
                    ),
                    onPressed: () {
                      _showSetTargetDialog(
                        context,
                        ref,
                        currentSyp: targetSyp,
                        currentUsd: targetUsd,
                        monthKey: monthKey,
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),

              if (!hasTarget)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      children: [
                        Text(
                          'لم يتم تحديد الهدف المالي لهذا الشهر بعد',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: Responsive.fontSize(context, 14),
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        ElevatedButton.icon(
                          onPressed: () {
                            _showSetTargetDialog(
                              context,
                              ref,
                              currentSyp: 0,
                              currentUsd: 0,
                              monthKey: monthKey,
                            );
                          },
                          icon: const Icon(Icons.add, size: 16, color: Colors.black),
                          label: const Text(
                            'تحديد الهدف الآن',
                            style: TextStyle(fontFamily: 'Cairo', color: Colors.black, fontWeight: FontWeight.w700),
                          ),
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.gold),
                        ),
                      ],
                    ),
                  ),
                )
              else if (isDesktop)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _TargetProgressBlock(
                        currencyLabel: 'ليرة سورية (SYP)',
                        collectedText: '${fmt.format(collectedSyp.toInt())} ل.س',
                        targetText: '${fmt.format(targetSyp.toInt())} ل.س',
                        percentage: progressSyp,
                        color: progressSyp >= 100 ? AppColors.success : AppColors.gold,
                      ),
                    ),
                    SizedBox(width: Responsive.spacing(context, 24)),
                    Expanded(
                      child: _TargetProgressBlock(
                        currencyLabel: 'دولار أمريكي (USD)',
                        collectedText: '\$ ${fmt.format(collectedUsd.toInt())}',
                        targetText: '\$ ${fmt.format(targetUsd.toInt())}',
                        percentage: progressUsd,
                        color: progressUsd >= 100 ? AppColors.success : AppColors.gold,
                      ),
                    ),
                  ],
                )
              else
                Column(
                  children: [
                    _TargetProgressBlock(
                      currencyLabel: 'ليرة سورية (SYP)',
                      collectedText: '${fmt.format(collectedSyp.toInt())} ل.س',
                      targetText: '${fmt.format(targetSyp.toInt())} ل.س',
                      percentage: progressSyp,
                      color: progressSyp >= 100 ? AppColors.success : AppColors.gold,
                    ),
                    const SizedBox(height: 16),
                    _TargetProgressBlock(
                      currencyLabel: 'دولار أمريكي (USD)',
                      collectedText: '\$ ${fmt.format(collectedUsd.toInt())}',
                      targetText: '\$ ${fmt.format(targetUsd.toInt())}',
                      percentage: progressUsd,
                      color: progressUsd >= 100 ? AppColors.success : AppColors.gold,
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  void _showSetTargetDialog(
    BuildContext context,
    WidgetRef ref, {
    required double currentSyp,
    required double currentUsd,
    required String monthKey,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => _SetMonthlyTargetDialog(
        currentSyp: currentSyp,
        currentUsd: currentUsd,
        monthKey: monthKey,
      ),
    );
  }
}

class _TargetProgressBlock extends StatelessWidget {
  final String currencyLabel;
  final String collectedText;
  final String targetText;
  final double percentage;
  final Color color;

  const _TargetProgressBlock({
    required this.currencyLabel,
    required this.collectedText,
    required this.targetText,
    required this.percentage,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final clampedRatio = (percentage / 100.0).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                currencyLabel,
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${percentage.toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: clampedRatio,
              minHeight: 10,
              backgroundColor: AppColors.cardBg,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'المحصّل: $collectedText',
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                'الهدف: $targetText',
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SetMonthlyTargetDialog extends ConsumerStatefulWidget {
  final double currentSyp;
  final double currentUsd;
  final String monthKey;

  const _SetMonthlyTargetDialog({
    required this.currentSyp,
    required this.currentUsd,
    required this.monthKey,
  });

  @override
  ConsumerState<_SetMonthlyTargetDialog> createState() => _SetMonthlyTargetDialogState();
}

class _SetMonthlyTargetDialogState extends ConsumerState<_SetMonthlyTargetDialog> {
  late final TextEditingController _sypCtrl;
  late final TextEditingController _usdCtrl;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _sypCtrl = TextEditingController(
      text: widget.currentSyp > 0 ? widget.currentSyp.toInt().toString() : '',
    );
    _usdCtrl = TextEditingController(
      text: widget.currentUsd > 0 ? widget.currentUsd.toInt().toString() : '',
    );
  }

  @override
  void dispose() {
    _sypCtrl.dispose();
    _usdCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final syp = double.tryParse(_sypCtrl.text.replaceAll(',', '').trim()) ?? 0.0;
    final usd = double.tryParse(_usdCtrl.text.replaceAll(',', '').trim()) ?? 0.0;

    setState(() => _loading = true);

    try {
      await ref.read(monthlyTargetRepositoryProvider).setMonthlyTarget(
        targetSyp: syp,
        targetUsd: usd,
        monthKey: widget.monthKey,
      );

      ref.invalidate(monthlyTargetProgressProvider);

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حفظ الهدف المالي بنجاح', style: TextStyle(fontFamily: 'Cairo')),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ أثناء حفظ الهدف: $e', style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.track_changes, color: AppColors.gold, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    'تحديد الهدف المالي (${widget.monthKey})',
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppColors.textSecondary, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _sypCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(color: AppColors.textPrimary, fontFamily: 'Cairo'),
                decoration: InputDecoration(
                  labelText: 'الهدف بالليرة السورية (SYP)',
                  labelStyle: const TextStyle(color: AppColors.textSecondary, fontFamily: 'Cairo'),
                  suffixText: 'ل.س',
                  suffixStyle: const TextStyle(color: AppColors.gold, fontFamily: 'Cairo'),
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.divider),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _usdCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(color: AppColors.textPrimary, fontFamily: 'Cairo'),
                decoration: InputDecoration(
                  labelText: 'الهدف بالدولار الأمريكي (USD)',
                  labelStyle: const TextStyle(color: AppColors.textSecondary, fontFamily: 'Cairo'),
                  suffixText: r'\$',
                  suffixStyle: const TextStyle(color: AppColors.gold, fontFamily: 'Cairo'),
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.divider),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                        side: const BorderSide(color: AppColors.divider),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _loading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.gold,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: _loading
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2),
                            )
                          : const Text(
                              'حفظ الهدف',
                              style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700, color: Colors.black),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
