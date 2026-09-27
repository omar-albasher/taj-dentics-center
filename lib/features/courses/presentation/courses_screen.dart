import 'package:admin_dashboard/features/courses/presentation/course_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/responsive.dart';
import '../data/courses_repository.dart';
import '../domain/course_model.dart';

class CoursesScreen extends ConsumerWidget {
  const CoursesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coursesAsync = ref.watch(coursesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Padding(
        padding: EdgeInsets.all(Responsive.spacing(context, 24)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Text(
                  'الكورسات',
                  style: TextStyle(
                    fontSize: Responsive.fontSize(context, 28),
                    fontWeight: FontWeight.w900,
                    color: AppColors.gold,
                    fontFamily: 'Cairo',
                  ),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: () => _showCourseDialog(context, ref),
                  icon: const Icon(Icons.add),
                  label: const Text(
                    'إضافة كورس',
                    style: TextStyle(fontFamily: 'Cairo'),
                  ),
                ),
              ],
            ),

            SizedBox(height: Responsive.spacing(context, 24)),

            // List
            Expanded(
              child: coursesAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(color: AppColors.gold),
                ),
                error: (e, _) => Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline,
                          color: AppColors.error, size: 48),
                      const SizedBox(height: 16),
                      Text('خطأ: $e',
                          style: const TextStyle(
                              color: AppColors.error, fontFamily: 'Cairo')),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: () => ref.invalidate(coursesProvider),
                        child: const Text('إعادة المحاولة',
                            style: TextStyle(fontFamily: 'Cairo')),
                      ),
                    ],
                  ),
                ),
                data: (courses) {
                  if (courses.isEmpty) {
                    return Center(
                      child: Text(
                        'لا توجد كورسات — أضف كورساً جديداً',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontFamily: 'Cairo',
                          fontSize: Responsive.fontSize(context, 16),
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    itemCount: courses.length,
                    separatorBuilder: (_, __) =>
                        SizedBox(height: Responsive.spacing(context, 8)),
                    itemBuilder: (context, index) {
                      final c = courses[index];
                      return _CourseCard(
                        course: c,
                        onEdit: () =>
                            _showCourseDialog(context, ref, course: c),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CourseDetailScreen(course: c),
                          ),
                        ),
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

  void _showCourseDialog(BuildContext context, WidgetRef ref,
      {CourseModel? course}) {
    showDialog(
      context: context,
      builder: (_) => _CourseDialog(
        course: course,
        onSaved: () => ref.invalidate(coursesProvider),
      ),
    );
  }
}

class _CourseCard extends StatelessWidget {
  final CourseModel course;
  final VoidCallback onEdit;
  final VoidCallback onTap;

  const _CourseCard(
      {required this.course, required this.onEdit, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,###');

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: EdgeInsets.all(Responsive.spacing(context, 16)),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: course.isActive
                ? AppColors.gold.withValues(alpha: 0.3)
                : AppColors.divider,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.school, color: AppColors.gold),
            ),
            SizedBox(width: Responsive.spacing(context, 16)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    course.name,
                    style: TextStyle(
                      fontSize: Responsive.fontSize(context, 16),
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      fontFamily: 'Cairo',
                    ),
                  ),
                  SizedBox(height: Responsive.spacing(context, 4)),
                  Row(
                    children: [
                      _Tag(
                        label: '${course.totalSessions} جلسة',
                        icon: Icons.calendar_today,
                      ),
                      SizedBox(width: Responsive.spacing(context, 8)),
                      _Tag(
                        label: '${fmt.format(course.price.toInt())} ل.س',
                        icon: Icons.attach_money,
                        color: AppColors.success,
                      ),
                    ],
                  ),
                  if (course.description != null &&
                      course.description!.isNotEmpty)
                    Padding(
                      padding:
                          EdgeInsets.only(top: Responsive.spacing(context, 4)),
                      child: Text(
                        course.description!,
                        style: TextStyle(
                          fontSize: Responsive.fontSize(context, 12),
                          color: AppColors.textSecondary,
                          fontFamily: 'Cairo',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
            Column(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: course.isActive
                        ? AppColors.success.withValues(alpha: 0.15)
                        : AppColors.error.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    course.isActive ? 'نشط' : 'موقوف',
                    style: TextStyle(
                      fontSize: Responsive.fontSize(context, 12),
                      color:
                          course.isActive ? AppColors.success : AppColors.error,
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                SizedBox(height: Responsive.spacing(context, 8)),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, color: AppColors.gold),
                  onPressed: onEdit,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const _Tag({
    required this.label,
    required this.icon,
    this.color = AppColors.textSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: Responsive.fontSize(context, 12),
            color: color,
            fontFamily: 'Cairo',
          ),
        ),
      ],
    );
  }
}

class _CourseDialog extends ConsumerStatefulWidget {
  final CourseModel? course;
  final VoidCallback onSaved;

  const _CourseDialog({this.course, required this.onSaved});

  @override
  ConsumerState<_CourseDialog> createState() => _CourseDialogState();
}

class _CourseDialogState extends ConsumerState<_CourseDialog> {
  final _nameCtrl = TextEditingController();
  final _sessionsCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  bool _isActive = true;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.course != null) {
      _nameCtrl.text = widget.course!.name;
      _sessionsCtrl.text = widget.course!.totalSessions.toString();
      _priceCtrl.text = widget.course!.price.toInt().toString();
      _descriptionCtrl.text = widget.course!.description ?? '';
      _isActive = widget.course!.isActive;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _sessionsCtrl.dispose();
    _priceCtrl.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_nameCtrl.text.isEmpty ||
        _sessionsCtrl.text.isEmpty ||
        _priceCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى تعبئة الحقول الإلزامية'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final repo = ref.read(coursesRepositoryProvider);

      if (widget.course == null) {
        await repo.addCourse(
          name: _nameCtrl.text.trim(),
          totalSessions: int.parse(_sessionsCtrl.text),
          price: double.parse(_priceCtrl.text),
          description: _descriptionCtrl.text.trim().isEmpty
              ? null
              : _descriptionCtrl.text.trim(),
        );
      } else {
        await repo.updateCourse(
          id: widget.course!.id,
          name: _nameCtrl.text.trim(),
          totalSessions: int.parse(_sessionsCtrl.text),
          price: double.parse(_priceCtrl.text),
          description: _descriptionCtrl.text.trim().isEmpty
              ? null
              : _descriptionCtrl.text.trim(),
          isActive: _isActive,
        );
      }

      if (!mounted) return;
      Navigator.pop(context);
      widget.onSaved();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.course == null
              ? 'تم إضافة الكورس بنجاح ✓'
              : 'تم تحديث الكورس بنجاح ✓'),
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
    final isEdit = widget.course != null;

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
                  Icon(isEdit ? Icons.edit : Icons.add_circle_outline,
                      color: AppColors.gold),
                  SizedBox(width: Responsive.spacing(context, 8)),
                  Text(
                    isEdit ? 'تعديل الكورس' : 'إضافة كورس جديد',
                    style: TextStyle(
                      fontSize: Responsive.fontSize(context, 18),
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
              _buildField(
                controller: _nameCtrl,
                label: 'اسم الكورس *',
                icon: Icons.school_outlined,
              ),
              SizedBox(height: Responsive.spacing(context, 12)),
              Row(
                children: [
                  Expanded(
                    child: _buildField(
                      controller: _sessionsCtrl,
                      label: 'عدد الجلسات *',
                      icon: Icons.calendar_today_outlined,
                      inputType: TextInputType.number,
                    ),
                  ),
                  SizedBox(width: Responsive.spacing(context, 12)),
                  Expanded(
                    child: _buildField(
                      controller: _priceCtrl,
                      label: 'السعر *',
                      icon: Icons.attach_money,
                      inputType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              SizedBox(height: Responsive.spacing(context, 12)),
              _buildField(
                controller: _descriptionCtrl,
                label: 'الوصف (اختياري)',
                icon: Icons.description_outlined,
              ),
              if (isEdit) ...[
                SizedBox(height: Responsive.spacing(context, 12)),
                Row(
                  children: [
                    const Text(
                      'الكورس نشط',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontFamily: 'Cairo',
                      ),
                    ),
                    const Spacer(),
                    Switch(
                      value: _isActive,
                      onChanged: (v) => setState(() => _isActive = v),
                      activeColor: AppColors.gold,
                    ),
                  ],
                ),
              ],
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
                                  color: Colors.black, strokeWidth: 2),
                            )
                          : Text(
                              isEdit ? 'حفظ' : 'إضافة',
                              style: const TextStyle(fontFamily: 'Cairo'),
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

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType inputType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      keyboardType: inputType,
      style: const TextStyle(color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
            color: AppColors.textSecondary, fontFamily: 'Cairo'),
        prefixIcon: Icon(icon, color: AppColors.gold),
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.gold, width: 2),
        ),
      ),
    );
  }
}
