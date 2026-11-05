import '../../whatsapp/domain/whatsapp_template_type.dart';
import '../../whatsapp/presentation/whatsapp_template_dialog.dart';
import '../../../core/utils/phone_utils.dart';
import '../../../core/utils/app_error_handler.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/utils/app_formatters.dart';
import '../../../core/utils/jwt_utils.dart';
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
                  KeepAliveWrapper(
                      child:
                          _EnrollmentsTab(onAddPayment: _showAddPaymentDialog)),
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
      {String? enrollmentId,
      String? traineeName,
      String? enrollmentCurrency}) {
    showDialog(
      context: context,
      builder: (_) => _AddPaymentDialog(
        enrollmentId: enrollmentId,
        traineeName: traineeName,
        enrollmentCurrency: enrollmentCurrency,
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
class _RecentPaymentsTab extends ConsumerStatefulWidget {
  @override
  ConsumerState<_RecentPaymentsTab> createState() => _RecentPaymentsTabState();
}

class _RecentPaymentsTabState extends ConsumerState<_RecentPaymentsTab> {
  final _searchCtrl = TextEditingController();
  String _methodFilter = 'all';
  String _searchQuery = '';
  Timer? _debounce;

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _searchQuery = v.trim());
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final params = PaymentFilterParams(
      search: _searchQuery.isEmpty ? null : _searchQuery,
      method: _methodFilter == 'all' ? null : _methodFilter,
    );
    final paymentsAsync = ref.watch(recentPaymentsProvider(params));
    final fmt = AppFormatters.amount;
    final role = JwtUtils.extractRole(
        Supabase.instance.client.auth.currentSession?.accessToken);
    final isAdmin = role == 'admin';

    return Column(
      children: [
        // ── Search & Filter Bar ──
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                style: const TextStyle(color: AppColors.textPrimary, fontFamily: 'Cairo'),
                decoration: InputDecoration(
                  hintText: 'بحث بالاسم، الكورس، رقم الوصل...',
                  hintStyle: const TextStyle(color: AppColors.textSecondary, fontFamily: 'Cairo', fontSize: 13),
                  prefixIcon: const Icon(Icons.search, color: AppColors.gold),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: AppColors.textSecondary, size: 18),
                          onPressed: () {
                            _debounce?.cancel();
                            _searchCtrl.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: AppColors.surface,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.divider)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.divider)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.gold, width: 2)),
                ),
                onChanged: _onSearchChanged,
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.divider),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _methodFilter,
                  dropdownColor: AppColors.cardBg,
                  style: const TextStyle(color: AppColors.textPrimary, fontFamily: 'Cairo', fontSize: 13),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('الكل', style: TextStyle(fontFamily: 'Cairo'))),
                    DropdownMenuItem(value: 'cash', child: Text('نقداً', style: TextStyle(fontFamily: 'Cairo'))),
                    DropdownMenuItem(value: 'sham_cash', child: Text('شام كاش', style: TextStyle(fontFamily: 'Cairo'))),
                    DropdownMenuItem(value: 'hawala', child: Text('حوالة', style: TextStyle(fontFamily: 'Cairo'))),
                    DropdownMenuItem(value: 'transfer', child: Text('تحويل بنكي', style: TextStyle(fontFamily: 'Cairo'))),
                  ],
                  onChanged: (v) => setState(() => _methodFilter = v ?? 'all'),
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: Responsive.spacing(context, 12)),
        // ── List ──
        Expanded(
          child: paymentsAsync.when(
            loading: () =>
                const Center(child: CircularProgressIndicator(color: AppColors.gold)),
            error: (e, _) => Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: AppColors.error, size: 48),
                  const SizedBox(height: 16),
                  Text(AppErrorHandler.friendlyMessage(e),
                      style: const TextStyle(
                          color: AppColors.error, fontFamily: 'Cairo')),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () => ref.invalidate(recentPaymentsProvider(params)),
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
                  final refunds = (p['payment_refunds'] as List?) ?? const [];
                  final refunded = refunds.fold<double>(
                      0,
                      (sum, r) =>
                          sum +
                          (((r as Map)['amount'] as num?)?.toDouble() ?? 0));
                  final refundable = amount - refunded;

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
                                  AppFormatters.dateOnly.format(date),
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
                              _getMethodLabel(p['method']),
                              style: TextStyle(
                                  fontSize: Responsive.fontSize(context, 12),
                                  color: AppColors.textSecondary,
                                  fontFamily: 'Cairo'),
                            ),
                            if (refunded > 0)
                              Text(
                                'مسترجع: ${fmt.format(refunded.toInt())} '
                                '${currency == 'USD' ? '\$' : 'ل.س'}',
                                style: TextStyle(
                                    fontSize: Responsive.fontSize(context, 11),
                                    color: AppColors.error,
                                    fontFamily: 'Cairo'),
                              ),
                            if (isAdmin) ...[
                              const SizedBox(height: 4),
                              InkWell(
                                onTap: refundable <= 0
                                    ? null
                                    : () => _showRefund(
                                          paymentId: p['id'] as String,
                                          amount: amount,
                                          refunded: refunded,
                                          currency:
                                              (p['currency'] as String?) ??
                                                  'SYP',
                                          traineeName: name,
                                        ),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: AppColors.error
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    refundable <= 0
                                        ? 'مسترجع بالكامل'
                                        : 'استرداد',
                                    style: TextStyle(
                                        color: refundable <= 0
                                            ? AppColors.textSecondary
                                            : AppColors.error,
                                        fontSize: 11,
                                        fontFamily: 'Cairo',
                                        fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ),
                            ],
                            Builder(
                              builder: (ctx) {
                                final rawWa = (trainee['whatsapp_number'] as String?)?.trim();
                                if (rawWa == null || PhoneUtils.sanitizePhone(rawWa) == null) {
                                  return const SizedBox.shrink();
                                }
                                return InkWell(
                                  onTap: () async {
                                    final enrollmentId = enrollment['id'] as String?;
                                    num? remBalance;
                                    if (enrollmentId != null) {
                                      final summary = await ref
                                          .read(paymentsRepositoryProvider)
                                          .getEnrollmentFinancialSummary(enrollmentId);
                                      remBalance = summary?['balance'] as num?;
                                    }
                                    if (ctx.mounted) {
                                      WhatsAppTemplateDialog.show(
                                        ctx,
                                        traineeName: name,
                                        whatsappNumber: rawWa,
                                        courseName: courseName,
                                        amount: amount,
                                        receiptNumber: p['receipt_number'] as String?,
                                        balance: remBalance,
                                        currency: currency == 'USD' ? r'$' : 'ل.س',
                                        initialType: WhatsAppTemplateType.paymentReceipt,
                                      );
                                    }
                                  },
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    margin: const EdgeInsets.only(top: 4),
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF25D366).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.receipt, color: Color(0xFF25D366), size: 13),
                                        SizedBox(width: 4),
                                        Text('إشعار واتساب',
                                            style: TextStyle(
                                                color: Color(0xFF25D366),
                                                fontSize: 11,
                                                fontFamily: 'Cairo',
                                                fontWeight: FontWeight.w700)),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _showRefund({
    required String paymentId,
    required double amount,
    required double refunded,
    required String currency,
    required String traineeName,
  }) {
    showDialog(
      context: context,
      builder: (_) => _RefundDialog(
        paymentId: paymentId,
        paymentAmount: amount,
        refundedAmount: refunded,
        currency: currency,
        traineeName: traineeName,
        onSaved: () {
          ref.invalidate(recentPaymentsProvider);
          ref.invalidate(allEnrollmentsProvider);
          ref.invalidate(overduePaymentsProvider);
        },
      ),
    );
  }

  String _getMethodLabel(String? method) {
    switch (method) {
      case 'cash': return 'نقداً';
      case 'sham_cash': return 'شام كاش';
      case 'hawala': return 'حوالة';
      case 'transfer': return 'تحويل بنكي';
      default: return 'أخرى';
    }
  }
}

// ─── Tab 2: Enrollments ───
class _EnrollmentsTab extends ConsumerStatefulWidget {
  final Function(BuildContext,
      {String? enrollmentId,
      String? traineeName,
      String? enrollmentCurrency}) onAddPayment;

  const _EnrollmentsTab({required this.onAddPayment});

  @override
  ConsumerState<_EnrollmentsTab> createState() => _EnrollmentsTabState();
}

class _EnrollmentsTabState extends ConsumerState<_EnrollmentsTab> {
  final _searchCtrl = TextEditingController();
  String _statusFilter = 'all';
  String _searchQuery = '';
  Timer? _debounce;

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _searchQuery = v.trim());
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final params = PaymentFilterParams(
      search: _searchQuery.isEmpty ? null : _searchQuery,
      status: _statusFilter == 'all' ? null : _statusFilter,
    );
    final enrollmentsAsync = ref.watch(allEnrollmentsProvider(params));
    final fmt = AppFormatters.amount;
    final role = JwtUtils.extractRole(
        Supabase.instance.client.auth.currentSession?.accessToken);
    final isAdmin = role == 'admin';

    return Column(
      children: [
        // ── Search & Filter Bar ──
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                style: const TextStyle(color: AppColors.textPrimary, fontFamily: 'Cairo'),
                decoration: InputDecoration(
                  hintText: 'بحث بالاسم أو الكورس...',
                  hintStyle: const TextStyle(color: AppColors.textSecondary, fontFamily: 'Cairo', fontSize: 13),
                  prefixIcon: const Icon(Icons.search, color: AppColors.gold),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: AppColors.textSecondary, size: 18),
                          onPressed: () {
                            _debounce?.cancel();
                            _searchCtrl.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: AppColors.surface,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.divider)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.divider)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.gold, width: 2)),
                ),
                onChanged: _onSearchChanged,
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.divider),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _statusFilter,
                  dropdownColor: AppColors.cardBg,
                  style: const TextStyle(color: AppColors.textPrimary, fontFamily: 'Cairo', fontSize: 13),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('كل الحالات', style: TextStyle(fontFamily: 'Cairo'))),
                    DropdownMenuItem(value: 'unpaid', child: Text('غير مدفوع', style: TextStyle(fontFamily: 'Cairo'))),
                    DropdownMenuItem(value: 'partial', child: Text('جزئي', style: TextStyle(fontFamily: 'Cairo'))),
                    DropdownMenuItem(value: 'complete', child: Text('مكتمل', style: TextStyle(fontFamily: 'Cairo'))),
                  ],
                  onChanged: (v) => setState(() => _statusFilter = v ?? 'all'),
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: Responsive.spacing(context, 12)),
        // ── List ──
        Expanded(
          child: enrollmentsAsync.when(
            loading: () =>
                const Center(child: CircularProgressIndicator(color: AppColors.gold)),
            error: (e, _) => Center(
              child: Text(AppErrorHandler.friendlyMessage(e),
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
                  final installments = (e['total_installments'] as num?)?.toInt() ?? 0;
                  final nextDue = DateTime.tryParse(
                      (e['next_due_date'] as String?) ?? '');
                  final overdue = (e['overdue_balance'] as num?)?.toDouble() ?? 0;

                  return Container(
                    padding: EdgeInsets.all(Responsive.spacing(context, 16)),
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
                        if (installments > 0) ...[
                          SizedBox(height: Responsive.spacing(context, 8)),
                          Row(
                            children: [
                              const Icon(Icons.event_note,
                                  color: AppColors.textSecondary, size: 14),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  nextDue == null
                                      ? 'الأقساط: $installments'
                                      : 'الأقساط: $installments • القسط القادم: '
                                          '${AppFormatters.dateOnly.format(nextDue)}',
                                  style: TextStyle(
                                      fontSize:
                                          Responsive.fontSize(context, 12),
                                      color: AppColors.textSecondary,
                                      fontFamily: 'Cairo'),
                                ),
                              ),
                              if (overdue > 0)
                                Text(
                                  'متأخر: ${fmt.format(overdue.toInt())} $sym',
                                  style: TextStyle(
                                      fontSize:
                                          Responsive.fontSize(context, 12),
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.error,
                                      fontFamily: 'Cairo'),
                                ),
                            ],
                          ),
                        ],
                        SizedBox(height: Responsive.spacing(context, 12)),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () => widget.onAddPayment(
                                  context,
                                  enrollmentId: e['enrollment_id'],
                                  traineeName: e['trainee_name'],
                                  enrollmentCurrency: currency,
                                ),
                                icon: const Icon(Icons.add, size: 16),
                                label: const Text('تسجيل دفعة',
                                    style: TextStyle(fontFamily: 'Cairo')),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _showInstallmentPlan(e),
                                icon: const Icon(Icons.calendar_month, size: 16),
                                label: const Text('الأقساط',
                                    style: TextStyle(fontFamily: 'Cairo')),
                              ),
                            ),
                          ],
                        ),
                        if (isAdmin) ...[
                          const SizedBox(height: 4),
                          SizedBox(
                            width: double.infinity,
                            child: TextButton.icon(
                              onPressed: () => _showFeeAdjustment(e),
                              icon: const Icon(Icons.tune, size: 16),
                              label: const Text('تعديل الرسوم (مدير)',
                                  style: TextStyle(fontFamily: 'Cairo')),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _refreshFinancials() {
    ref.invalidate(allEnrollmentsProvider);
    ref.invalidate(recentPaymentsProvider);
    ref.invalidate(overduePaymentsProvider);
  }

  void _showInstallmentPlan(Map<String, dynamic> e) {
    final id = e['enrollment_id'] as String?;
    if (id == null) return;
    showDialog(
      context: context,
      builder: (_) => _InstallmentPlanDialog(
        enrollmentId: id,
        traineeName: (e['trainee_name'] as String?) ?? '',
        onSaved: _refreshFinancials,
      ),
    );
  }

  void _showFeeAdjustment(Map<String, dynamic> e) {
    final id = e['enrollment_id'] as String?;
    if (id == null) return;
    showDialog(
      context: context,
      builder: (_) => _FeeAdjustmentDialog(
        enrollmentId: id,
        traineeName: (e['trainee_name'] as String?) ?? '',
        onSaved: _refreshFinancials,
      ),
    );
  }
}

// ─── Tab 3: Overdue ───
class _OverdueTab extends ConsumerStatefulWidget {
  @override
  ConsumerState<_OverdueTab> createState() => _OverdueTabState();
}

class _OverdueTabState extends ConsumerState<_OverdueTab> {
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  Timer? _debounce;

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _searchQuery = v.trim());
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final overdueAsync = ref.watch(overduePaymentsProvider(_searchQuery.isEmpty ? null : _searchQuery));
    final fmt = AppFormatters.amount;

    return Column(
      children: [
        // ── Search Bar ──
        TextField(
          controller: _searchCtrl,
          style: const TextStyle(color: AppColors.textPrimary, fontFamily: 'Cairo'),
          decoration: InputDecoration(
            hintText: 'بحث بالاسم أو الكود أو الكورس...',
            hintStyle: const TextStyle(color: AppColors.textSecondary, fontFamily: 'Cairo', fontSize: 13),
            prefixIcon: const Icon(Icons.search, color: AppColors.gold),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, color: AppColors.textSecondary, size: 18),
                    onPressed: () {
                      _debounce?.cancel();
                      _searchCtrl.clear();
                      setState(() => _searchQuery = '');
                    },
                  )
                : null,
            filled: true,
            fillColor: AppColors.surface,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.divider)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.divider)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.gold, width: 2)),
          ),
          onChanged: _onSearchChanged,
        ),
        SizedBox(height: Responsive.spacing(context, 12)),
        // ── List ──
        Expanded(
          child: overdueAsync.when(
            loading: () =>
                const Center(child: CircularProgressIndicator(color: AppColors.gold)),
            error: (e, _) => Center(
              child: Text(AppErrorHandler.friendlyMessage(e),
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
                  final whatsappNumber = (e['whatsapp_number'] as String?)?.trim();
                  final isValidWa = PhoneUtils.sanitizePhone(whatsappNumber) != null;

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
                            if (isValidWa)
                              GestureDetector(
                                onTap: () {
                                  WhatsAppTemplateDialog.show(
                                    context,
                                    traineeName: e['trainee_name'] ?? '',
                                    whatsappNumber: whatsappNumber,
                                    courseName: e['course_name'] ?? '',
                                    balance: balance,
                                    currency: (e['currency'] == 'USD') ? r'$' : 'ل.س',
                                    initialType: WhatsAppTemplateType.paymentReminder,
                                  );
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
                                      Text('تذكير واتساب',
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
          ),
        ),
      ],
    );
  }
}

// ─── Add Payment Dialog ───
class _AddPaymentDialog extends ConsumerStatefulWidget {
  final String? enrollmentId;
  final String? traineeName;
  final String? enrollmentCurrency;
  final VoidCallback onAdded;

  const _AddPaymentDialog({
    this.enrollmentId,
    this.traineeName,
    this.enrollmentCurrency,
    required this.onAdded,
  });

  @override
  ConsumerState<_AddPaymentDialog> createState() => _AddPaymentDialogState();
}

class _AddPaymentDialogState extends ConsumerState<_AddPaymentDialog> {
  final _amountCtrl = TextEditingController();
  final _receiptCtrl = TextEditingController();
  final _externalRefCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  DateTime _paidAt = DateTime.now();

  String? _selectedEnrollmentId;
  String _currency = 'SYP';
  String _method = 'cash';
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _selectedEnrollmentId = widget.enrollmentId;
    if (widget.enrollmentCurrency != null) {
      _currency = widget.enrollmentCurrency!;
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _receiptCtrl.dispose();
    _externalRefCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _paidAt,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
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
      setState(() => _paidAt = picked);
    }
  }

  Future<void> _submit() async {
    final amount =
        double.tryParse(_amountCtrl.text.replaceAll(',', '').trim());
    if (_selectedEnrollmentId == null || amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى اختيار التسجيل وإدخال مبلغ صحيح أكبر من صفر',
              style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      await ref.read(paymentsRepositoryProvider).addPayment(
            enrollmentId: _selectedEnrollmentId!,
            amount: amount,
            currency: _currency,
            method: _method,
            receiptNumber: _receiptCtrl.text.trim().isEmpty ? null : _receiptCtrl.text.trim(),
            externalReference: _externalRefCtrl.text.trim().isEmpty ? null : _externalRefCtrl.text.trim(),
            notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
            paidAt: _paidAt,
          );

      if (!mounted) return;
      Navigator.pop(context);
      widget.onAdded();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تسجيل الدفعة بنجاح ✓', style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppErrorHandler.friendlyMessage(e), style: const TextStyle(fontFamily: 'Cairo')), backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enrollmentsAsync =
        ref.watch(allEnrollmentsProvider(const PaymentFilterParams()));

    final isTransferOrEcash = _method == 'sham_cash' || _method == 'hawala' || _method == 'transfer';

    return Dialog(
      backgroundColor: AppColors.cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
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
                  error: (e, _) => Text(AppErrorHandler.friendlyMessage(e), style: const TextStyle(color: AppColors.error, fontFamily: 'Cairo')),
                  data: (enrollments) => DropdownButtonFormField<String>(
                    initialValue: _selectedEnrollmentId,
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
                    onChanged: (v) => setState(() {
                      _selectedEnrollmentId = v;
                      final selected = enrollments
                          .where((row) => row['enrollment_id'] == v)
                          .toList();
                      final selectedCurrency = selected.isEmpty
                          ? null
                          : selected.first['currency'] as String?;
                      if (selectedCurrency != null) {
                        _currency = selectedCurrency;
                      }
                    }),
                  ),
                ),

              if (widget.enrollmentId == null)
                SizedBox(height: Responsive.spacing(context, 12)),

              // Amount & Currency
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _amountCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: AppColors.textPrimary, fontFamily: 'Cairo'),
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
                      key: ValueKey('payment_currency_$_currency'),
                      initialValue: _currency,
                      dropdownColor: AppColors.cardBg,
                      decoration: InputDecoration(
                        labelText: _selectedEnrollmentId == null
                            ? 'العملة'
                            : 'العملة (مقفلة)',
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
                          child: Text(r'$',
                              style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontFamily: 'Cairo')),
                        ),
                      ],
                      onChanged: _selectedEnrollmentId == null
                          ? (v) => setState(() => _currency = v ?? 'SYP')
                          : null,
                    ),
                  ),
                ],
              ),
              if (_selectedEnrollmentId != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6, right: 4),
                  child: Text(
                    'الدفعة مقفلة بعملة التسجيل — لا يمكن اختيار عملة مختلفة.',
                    style: TextStyle(
                        fontSize: Responsive.fontSize(context, 11),
                        color: AppColors.textSecondary,
                        fontFamily: 'Cairo'),
                  ),
                ),

              SizedBox(height: Responsive.spacing(context, 12)),

              // Payment Method
              DropdownButtonFormField<String>(
                initialValue: _method,
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
                    child: Text('نقداً (Cash)',
                        style: TextStyle(
                            color: AppColors.textPrimary, fontFamily: 'Cairo')),
                  ),
                  DropdownMenuItem(
                    value: 'sham_cash',
                    child: Text('شام كاش (Sham Cash)',
                        style: TextStyle(
                            color: AppColors.textPrimary, fontFamily: 'Cairo')),
                  ),
                  DropdownMenuItem(
                    value: 'hawala',
                    child: Text('حوالة (هرم)',
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

              if (isTransferOrEcash) ...[
                SizedBox(height: Responsive.spacing(context, 12)),
                TextField(
                  controller: _externalRefCtrl,
                  style: const TextStyle(color: AppColors.textPrimary, fontFamily: 'Cairo'),
                  decoration: InputDecoration(
                    labelText: _method == 'sham_cash'
                        ? 'رقم عملية شام كاش *'
                        : _method == 'hawala'
                            ? 'رقم إشعار الحوالة (الهرم) *'
                            : 'رقم التحويل البنكي *',
                    labelStyle: const TextStyle(
                        color: AppColors.gold, fontFamily: 'Cairo'),
                    prefixIcon:
                        const Icon(Icons.confirmation_number_outlined, color: AppColors.gold),
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.gold)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.gold)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: AppColors.gold, width: 2)),
                  ),
                ),
              ],

              SizedBox(height: Responsive.spacing(context, 12)),

              // Receipt number & Payment Date row
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _receiptCtrl,
                      style: const TextStyle(color: AppColors.textPrimary, fontFamily: 'Cairo'),
                      decoration: InputDecoration(
                        labelText: 'رقم الإيصال (اختياري)',
                        labelStyle: const TextStyle(
                            color: AppColors.textSecondary, fontFamily: 'Cairo', fontSize: 13),
                        prefixIcon:
                            const Icon(Icons.receipt_long, color: AppColors.gold),
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
                  ),
                  SizedBox(width: Responsive.spacing(context, 12)),
                  Expanded(
                    child: InkWell(
                      onTap: _pickDate,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.divider),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today, color: AppColors.gold, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                AppFormatters.dateOnly.format(_paidAt),
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontFamily: 'Cairo',
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              SizedBox(height: Responsive.spacing(context, 12)),

              // Notes
              TextField(
                controller: _notesCtrl,
                style: const TextStyle(color: AppColors.textPrimary, fontFamily: 'Cairo'),
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

// ─── Installment Plan Dialog ───
class _InstallmentRow {
  _InstallmentRow({required String amount, required this.dueDate})
      : amountCtrl = TextEditingController(text: amount);

  final TextEditingController amountCtrl;
  DateTime dueDate;

  double get amount =>
      double.tryParse(amountCtrl.text.replaceAll(',', '').trim()) ?? 0;

  void dispose() => amountCtrl.dispose();
}

class _InstallmentPlanDialog extends ConsumerStatefulWidget {
  final String enrollmentId;
  final String traineeName;
  final VoidCallback onSaved;

  const _InstallmentPlanDialog({
    required this.enrollmentId,
    required this.traineeName,
    required this.onSaved,
  });

  @override
  ConsumerState<_InstallmentPlanDialog> createState() =>
      _InstallmentPlanDialogState();
}

class _InstallmentPlanDialogState
    extends ConsumerState<_InstallmentPlanDialog> {
  bool _loading = true;
  bool _saving = false;
  String? _loadError;
  double _netDue = 0;
  double _netPaid = 0;
  String _currency = 'SYP';
  final List<_InstallmentRow> _rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final repo = ref.read(paymentsRepositoryProvider);
      final results = await Future.wait([
        repo.getEnrollmentFinancialSummary(widget.enrollmentId),
        repo.getEnrollmentInstallments(widget.enrollmentId),
      ]);
      final summary = results[0] as Map<String, dynamic>?;
      final installments = results[1] as List<Map<String, dynamic>>;
      if (!mounted) return;

      setState(() {
        _netDue = (summary?['net_due'] as num?)?.toDouble() ?? 0;
        _netPaid = (summary?['net_paid'] as num?)?.toDouble() ?? 0;
        _currency = (summary?['currency'] as String?) ?? 'SYP';
        for (final row in _rows) {
          row.dispose();
        }
        _rows.clear();
        if (installments.isEmpty) {
          if (_netDue > 0) {
            _rows.add(_InstallmentRow(
                amount: _netDue.toStringAsFixed(2),
                dueDate: DateTime.now()));
          }
        } else {
          for (final item in installments) {
            _rows.add(_InstallmentRow(
              amount: ((item['amount'] as num?)?.toDouble() ?? 0)
                  .toStringAsFixed(2),
              dueDate: DateTime.tryParse(item['due_date']?.toString() ?? '') ??
                  DateTime.now(),
            ));
          }
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = AppErrorHandler.friendlyMessage(e);
      });
    }
  }

  double get _assigned => _rows.fold(0.0, (sum, row) => sum + row.amount);

  bool get _valid {
    if (_rows.isEmpty) return false;
    for (final row in _rows) {
      if (row.amount <= 0) return false;
    }
    return (_assigned - _netDue).abs() < 0.01;
  }

  Future<void> _pickDate(_InstallmentRow row) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: row.dueDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.gold,
            onPrimary: Colors.black,
            surface: AppColors.cardBg,
            onSurface: AppColors.textPrimary,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => row.dueDate = picked);
    }
  }

  void _addRow() {
    final remaining = _netDue - _assigned;
    setState(() {
      _rows.add(_InstallmentRow(
        amount: remaining > 0 ? remaining.toStringAsFixed(2) : '0',
        dueDate: _rows.isEmpty
            ? DateTime.now()
            : _rows.last.dueDate.add(const Duration(days: 30)),
      ));
    });
  }

  void _removeRow(int index) {
    setState(() => _rows.removeAt(index).dispose());
  }

  Future<void> _submit() async {
    if (!_valid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('مجموع الأقساط يجب أن يطابق صافي الرسوم تماماً',
              style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final payload = _rows
          .map((row) => <String, dynamic>{
                'amount': row.amount,
                'due_date': AppFormatters.dayKey.format(row.dueDate),
              })
          .toList();
      await ref.read(paymentsRepositoryProvider).setInstallmentPlan(
            enrollmentId: widget.enrollmentId,
            installments: payload,
          );
      if (!mounted) return;
      Navigator.pop(context);
      widget.onSaved();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم حفظ خطة الأقساط وإعادة توزيع الدفعات',
              style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(AppErrorHandler.friendlyMessage(e),
                style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(Responsive.spacing(context, 24)),
          child: _loading
              ? const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                      child:
                          CircularProgressIndicator(color: AppColors.gold)),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.calendar_month,
                            color: AppColors.gold),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'خطة الأقساط — ${widget.traineeName}',
                            style: TextStyle(
                                fontSize: Responsive.fontSize(context, 17),
                                fontWeight: FontWeight.w700,
                                color: AppColors.gold,
                                fontFamily: 'Cairo'),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close,
                              color: AppColors.textSecondary),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const Divider(color: AppColors.divider),
                    if (_loadError != null)
                      Text(_loadError!,
                          style: const TextStyle(
                              color: AppColors.error,
                              fontFamily: 'Cairo'))
                    else ...[
                      _buildSummary(context),
                      SizedBox(height: Responsive.spacing(context, 12)),
                      if (_netPaid > 0)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: AppColors.gold.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            'إعادة التخطيط تعيد توزيع الدفعات المسجلة على '
                            'الأقساط تلقائياً حسب تاريخ الاستحقاق (FIFO).',
                            style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                                fontFamily: 'Cairo'),
                          ),
                        ),
                      ..._buildRows(context),
                      SizedBox(height: Responsive.spacing(context, 8)),
                      TextButton.icon(
                        onPressed: _addRow,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('إضافة قسط',
                            style: TextStyle(fontFamily: 'Cairo')),
                      ),
                      const Divider(color: AppColors.divider),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'المجموع: '
                              '${AppFormatters.amount.format(_assigned.toInt())} '
                              '${_currencySymbol(_currency)}',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: _valid
                                      ? AppColors.success
                                      : AppColors.error,
                                  fontFamily: 'Cairo'),
                            ),
                          ),
                          Text(
                            'المطلوب: '
                            '${AppFormatters.amount.format(_netDue.toInt())} '
                            '${_currencySymbol(_currency)}',
                            style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontFamily: 'Cairo'),
                          ),
                        ],
                      ),
                      SizedBox(height: Responsive.spacing(context, 20)),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(context),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.textSecondary,
                                side: const BorderSide(
                                    color: AppColors.divider),
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(12)),
                                padding: const EdgeInsets.symmetric(
                                    vertical: 14),
                              ),
                              child: const Text('إلغاء',
                                  style: TextStyle(fontFamily: 'Cairo')),
                            ),
                          ),
                          SizedBox(width: Responsive.spacing(context, 12)),
                          Expanded(
                            child: ElevatedButton(
                              onPressed:
                                  (_saving || !_valid) ? null : _submit,
                              child: _saving
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                          color: Colors.black,
                                          strokeWidth: 2))
                                  : const Text('حفظ الخطة',
                                      style:
                                          TextStyle(fontFamily: 'Cairo')),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildSummary(BuildContext context) {
    final remaining = _netDue - _netPaid;
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        _SummaryChip(
            label: 'صافي الرسوم',
            value:
                '${AppFormatters.amount.format(_netDue.toInt())} ${_currencySymbol(_currency)}'),
        _SummaryChip(
            label: 'المسدد',
            value:
                '${AppFormatters.amount.format(_netPaid.toInt())} ${_currencySymbol(_currency)}',
            color: AppColors.success),
        _SummaryChip(
            label: 'المتبقي',
            value:
                '${AppFormatters.amount.format(remaining.toInt())} ${_currencySymbol(_currency)}',
            color: remaining > 0 ? AppColors.error : AppColors.success),
      ],
    );
  }

  List<Widget> _buildRows(BuildContext context) {
    return List.generate(_rows.length, (index) {
      final row = _rows[index];
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            SizedBox(
              width: 56,
              child: Text(
                'قسط ${index + 1}',
                style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontFamily: 'Cairo'),
              ),
            ),
            Expanded(
              flex: 2,
              child: TextField(
                controller: row.amountCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(
                    color: AppColors.textPrimary, fontFamily: 'Cairo'),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'المبلغ',
                  suffixText: _currencySymbol(_currency),
                  suffixStyle: const TextStyle(
                      color: AppColors.textSecondary,
                      fontFamily: 'Cairo'),
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          const BorderSide(color: AppColors.divider)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          const BorderSide(color: AppColors.divider)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                          color: AppColors.gold, width: 2)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: InkWell(
                onTap: () => _pickDate(row),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today,
                          color: AppColors.gold, size: 14),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          AppFormatters.dateOnly.format(row.dueDate),
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 12,
                              fontFamily: 'Cairo'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  color: AppColors.error, size: 18),
              onPressed: _rows.length > 1 ? () => _removeRow(index) : null,
            ),
          ],
        ),
      );
    });
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _SummaryChip({
    required this.label,
    required this.value,
    this.color = AppColors.textPrimary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ',
              style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  fontFamily: 'Cairo')),
          Text(value,
              style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Cairo')),
        ],
      ),
    );
  }
}

// ─── Refund Dialog (admin only) ───
class _RefundDialog extends ConsumerStatefulWidget {
  final String paymentId;
  final double paymentAmount;
  final double refundedAmount;
  final String currency;
  final String traineeName;
  final VoidCallback onSaved;

  const _RefundDialog({
    required this.paymentId,
    required this.paymentAmount,
    required this.refundedAmount,
    required this.currency,
    required this.traineeName,
    required this.onSaved,
  });

  @override
  ConsumerState<_RefundDialog> createState() => _RefundDialogState();
}

class _RefundDialogState extends ConsumerState<_RefundDialog> {
  final _amountCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  bool _saving = false;

  double get _maxRefundable =>
      widget.paymentAmount - widget.refundedAmount;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount =
        double.tryParse(_amountCtrl.text.replaceAll(',', '').trim());
    final reason = _reasonCtrl.text.trim();

    if (amount == null || amount <= 0 || amount > _maxRefundable + 0.001) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'أدخل مبلغاً صحيحاً لا يتجاوز المتبقي القابل للاسترداد',
              style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    if (reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('سبب الاسترداد إلزامي',
              style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(paymentsRepositoryProvider).addRefund(
            paymentId: widget.paymentId,
            amount: amount,
            reason: reason,
          );
      if (!mounted) return;
      Navigator.pop(context);
      widget.onSaved();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تسجيل الاسترداد بنجاح',
              style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(AppErrorHandler.friendlyMessage(e),
                style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxRefundable = _maxRefundable;
    final sym = _currencySymbol(widget.currency);

    return Dialog(
      backgroundColor: AppColors.cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(Responsive.spacing(context, 24)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.undo, color: AppColors.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'استرداد دفعة — ${widget.traineeName}',
                      style: TextStyle(
                          fontSize: Responsive.fontSize(context, 17),
                          fontWeight: FontWeight.w700,
                          color: AppColors.error,
                          fontFamily: 'Cairo'),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close,
                        color: AppColors.textSecondary),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(color: AppColors.divider),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _SummaryChip(
                      label: 'الدفعة',
                      value:
                          '${AppFormatters.amount.format(widget.paymentAmount.toInt())} $sym'),
                  _SummaryChip(
                      label: 'مسترجع سابقاً',
                      value:
                          '${AppFormatters.amount.format(widget.refundedAmount.toInt())} $sym',
                      color: AppColors.error),
                  _SummaryChip(
                      label: 'القابل للاسترداد',
                      value:
                          '${AppFormatters.amount.format(maxRefundable.toInt())} $sym',
                      color: AppColors.gold),
                ],
              ),
              SizedBox(height: Responsive.spacing(context, 16)),
              if (maxRefundable <= 0)
                const Text(
                  'تم استرداد كامل قيمة الدفعة — لا يوجد مبلغ متبقٍ.',
                  style: TextStyle(
                      color: AppColors.error, fontFamily: 'Cairo'),
                )
              else ...[
                TextField(
                  controller: _amountCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontFamily: 'Cairo'),
                  decoration: InputDecoration(
                    labelText: 'مبلغ الاسترداد *',
                    labelStyle: const TextStyle(
                        color: AppColors.textSecondary,
                        fontFamily: 'Cairo'),
                    prefixIcon:
                        const Icon(Icons.attach_money, color: AppColors.gold),
                    suffixText: sym,
                    suffixStyle: const TextStyle(
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
                        borderSide:
                            const BorderSide(color: AppColors.gold, width: 2)),
                  ),
                ),
                SizedBox(height: Responsive.spacing(context, 12)),
                TextField(
                  controller: _reasonCtrl,
                  maxLines: 2,
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontFamily: 'Cairo'),
                  decoration: InputDecoration(
                    labelText: 'سبب الاسترداد *',
                    labelStyle: const TextStyle(
                        color: AppColors.textSecondary,
                        fontFamily: 'Cairo'),
                    prefixIcon:
                        const Icon(Icons.notes, color: AppColors.gold),
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
                        borderSide:
                            const BorderSide(color: AppColors.gold, width: 2)),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'الاسترداد متاح لمدير المركز فقط، وسيُعاد توزيع الدفعة '
                  'على الأقساط تلقائياً بعد الاسترداد.',
                  style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                      fontFamily: 'Cairo'),
                ),
              ],
              SizedBox(height: Responsive.spacing(context, 20)),
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
                      onPressed: (_saving || maxRefundable <= 0)
                          ? null
                          : _submit,
                      child: _saving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.black, strokeWidth: 2))
                          : const Text('تأكيد الاسترداد',
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

// ─── Fee Adjustment Dialog (admin only) ───
class _FeeAdjustmentDialog extends ConsumerStatefulWidget {
  final String enrollmentId;
  final String traineeName;
  final VoidCallback onSaved;

  const _FeeAdjustmentDialog({
    required this.enrollmentId,
    required this.traineeName,
    required this.onSaved,
  });

  @override
  ConsumerState<_FeeAdjustmentDialog> createState() =>
      _FeeAdjustmentDialogState();
}

class _FeeAdjustmentDialogState extends ConsumerState<_FeeAdjustmentDialog> {
  final _amountCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  bool _increase = true;
  bool _saving = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final value =
        double.tryParse(_amountCtrl.text.replaceAll(',', '').trim());
    final reason = _reasonCtrl.text.trim();

    if (value == null || value <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('أدخل مبلغ تعديل صحيحاً أكبر من صفر',
              style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    if (reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('سبب تعديل الرسوم إلزامي',
              style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(paymentsRepositoryProvider).addFeeAdjustment(
            enrollmentId: widget.enrollmentId,
            amount: _increase ? value : -value,
            reason: reason,
          );
      if (!mounted) return;
      Navigator.pop(context);
      widget.onSaved();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تسجيل تعديل الرسوم وتحديث خطة الأقساط',
              style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(AppErrorHandler.friendlyMessage(e),
                style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(Responsive.spacing(context, 24)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.tune, color: AppColors.gold),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'تعديل الرسوم — ${widget.traineeName}',
                      style: TextStyle(
                          fontSize: Responsive.fontSize(context, 17),
                          fontWeight: FontWeight.w700,
                          color: AppColors.gold,
                          fontFamily: 'Cairo'),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close,
                        color: AppColors.textSecondary),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(color: AppColors.divider),
              const Text(
                'سيتم تعديل صافي الرسوم وخطة الأقساط معاً بشكل تلقائي.',
                style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                    fontFamily: 'Cairo'),
              ),
              SizedBox(height: Responsive.spacing(context, 12)),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('زيادة الرسوم',
                        style: TextStyle(fontFamily: 'Cairo')),
                    selected: _increase,
                    selectedColor: AppColors.gold.withValues(alpha: 0.2),
                    onSelected: (_) => setState(() => _increase = true),
                  ),
                  ChoiceChip(
                    label: const Text('خصم إضافي',
                        style: TextStyle(fontFamily: 'Cairo')),
                    selected: !_increase,
                    selectedColor: AppColors.error.withValues(alpha: 0.2),
                    onSelected: (_) => setState(() => _increase = false),
                  ),
                ],
              ),
              SizedBox(height: Responsive.spacing(context, 12)),
              TextField(
                controller: _amountCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(
                    color: AppColors.textPrimary, fontFamily: 'Cairo'),
                decoration: InputDecoration(
                  labelText: 'مبلغ التعديل *',
                  labelStyle: const TextStyle(
                      color: AppColors.textSecondary, fontFamily: 'Cairo'),
                  prefixIcon: const Icon(Icons.attach_money,
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
              SizedBox(height: Responsive.spacing(context, 12)),
              TextField(
                controller: _reasonCtrl,
                maxLines: 2,
                style: const TextStyle(
                    color: AppColors.textPrimary, fontFamily: 'Cairo'),
                decoration: InputDecoration(
                  labelText: 'سبب التعديل *',
                  labelStyle: const TextStyle(
                      color: AppColors.textSecondary, fontFamily: 'Cairo'),
                  prefixIcon: const Icon(Icons.notes, color: AppColors.gold),
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
              const SizedBox(height: 8),
              const Text(
                'الزيادة تُضاف إلى آخر قسط، والخصم يُقتطع من الأقساط غير '
                'المسددة. القيود الصادرة لا تُعدّل — تُعالج بقيد معاكس.',
                style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                    fontFamily: 'Cairo'),
              ),
              SizedBox(height: Responsive.spacing(context, 20)),
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
                      onPressed: _saving ? null : _submit,
                      child: _saving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.black, strokeWidth: 2))
                          : const Text('حفظ التعديل',
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
String _currencySymbol(String? currency) => currency == 'USD' ? r'$' : 'ل.س';

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
