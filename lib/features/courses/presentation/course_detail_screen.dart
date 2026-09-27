import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/responsive.dart';
import '../data/courses_repository.dart';
import '../domain/course_model.dart';
import '../domain/cohort_model.dart';
import '../../trainees/data/trainees_repository.dart';

class CourseDetailScreen extends ConsumerWidget {
  final CourseModel course;
  const CourseDetailScreen({super.key, required this.course});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cohortsAsync = ref.watch(cohortsByCourseProvider(course.id));
    final fmt = NumberFormat('#,###');

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text(
          course.name,
          style: const TextStyle(
            color: AppColors.gold,
            fontFamily: 'Cairo',
            fontWeight: FontWeight.w700,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: AppColors.gold),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          ElevatedButton.icon(
            onPressed: () => _showAddCohortDialog(context, ref),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('إضافة مجموعة',
                style: TextStyle(fontFamily: 'Cairo', fontSize: 13)),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.all(Responsive.spacing(context, 24)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Course Info Card
            Container(
              padding: EdgeInsets.all(Responsive.spacing(context, 20)),
              decoration: BoxDecoration(
                color: AppColors.cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          course.name,
                          style: TextStyle(
                            fontSize: Responsive.fontSize(context, 20),
                            fontWeight: FontWeight.w900,
                            color: AppColors.gold,
                            fontFamily: 'Cairo',
                          ),
                        ),
                        if (course.description != null)
                          Text(
                            course.description!,
                            style: TextStyle(
                              fontSize: Responsive.fontSize(context, 13),
                              color: AppColors.textSecondary,
                              fontFamily: 'Cairo',
                            ),
                          ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${fmt.format(course.price.toInt())} ل.س',
                        style: TextStyle(
                          fontSize: Responsive.fontSize(context, 18),
                          fontWeight: FontWeight.w900,
                          color: AppColors.success,
                          fontFamily: 'Cairo',
                        ),
                      ),
                      Text(
                        '${course.totalSessions} جلسة',
                        style: TextStyle(
                          fontSize: Responsive.fontSize(context, 13),
                          color: AppColors.textSecondary,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            SizedBox(height: Responsive.spacing(context, 24)),

            Text(
              'المجموعات',
              style: TextStyle(
                fontSize: Responsive.fontSize(context, 18),
                fontWeight: FontWeight.w700,
                color: AppColors.gold,
                fontFamily: 'Cairo',
              ),
            ),

            SizedBox(height: Responsive.spacing(context, 12)),

            Expanded(
              child: cohortsAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(color: AppColors.gold),
                ),
                error: (e, _) => Center(
                  child: Text('خطأ: $e',
                      style: const TextStyle(
                          color: AppColors.error, fontFamily: 'Cairo')),
                ),
                data: (cohorts) {
                  if (cohorts.isEmpty) {
                    return Center(
                      child: Text(
                        'لا توجد مجموعات — أضف مجموعة جديدة',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontFamily: 'Cairo',
                          fontSize: Responsive.fontSize(context, 14),
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    itemCount: cohorts.length,
                    separatorBuilder: (_, __) =>
                        SizedBox(height: Responsive.spacing(context, 8)),
                    itemBuilder: (context, index) {
                      final cohort = cohorts[index];
                      return _CohortCard(
                        cohort: cohort,
                        course: course,
                        onEnroll: () => _showEnrollDialog(context, ref, cohort),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddCohortDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => _AddCohortDialog(
        course: course,
        onSaved: () => ref.invalidate(cohortsByCourseProvider(course.id)),
      ),
    );
  }

  void _showEnrollDialog(
      BuildContext context, WidgetRef ref, CohortModel cohort) {
    showDialog(
      context: context,
      builder: (_) => _EnrollTraineeDialog(
        cohort: cohort,
        course: course,
        onEnrolled: () => ref.invalidate(cohortsByCourseProvider(course.id)),
      ),
    );
  }
}

// ─── Cohort Card ───
class _CohortCard extends StatelessWidget {
  final CohortModel cohort;
  final CourseModel course;
  final VoidCallback onEnroll;

  const _CohortCard({
    required this.cohort,
    required this.course,
    required this.onEnroll,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(Responsive.spacing(context, 16)),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.darkGreen.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.group, color: AppColors.gold),
          ),
          SizedBox(width: Responsive.spacing(context, 12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cohort.name,
                  style: TextStyle(
                    fontSize: Responsive.fontSize(context, 15),
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    fontFamily: 'Cairo',
                  ),
                ),
                if (cohort.startsAt != null)
                  Text(
                    'تبدأ: ${DateFormat('yyyy/MM/dd').format(cohort.startsAt!)}',
                    style: TextStyle(
                      fontSize: Responsive.fontSize(context, 12),
                      color: AppColors.textSecondary,
                      fontFamily: 'Cairo',
                    ),
                  ),
              ],
            ),
          ),
          ElevatedButton.icon(
            onPressed: onEnroll,
            icon: const Icon(Icons.person_add, size: 16),
            label: const Text('تسجيل متدرب',
                style: TextStyle(fontFamily: 'Cairo', fontSize: 12)),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Add Cohort Dialog ───
class _AddCohortDialog extends ConsumerStatefulWidget {
  final CourseModel course;
  final VoidCallback onSaved;

  const _AddCohortDialog({required this.course, required this.onSaved});

  @override
  ConsumerState<_AddCohortDialog> createState() => _AddCohortDialogState();
}

class _AddCohortDialogState extends ConsumerState<_AddCohortDialog> {
  final _nameCtrl = TextEditingController();
  DateTime? _startsAt;
  bool _loading = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_nameCtrl.text.isEmpty) return;
    setState(() => _loading = true);
    try {
      final currentUserId = Supabase.instance.client.auth.currentUser!.id;
      await ref.read(coursesRepositoryProvider).addCohort(
            courseId: widget.course.id,
            name: _nameCtrl.text.trim(),
            trainerId: currentUserId,
            startsAt: _startsAt,
          );

      if (!mounted) return;
      Navigator.pop(context);
      widget.onSaved();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم إضافة المجموعة بنجاح ✓'),
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
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: EdgeInsets.all(Responsive.spacing(context, 24)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.group_add, color: AppColors.gold),
                  SizedBox(width: Responsive.spacing(context, 8)),
                  Text(
                    'إضافة مجموعة — ${widget.course.name}',
                    style: TextStyle(
                      fontSize: Responsive.fontSize(context, 16),
                      fontWeight: FontWeight.w700,
                      color: AppColors.gold,
                      fontFamily: 'Cairo',
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon:
                        const Icon(Icons.close, color: AppColors.textSecondary),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(color: AppColors.divider),
              SizedBox(height: Responsive.spacing(context, 16)),

              TextField(
                controller: _nameCtrl,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  labelText: 'اسم المجموعة *',
                  labelStyle: const TextStyle(
                      color: AppColors.textSecondary, fontFamily: 'Cairo'),
                  prefixIcon:
                      const Icon(Icons.group_outlined, color: AppColors.gold),
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

              // Date Picker
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime(2024),
                    lastDate: DateTime(2030),
                  );
                  if (picked != null) setState(() => _startsAt = picked);
                },
                child: Container(
                  padding: EdgeInsets.all(Responsive.spacing(context, 14)),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today,
                          color: AppColors.gold, size: 20),
                      SizedBox(width: Responsive.spacing(context, 8)),
                      Text(
                        _startsAt != null
                            ? DateFormat('yyyy/MM/dd').format(_startsAt!)
                            : 'تاريخ البدء (اختياري)',
                        style: TextStyle(
                          color: _startsAt != null
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              SizedBox(height: Responsive.spacing(context, 24)),

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
                          : const Text('إضافة',
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

// ─── Enroll Trainee Dialog ───
class _EnrollTraineeDialog extends ConsumerStatefulWidget {
  final CohortModel cohort;
  final CourseModel course;
  final VoidCallback onEnrolled;

  const _EnrollTraineeDialog({
    required this.cohort,
    required this.course,
    required this.onEnrolled,
  });

  @override
  ConsumerState<_EnrollTraineeDialog> createState() =>
      _EnrollTraineeDialogState();
}

class _EnrollTraineeDialogState extends ConsumerState<_EnrollTraineeDialog> {
  String? _selectedTraineeId;
  final _priceCtrl = TextEditingController();
  final _discountCtrl = TextEditingController(text: '0');
  String _currency = 'SYP';
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _priceCtrl.text = widget.course.price.toInt().toString();
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    _discountCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selectedTraineeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى اختيار متدرب'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      await ref.read(coursesRepositoryProvider).enrollTrainee(
            traineeId: _selectedTraineeId!,
            cohortId: widget.cohort.id,
            totalDue: double.tryParse(_priceCtrl.text) ?? widget.course.price,
            discountAmount: double.tryParse(_discountCtrl.text) ?? 0,
            currency: _currency,
          );

      if (!mounted) return;
      Navigator.pop(context);
      widget.onEnrolled();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تسجيل المتدرب بنجاح ✓'),
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
    final traineesAsync = ref.watch(traineesProvider(null));
    return Dialog(
      backgroundColor: AppColors.cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: EdgeInsets.all(Responsive.spacing(context, 24)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.person_add, color: AppColors.gold),
                  SizedBox(width: Responsive.spacing(context, 8)),
                  Expanded(
                    child: Text(
                      'تسجيل متدرب — ${widget.cohort.name}',
                      style: TextStyle(
                        fontSize: Responsive.fontSize(context, 16),
                        fontWeight: FontWeight.w700,
                        color: AppColors.gold,
                        fontFamily: 'Cairo',
                      ),
                    ),
                  ),
                  IconButton(
                    icon:
                        const Icon(Icons.close, color: AppColors.textSecondary),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(color: AppColors.divider),
              SizedBox(height: Responsive.spacing(context, 16)),

              // Trainee Dropdown
              traineesAsync.when(
                loading: () =>
                    const CircularProgressIndicator(color: AppColors.gold),
                error: (e, _) => Text('خطأ: $e',
                    style: const TextStyle(color: AppColors.error)),
                data: (trainees) => DropdownButtonFormField<String>(
                  value: _selectedTraineeId,
                  dropdownColor: AppColors.cardBg,
                  decoration: InputDecoration(
                    labelText: 'اختر المتدرب *',
                    labelStyle: const TextStyle(
                        color: AppColors.textSecondary, fontFamily: 'Cairo'),
                    prefixIcon:
                        const Icon(Icons.person_outline, color: AppColors.gold),
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
                  items: trainees.map((t) {
                    return DropdownMenuItem(
                      value: t.id,
                      child: Text(
                        t.fullName,
                        style: const TextStyle(
                            color: AppColors.textPrimary, fontFamily: 'Cairo'),
                      ),
                    );
                  }).toList(),
                  onChanged: (v) => setState(() => _selectedTraineeId = v),
                ),
              ),

              SizedBox(height: Responsive.spacing(context, 12)),

              // Price + Currency
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _priceCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        labelText: 'السعر *',
                        labelStyle: const TextStyle(
                            color: AppColors.textSecondary,
                            fontFamily: 'Cairo'),
                        prefixIcon: const Icon(Icons.attach_money,
                            color: AppColors.gold),
                        filled: true,
                        fillColor: AppColors.surface,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: AppColors.divider)),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: AppColors.divider)),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                                color: AppColors.gold, width: 2)),
                      ),
                    ),
                  ),
                  SizedBox(width: Responsive.spacing(context, 12)),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _currency,
                      dropdownColor: AppColors.cardBg,
                      decoration: InputDecoration(
                        labelText: 'العملة',
                        labelStyle: const TextStyle(
                            color: AppColors.textSecondary,
                            fontFamily: 'Cairo'),
                        filled: true,
                        fillColor: AppColors.surface,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: AppColors.divider)),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: AppColors.divider)),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                                color: AppColors.gold, width: 2)),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'SYP',
                          child: Text('ل.س',
                              style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontFamily: 'Cairo')),
                        ),
                        DropdownMenuItem(
                          value: 'USD',
                          child: Text('\$',
                              style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontFamily: 'Cairo')),
                        ),
                      ],
                      onChanged: (v) => setState(() => _currency = v ?? 'SYP'),
                    ),
                  ),
                ],
              ),

              SizedBox(height: Responsive.spacing(context, 12)),

              // Discount
              TextField(
                controller: _discountCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  labelText: 'الخصم (اختياري)',
                  labelStyle: const TextStyle(
                      color: AppColors.textSecondary, fontFamily: 'Cairo'),
                  prefixIcon: const Icon(Icons.discount_outlined,
                      color: AppColors.gold),
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

              SizedBox(height: Responsive.spacing(context, 24)),

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
                          : const Text('تسجيل',
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
