import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/app_formatters.dart';
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
                  Text('خطأ: $e',
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
  final Function(BuildContext, {String? enrollmentId, String? traineeName})
      onAddPayment;

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
                        SizedBox(height: Responsive.spacing(context, 12)),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => widget.onAddPayment(
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
          ),
        ),
      ],
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
    if (_selectedEnrollmentId == null || _amountCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى تعبئة الحقول الإلزامية', style: TextStyle(fontFamily: 'Cairo')),
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
        SnackBar(content: Text('خطأ: $e', style: const TextStyle(fontFamily: 'Cairo')), backgroundColor: AppColors.error),
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
                  error: (e, _) => Text('خطأ: $e', style: const TextStyle(color: AppColors.error, fontFamily: 'Cairo')),
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
                    onChanged: (v) =>
                        setState(() => _selectedEnrollmentId = v),
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
                          child: Text(r'$',
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
