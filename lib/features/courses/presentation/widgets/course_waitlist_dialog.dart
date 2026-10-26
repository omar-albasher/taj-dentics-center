import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/app_error_handler.dart';
import '../../../../core/utils/app_formatters.dart';
import '../../../../core/utils/responsive.dart';
import '../../../trainees/data/trainees_repository.dart';
import '../../data/courses_repository.dart';
import '../../domain/cohort_model.dart';
import '../../domain/cohort_seat_status.dart';
import '../../domain/course_model.dart';
import '../../domain/waitlist_entry_model.dart';
import 'seat_status_badge.dart';

class CourseWaitlistDialog extends ConsumerStatefulWidget {
  final CohortModel cohort;
  final CourseModel course;

  const CourseWaitlistDialog({
    super.key,
    required this.cohort,
    required this.course,
  });

  @override
  ConsumerState<CourseWaitlistDialog> createState() =>
      _CourseWaitlistDialogState();
}

class _CourseWaitlistDialogState extends ConsumerState<CourseWaitlistDialog> {
  String? _selectedTraineeId;
  bool _busy = false;

  void _refresh() {
    ref.invalidate(waitlistProvider(widget.cohort.id));
    ref.invalidate(cohortSeatStatusProvider(widget.course.id));
    ref.invalidate(cohortsByCourseProvider(widget.course.id));
  }

  void _showMessage(String message,
      {bool success = false, bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontFamily: 'Cairo')),
        backgroundColor: error
            ? AppColors.error
            : success
                ? AppColors.success
                : AppColors.surface,
      ),
    );
  }

  Future<void> _addSelected() async {
    final traineeId = _selectedTraineeId;
    if (traineeId == null) return;

    setState(() => _busy = true);
    try {
      final result = await ref.read(coursesRepositoryProvider).joinWaitlist(
            cohortId: widget.cohort.id,
            traineeId: traineeId,
          );

      if (!mounted) return;
      _refresh();
      final alreadyJoined = result['already_joined'] == true;
      final position = result['queue_position'];
      final message = alreadyJoined
          ? 'هذا المتدرب موجود مسبقاً في قائمة الانتظار'
          : position != null
              ? 'تمت إضافة المتدرب — الترتيب $position'
              : 'تمت إضافة المتدرب إلى قائمة الانتظار';
      _showMessage(message, success: !alreadyJoined);
    } catch (e) {
      if (!mounted) return;
      _showMessage(AppErrorHandler.friendlyMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _promote(WaitlistEntryModel entry) async {
    setState(() => _busy = true);
    try {
      final promoted = await showDialog<bool>(
        context: context,
        builder: (_) => _PromoteWaitlistDialog(
          entry: entry,
          course: widget.course,
          cohortName: widget.cohort.name,
        ),
      );
      if (!mounted || promoted != true) return;

      _refresh();
      final name = entry.traineeName.isEmpty ? 'المتدرب' : entry.traineeName;
      _showMessage('تمت ترقية $name وتسجيله بنجاح', success: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel(WaitlistEntryModel entry) async {
    final name = entry.traineeName.isEmpty ? 'المتدرب' : entry.traineeName;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.cardBg,
        title: const Text(
          'إلغاء طلب الانتظار',
          style: TextStyle(color: AppColors.gold, fontFamily: 'Cairo'),
        ),
        content: Text(
          'هل تريد إلغاء طلب $name؟',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontFamily: 'Cairo',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text(
              'رجوع',
              style: TextStyle(
                fontFamily: 'Cairo',
                color: AppColors.textSecondary,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text(
              'إلغاء الطلب',
              style: TextStyle(fontFamily: 'Cairo'),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(coursesRepositoryProvider).cancelWaitlist(entry.id);
      if (!mounted) return;
      _refresh();
      _showMessage('تم إلغاء طلب الانتظار', success: true);
    } catch (e) {
      if (!mounted) return;
      _showMessage(AppErrorHandler.friendlyMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  CohortSeatStatus? _findSeatStatus(List<CohortSeatStatus>? statuses) {
    for (final status in statuses ?? const <CohortSeatStatus>[]) {
      if (status.cohortId == widget.cohort.id) return status;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final waitlistAsync = ref.watch(waitlistProvider(widget.cohort.id));
    final seatAsync = ref.watch(cohortSeatStatusProvider(widget.course.id));
    final traineesAsync = ref.watch(traineesProvider(null));
    final seat = _findSeatStatus(seatAsync.asData?.value);

    return Dialog(
      backgroundColor: AppColors.cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780, maxHeight: 700),
        child: Padding(
          padding: EdgeInsets.all(Responsive.spacing(context, 24)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.hourglass_bottom, color: AppColors.warning),
                  SizedBox(width: Responsive.spacing(context, 8)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'قائمة الانتظار — ${widget.cohort.name}',
                          style: TextStyle(
                            fontSize: Responsive.fontSize(context, 16),
                            fontWeight: FontWeight.w700,
                            color: AppColors.gold,
                            fontFamily: 'Cairo',
                          ),
                        ),
                        Text(
                          widget.course.name,
                          style: TextStyle(
                            fontSize: Responsive.fontSize(context, 12),
                            color: AppColors.textSecondary,
                            fontFamily: 'Cairo',
                          ),
                        ),
                      ],
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
              SizedBox(height: Responsive.spacing(context, 8)),
              if (seat != null)
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    SeatStatusBadge(
                      label: seat.isUnlimited
                          ? 'غير محدود'
                          : seat.isFull
                              ? 'ممتلئ'
                              : 'متبقي ${seat.availableSeats ?? 0}',
                      color: seat.isUnlimited
                          ? AppColors.silver
                          : seat.isFull
                              ? AppColors.error
                              : AppColors.success,
                      icon: seat.isFull ? Icons.block : Icons.event_seat,
                    ),
                    SeatStatusBadge(
                      label: 'مسجل ${seat.enrolledCount}',
                      color: AppColors.silver,
                      icon: Icons.people_outline,
                    ),
                    SeatStatusBadge(
                      label: 'انتظار ${seat.waitlistCount}',
                      color: AppColors.warning,
                      icon: Icons.hourglass_bottom,
                    ),
                  ],
                ),
              SizedBox(height: Responsive.spacing(context, 12)),
              if (seat?.isFull == true)
                traineesAsync.when(
                  loading: () => const SizedBox(
                    height: 48,
                    child: Center(
                      child: CircularProgressIndicator(
                        color: AppColors.gold,
                        strokeWidth: 2,
                      ),
                    ),
                  ),
                  error: (e, _) => Text(
                    AppErrorHandler.friendlyMessage(e),
                    style: const TextStyle(
                      color: AppColors.error,
                      fontFamily: 'Cairo',
                    ),
                  ),
                  data: (trainees) => Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _selectedTraineeId,
                          isExpanded: true,
                          dropdownColor: AppColors.cardBg,
                          decoration: _dialogDecoration(
                            'إضافة متدرب إلى الانتظار',
                            Icons.person_add_alt_1,
                          ),
                          items: trainees
                              .map(
                                (t) => DropdownMenuItem(
                                  value: t.id,
                                  child: Text(
                                    t.fullName,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontFamily: 'Cairo',
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _selectedTraineeId = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: _selectedTraineeId == null || _busy
                            ? null
                            : _addSelected,
                        icon: const Icon(Icons.playlist_add, size: 18),
                        label: const Text(
                          'إضافة',
                          style: TextStyle(fontFamily: 'Cairo'),
                        ),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else if (seat != null)
                Text(
                  seat.isUnlimited
                      ? 'هذه المجموعة غير محدودة السعة — لا حاجة لقائمة انتظار.'
                      : 'لا يمكن إضافة متدرب إلى الانتظار قبل امتلاء المجموعة — '
                          'ما زال هناك ${seat.availableSeats ?? 0} مقعد متاح.',
                  style: TextStyle(
                    fontSize: Responsive.fontSize(context, 12),
                    color: AppColors.textSecondary,
                    fontFamily: 'Cairo',
                  ),
                ),
              SizedBox(height: Responsive.spacing(context, 12)),
              const Divider(color: AppColors.divider),
              SizedBox(height: Responsive.spacing(context, 8)),
              Flexible(
                child: SizedBox(
                  height: 280,
                  child: waitlistAsync.when(
                    loading: () => const Center(
                      child: CircularProgressIndicator(color: AppColors.gold),
                    ),
                    error: (e, _) => Center(
                      child: Text(
                        AppErrorHandler.friendlyMessage(e),
                        style: const TextStyle(
                          color: AppColors.error,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ),
                    data: (entries) {
                      if (entries.isEmpty) {
                        return Center(
                          child: Text(
                            'لا يوجد أحد في قائمة الانتظار حالياً',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontFamily: 'Cairo',
                              fontSize: Responsive.fontSize(context, 13),
                            ),
                          ),
                        );
                      }

                      return ListView.separated(
                        shrinkWrap: true,
                        itemCount: entries.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) =>
                            _buildEntry(entries[index], index),
                      );
                    },
                  ),
                ),
              ),
              SizedBox(height: Responsive.spacing(context, 8)),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'إغلاق',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEntry(WaitlistEntryModel entry, int index) {
    final notified = entry.isNotified;
    final name = entry.traineeName.isEmpty ? 'متدرب' : entry.traineeName;
    final subtitle = [
      if (entry.traineeCode.isNotEmpty) entry.traineeCode,
      if (entry.traineePhone.isNotEmpty) entry.traineePhone,
    ].join(' • ');

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: notified
              ? AppColors.warning.withValues(alpha: 0.5)
              : AppColors.divider,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: AppColors.darkGreen,
            child: Text(
              '${index + 1}',
              style: const TextStyle(
                color: AppColors.gold,
                fontSize: 11,
                fontFamily: 'Cairo',
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontFamily: 'Cairo',
                      fontSize: 11,
                    ),
                  ),
                if (entry.joinedAt != null)
                  Text(
                    'انضم: ${AppFormatters.dateTime.format(entry.joinedAt!)}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontFamily: 'Cairo',
                      fontSize: 10,
                    ),
                  ),
                if (notified && entry.expiresAt != null)
                  Text(
                    'مهلة الإشعار حتى: '
                    '${AppFormatters.dateTime.format(entry.expiresAt!)}',
                    style: const TextStyle(
                      color: AppColors.warning,
                      fontFamily: 'Cairo',
                      fontSize: 10,
                    ),
                  ),
                if (!entry.traineeUserActive)
                  const Text(
                    'حساب المتدرب غير مفعّل',
                    style: TextStyle(
                      color: AppColors.error,
                      fontFamily: 'Cairo',
                      fontSize: 10,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SeatStatusBadge(
            label: notified ? 'تم الإشعار' : 'بانتظار',
            color: notified ? AppColors.warning : AppColors.silver,
            icon: notified
                ? Icons.notifications_active_outlined
                : Icons.hourglass_empty,
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.upgrade, color: AppColors.success, size: 20),
            tooltip: 'ترقية إلى تسجيل',
            onPressed: _busy ? null : () => _promote(entry),
          ),
          IconButton(
            icon: const Icon(Icons.cancel_outlined,
                color: AppColors.error, size: 20),
            tooltip: 'إلغاء الطلب',
            onPressed: _busy ? null : () => _cancel(entry),
          ),
        ],
      ),
    );
  }
}

InputDecoration _dialogDecoration(String label, IconData icon) {
  return InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(
      color: AppColors.textSecondary,
      fontFamily: 'Cairo',
    ),
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
  );
}

class _PromoteWaitlistDialog extends ConsumerStatefulWidget {
  final WaitlistEntryModel entry;
  final CourseModel course;
  final String cohortName;

  const _PromoteWaitlistDialog({
    required this.entry,
    required this.course,
    required this.cohortName,
  });

  @override
  ConsumerState<_PromoteWaitlistDialog> createState() =>
      _PromoteWaitlistDialogState();
}

class _PromoteWaitlistDialogState
    extends ConsumerState<_PromoteWaitlistDialog> {
  late final TextEditingController _priceCtrl;
  final _discountCtrl = TextEditingController(text: '0');
  String _currency = 'SYP';
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _priceCtrl =
        TextEditingController(text: widget.course.price.toInt().toString());
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    _discountCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final totalDue = double.tryParse(_priceCtrl.text);
    if (totalDue == null || totalDue < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'قيمة السعر غير صالحة',
            style: TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      await ref.read(coursesRepositoryProvider).promoteWaitlist(
            waitlistId: widget.entry.id,
            totalDue: totalDue,
            discountAmount: double.tryParse(_discountCtrl.text) ?? 0,
            currency: _currency,
          );

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppErrorHandler.friendlyMessage(e),
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name =
        widget.entry.traineeName.isEmpty ? 'متدرب' : widget.entry.traineeName;

    return Dialog(
      backgroundColor: AppColors.cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Padding(
          padding: EdgeInsets.all(Responsive.spacing(context, 24)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.upgrade, color: AppColors.success),
                  SizedBox(width: Responsive.spacing(context, 8)),
                  Expanded(
                    child: Text(
                      'ترقية إلى تسجيل — $name',
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
              SizedBox(height: Responsive.spacing(context, 12)),
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(Responsive.spacing(context, 12)),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${widget.course.name} — ${widget.cohortName}',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontFamily: 'Cairo',
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'ستُنشئ العملية تسجيلاً مالياً فعلياً وتُغلق طلب الانتظار.',
                      style: TextStyle(
                        color: AppColors.warning,
                        fontFamily: 'Cairo',
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: Responsive.spacing(context, 16)),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _priceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration:
                          _dialogDecoration('السعر *', Icons.attach_money),
                    ),
                  ),
                  SizedBox(width: Responsive.spacing(context, 12)),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _currency,
                      dropdownColor: AppColors.cardBg,
                      decoration:
                          _dialogDecoration('العملة', Icons.payments_outlined),
                      items: const [
                        DropdownMenuItem(
                          value: 'SYP',
                          child: Text(
                            'ل.س',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontFamily: 'Cairo',
                            ),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'USD',
                          child: Text(
                            '\$',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontFamily: 'Cairo',
                            ),
                          ),
                        ),
                      ],
                      onChanged: (v) => setState(() => _currency = v ?? 'SYP'),
                    ),
                  ),
                ],
              ),
              SizedBox(height: Responsive.spacing(context, 12)),
              TextField(
                controller: _discountCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: _dialogDecoration(
                  'الخصم (اختياري)',
                  Icons.discount_outlined,
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
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text(
                        'إلغاء',
                        style: TextStyle(fontFamily: 'Cairo'),
                      ),
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
                                color: Colors.black,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              'ترقية وتسجيل',
                              style: TextStyle(fontFamily: 'Cairo'),
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
