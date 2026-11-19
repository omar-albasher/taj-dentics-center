import 'package:flutter/material.dart';

class FinancialAccountBalance {
  final String accountId;
  final String nameAr;
  final String? nameEn;
  final String accountType; // cash, bank, wallet
  final String currency; // SYP, USD
  final bool isActive;
  final double balance;
  final double totalInflow;
  final double totalOutflow;
  final int transactionCount;
  final DateTime? lastTransactionAt;

  const FinancialAccountBalance({
    required this.accountId,
    required this.nameAr,
    this.nameEn,
    required this.accountType,
    required this.currency,
    required this.isActive,
    required this.balance,
    required this.totalInflow,
    required this.totalOutflow,
    required this.transactionCount,
    this.lastTransactionAt,
  });

  factory FinancialAccountBalance.fromMap(Map<String, dynamic> map) {
    return FinancialAccountBalance(
      accountId: map['account_id']?.toString() ?? '',
      nameAr: map['name_ar']?.toString() ?? '',
      nameEn: map['name_en']?.toString(),
      accountType: map['account_type']?.toString() ?? 'cash',
      currency: map['currency']?.toString() ?? 'SYP',
      isActive: map['is_active'] == true,
      balance: (map['balance'] as num?)?.toDouble() ?? 0.0,
      totalInflow: (map['total_inflow'] as num?)?.toDouble() ?? 0.0,
      totalOutflow: (map['total_outflow'] as num?)?.toDouble() ?? 0.0,
      transactionCount: (map['transaction_count'] as num?)?.toInt() ?? 0,
      lastTransactionAt: map['last_transaction_at'] != null
          ? DateTime.tryParse(map['last_transaction_at'].toString())
          : null,
    );
  }

  String get accountTypeLabel {
    switch (accountType) {
      case 'cash':
        return 'صندوق نقدي';
      case 'bank':
        return 'حساب بنكي';
      case 'wallet':
        return 'محفظة إلكترونية';
      default:
        return accountType;
    }
  }

  IconData get typeIcon {
    switch (accountType) {
      case 'cash':
        return Icons.point_of_sale_outlined;
      case 'bank':
        return Icons.account_balance_outlined;
      case 'wallet':
        return Icons.account_balance_wallet_outlined;
      default:
        return Icons.account_balance_outlined;
    }
  }
}

class AccountLedgerEntry {
  final String id;
  final String accountId;
  final String accountNameAr;
  final String? accountNameEn;
  final String accountType;
  final String currency;
  final String direction; // inflow, outflow
  final double amount;
  final String sourceType; // payment, expense, refund, transfer, adjustment
  final String? sourceId;
  final String? transferGroup;
  final String derivation; // manual, auto_method, auto_expense_cash, backfill, admin_attested
  final DateTime occurredAt;
  final String? notes;
  final String? createdBy;
  final String? performedByName;
  final DateTime createdAt;

  const AccountLedgerEntry({
    required this.id,
    required this.accountId,
    required this.accountNameAr,
    this.accountNameEn,
    required this.accountType,
    required this.currency,
    required this.direction,
    required this.amount,
    required this.sourceType,
    this.sourceId,
    this.transferGroup,
    required this.derivation,
    required this.occurredAt,
    this.notes,
    this.createdBy,
    this.performedByName,
    required this.createdAt,
  });

  factory AccountLedgerEntry.fromMap(Map<String, dynamic> map) {
    return AccountLedgerEntry(
      id: map['id']?.toString() ?? '',
      accountId: map['account_id']?.toString() ?? '',
      accountNameAr: map['account_name_ar']?.toString() ?? '',
      accountNameEn: map['account_name_en']?.toString(),
      accountType: map['account_type']?.toString() ?? 'cash',
      currency: map['currency']?.toString() ?? 'SYP',
      direction: map['direction']?.toString() ?? 'inflow',
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      sourceType: map['source_type']?.toString() ?? 'payment',
      sourceId: map['source_id']?.toString(),
      transferGroup: map['transfer_group']?.toString(),
      derivation: map['derivation']?.toString() ?? 'manual',
      occurredAt: DateTime.tryParse(map['occurred_at']?.toString() ?? '') ??
          DateTime.now(),
      notes: map['notes']?.toString(),
      createdBy: map['created_by']?.toString(),
      performedByName: map['performed_by_name']?.toString(),
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  String get sourceTypeLabel {
    switch (sourceType) {
      case 'payment':
        return 'دفعة متدرب';
      case 'expense':
        return 'مصروف تشغيلي';
      case 'refund':
        return 'استرداد دفعة';
      case 'transfer':
        return 'تحويل داخلي';
      case 'adjustment':
        return 'قيد تسوية';
      default:
        return sourceType;
    }
  }

  String get derivationLabel {
    switch (derivation) {
      case 'manual':
        return 'يدوي';
      case 'auto_method':
        return 'تلقائي (طريقة الدفع)';
      case 'auto_expense_cash':
        return 'تلقائي (صندوق)';
      case 'backfill':
        return 'ترحيل سابق';
      case 'admin_attested':
        return 'تأكيد إداري';
      default:
        return derivation;
    }
  }
}

class AccountFilterParams {
  final String? accountId;
  final String? sourceType;
  final DateTime? fromDate;
  final DateTime? toDate;
  final int page;
  final int pageSize;

  const AccountFilterParams({
    this.accountId,
    this.sourceType,
    this.fromDate,
    this.toDate,
    this.page = 1,
    this.pageSize = 25,
  });

  AccountFilterParams copyWith({
    String? accountId,
    bool clearAccountId = false,
    String? sourceType,
    bool clearSourceType = false,
    DateTime? fromDate,
    bool clearFromDate = false,
    DateTime? toDate,
    bool clearToDate = false,
    int? page,
    int? pageSize,
  }) {
    return AccountFilterParams(
      accountId: clearAccountId ? null : (accountId ?? this.accountId),
      sourceType: clearSourceType ? null : (sourceType ?? this.sourceType),
      fromDate: clearFromDate ? null : (fromDate ?? this.fromDate),
      toDate: clearToDate ? null : (toDate ?? this.toDate),
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AccountFilterParams &&
          runtimeType == other.runtimeType &&
          accountId == other.accountId &&
          sourceType == other.sourceType &&
          fromDate == other.fromDate &&
          toDate == other.toDate &&
          page == other.page &&
          pageSize == other.pageSize;

  @override
  int get hashCode =>
      accountId.hashCode ^
      sourceType.hashCode ^
      fromDate.hashCode ^
      toDate.hashCode ^
      page.hashCode ^
      pageSize.hashCode;
}
