import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/responsive.dart';
import '../data/payments_repository.dart';
import 'package:admin_dashboard/core/widgets/keep_alive_wrapper.dart';

class PaymentsScreen extends ConsumerStatefulWidget {
  const PaymentsScreen({super.key});

  @override
  ConsumerState<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends ConsumerState<PaymentsScreen>
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
            // Header
            Row(
              children: [
                Text(
                  'المدفوعات',
                  style: TextStyle(
                    fontSize: Responsive.fontSize(context, 28),
                    fontWeight: FontWeight.w900,
                    color: AppColors.gold,
                    fontFamily: 'Cairo',
                  ),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: () => _showAddPaymentDialog(context),
                  icon: const Icon(Icons.add),
                  label: const Text('تسجيل دفعة',
                      style: TextStyle(fontFamily: 'Cairo')),
                ),
              ],
            ),

            SizedBox(height: Responsive.spacing(context, 16)),

            // Tabs
            TabBar(
              controller: _tabController,
              labelColor: AppColors.gold,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.gold,
              labelStyle: const TextStyle(
                  fontFamily: 'Cairo', fontWeight: FontWeight.w700),
              tabs: const [
                Tab(text: 'سجل الدفعات'),
                Tab(text: 'المستحقات'),
                Tab(text: 'المتأخرون'),
              ],
            ),

            SizedBox(height: Responsive.spacing(context, 16)),

            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  KeepAliveWrapper(child: _RecentPaymentsTab()),
                  KeepAliveWrapper(child: _EnrollmentsTab(onAddPayment: _showAddPaymentDialog)),
                  KeepAliveWrapper(child: _OverdueTab()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddPaymentDialog(BuildContext context,
      {String? enrollmentId, String? traineeName}) {
    showDialog(
      context: context,
      builder: (_) => _AddPaymentDialog(
        enrollmentId: enrollmentId,
        traineeName: traineeName,
        onAdded: () {
          ref.invalidate(recentPaymentsProvider);
          ref.invalidate(allEnrollmentsProvider);
          ref.invalidate(overduePaymentsProvider);
        },
      ),
    );
  }
}

// ─── Tab 1: Recent Payments ───
class _RecentPaymentsTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paymentsAsync = ref.watch(recentPaymentsProvider);
    final fmt = NumberFormat('#,###');

    return paymentsAsync.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(color: AppColors.gold)),
      error: (e, _) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 48),
            const SizedBox(height: 16),
            Text('خطأ: $e',
                style: const TextStyle(
                    color: AppColors.error, fontFamily: 'Cairo')),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => ref.invalidate(recentPaymentsProvider),
              child: const Text('إعادة المحاولة',
                  style: TextStyle(fontFamily: 'Cairo')),
            ),
          ],
        ),
      ),
      data: (payments) {
        if (payments.isEmpty) {
          return Center(
            child: Text('لا توجد دفعات مسجّلة',
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontFamily: 'Cairo',
                    fontSize: Responsive.fontSize(context, 16))),
          );
        }

        return ListView.separated(
          itemCount: payments.length,
          separatorBuilder: (_, __) =>
              SizedBox(height: Responsive.spacing(context, 8)),
          itemBuilder: (context, index) {
            final p = payments[index];
            final enrollment = p['enrollments'] as Map<String, dynamic>? ?? {};
            final trainee =
                enrollment['trainees'] as Map<String, dynamic>? ?? {};
            final user = trainee['users'] as Map<String, dynamic>? ?? {};
            final cohort = enrollment['cohorts'] as Map<String, dynamic>? ?? {};
            final course = cohort['courses'] as Map<String, dynamic>? ?? {};

            final name = user['full_name'] ?? 'متدرب';
            final courseName = course['name'] ?? '';
            final amount = (p['amount'] as num?)?.toDouble() ?? 0;
            final currency = p['currency'] ?? 'SYP';
            final date = DateTime.tryParse(p['paid_at'] ?? '');

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
                      color: AppColors.success.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.payment, color: AppColors.success),
                  ),
                  SizedBox(width: Responsive.spacing(context, 12)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            style: TextStyle(
                                fontSize: Responsive.fontSize(context, 15),
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                                fontFamily: 'Cairo')),
                        Text(courseName,
                            style: TextStyle(
                                fontSize: Responsive.fontSize(context, 12),
                                color: AppColors.textSecondary,
                                fontFamily: 'Cairo')),
                        if (date != null)
                          Text(
                            DateFormat('yyyy/MM/dd').format(date),
                            style: TextStyle(
                                fontSize: Responsive.fontSize(context, 11),
                                color: AppColors.textSecondary,
                                fontFamily: 'Cairo'),
                          ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${fmt.format(amount.toInt())} ${currency == 'USD' ? '\$' : 'ل.س'}',
                        style: TextStyle(
                            fontSize: Responsive.fontSize(context, 16),
                            fontWeight: FontWeight.w900,
                            color: AppColors.success,
                            fontFamily: 'Cairo'),
                      ),
                      Text(
                        p['method'] == 'cash' ? 'نقداً' : 'تحويل',
                        style: TextStyle(
                            fontSize: Responsive.fontSize(context, 12),
                            color: AppColors.textSecondary,
                            fontFamily: 'Cairo'),
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
}

// ─── Tab 2: Enrollments ───
class _EnrollmentsTab extends ConsumerWidget {
  final Function(BuildContext, {String? enrollmentId, String? traineeName})
      onAddPayment;

  const _EnrollmentsTab({required this.onAddPayment});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enrollmentsAsync = ref.watch(allEnrollmentsProvider);
    final fmt = NumberFormat('#,###');

    return enrollmentsAsync.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(color: AppColors.gold)),
      error: (e, _) => Center(
        child: Text('خطأ: $e',
            style:
                const TextStyle(color: AppColors.error, fontFamily: 'Cairo')),
      ),
      data: (enrollments) {
        if (enrollments.isEmpty) {
          return Center(
            child: Text('لا توجد تسجيلات',
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontFamily: 'Cairo',
                    fontSize: Responsive.fontSize(context, 16))),
          );
        }

        return ListView.separated(
          itemCount: enrollments.length,
          separatorBuilder: (_, __) =>
              SizedBox(height: Responsive.spacing(context, 8)),
          itemBuilder: (context, index) {
            final e = enrollments[index];
            final due = (e['net_due'] as num?)?.toDouble() ?? 0;
            final paid = (e['total_paid'] as num?)?.toDouble() ?? 0;
            final balance = (e['balance'] as num?)?.toDouble() ?? 0;
            final status = e['payment_status'] ?? 'unpaid';
            final currency = e['currency'] ?? 'SYP';
            final sym = currency == 'USD' ? '\$' : 'ل.س';

            return Container(
              padding: EdgeInsets.all(Responsive.spacing(context, 16)),
              decoration: BoxDecoration(
                color: AppColors.cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.divider),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(e['trainee_name'] ?? '',
                                style: TextStyle(
                                    fontSize: Responsive.fontSize(context, 15),
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary,
                                    fontFamily: 'Cairo')),
                            Text(e['course_name'] ?? '',
                                style: TextStyle(
                                    fontSize: Responsive.fontSize(context, 12),
                                    color: AppColors.textSecondary,
                                    fontFamily: 'Cairo')),
                          ],
                        ),
                      ),
                      _StatusBadge(status: status),
                    ],
                  ),
                  SizedBox(height: Responsive.spacing(context, 12)),
                  Row(
                    children: [
                      _AmountInfo(
                          label: 'المستحق',
                          value: '${fmt.format(due.toInt())} $sym',
                          color: AppColors.textPrimary),
                      _AmountInfo(
                          label: 'المدفوع',
                          value: '${fmt.format(paid.toInt())} $sym',
                          color: AppColors.success),
                      _AmountInfo(
                          label: 'المتبقي',
                          value: '${fmt.format(balance.toInt())} $sym',
                          color: balance > 0
                              ? AppColors.error
                              : AppColors.success),
                    ],
                  ),
                  SizedBox(height: Responsive.spacing(context, 12)),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => onAddPayment(
                        context,
                        enrollmentId: e['enrollment_id'],
                        traineeName: e['trainee_name'],
                      ),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('تسجيل دفعة',
                          style: TextStyle(fontFamily: 'Cairo')),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ─── Tab 3: Overdue ───
class _OverdueTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overdueAsync = ref.watch(overduePaymentsProvider);
    final fmt = NumberFormat('#,###');

    return overdueAsync.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(color: AppColors.gold)),
      error: (e, _) => Center(
        child: Text('خطأ: $e',
            style:
                const TextStyle(color: AppColors.error, fontFamily: 'Cairo')),
      ),
      data: (list) {
        if (list.isEmpty) {
          return Center(
            child: Text('🎉 لا توجد مستحقات متأخرة',
                style: TextStyle(
                    color: AppColors.success,
                    fontFamily: 'Cairo',
                    fontSize: Responsive.fontSize(context, 16))),
          );
        }

        return ListView.separated(
          itemCount: list.length,
          separatorBuilder: (_, __) =>
              SizedBox(height: Responsive.spacing(context, 8)),
          itemBuilder: (context, index) {
            final e = list[index];
            final balance = (e['balance_due'] as num?)?.toDouble() ?? 0;
            final phone = e['phone'] ?? '';

            return Container(
              padding: EdgeInsets.all(Responsive.spacing(context, 16)),
              decoration: BoxDecoration(
                color: AppColors.cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: AppColors.error.withValues(alpha: 0.15),
                    child: Text('${index + 1}',
                        style: const TextStyle(
                            color: AppColors.error,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'Cairo')),
                  ),
                  SizedBox(width: Responsive.spacing(context, 12)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e['trainee_name'] ?? '',
                            style: TextStyle(
                                fontSize: Responsive.fontSize(context, 15),
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                                fontFamily: 'Cairo')),
                        Text(e['course_name'] ?? '',
                            style: TextStyle(
                                fontSize: Responsive.fontSize(context, 12),
                                color: AppColors.textSecondary,
                                fontFamily: 'Cairo')),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${fmt.format(balance.toInt())} ل.س',
                        style: TextStyle(
                            fontSize: Responsive.fontSize(context, 15),
                            fontWeight: FontWeight.w900,
                            color: AppColors.error,
                            fontFamily: 'Cairo'),
                      ),
                      if (phone.isNotEmpty)
                        GestureDetector(
                          onTap: () async {
                            String formattedPhone =
                                phone.replaceAll(RegExp(r'[^0-9]'), '');
                            if (formattedPhone.startsWith('09')) {
                              formattedPhone =
                                  '963${formattedPhone.substring(1)}';
                            } else if (formattedPhone.startsWith('9') &&
                                formattedPhone.length == 9) {
                              formattedPhone = '963$formattedPhone';
                            }
                            final url =
                                Uri.parse('https://wa.me/$formattedPhone');
                            if (await canLaunchUrl(url)) {
                              await launchUrl(url);
                            }
                          },
                          child: Container(
                            margin: const EdgeInsets.only(top: 4),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF25D366).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.chat,
                                    color: Color(0xFF25D366), size: 14),
                                SizedBox(width: 4),
                                Text('واتساب',
                                    style: TextStyle(
                                        color: Color(0xFF25D366),
                                        fontSize: 12,
                                        fontFamily: 'Cairo',
                                        fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
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
}

// ─── Add Payment Dialog ───
class _AddPaymentDialog extends ConsumerStatefulWidget {
  final String? enrollmentId;
  final String? traineeName;
  final VoidCallback onAdded;

  const _AddPaymentDialog({
    this.enrollmentId,
    this.traineeName,
    required this.onAdded,
  });

  @override
  ConsumerState<_AddPaymentDialog> createState() => _AddPaymentDialogState();
}

class _AddPaymentDialogState extends ConsumerState<_AddPaymentDialog> {
  final _amountCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String? _selectedEnrollmentId;
  String _currency = 'SYP';
  String _method = 'cash';
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _selectedEnrollmentId = widget.enrollmentId;
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selectedEnrollmentId == null || _amountCtrl.text.isEmpty) {
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
      await ref.read(paymentsRepositoryProvider).addPayment(
            enrollmentId: _selectedEnrollmentId!,
            amount: double.parse(_amountCtrl.text),
            currency: _currency,
            method: _method,
            notes: _notesCtrl.text.isEmpty ? null : _notesCtrl.text,
          );

      if (!mounted) return;
      Navigator.pop(context);
      widget.onAdded();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تسجيل الدفعة بنجاح ✓'),
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
    final enrollmentsAsync = ref.watch(allEnrollmentsProvider);

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
                  const Icon(Icons.add_card, color: AppColors.gold),
                  SizedBox(width: Responsive.spacing(context, 8)),
                  Text(
                    widget.traineeName != null
                        ? 'دفعة — ${widget.traineeName}'
                        : 'تسجيل دفعة جديدة',
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

              // Enrollment selector (if not pre-selected)
              if (widget.enrollmentId == null)
                enrollmentsAsync.when(
                  loading: () =>
                      const CircularProgressIndicator(color: AppColors.gold),
                  error: (e, _) => Text('خطأ: $e'),
                  data: (enrollments) => DropdownButtonFormField<String>(
                    value: _selectedEnrollmentId,
                    dropdownColor: AppColors.cardBg,
                    decoration: InputDecoration(
                      labelText: 'اختر المتدرب / الكورس *',
                      labelStyle: const TextStyle(
                          color: AppColors.textSecondary, fontFamily: 'Cairo'),
                      prefixIcon: const Icon(Icons.person_outline,
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
                    items: enrollments.map((e) {
                      return DropdownMenuItem(
                        value: e['enrollment_id'] as String,
                        child: Text(
                          '${e['trainee_name']} — ${e['course_name']}',
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontFamily: 'Cairo',
                              fontSize: 13),
                        ),
                      );
                    }).toList(),
                    onChanged: (v) => setState(() => _selectedEnrollmentId = v),
                  ),
                ),

              if (widget.enrollmentId == null)
                SizedBox(height: Responsive.spacing(context, 12)),

              // Amount + Currency
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _amountCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        labelText: 'المبلغ *',
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

              // Method
              DropdownButtonFormField<String>(
                value: _method,
                dropdownColor: AppColors.cardBg,
                decoration: InputDecoration(
                  labelText: 'طريقة الدفع',
                  labelStyle: const TextStyle(
                      color: AppColors.textSecondary, fontFamily: 'Cairo'),
                  prefixIcon: const Icon(Icons.payment, color: AppColors.gold),
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
                items: const [
                  DropdownMenuItem(
                    value: 'cash',
                    child: Text('نقداً',
                        style: TextStyle(
                            color: AppColors.textPrimary, fontFamily: 'Cairo')),
                  ),
                  DropdownMenuItem(
                    value: 'transfer',
                    child: Text('تحويل بنكي',
                        style: TextStyle(
                            color: AppColors.textPrimary, fontFamily: 'Cairo')),
                  ),
                  DropdownMenuItem(
                    value: 'other',
                    child: Text('أخرى',
                        style: TextStyle(
                            color: AppColors.textPrimary, fontFamily: 'Cairo')),
                  ),
                ],
                onChanged: (v) => setState(() => _method = v ?? 'cash'),
              ),

              SizedBox(height: Responsive.spacing(context, 12)),

              // Notes
              TextField(
                controller: _notesCtrl,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  labelText: 'ملاحظات (اختياري)',
                  labelStyle: const TextStyle(
                      color: AppColors.textSecondary, fontFamily: 'Cairo'),
                  prefixIcon:
                      const Icon(Icons.note_outlined, color: AppColors.gold),
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

// ─── Helpers ───
class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = status == 'complete'
        ? AppColors.success
        : status == 'partial'
            ? AppColors.warning
            : AppColors.error;

    final label = status == 'complete'
        ? 'مكتمل'
        : status == 'partial'
            ? 'جزئي'
            : 'غير مدفوع';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              color: color,
              fontFamily: 'Cairo',
              fontSize: 12,
              fontWeight: FontWeight.w700)),
    );
  }
}

class _AmountInfo extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _AmountInfo({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontFamily: 'Cairo',
                  fontSize: 12)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  color: color,
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.w700,
                  fontSize: 13),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
