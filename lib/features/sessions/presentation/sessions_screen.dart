import 'package:flutter/material.dart';
import 'package:admin_dashboard/core/widgets/app_error_widget.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/responsive.dart';
import '../data/admin_sessions_repository.dart';
import '../domain/session_model.dart';
import '../../courses/data/courses_repository.dart';

class SessionsScreen extends ConsumerStatefulWidget {
  const SessionsScreen({super.key});

  @override
  ConsumerState<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends ConsumerState<SessionsScreen>
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
            Row(
              children: [
                Text(
                  'الجلسات',
                  style: TextStyle(
                    fontSize: Responsive.fontSize(context, 28),
                    fontWeight: FontWeight.w900,
                    color: AppColors.gold,
                    fontFamily: 'Cairo',
                  ),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: () => _showCreateSessionDialog(context),
                  icon: const Icon(Icons.add),
                  label: const Text('جلسة جديدة',
                      style: TextStyle(fontFamily: 'Cairo')),
                ),
              ],
            ),
            SizedBox(height: Responsive.spacing(context, 16)),
            TabBar(
              controller: _tabController,
              labelColor: AppColors.gold,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.gold,
              labelStyle: const TextStyle(
                  fontFamily: 'Cairo', fontWeight: FontWeight.w700),
              tabs: const [
                Tab(text: 'المفتوحة'),
                Tab(text: 'المجدولة'),
                Tab(text: 'المغلقة'),
              ],
            ),
            SizedBox(height: Responsive.spacing(context, 16)),
            Expanded(
              child: Consumer(
                builder: (context, ref, _) {
                  final sessionsAsync = ref.watch(adminSessionsProvider);
                  return sessionsAsync.when(
                    loading: () => const Center(
                      child: CircularProgressIndicator(color: AppColors.gold),
                    ),
                    error: (e, _) => AppErrorWidget(
                      message: 'خطأ: $e',
                      onRetry: () => ref.invalidate(adminSessionsProvider),
                    ),
                    data: (sessions) {
                      final open = sessions.where((s) => s.isOpen).toList();
                      final scheduled =
                          sessions.where((s) => s.isScheduled).toList();
                      final closed = sessions.where((s) => s.isClosed).toList();

                      return TabBarView(
                        controller: _tabController,
                        children: [
                          _SessionsList(
                            sessions: open,
                            emptyMessage: 'لا توجد جلسات مفتوحة',
                          ),
                          _SessionsList(
                            sessions: scheduled,
                            emptyMessage: 'لا توجد جلسات مجدولة',
                          ),
                          _SessionsList(
                            sessions: closed,
                            emptyMessage: 'لا توجد جلسات مغلقة',
                          ),
                        ],
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

  void _showCreateSessionDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => _CreateSessionDialog(
        onCreated: () => ref.invalidate(adminSessionsProvider),
      ),
    );
  }
}

class _SessionsList extends ConsumerWidget {
  final List<AdminSessionModel> sessions;
  final String emptyMessage;

  const _SessionsList({
    required this.sessions,
    required this.emptyMessage,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (sessions.isEmpty) {
      return Center(
        child: Text(emptyMessage,
            style: TextStyle(
                color: AppColors.textSecondary,
                fontFamily: 'Cairo',
                fontSize: Responsive.fontSize(context, 16))),
      );
    }

    return ListView.separated(
      itemCount: sessions.length,
      separatorBuilder: (_, __) =>
          SizedBox(height: Responsive.spacing(context, 8)),
      itemBuilder: (context, index) {
        return _SessionCard(
          session: sessions[index],
          onRefresh: () => ref.invalidate(adminSessionsProvider),
        );
      },
    );
  }
}

class _SessionCard extends ConsumerStatefulWidget {
  final AdminSessionModel session;
  final VoidCallback onRefresh;

  const _SessionCard({required this.session, required this.onRefresh});

  @override
  ConsumerState<_SessionCard> createState() => _SessionCardState();
}

class _SessionCardState extends ConsumerState<_SessionCard> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('yyyy/MM/dd — HH:mm');

    Color statusColor;
    String statusLabel;
    switch (widget.session.status) {
      case 'open':
        statusColor = AppColors.success;
        statusLabel = 'مفتوحة';
        break;
      case 'closed':
        statusColor = AppColors.error;
        statusLabel = 'مغلقة';
        break;
      default:
        statusColor = AppColors.warning;
        statusLabel = 'مجدولة';
    }

    return Container(
      padding: EdgeInsets.all(Responsive.spacing(context, 16)),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    '#${widget.session.sessionNumber}',
                    style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'Cairo'),
                  ),
                ),
              ),
              SizedBox(width: Responsive.spacing(context, 12)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.session.courseName,
                        style: TextStyle(
                            fontSize: Responsive.fontSize(context, 15),
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                            fontFamily: 'Cairo')),
                    Text(widget.session.cohortName,
                        style: TextStyle(
                            fontSize: Responsive.fontSize(context, 12),
                            color: AppColors.textSecondary,
                            fontFamily: 'Cairo')),
                    Text(fmt.format(widget.session.scheduledAt),
                        style: TextStyle(
                            fontSize: Responsive.fontSize(context, 11),
                            color: AppColors.textSecondary,
                            fontFamily: 'Cairo')),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(statusLabel,
                    style: TextStyle(
                        color: statusColor,
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),

          SizedBox(height: Responsive.spacing(context, 12)),

          // Actions
          Row(
            children: [
              if (widget.session.isScheduled)
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : () => _openSession(context),
                    icon: _isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.play_arrow, size: 18),
                    label: const Text('فتح الجلسة',
                        style: TextStyle(fontFamily: 'Cairo')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                    ),
                  ),
                ),
              if (widget.session.isOpen) ...[
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : () => _closeSession(context),
                    icon: _isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.stop, size: 18),
                    label: const Text('إغلاق الجلسة',
                        style: TextStyle(fontFamily: 'Cairo')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.error,
                    ),
                  ),
                ),
                SizedBox(width: Responsive.spacing(context, 8)),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        _isLoading ? null : () => _showAttendance(context),
                    icon: const Icon(Icons.people_outline,
                        color: AppColors.gold, size: 18),
                    label: const Text('الحاضرون',
                        style: TextStyle(
                            color: AppColors.gold, fontFamily: 'Cairo')),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.gold),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
              if (widget.session.isClosed)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showAttendance(context),
                    icon: const Icon(Icons.people_outline,
                        color: AppColors.gold, size: 18),
                    label: const Text('عرض الحاضرين',
                        style: TextStyle(
                            color: AppColors.gold, fontFamily: 'Cairo')),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.gold),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openSession(BuildContext context) async {
    setState(() => _isLoading = true);
    try {
      await ref
          .read(adminSessionsRepositoryProvider)
          .openSession(widget.session.id);
      widget.onRefresh();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم فتح الجلسة بنجاح ✓'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _closeSession(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.cardBg,
        title: const Text('إغلاق الجلسة',
            style: TextStyle(color: AppColors.gold, fontFamily: 'Cairo')),
        content: const Text(
            'هل أنت متأكد من إغلاق الجلسة؟ لن يتمكن المتدربون من تسجيل حضورهم بعد الإغلاق.',
            style:
                TextStyle(color: AppColors.textSecondary, fontFamily: 'Cairo')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء',
                style: TextStyle(
                    color: AppColors.textSecondary, fontFamily: 'Cairo')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('إغلاق', style: TextStyle(fontFamily: 'Cairo')),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      await ref
          .read(adminSessionsRepositoryProvider)
          .closeSession(widget.session.id);
      widget.onRefresh();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إغلاق الجلسة بنجاح ✓'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showAttendance(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => _AttendanceDialog(sessionId: widget.session.id),
    );
  }
}

class _AttendanceDialog extends ConsumerWidget {
  final String sessionId;
  const _AttendanceDialog({required this.sessionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attendanceAsync = ref.watch(sessionAttendanceProvider(sessionId));

    return Dialog(
      backgroundColor: AppColors.cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 500),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.people, color: AppColors.gold),
                  const SizedBox(width: 8),
                  const Text('قائمة الحاضرين',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.gold,
                          fontFamily: 'Cairo')),
                  const Spacer(),
                  IconButton(
                    icon:
                        const Icon(Icons.close, color: AppColors.textSecondary),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(color: AppColors.divider),
              Expanded(
                child: attendanceAsync.when(
                  loading: () => const Center(
                    child: CircularProgressIndicator(color: AppColors.gold),
                  ),
                  error: (e, _) => Center(
                    child: Text('خطأ: $e',
                        style: const TextStyle(
                            color: AppColors.error, fontFamily: 'Cairo')),
                  ),
                  data: (list) {
                    if (list.isEmpty) {
                      return const Center(
                        child: Text('لا يوجد حاضرون',
                            style: TextStyle(
                                color: AppColors.textSecondary,
                                fontFamily: 'Cairo')),
                      );
                    }

                    return ListView.separated(
                      itemCount: list.length,
                      separatorBuilder: (_, __) =>
                          const Divider(color: AppColors.divider, height: 1),
                      itemBuilder: (context, index) {
                        final a = list[index];
                        final date = DateTime.tryParse(a['recorded_at'] ?? '');

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor:
                                AppColors.success.withValues(alpha: 0.15),
                            child: Text('${index + 1}',
                                style: const TextStyle(
                                    color: AppColors.success,
                                    fontWeight: FontWeight.w700,
                                    fontFamily: 'Cairo')),
                          ),
                          title: Text(a['full_name'] ?? '',
                              style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontFamily: 'Cairo',
                                  fontWeight: FontWeight.w700)),
                          trailing: date != null
                              ? Text(
                                  DateFormat('HH:mm').format(date),
                                  style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontFamily: 'Cairo'),
                                )
                              : null,
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CreateSessionDialog extends ConsumerStatefulWidget {
  final VoidCallback onCreated;
  const _CreateSessionDialog({required this.onCreated});

  @override
  ConsumerState<_CreateSessionDialog> createState() =>
      _CreateSessionDialogState();
}

class _CreateSessionDialogState extends ConsumerState<_CreateSessionDialog> {
  String? _selectedCohortId;
  final _sessionNumberCtrl = TextEditingController();
  DateTime _scheduledAt = DateTime.now();
  bool _loading = false;

  @override
  void dispose() {
    _sessionNumberCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selectedCohortId == null || _sessionNumberCtrl.text.isEmpty) {
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
      await ref.read(adminSessionsRepositoryProvider).createSession(
            cohortId: _selectedCohortId!,
            sessionNumber: int.parse(_sessionNumberCtrl.text),
            scheduledAt: _scheduledAt,
          );

      if (!mounted) return;
      Navigator.pop(context);
      widget.onCreated();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم إنشاء الجلسة بنجاح ✓'),
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
    final coursesAsync = ref.watch(coursesProvider);

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
                  const Icon(Icons.calendar_month, color: AppColors.gold),
                  SizedBox(width: Responsive.spacing(context, 8)),
                  Text('جلسة جديدة',
                      style: TextStyle(
                          fontSize: Responsive.fontSize(context, 18),
                          fontWeight: FontWeight.w700,
                          color: AppColors.gold,
                          fontFamily: 'Cairo')),
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

              // Cohort selector — نجيب المجموعات من الكورسات
              coursesAsync.when(
                loading: () =>
                    const CircularProgressIndicator(color: AppColors.gold),
                error: (e, _) => Text('خطأ: $e'),
                data: (courses) {
                  return FutureBuilder<List<Map<String, dynamic>>>(
                    future: _getAllCohorts(ref),
                    builder: (context, snapshot) {
                      final cohorts = snapshot.data ?? [];
                      return DropdownButtonFormField<String>(
                        value: _selectedCohortId,
                        dropdownColor: AppColors.cardBg,
                        decoration: _inputDecoration(
                            'اختر المجموعة *', Icons.group_outlined),
                        items: cohorts.map((c) {
                          return DropdownMenuItem(
                            value: c['id'] as String,
                            child: Text(
                              '${c['name']} — ${c['course_name']}',
                              style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontFamily: 'Cairo',
                                  fontSize: 13),
                            ),
                          );
                        }).toList(),
                        onChanged: (v) => setState(() => _selectedCohortId = v),
                      );
                    },
                  );
                },
              ),

              SizedBox(height: Responsive.spacing(context, 12)),

              TextField(
                controller: _sessionNumberCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: _inputDecoration('رقم الجلسة *', Icons.numbers),
              ),

              SizedBox(height: Responsive.spacing(context, 12)),

              InkWell(
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: _scheduledAt,
                    firstDate: DateTime(2024),
                    lastDate: DateTime(2030),
                  );
                  if (date != null && context.mounted) {
                    final time = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(_scheduledAt),
                    );
                    if (time != null && mounted) {
                      setState(() {
                        _scheduledAt = DateTime(
                          date.year,
                          date.month,
                          date.day,
                          time.hour,
                          time.minute,
                        );
                      });
                    }
                  }
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
                        DateFormat('yyyy/MM/dd — HH:mm').format(_scheduledAt),
                        style: const TextStyle(
                            color: AppColors.textPrimary, fontFamily: 'Cairo'),
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
                          : const Text('إنشاء',
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

  Future<List<Map<String, dynamic>>> _getAllCohorts(WidgetRef ref) async {
    final response = await Supabase.instance.client
        .from('cohorts')
        .select('id, name, courses!cohorts_course_id_fkey(name)')
        .eq('is_active', true);

    return (response as List).map((c) {
      final course = c['courses'] as Map<String, dynamic>? ?? {};
      return {
        'id': c['id'],
        'name': c['name'],
        'course_name': course['name'] ?? '',
      };
    }).toList();
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle:
          const TextStyle(color: AppColors.textSecondary, fontFamily: 'Cairo'),
      prefixIcon: Icon(icon, color: AppColors.gold),
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
          borderSide: const BorderSide(color: AppColors.gold, width: 2)),
    );
  }
}
