import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/account_models.dart';

class AccountLedgerQueryResult {
  final List<AccountLedgerEntry> entries;
  final int totalCount;
  final int currentPage;
  final int pageSize;

  const AccountLedgerQueryResult({
    required this.entries,
    required this.totalCount,
    required this.currentPage,
    required this.pageSize,
  });

  int get totalPages => (totalCount / pageSize).ceil();
  bool get hasNextPage => currentPage < totalPages;
  bool get hasPrevPage => currentPage > 1;
}

class AccountsRepository {
  final SupabaseClient _client;

  AccountsRepository([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  /// جلب أرصدة الحسابات المشتقة من view account_balances_v
  Future<List<FinancialAccountBalance>> getBalances() async {
    final response = await _client
        .from('account_balances_v')
        .select()
        .order('currency')
        .order('account_type');

    return (response as List)
        .map((row) =>
            FinancialAccountBalance.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  /// جلب دفتر الحركات مفلتراً ومقسماً لصفحات عبر account_ledger_v
  Future<AccountLedgerQueryResult> getLedger(AccountFilterParams params) async {
    DateTime? startUtc;
    DateTime? endUtc;

    // البداية والنهاية بتوقيت الجهاز المحلي ثم تحويلهما إلى UTC، حتى يطابق
    // اختيار "اليوم" في دمشق حدود الحركات الفعلية بدل منتصف الليل UTC.
    if (params.fromDate != null) {
      startUtc = DateTime(
        params.fromDate!.year,
        params.fromDate!.month,
        params.fromDate!.day,
      ).toUtc();
    }

    if (params.toDate != null) {
      endUtc = DateTime(
        params.toDate!.year,
        params.toDate!.month,
        params.toDate!.day,
        23,
        59,
        59,
        999,
      ).toUtc();
    }

    // 1. حساب الإجمالي
    var countQuery = _client.from('account_ledger_v').count(CountOption.exact);

    if (params.accountId != null &&
        params.accountId != 'الكل' &&
        params.accountId!.isNotEmpty) {
      countQuery = countQuery.eq('account_id', params.accountId!);
    }

    if (params.sourceType != null &&
        params.sourceType != 'الكل' &&
        params.sourceType!.isNotEmpty) {
      countQuery = countQuery.eq('source_type', params.sourceType!);
    }

    if (startUtc != null) {
      countQuery = countQuery.gte('occurred_at', startUtc.toIso8601String());
    }

    if (endUtc != null) {
      countQuery = countQuery.lte('occurred_at', endUtc.toIso8601String());
    }

    final totalCount = await countQuery;

    // 2. جلب الصفحة المحددة
    final offset = (params.page - 1) * params.pageSize;
    final toIndex = offset + params.pageSize - 1;

    var dataQuery = _client.from('account_ledger_v').select();

    if (params.accountId != null &&
        params.accountId != 'الكل' &&
        params.accountId!.isNotEmpty) {
      dataQuery = dataQuery.eq('account_id', params.accountId!);
    }

    if (params.sourceType != null &&
        params.sourceType != 'الكل' &&
        params.sourceType!.isNotEmpty) {
      dataQuery = dataQuery.eq('source_type', params.sourceType!);
    }

    if (startUtc != null) {
      dataQuery = dataQuery.gte('occurred_at', startUtc.toIso8601String());
    }

    if (endUtc != null) {
      dataQuery = dataQuery.lte('occurred_at', endUtc.toIso8601String());
    }

    final response = await dataQuery
        .order('occurred_at', ascending: false)
        .order('id', ascending: false)
        .range(offset, toIndex);

    final entries = (response as List)
        .map((row) => AccountLedgerEntry.fromMap(row as Map<String, dynamic>))
        .toList();

    return AccountLedgerQueryResult(
      entries: entries,
      totalCount: totalCount,
      currentPage: params.page,
      pageSize: params.pageSize,
    );
  }

  /// تنفيذ تحويل داخلي عبر RPC transfer_between_accounts
  Future<String> transferBetweenAccounts({
    required String fromAccountId,
    required String toAccountId,
    required double amount,
    String? notes,
  }) async {
    final response = await _client.rpc(
      'transfer_between_accounts',
      params: {
        'p_from_account_id': fromAccountId,
        'p_to_account_id': toAccountId,
        'p_amount': amount,
        'p_notes': notes,
      },
    );
    return response.toString();
  }
}

final accountsRepositoryProvider = Provider<AccountsRepository>((ref) {
  return AccountsRepository();
});

final accountBalancesProvider =
    FutureProvider<List<FinancialAccountBalance>>((ref) async {
  return ref.watch(accountsRepositoryProvider).getBalances();
});

class AccountFilterNotifier extends Notifier<AccountFilterParams> {
  @override
  AccountFilterParams build() => const AccountFilterParams();

  void updateParams(
      AccountFilterParams Function(AccountFilterParams) updater) {
    state = updater(state);
  }
}

final accountFilterParamsProvider =
    NotifierProvider<AccountFilterNotifier, AccountFilterParams>(
  AccountFilterNotifier.new,
);

final accountLedgerProvider =
    FutureProvider<AccountLedgerQueryResult>((ref) async {
  final params = ref.watch(accountFilterParamsProvider);
  return ref.watch(accountsRepositoryProvider).getLedger(params);
});
