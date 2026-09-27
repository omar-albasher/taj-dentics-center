import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:admin_dashboard/core/widgets/app_error_widget.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/responsive.dart';
import '../data/trainees_repository.dart';
import '../domain/trainee_model.dart';
import 'enroll_in_course_dialog.dart';

class TraineeProfileScreen extends ConsumerWidget {
  final String traineeId;
  const TraineeProfileScreen({super.key, required this.traineeId});

  String _formatAmount(double amount) =>
      NumberFormat('#,###').format(amount.toInt());

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final traineeAsync = ref.watch(traineeByIdProvider(traineeId));
    final profileAsync = ref.watch(traineeProfileProvider(traineeId));

    if (traineeAsync.isLoading || profileAsync.isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.gold),
        ),
      );
    }

    if (traineeAsync.hasError ||
        (traineeAsync.hasValue && traineeAsync.value == null)) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: AppErrorWidget(
          message: 'لم يتم العثور على بيانات المتدرب',
          onRetry: () => ref.invalidate(traineeByIdProvider(traineeId)),
        ),
      );
    }

    if (profileAsync.hasError) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: AppErrorWidget(
          message: 'خطأ في تحميل تفاصيل المتدرب: ${profileAsync.error}',
          onRetry: () => ref.invalidate(traineeProfileProvider(traineeId)),
        ),
      );
    }

    final trainee = traineeAsync.value!;
    final data = profileAsync.value ?? <String, dynamic>{};

    final traineeName = trainee.fullName.isNotEmpty ? trainee.fullName : 'ملف المتدرب';
    final financial = List<Map<String, dynamic>>.from(data['financial'] ?? []);
    final progress = List<Map<String, dynamic>>.from(data['progress'] ?? []);
    final payments = List<Map<String, dynamic>>.from(data['payments'] ?? []);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Row(
          children: [
            Text(
              traineeName,
              style: const TextStyle(
                color: AppColors.gold,
                fontFamily: 'Cairo',
                fontWeight: FontWeight.w700,
              ),
            ),
            if (trainee.traineeCode != null) ...[
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.gold.withValues(alpha: 0.5)),
                ),
                child: Text(
                  trainee.traineeCode!,
                  style: const TextStyle(
                    color: AppColors.gold,
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: AppColors.gold),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            tooltip: 'تعديل البيانات',
            icon: const Icon(Icons.edit_outlined, color: AppColors.gold),
            onPressed: () => _showEditDialog(context, ref, trainee),
          ),
          ElevatedButton.icon(
            onPressed: () {
              showDialog(
                context: context,
                builder: (_) => EnrollInCourseDialog(
                  traineeId: traineeId,
                  traineeName: traineeName,
                  onEnrolled: () {
                    ref.invalidate(traineeProfileProvider(traineeId));
                  },
                ),
              );
            },
            icon: const Icon(Icons.add, size: 18),
            label: const Text('تسجيل بكورس',
                style: TextStyle(fontFamily: 'Cairo', fontSize: 13)),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(Responsive.spacing(context, 24)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Personal & Contact Information
            _SectionCard(
              title: 'المعلومات الشخصية والاتصال',
              icon: Icons.person_outline,
              child: Column(
                children: [
                  if (trainee.traineeCode != null)
                    _InfoRow(label: 'كود المتدرب الفريد', value: trainee.traineeCode!, isLtr: true, valueColor: AppColors.gold),
                  _InfoRow(label: 'الاسم بالعربي', value: trainee.fullName),
                  if (trainee.fullNameEn != null && trainee.fullNameEn!.isNotEmpty)
                    _InfoRow(
                      label: 'الاسم بالإنكليزي (جواز السفر)',
                      value: trainee.fullNameEn!,
                      isLtr: true,
                    ),
                  _InfoRow(label: 'البريد الإلكتروني', value: trainee.email, isLtr: true),
                  _InfoRow(label: 'رقم الجوال', value: trainee.phone, isLtr: true),
                  if (trainee.whatsapp.isNotEmpty)
                    _InfoRow(label: 'رقم الواتساب', value: trainee.whatsapp, isLtr: true),
                  if (trainee.province.isNotEmpty)
                    _InfoRow(label: 'المحافظة', value: trainee.province),
                  if (trainee.address.isNotEmpty)
                    _InfoRow(label: 'عنوان السكن', value: trainee.address),
                  _InfoRow(
                    label: 'تاريخ التسجيل / الدفعة',
                    value: DateFormat('yyyy/MM/dd').format(trainee.createdAt),
                  ),
                  _InfoRow(
                    label: 'حالة الحساب',
                    value: trainee.isActive ? 'نشط' : 'غير نشط',
                    valueColor: trainee.isActive ? AppColors.success : AppColors.error,
                  ),
                ],
              ),
            ),
            SizedBox(height: Responsive.spacing(context, 16)),

            // 2. Academic Information
            _SectionCard(
              title: 'المعلومات الأكاديمية',
              icon: Icons.school_outlined,
              child: Column(
                children: [
                  _InfoRow(
                    label: 'اسم الجامعة أو المعهد',
                    value: (trainee.university != null && trainee.university!.isNotEmpty)
                        ? trainee.university!
                        : 'غير محدد',
                  ),
                  _InfoRow(
                    label: 'السنة الدراسية',
                    value: (trainee.academicYear != null && trainee.academicYear!.isNotEmpty)
                        ? trainee.academicYear!
                        : 'غير محدد',
                  ),
                ],
              ),
            ),
            SizedBox(height: Responsive.spacing(context, 16)),

            // 3. Behavioral and Academic Notes
            if ((trainee.behavioralNotes != null && trainee.behavioralNotes!.isNotEmpty) ||
                (trainee.academicNotes != null && trainee.academicNotes!.isNotEmpty) ||
                (trainee.notes != null && trainee.notes!.isNotEmpty)) ...[
              _SectionCard(
                title: 'ملاحظات وتقييم المتدرب',
                icon: Icons.rate_review_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (trainee.behavioralNotes != null && trainee.behavioralNotes!.isNotEmpty)
                      _NoteBlock(
                        title: 'ملاحظات سلوكية عن المتدرب',
                        content: trainee.behavioralNotes!,
                        icon: Icons.psychology_outlined,
                      ),
                    if (trainee.academicNotes != null && trainee.academicNotes!.isNotEmpty)
                      _NoteBlock(
                        title: 'ملاحظات أكاديمية عن المتدرب',
                        content: trainee.academicNotes!,
                        icon: Icons.auto_stories_outlined,
                      ),
                    if (trainee.notes != null && trainee.notes!.isNotEmpty)
                      _NoteBlock(
                        title: 'ملاحظات عامة',
                        content: trainee.notes!,
                        icon: Icons.notes_outlined,
                      ),
                  ],
                ),
              ),
              SizedBox(height: Responsive.spacing(context, 16)),
            ],

            // 4. Financial Summary
            if (financial.isNotEmpty) ...[
              _SectionCard(
                title: 'الملخص المالي',
                icon: Icons.account_balance_wallet,
                child: Column(
                  children: financial.map((e) {
                    final due = (e['total_due'] as num?)?.toDouble() ?? 0;
                    final paid = (e['total_paid'] as num?)?.toDouble() ?? 0;
                    final balance = (e['balance'] as num?)?.toDouble() ?? 0;
                    final status = e['payment_status'] ?? '';

                    return Column(
                      children: [
                        _InfoRow(
                            label: 'الكورس', value: e['course_name'] ?? ''),
                        _InfoRow(
                            label: 'إجمالي الرسوم',
                            value: '${_formatAmount(due)} ل.س'),
                        _InfoRow(
                            label: 'المدفوع',
                            value: '${_formatAmount(paid)} ل.س',
                            valueColor: AppColors.success),
                        _InfoRow(
                          label: 'المتبقي',
                          value: '${_formatAmount(balance)} ل.س',
                          valueColor:
                              balance > 0 ? AppColors.error : AppColors.success,
                        ),
                        _InfoRow(
                          label: 'الحالة',
                          value: status == 'complete'
                              ? 'مكتمل'
                              : status == 'partial'
                                  ? 'جزئي'
                                  : 'غير مدفوع',
                          valueColor: status == 'complete'
                              ? AppColors.success
                              : status == 'partial'
                                  ? AppColors.warning
                                  : AppColors.error,
                        ),
                        const Divider(color: AppColors.divider),
                      ],
                    );
                  }).toList(),
                ),
              ),
              SizedBox(height: Responsive.spacing(context, 16)),
            ],

            // 5. Academic Progress
            if (progress.isNotEmpty) ...[
              _SectionCard(
                title: 'التقدم الأكاديمي',
                icon: Icons.school,
                child: Column(
                  children: progress.map((e) {
                    final attended =
                        (e['sessions_attended'] as num?)?.toInt() ?? 0;
                    final total = (e['total_sessions'] as num?)?.toInt() ?? 1;
                    final pct =
                        (e['attendance_percentage'] as num?)?.toDouble() ?? 0;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _InfoRow(
                            label: 'الكورس', value: e['course_name'] ?? ''),
                        _InfoRow(
                            label: 'الحضور', value: '$attended / $total جلسة'),
                        SizedBox(height: Responsive.spacing(context, 8)),
                        Row(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: LinearProgressIndicator(
                                  value: pct / 100,
                                  backgroundColor: AppColors.divider,
                                  valueColor: AlwaysStoppedAnimation(
                                    pct >= 75
                                        ? AppColors.success
                                        : pct >= 50
                                            ? AppColors.warning
                                            : AppColors.error,
                                  ),
                                  minHeight: 8,
                                ),
                              ),
                            ),
                            SizedBox(width: Responsive.spacing(context, 8)),
                            Text('$pct%',
                                style: const TextStyle(
                                    color: AppColors.gold,
                                    fontFamily: 'Cairo',
                                    fontWeight: FontWeight.w700)),
                          ],
                        ),
                        const Divider(color: AppColors.divider),
                      ],
                    );
                  }).toList(),
                ),
              ),
              SizedBox(height: Responsive.spacing(context, 16)),
            ],

            // 6. Payment Records
            if (payments.isNotEmpty)
              _SectionCard(
                title: 'سجل الدفعات',
                icon: Icons.receipt_long,
                child: Column(
                  children: payments.map((e) {
                    final amount = (e['amount'] as num?)?.toDouble() ?? 0;
                    final date = DateTime.tryParse(e['paid_at'] ?? '');
                    return _InfoRow(
                      label: date != null
                          ? DateFormat('yyyy/MM/dd').format(date)
                          : '',
                      value: '${_formatAmount(amount)} ل.س',
                      valueColor: AppColors.success,
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showEditDialog(BuildContext context, WidgetRef ref, TraineeModel trainee) {
    final codeCtrl = TextEditingController(text: trainee.traineeCode ?? '');
    final nameArCtrl = TextEditingController(text: trainee.fullNameAr ?? trainee.fullName);
    final nameEnCtrl = TextEditingController(text: trainee.fullNameEn ?? '');
    final whatsappCtrl = TextEditingController(text: trainee.whatsapp);
    final universityCtrl = TextEditingController(text: trainee.university ?? '');
    final academicYearCtrl = TextEditingController(text: trainee.academicYear ?? '');
    final provinceCtrl = TextEditingController(text: trainee.province);
    final addressCtrl = TextEditingController(text: trainee.address);
    final behavioralCtrl = TextEditingController(text: trainee.behavioralNotes ?? '');
    final academicCtrl = TextEditingController(text: trainee.academicNotes ?? '');
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppColors.cardBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.edit, color: AppColors.gold, size: 22),
              SizedBox(width: 8),
              Text('تعديل بيانات المتدرب',
                  style: TextStyle(
                      color: AppColors.gold,
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
            ],
          ),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _dialogField(controller: codeCtrl, label: 'كود المتدرب الفريد (T10001)', isLtr: true),
                  _dialogField(controller: nameArCtrl, label: 'الاسم بالعربي (جواز السفر)'),
                  _dialogField(controller: nameEnCtrl, label: 'الاسم بالإنكليزي (جواز السفر)', isLtr: true),
                  _dialogField(controller: whatsappCtrl, label: 'رقم الواتساب', isLtr: true),
                  _dialogField(controller: universityCtrl, label: 'اسم الجامعة أو المعهد'),
                  _dialogField(controller: academicYearCtrl, label: 'السنة الدراسية'),
                  _dialogField(controller: provinceCtrl, label: 'المحافظة'),
                  _dialogField(controller: addressCtrl, label: 'عنوان السكن'),
                  _dialogField(controller: behavioralCtrl, label: 'ملاحظات سلوكية عن المتدرب', maxLines: 2),
                  _dialogField(controller: academicCtrl, label: 'ملاحظات أكاديمية عن المتدرب', maxLines: 2),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('إلغاء', style: TextStyle(color: AppColors.textSecondary, fontFamily: 'Cairo')),
            ),
            ElevatedButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      setDialogState(() => isSaving = true);
                      try {
                        final repo = ref.read(traineesRepositoryProvider);
                        await repo.updateTraineeDetails(
                          traineeId: trainee.id,
                          traineeCode: codeCtrl.text.trim().isNotEmpty ? codeCtrl.text.trim() : null,
                          fullNameAr: nameArCtrl.text.trim().isNotEmpty ? nameArCtrl.text.trim() : null,
                          fullNameEn: nameEnCtrl.text.trim().isNotEmpty ? nameEnCtrl.text.trim() : null,
                          whatsapp: whatsappCtrl.text.trim().isNotEmpty ? whatsappCtrl.text.trim() : null,
                          university: universityCtrl.text.trim().isNotEmpty ? universityCtrl.text.trim() : null,
                          academicYear: academicYearCtrl.text.trim().isNotEmpty ? academicYearCtrl.text.trim() : null,
                          province: provinceCtrl.text.trim().isNotEmpty ? provinceCtrl.text.trim() : null,
                          address: addressCtrl.text.trim().isNotEmpty ? addressCtrl.text.trim() : null,
                          behavioralNotes: behavioralCtrl.text.trim().isNotEmpty ? behavioralCtrl.text.trim() : null,
                          academicNotes: academicCtrl.text.trim().isNotEmpty ? academicCtrl.text.trim() : null,
                        );
                        ref.invalidate(traineeByIdProvider(trainee.id));
                        if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                      } catch (e) {
                        setDialogState(() => isSaving = false);
                      }
                    },
              child: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                    )
                  : const Text('حفظ', style: TextStyle(fontFamily: 'Cairo')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dialogField({
    required TextEditingController controller,
    required String label,
    bool isLtr = false,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        textDirection: isLtr ? TextDirection.ltr : TextDirection.rtl,
        style: const TextStyle(color: AppColors.textPrimary, fontFamily: 'Cairo'),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: AppColors.textSecondary, fontFamily: 'Cairo', fontSize: 13),
          filled: true,
          fillColor: AppColors.surface,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.divider)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.divider)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.gold, width: 1.5)),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _SectionCard(
      {required this.title, required this.icon, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(Responsive.spacing(context, 20)),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.gold, size: 20),
              SizedBox(width: Responsive.spacing(context, 8)),
              Text(title,
                  style: TextStyle(
                      fontSize: Responsive.fontSize(context, 16),
                      fontWeight: FontWeight.w700,
                      color: AppColors.gold,
                      fontFamily: 'Cairo')),
            ],
          ),
          const Divider(color: AppColors.divider),
          child,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool isLtr;

  const _InfoRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.isLtr = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: Responsive.spacing(context, 6)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontFamily: 'Cairo',
                  fontSize: 14)),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              textDirection: isLtr ? TextDirection.ltr : null,
              style: TextStyle(
                color: valueColor ?? AppColors.textPrimary,
                fontFamily: 'Cairo',
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoteBlock extends StatelessWidget {
  final String title;
  final String content;
  final IconData icon;

  const _NoteBlock({
    required this.title,
    required this.content,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.gold, size: 16),
              const SizedBox(width: 6),
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.gold,
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            content,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontFamily: 'Cairo',
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
