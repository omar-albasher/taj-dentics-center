import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/responsive.dart';
import '../data/surveys_repository.dart';
import '../domain/survey_model.dart';

class SurveysScreen extends ConsumerStatefulWidget {
  const SurveysScreen({super.key});

  @override
  ConsumerState<SurveysScreen> createState() => _SurveysScreenState();
}

class _SurveysScreenState extends ConsumerState<SurveysScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Padding(
        padding: EdgeInsets.all(Responsive.spacing(context, 24)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'الاستبيانات',
                  style: TextStyle(
                    fontSize: Responsive.fontSize(context, 28),
                    fontWeight: FontWeight.w900,
                    color: AppColors.gold,
                    fontFamily: 'Cairo',
                  ),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: () => _showAddTemplateDialog(context),
                  icon: const Icon(Icons.add),
                  label: const Text('استبيان جديد',
                      style: TextStyle(fontFamily: 'Cairo')),
                ),
              ],
            ),
            SizedBox(height: Responsive.spacing(context, 16)),
            TabBar(
              controller: _tabController,
              labelColor: AppColors.gold,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.gold,
              labelStyle: const TextStyle(
                  fontFamily: 'Cairo', fontWeight: FontWeight.w700),
              tabs: const [
                Tab(text: 'القوالب'),
                Tab(text: 'الردود'),
                Tab(text: 'الإحصائيات'),
              ],
            ),
            SizedBox(height: Responsive.spacing(context, 16)),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _TemplatesTab(),
                  _ResponsesTab(),
                  _StatsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddTemplateDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => _AddTemplateDialog(
        onAdded: () => ref.invalidate(surveyTemplatesProvider),
      ),
    );
  }
}

// ─── Templates Tab ───
class _TemplatesTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templatesAsync = ref.watch(surveyTemplatesProvider);

    return templatesAsync.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(color: AppColors.gold)),
      error: (e, _) => Center(
          child: Text('خطأ: $e',
              style: const TextStyle(
                  color: AppColors.error, fontFamily: 'Cairo'))),
      data: (templates) {
        if (templates.isEmpty) {
          return Center(
            child: Text('لا توجد استبيانات — أنشئ استبياناً جديداً',
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontFamily: 'Cairo',
                    fontSize: Responsive.fontSize(context, 16))),
          );
        }

        return ListView.separated(
          itemCount: templates.length,
          separatorBuilder: (_, __) =>
              SizedBox(height: Responsive.spacing(context, 8)),
          itemBuilder: (context, index) {
            final t = templates[index];
            return Container(
              padding: EdgeInsets.all(Responsive.spacing(context, 16)),
              decoration: BoxDecoration(
                color: AppColors.cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: t.isActive
                      ? AppColors.gold.withValues(alpha: 0.3)
                      : AppColors.divider,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.gold.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.assignment_outlined,
                        color: AppColors.gold),
                  ),
                  SizedBox(width: Responsive.spacing(context, 12)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.title,
                            style: TextStyle(
                                fontSize: Responsive.fontSize(context, 15),
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                                fontFamily: 'Cairo')),
                        Text(
                          '${t.questions.length} سؤال • يُرسل كل ${t.triggerAfterSessions} جلسات',
                          style: TextStyle(
                              fontSize: Responsive.fontSize(context, 12),
                              color: AppColors.textSecondary,
                              fontFamily: 'Cairo'),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    children: [
                      Switch(
                        value: t.isActive,
                        onChanged: (v) async {
                          await ref
                              .read(surveysRepositoryProvider)
                              .toggleTemplate(t.id, v);
                          ref.invalidate(surveyTemplatesProvider);
                        },
                        activeColor: AppColors.gold,
                      ),
                      ElevatedButton(
                        onPressed: () => _sendToAll(context, ref, t),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          textStyle: const TextStyle(fontSize: 11),
                        ),
                        child: const Text('إرسال للكل',
                            style: TextStyle(fontFamily: 'Cairo')),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _sendToAll(
      BuildContext context, WidgetRef ref, SurveyTemplate template) async {
    try {
      final count = await ref
          .read(surveysRepositoryProvider)
          .sendSurveyToAll(template.id);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم إرسال الاستبيان إلى $count متدرب ✓'),
            backgroundColor: AppColors.success,
          ),
        );
        ref.invalidate(surveyDispatchesProvider);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }
}

// ─── Responses Tab ───
class _ResponsesTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dispatchesAsync = ref.watch(surveyDispatchesProvider);

    return dispatchesAsync.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(color: AppColors.gold)),
      error: (e, _) => Center(
          child: Text('خطأ: $e',
              style: const TextStyle(
                  color: AppColors.error, fontFamily: 'Cairo'))),
      data: (dispatches) {
        if (dispatches.isEmpty) {
          return Center(
            child: Text('لا توجد ردود بعد',
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontFamily: 'Cairo',
                    fontSize: Responsive.fontSize(context, 16))),
          );
        }

        return ListView.separated(
          itemCount: dispatches.length,
          separatorBuilder: (_, __) =>
              SizedBox(height: Responsive.spacing(context, 8)),
          itemBuilder: (context, index) {
            final d = dispatches[index];
            final hasAnswer = d.answers != null;

            return Container(
              padding: EdgeInsets.all(Responsive.spacing(context, 16)),
              decoration: BoxDecoration(
                color: AppColors.cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: hasAnswer
                      ? AppColors.success.withValues(alpha: 0.3)
                      : AppColors.divider,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(d.traineeName,
                                style: TextStyle(
                                    fontSize: Responsive.fontSize(context, 15),
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary,
                                    fontFamily: 'Cairo')),
                            Text(d.courseName,
                                style: TextStyle(
                                    fontSize: Responsive.fontSize(context, 12),
                                    color: AppColors.textSecondary,
                                    fontFamily: 'Cairo')),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: hasAnswer
                              ? AppColors.success.withValues(alpha: 0.15)
                              : AppColors.warning.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          hasAnswer ? 'تمت الإجابة' : 'بانتظار الرد',
                          style: TextStyle(
                              color: hasAnswer
                                  ? AppColors.success
                                  : AppColors.warning,
                              fontFamily: 'Cairo',
                              fontSize: 12,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  if (hasAnswer) ...[
                    SizedBox(height: Responsive.spacing(context, 12)),
                    const Divider(color: AppColors.divider),
                    SizedBox(height: Responsive.spacing(context, 8)),
                    ...d.answers!.entries.map((entry) {
                      return Padding(
                        padding: EdgeInsets.only(
                            bottom: Responsive.spacing(context, 4)),
                        child: Row(
                          children: [
                            Text('${entry.key}: ',
                                style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontFamily: 'Cairo',
                                    fontSize: 13)),
                            Text('${entry.value}',
                                style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontFamily: 'Cairo',
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13)),
                          ],
                        ),
                      );
                    }),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ─── Stats Tab ───
class _StatsTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dispatchesAsync = ref.watch(surveyDispatchesProvider);

    return dispatchesAsync.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(color: AppColors.gold)),
      error: (e, _) => Center(
          child: Text('خطأ: $e',
              style: const TextStyle(
                  color: AppColors.error, fontFamily: 'Cairo'))),
      data: (dispatches) {
        final total = dispatches.length;
        final answered = dispatches.where((d) => d.answers != null).length;
        final pending = total - answered;
        final rate = total > 0 ? (answered / total * 100) : 0.0;

        final ratings = dispatches
            .where((d) => d.answers != null && d.answers!['q1'] != null)
            .map((d) {
              final val = d.answers!['q1'];
              if (val is num) return val.toDouble();
              if (val is String) return double.tryParse(val) ?? 0.0;
              return 0.0;
            })
            .where((r) => r > 0)
            .toList();
        final avgRating = ratings.isNotEmpty
            ? ratings.reduce((a, b) => a + b) / ratings.length
            : 0.0;

        return SingleChildScrollView(
          child: Column(
            children: [
              Row(
                children: [
                  _StatCard(
                    label: 'إجمالي الاستبيانات',
                    value: '$total',
                    icon: Icons.assignment,
                    color: AppColors.gold,
                  ),
                  SizedBox(width: Responsive.spacing(context, 12)),
                  _StatCard(
                    label: 'تمت الإجابة',
                    value: '$answered',
                    icon: Icons.check_circle,
                    color: AppColors.success,
                  ),
                  SizedBox(width: Responsive.spacing(context, 12)),
                  _StatCard(
                    label: 'بانتظار الرد',
                    value: '$pending',
                    icon: Icons.hourglass_empty,
                    color: AppColors.warning,
                  ),
                ],
              ),

              SizedBox(height: Responsive.spacing(context, 16)),

              Row(
                children: [
                  _StatCard(
                    label: 'نسبة الاستجابة',
                    value: '${rate.toStringAsFixed(0)}%',
                    icon: Icons.percent,
                    color: AppColors.gold,
                  ),
                  SizedBox(width: Responsive.spacing(context, 12)),
                  _StatCard(
                    label: 'متوسط التقييم',
                    value: avgRating > 0
                        ? '${avgRating.toStringAsFixed(1)} / 5'
                        : 'لا يوجد',
                    icon: Icons.star,
                    color: AppColors.warning,
                  ),
                ],
              ),

              SizedBox(height: Responsive.spacing(context, 16)),

              // Response Rate Bar
              Container(
                padding: EdgeInsets.all(Responsive.spacing(context, 20)),
                decoration: BoxDecoration(
                  color: AppColors.cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('نسبة الاستجابة',
                        style: TextStyle(
                            fontSize: Responsive.fontSize(context, 16),
                            fontWeight: FontWeight.w700,
                            color: AppColors.gold,
                            fontFamily: 'Cairo')),
                    SizedBox(height: Responsive.spacing(context, 12)),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: rate / 100,
                        backgroundColor: AppColors.divider,
                        valueColor: AlwaysStoppedAnimation(
                          rate >= 75
                              ? AppColors.success
                              : rate >= 50
                                  ? AppColors.warning
                                  : AppColors.error,
                        ),
                        minHeight: 12,
                      ),
                    ),
                    SizedBox(height: Responsive.spacing(context, 8)),
                    Text('$answered من $total متدرب أجابوا',
                        style: TextStyle(
                            fontSize: Responsive.fontSize(context, 13),
                            color: AppColors.textSecondary,
                            fontFamily: 'Cairo')),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.all(Responsive.spacing(context, 16)),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            SizedBox(height: Responsive.spacing(context, 8)),
            Text(value,
                style: TextStyle(
                    fontSize: Responsive.fontSize(context, 22),
                    fontWeight: FontWeight.w900,
                    color: color,
                    fontFamily: 'Cairo')),
            Text(label,
                style: TextStyle(
                    fontSize: Responsive.fontSize(context, 12),
                    color: AppColors.textSecondary,
                    fontFamily: 'Cairo'),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

// ─── Add Template Dialog ───
class _AddTemplateDialog extends ConsumerStatefulWidget {
  final VoidCallback onAdded;
  const _AddTemplateDialog({required this.onAdded});

  @override
  ConsumerState<_AddTemplateDialog> createState() => _AddTemplateDialogState();
}

class _AddTemplateDialogState extends ConsumerState<_AddTemplateDialog> {
  final _titleCtrl = TextEditingController();
  final _triggerCtrl = TextEditingController(text: '3');
  final List<Map<String, dynamic>> _questions = [];
  bool _loading = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _triggerCtrl.dispose();
    super.dispose();
  }

  void _addQuestion() {
    setState(() {
      _questions.add({
        'id': 'q${_questions.length + 1}',
        'text': '',
        'type': 'rating',
        'required': true,
      });
    });
  }

  Future<void> _submit() async {
    if (_titleCtrl.text.isEmpty || _questions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى إدخال العنوان وسؤال واحد على الأقل'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      await ref.read(surveysRepositoryProvider).addTemplate(
            title: _titleCtrl.text.trim(),
            questions: _questions,
            triggerAfterSessions: int.tryParse(_triggerCtrl.text) ?? 3,
          );

      if (!mounted) return;
      Navigator.pop(context);
      widget.onAdded();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم إنشاء الاستبيان بنجاح ✓'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ: $e'), backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 600),
        child: Padding(
          padding: EdgeInsets.all(Responsive.spacing(context, 24)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.assignment_add, color: AppColors.gold),
                  SizedBox(width: Responsive.spacing(context, 8)),
                  Text('استبيان جديد',
                      style: TextStyle(
                          fontSize: Responsive.fontSize(context, 18),
                          fontWeight: FontWeight.w700,
                          color: AppColors.gold,
                          fontFamily: 'Cairo')),
                  const Spacer(),
                  IconButton(
                    icon:
                        const Icon(Icons.close, color: AppColors.textSecondary),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(color: AppColors.divider),
              SizedBox(height: Responsive.spacing(context, 12)),

              // Title
              TextField(
                controller: _titleCtrl,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  labelText: 'عنوان الاستبيان *',
                  labelStyle: const TextStyle(
                      color: AppColors.textSecondary, fontFamily: 'Cairo'),
                  prefixIcon: const Icon(Icons.title, color: AppColors.gold),
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.divider)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.divider)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: AppColors.gold, width: 2)),
                ),
              ),

              SizedBox(height: Responsive.spacing(context, 12)),

              // Trigger
              TextField(
                controller: _triggerCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  labelText: 'يُرسل كل كم جلسة؟',
                  labelStyle: const TextStyle(
                      color: AppColors.textSecondary, fontFamily: 'Cairo'),
                  prefixIcon: const Icon(Icons.repeat, color: AppColors.gold),
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.divider)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.divider)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: AppColors.gold, width: 2)),
                ),
              ),

              SizedBox(height: Responsive.spacing(context, 12)),

              // Questions
              Row(
                children: [
                  Text('الأسئلة',
                      style: TextStyle(
                          fontSize: Responsive.fontSize(context, 14),
                          fontWeight: FontWeight.w700,
                          color: AppColors.gold,
                          fontFamily: 'Cairo')),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _addQuestion,
                    icon:
                        const Icon(Icons.add, color: AppColors.gold, size: 18),
                    label: const Text('إضافة سؤال',
                        style: TextStyle(
                            color: AppColors.gold, fontFamily: 'Cairo')),
                  ),
                ],
              ),

              Expanded(
                child: _questions.isEmpty
                    ? Center(
                        child: Text('أضف سؤالاً واحداً على الأقل',
                            style: TextStyle(
                                color: AppColors.textSecondary,
                                fontFamily: 'Cairo',
                                fontSize: Responsive.fontSize(context, 13))),
                      )
                    : ListView.separated(
                        itemCount: _questions.length,
                        separatorBuilder: (_, __) =>
                            SizedBox(height: Responsive.spacing(context, 8)),
                        itemBuilder: (context, index) {
                          return Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  onChanged: (v) =>
                                      _questions[index]['text'] = v,
                                  style: const TextStyle(
                                      color: AppColors.textPrimary),
                                  decoration: InputDecoration(
                                    hintText: 'نص السؤال ${index + 1}',
                                    hintStyle: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontFamily: 'Cairo'),
                                    filled: true,
                                    fillColor: AppColors.surface,
                                    border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                            color: AppColors.divider)),
                                    enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                            color: AppColors.divider)),
                                    focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                            color: AppColors.gold, width: 2)),
                                  ),
                                ),
                              ),
                              SizedBox(width: Responsive.spacing(context, 8)),
                              DropdownButton<String>(
                                value: _questions[index]['type'],
                                dropdownColor: AppColors.cardBg,
                                style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontFamily: 'Cairo'),
                                items: const [
                                  DropdownMenuItem(
                                      value: 'rating', child: Text('تقييم')),
                                  DropdownMenuItem(
                                      value: 'text', child: Text('نص')),
                                ],
                                onChanged: (v) => setState(
                                    () => _questions[index]['type'] = v),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    color: AppColors.error),
                                onPressed: () =>
                                    setState(() => _questions.removeAt(index)),
                              ),
                            ],
                          );
                        },
                      ),
              ),

              SizedBox(height: Responsive.spacing(context, 16)),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                        side: const BorderSide(color: AppColors.divider),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('إلغاء',
                          style: TextStyle(fontFamily: 'Cairo')),
                    ),
                  ),
                  SizedBox(width: Responsive.spacing(context, 12)),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _loading ? null : _submit,
                      child: _loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.black, strokeWidth: 2))
                          : const Text('إنشاء',
                              style: TextStyle(fontFamily: 'Cairo')),
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
