import 'widgets/course_materials_dialog.dart';
import '../../sessions/data/admin_sessions_repository.dart';
import '../../../core/utils/app_error_handler.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/app_formatters.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/responsive.dart';
import '../data/courses_repository.dart';
import '../domain/course_model.dart';
import '../domain/cohort_model.dart';
import '../../trainees/data/trainees_repository.dart';

class CourseDetailScreen extends ConsumerWidget {
  final String courseId;
  final CourseModel? course;

  const CourseDetailScreen({
    super.key,
    required this.courseId,
    this.course,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (course != null) {
      return _buildContent(context, ref, course!);
    }

    final courseAsync = ref.watch(courseByIdProvider(courseId));

    return courseAsync.when(
      loading: () => const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.gold),
        ),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios, color: AppColors.gold),
            onPressed: () => context.canPop() ? context.pop() : context.go(AppRouter.courses),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: AppColors.error, size: 48),
              const SizedBox(height: 16),
              Text(AppErrorHandler.friendlyMessage(e),
                  style: const TextStyle(color: AppColors.error, fontFamily: 'Cairo')),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => ref.invalidate(courseByIdProvider(courseId)),
                child: const Text('إعادة المحاولة',
                    style: TextStyle(fontFamily: 'Cairo')),
              ),
            ],
          ),
        ),
      ),
      data: (loadedCourse) {
        if (loadedCourse == null) {
          return Scaffold(
            backgroundColor: AppColors.background,
            appBar: AppBar(
              backgroundColor: AppColors.background,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios, color: AppColors.gold),
                onPressed: () => context.canPop() ? context.pop() : context.go(AppRouter.courses),
              ),
            ),
            body: const Center(
              child: Text(
                'الكورس غير موجود أو تم حذفه',
                style: TextStyle(color: AppColors.textSecondary, fontFamily: 'Cairo'),
              ),
            ),
          );
        }
        return _buildContent(context, ref, loadedCourse);
      },
    );
  }

  Widget _buildContent(BuildContext context, WidgetRef ref, CourseModel course) {
    final cohortsAsync = ref.watch(cohortsByCourseProvider(course.id));
    final fmt = AppFormatters.amount;

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
          onPressed: () => context.canPop() ? context.pop() : context.go(AppRouter.courses),
        ),
        actions: [
          OutlinedButton.icon(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => CourseMaterialsDialog(course: course),
            ),
            icon: const Icon(Icons.folder_open_outlined, size: 18, color: AppColors.gold),
            label: const Text(
              'مواد ومرفقات الكورس',
              style: TextStyle(fontFamily: 'Cairo', fontSize: 13, color: AppColors.gold),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.gold),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () => _showAddCohortDialog(context, ref, course),
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
                  child: Text(AppErrorHandler.friendlyMessage(e),
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
                        onEnroll: () => _showEnrollDialog(context, ref, cohort, course),
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

  void _showAddCohortDialog(BuildContext context, WidgetRef ref, CourseModel course) {
    showDialog(
      context: context,
      builder: (_) => _AddCohortDialog(
        course: course,
        onSaved: () => ref.invalidate(cohortsByCourseProvider(course.id)),
      ),
    );
  }

  void _showEnrollDialog(
      BuildContext context, WidgetRef ref, CohortModel cohort, CourseModel course) {
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
                    'تبدأ: ${AppFormatters.dateOnly.format(cohort.startsAt!)}',
                    style: TextStyle(
                      fontSize: Responsive.fontSize(context, 12),
                      color: AppColors.textSecondary,
                      fontFamily: 'Cairo',
                    ),
                  ),
              ],
            ),
          ),
          // زر جدولة الجلسات بالجملة (المرحلة 8)
          IconButton(
            icon: const Icon(Icons.playlist_add, color: AppColors.gold, size: 22),
            tooltip: 'جدولة جلسات الدفعة بالجملة',
            onPressed: () {
              showDialog(
                context: context,
                builder: (_) => _BulkScheduleSessionsDialog(
                  cohort: cohort,
                  course: course,
                ),
              );
            },
          ),
          // زر ترحيل المواعيد (المرحلة 7)
          IconButton(
            icon: const Icon(Icons.edit_calendar, color: AppColors.textSecondary, size: 20),
            tooltip: 'ترحيل مواعيد الجلسات',
            onPressed: () {
              showDialog(
                context: context,
                builder: (_) => _ShiftCohortSessionsDialog(
                  cohort: cohort,
                  onShifted: () {},
                ),
              );
            },
          ),
          SizedBox(width: Responsive.spacing(context, 8)),
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
        SnackBar(content: Text(AppErrorHandler.friendlyMessage(e)), backgroundColor: AppColors.error),
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
                            ? AppFormatters.dateOnly.format(_startsAt!)
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
        SnackBar(content: Text(AppErrorHandler.friendlyMessage(e)), backgroundColor: AppColors.error),
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
                error: (e, _) => Text(AppErrorHandler.friendlyMessage(e),
                    style: const TextStyle(color: AppColors.error)),
                data: (trainees) => DropdownButtonFormField<String>(
                  initialValue: _selectedTraineeId,
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
                      initialValue: _currency,
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


// ─── Shift Cohort Sessions Dialog (Phase 7) ──────────────────────────────────
class _ShiftCohortSessionsDialog extends ConsumerStatefulWidget {
  final CohortModel cohort;
  final VoidCallback onShifted;

  const _ShiftCohortSessionsDialog({
    required this.cohort,
    required this.onShifted,
  });

  @override
  ConsumerState<_ShiftCohortSessionsDialog> createState() =>
      _ShiftCohortSessionsDialogState();
}

class _ShiftCohortSessionsDialogState
    extends ConsumerState<_ShiftCohortSessionsDialog> {
  DateTime _newDate = DateTime.now().add(const Duration(days: 7));
  TimeOfDay _newTime = const TimeOfDay(hour: 16, minute: 0);
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.cohort.startsAt != null) {
      _newDate = widget.cohort.startsAt!;
      _newTime = TimeOfDay.fromDateTime(widget.cohort.startsAt!);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _newDate,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.gold,
              onPrimary: Colors.black,
              surface: AppColors.cardBg,
              onSurface: AppColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _newDate = picked);
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _newTime,
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.gold,
              onPrimary: Colors.black,
              surface: AppColors.cardBg,
              onSurface: AppColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _newTime = picked);
    }
  }

  Future<void> _submit() async {
    final combinedDateTime = DateTime(
      _newDate.year,
      _newDate.month,
      _newDate.day,
      _newTime.hour,
      _newTime.minute,
    );

    setState(() => _loading = true);
    try {
      final res = await ref.read(coursesRepositoryProvider).shiftCohortSessions(
            cohortId: widget.cohort.id,
            newStartDate: combinedDateTime,
          );

      if (!mounted) return;

      if (res['success'] == true) {
        Navigator.pop(context);
        widget.onShifted();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['message']?.toString() ?? 'تمت إزاحة الجلسات بنجاح ✓',
                style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: AppColors.success,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['message']?.toString() ?? 'تعذر إزاحة الجلسات',
                style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppErrorHandler.friendlyMessage(e),
              style: const TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final timeStr = '${_newTime.hour.toString().padLeft(2, '0')}:${_newTime.minute.toString().padLeft(2, '0')}';
    final dateStr = AppFormatters.dateOnly.format(_newDate);

    return Dialog(
      backgroundColor: AppColors.cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                  const Icon(Icons.edit_calendar, color: AppColors.gold),
                  SizedBox(width: Responsive.spacing(context, 8)),
                  Expanded(
                    child: Text(
                      'إزاحة مواعيد الجلسات — ${widget.cohort.name}',
                      style: TextStyle(
                        fontSize: Responsive.fontSize(context, 16),
                        fontWeight: FontWeight.w700,
                        color: AppColors.gold,
                        fontFamily: 'Cairo',
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppColors.textSecondary),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(color: AppColors.divider),
              SizedBox(height: Responsive.spacing(context, 12)),

              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, color: AppColors.warning, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'سيتم حساب الفارق الزمني وإزاحة جميع الجلسات المجدولة تلقائياً مع الحفاظ على الفواصل الأصلية. الجلسات المنفذة أو المفتوحة لن تتأثر.',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 12,
                          fontFamily: 'Cairo',
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: Responsive.spacing(context, 16)),

              Text(
                'تاريخ ووقت البداية الجديد للجلسات المجدولة:',
                style: TextStyle(
                  fontSize: Responsive.fontSize(context, 13),
                  color: AppColors.textSecondary,
                  fontFamily: 'Cairo',
                ),
              ),
              SizedBox(height: Responsive.spacing(context, 8)),

              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: _pickDate,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.divider),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today, size: 16, color: AppColors.gold),
                            const SizedBox(width: 8),
                            Text(dateStr, style: const TextStyle(color: AppColors.textPrimary, fontFamily: 'Cairo')),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: Responsive.spacing(context, 8)),
                  Expanded(
                    child: InkWell(
                      onTap: _pickTime,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.divider),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.access_time, size: 16, color: AppColors.gold),
                            const SizedBox(width: 8),
                            Text(timeStr, style: const TextStyle(color: AppColors.textPrimary, fontFamily: 'Cairo')),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
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
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
                    ),
                  ),
                  SizedBox(width: Responsive.spacing(context, 12)),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _loading ? null : _submit,
                      icon: _loading ? const SizedBox.shrink() : const Icon(Icons.check, size: 18),
                      label: _loading
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                          : const Text('تطبيق الإزاحة', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
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


// ─── Phase 8: Bulk Schedule Sessions Dialog ───
class _BulkScheduleSessionsDialog extends ConsumerStatefulWidget {
  final CohortModel cohort;
  final CourseModel course;

  const _BulkScheduleSessionsDialog({
    required this.cohort,
    required this.course,
  });

  @override
  ConsumerState<_BulkScheduleSessionsDialog> createState() =>
      _BulkScheduleSessionsDialogState();
}

class _BulkScheduleSessionsDialogState
    extends ConsumerState<_BulkScheduleSessionsDialog> {
  late DateTime _startDate;
  TimeOfDay _startTime = const TimeOfDay(hour: 15, minute: 0);
  late final TextEditingController _sessionCountCtrl;
  late final TextEditingController _durationCtrl;
  final Set<int> _selectedDays = {6, 1, 3}; // السبت، الإثنين، الأربعاء كافتراضي
  bool _loading = false;

  final Map<int, String> _weekdaysMap = {
    6: 'السبت',
    0: 'الأحد',
    1: 'الإثنين',
    2: 'الثلاثاء',
    3: 'الأربعاء',
    4: 'الخميس',
    5: 'الجمعة',
  };

  @override
  void initState() {
    super.initState();
    _startDate = widget.cohort.startsAt ?? DateTime.now();
    _sessionCountCtrl = TextEditingController(
      text: widget.course.totalSessions.toString(),
    );
    _durationCtrl = TextEditingController(text: '120');
  }

  @override
  void dispose() {
    _sessionCountCtrl.dispose();
    _durationCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selectedDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى اختيار يوم واحد على الأقل من أيام الأسبوع'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final count = int.tryParse(_sessionCountCtrl.text.trim()) ?? 0;
    if (count <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى تحديد عدد جلسات صحيح أكبر من الصفر'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final duration = int.tryParse(_durationCtrl.text.trim()) ?? 120;
    final timeStr = '${_startTime.hour.toString().padLeft(2, '0')}:${_startTime.minute.toString().padLeft(2, '0')}:00';

    setState(() => _loading = true);
    try {
      final res = await ref
          .read(adminSessionsRepositoryProvider)
          .bulkScheduleSessions(
            cohortId: widget.cohort.id,
            startDate: _startDate,
            startTime: timeStr,
            daysOfWeek: _selectedDays.toList(),
            sessionCount: count,
            durationMinutes: duration,
          );

      if (!mounted) return;
      Navigator.pop(context);
      ref.invalidate(cohortsByCourseProvider(widget.course.id));
      ref.invalidate(adminSessionsProvider);

      final msg = res['message'] ?? 'تمت جدولة الجلسات بنجاح';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg.toString()),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppErrorHandler.friendlyMessage(e)),
          backgroundColor: AppColors.error,
        ),
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
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: EdgeInsets.all(Responsive.spacing(context, 24)),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.playlist_add, color: AppColors.gold, size: 26),
                    SizedBox(width: Responsive.spacing(context, 8)),
                    Expanded(
                      child: Text(
                        'جدولة جلسات الدفعة بالجملة',
                        style: TextStyle(
                          fontSize: Responsive.fontSize(context, 18),
                          fontWeight: FontWeight.w700,
                          color: AppColors.gold,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: AppColors.textSecondary),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                Text(
                  'الدفعة: ${widget.cohort.name} — ${widget.course.name}',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: Responsive.fontSize(context, 13),
                    fontFamily: 'Cairo',
                  ),
                ),
                const Divider(color: AppColors.divider, height: 24),

                // Start Date
                Text('تاريخ أول جلسة:',
                    style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                SizedBox(height: Responsive.spacing(context, 6)),
                InkWell(
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _startDate,
                      firstDate: DateTime(2024),
                      lastDate: DateTime(2030),
                    );
                    if (d != null && mounted) setState(() => _startDate = d);
                  },
                  child: Container(
                    padding: EdgeInsets.all(Responsive.spacing(context, 12)),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today, color: AppColors.gold, size: 18),
                        SizedBox(width: Responsive.spacing(context, 8)),
                        Text(AppFormatters.dateOnly.format(_startDate),
                            style: const TextStyle(
                                color: AppColors.textPrimary, fontFamily: 'Cairo')),
                      ],
                    ),
                  ),
                ),

                SizedBox(height: Responsive.spacing(context, 14)),

                // Start Time
                Text('وقت بدء الجلسة:',
                    style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                SizedBox(height: Responsive.spacing(context, 6)),
                InkWell(
                  onTap: () async {
                    final t = await showTimePicker(
                      context: context,
                      initialTime: _startTime,
                    );
                    if (t != null && mounted) setState(() => _startTime = t);
                  },
                  child: Container(
                    padding: EdgeInsets.all(Responsive.spacing(context, 12)),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.access_time, color: AppColors.gold, size: 18),
                        SizedBox(width: Responsive.spacing(context, 8)),
                        Text(_startTime.format(context),
                            style: const TextStyle(
                                color: AppColors.textPrimary, fontFamily: 'Cairo')),
                      ],
                    ),
                  ),
                ),

                SizedBox(height: Responsive.spacing(context, 14)),

                // Days of week
                Text('أيام انعقاد الجلسات بالأسبوع:',
                    style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                SizedBox(height: Responsive.spacing(context, 8)),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: _weekdaysMap.entries.map((entry) {
                    final isSelected = _selectedDays.contains(entry.key);
                    return FilterChip(
                      label: Text(entry.value,
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? Colors.black : AppColors.textPrimary,
                          )),
                      selected: isSelected,
                      selectedColor: AppColors.gold,
                      checkmarkColor: Colors.black,
                      backgroundColor: AppColors.surface,
                      onSelected: (val) {
                        setState(() {
                          if (val) {
                            _selectedDays.add(entry.key);
                          } else {
                            _selectedDays.remove(entry.key);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),

                SizedBox(height: Responsive.spacing(context, 14)),

                // Session Count & Duration
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('عدد الجلسات:',
                              style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary)),
                          SizedBox(height: Responsive.spacing(context, 6)),
                          TextField(
                            controller: _sessionCountCtrl,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: AppColors.textPrimary),
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: AppColors.surface,
                              prefixIcon: const Icon(Icons.numbers, color: AppColors.gold, size: 18),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: AppColors.divider),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: Responsive.spacing(context, 12)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('المدة (بالدقائق):',
                              style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary)),
                          SizedBox(height: Responsive.spacing(context, 6)),
                          TextField(
                            controller: _durationCtrl,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: AppColors.textPrimary),
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: AppColors.surface,
                              prefixIcon: const Icon(Icons.timer_outlined, color: AppColors.gold, size: 18),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: AppColors.divider),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                SizedBox(height: Responsive.spacing(context, 24)),

                // Actions
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textSecondary,
                          side: const BorderSide(color: AppColors.divider),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('إلغاء',
                            style: TextStyle(fontFamily: 'Cairo')),
                      ),
                    ),
                    SizedBox(width: Responsive.spacing(context, 12)),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _loading ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.gold,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: _loading
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.black),
                              )
                            : const Text('جدولة بالجملة',
                                style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
