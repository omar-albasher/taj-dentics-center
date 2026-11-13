import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuditQueryResult {
  final List<Map<String, dynamic>> logs;
  final int totalCount;
  final int currentPage;
  final int pageSize;

  const AuditQueryResult({
    required this.logs,
    required this.totalCount,
    required this.currentPage,
    required this.pageSize,
  });

  int get totalPages => (totalCount / pageSize).ceil();
  bool get hasNextPage => currentPage < totalPages;
  bool get hasPrevPage => currentPage > 1;
}

class AuditFilterParams {
  final int page;
  final int pageSize;
  final String? tableName;
  final String? operation;
  final DateTime? fromDate;
  final DateTime? toDate;

  const AuditFilterParams({
    this.page = 1,
    this.pageSize = 25,
    this.tableName,
    this.operation,
    this.fromDate,
    this.toDate,
  });

  AuditFilterParams copyWith({
    int? page,
    int? pageSize,
    String? tableName,
    String? operation,
    DateTime? fromDate,
    DateTime? toDate,
    bool clearFromDate = false,
    bool clearToDate = false,
  }) {
    return AuditFilterParams(
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
      tableName: tableName ?? this.tableName,
      operation: operation ?? this.operation,
      fromDate: clearFromDate ? null : (fromDate ?? this.fromDate),
      toDate: clearToDate ? null : (toDate ?? this.toDate),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuditFilterParams &&
          runtimeType == other.runtimeType &&
          page == other.page &&
          pageSize == other.pageSize &&
          tableName == other.tableName &&
          operation == other.operation &&
          fromDate == other.fromDate &&
          toDate == other.toDate;

  @override
  int get hashCode => Object.hash(
        page,
        pageSize,
        tableName,
        operation,
        fromDate,
        toDate,
      );
}

class AuditRepository {
  final SupabaseClient _client;

  AuditRepository(this._client);

  static const List<String> defaultTrackedTables = [
    'payments',
    'enrollments',
    'expenses',
    'payment_refunds',
    'fee_adjustments',
    'enrollment_withdrawals',
    'course_materials',
    'installment_schedule',
    'payment_allocations',
  ];

  Future<AuditQueryResult> fetchLogs(AuditFilterParams params) async {
    final fromIndex = (params.page - 1) * params.pageSize;
    final toIndex = fromIndex + params.pageSize - 1;

    DateTime? startUtc;
    DateTime? endUtc;
    if (params.fromDate != null) {
      startUtc = DateTime(
        params.fromDate!.year,
        params.fromDate!.month,
        params.fromDate!.day,
        0,
        0,
        0,
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

    // Build count query
    var countQuery = _client.from('audit_log').count(CountOption.exact);

    if (params.tableName != null &&
        params.tableName != 'الكل' &&
        params.tableName!.isNotEmpty) {
      countQuery = countQuery.eq('table_name', params.tableName!);
    }

    if (params.operation != null &&
        params.operation != 'الكل' &&
        params.operation!.isNotEmpty) {
      countQuery = countQuery.eq('operation', params.operation!);
    }

    if (startUtc != null) {
      countQuery = countQuery.gte('performed_at', startUtc.toIso8601String());
    }

    if (endUtc != null) {
      countQuery = countQuery.lte('performed_at', endUtc.toIso8601String());
    }

    // Build data query
    var dataQuery = _client.from('audit_log').select('''
        id,
        table_name,
        operation,
        record_id,
        performed_at,
        performed_by,
        actor_source,
        actor_role,
        old_data,
        new_data,
        users!audit_log_performed_by_fkey(full_name, email)
      ''');

    if (params.tableName != null &&
        params.tableName != 'الكل' &&
        params.tableName!.isNotEmpty) {
      dataQuery = dataQuery.eq('table_name', params.tableName!);
    }

    if (params.operation != null &&
        params.operation != 'الكل' &&
        params.operation!.isNotEmpty) {
      dataQuery = dataQuery.eq('operation', params.operation!);
    }

    if (startUtc != null) {
      dataQuery = dataQuery.gte('performed_at', startUtc.toIso8601String());
    }

    if (endUtc != null) {
      dataQuery = dataQuery.lte('performed_at', endUtc.toIso8601String());
    }

    final totalCount = await countQuery;
    final rawData = await dataQuery
        .order('performed_at', ascending: false)
        .order('id', ascending: false)
        .range(fromIndex, toIndex);
    final logs = List<Map<String, dynamic>>.from(rawData);

    return AuditQueryResult(
      logs: logs,
      totalCount: totalCount,
      currentPage: params.page,
      pageSize: params.pageSize,
    );
  }

  /// جلب ما يصل إلى maxLimit سجلاً بحلقات مصفّحة (1000 لكل صفحة) لتفادي سقف Supabase Max Rows
  Future<List<Map<String, dynamic>>> fetchLogsForExport(
    AuditFilterParams params, {
    int maxLimit = 5000,
  }) async {
    final List<Map<String, dynamic>> allLogs = [];
    const chunkSize = 1000;
    int offset = 0;

    DateTime? startUtc;
    DateTime? endUtc;
    if (params.fromDate != null) {
      startUtc = DateTime(
        params.fromDate!.year,
        params.fromDate!.month,
        params.fromDate!.day,
        0,
        0,
        0,
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

    while (allLogs.length < maxLimit) {
      final currentChunk = (maxLimit - allLogs.length).clamp(1, chunkSize);
      final toIndex = offset + currentChunk - 1;

      var query = _client.from('audit_log').select('''
          id,
          table_name,
          operation,
          record_id,
          performed_at,
          performed_by,
          actor_source,
          actor_role,
          old_data,
          new_data,
          users!audit_log_performed_by_fkey(full_name, email)
        ''');

      if (params.tableName != null &&
          params.tableName != 'الكل' &&
          params.tableName!.isNotEmpty) {
        query = query.eq('table_name', params.tableName!);
      }

      if (params.operation != null &&
          params.operation != 'الكل' &&
          params.operation!.isNotEmpty) {
        query = query.eq('operation', params.operation!);
      }

      if (startUtc != null) {
        query = query.gte('performed_at', startUtc.toIso8601String());
      }

      if (endUtc != null) {
        query = query.lte('performed_at', endUtc.toIso8601String());
      }

      final chunk = await query
          .order('performed_at', ascending: false)
          .order('id', ascending: false)
          .range(offset, toIndex);

      final chunkList = List<Map<String, dynamic>>.from(chunk);
      if (chunkList.isEmpty) break;

      allLogs.addAll(chunkList);
      offset += chunkList.length;
    }

    return allLogs;
  }
}

final auditRepositoryProvider = Provider<AuditRepository>((ref) {
  return AuditRepository(Supabase.instance.client);
});

class AuditFilterNotifier extends Notifier<AuditFilterParams> {
  @override
  AuditFilterParams build() => const AuditFilterParams();

  void updateParams(AuditFilterParams Function(AuditFilterParams) updater) {
    state = updater(state);
  }
}

final auditFilterParamsProvider =
    NotifierProvider<AuditFilterNotifier, AuditFilterParams>(
  AuditFilterNotifier.new,
);

final auditLogsPaginatedProvider =
    FutureProvider<AuditQueryResult>((ref) async {
  final params = ref.watch(auditFilterParamsProvider);
  return ref.watch(auditRepositoryProvider).fetchLogs(params);
});
