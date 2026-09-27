import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:admin_dashboard/core/widgets/app_error_widget.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/responsive.dart';
import '../../sessions/data/admin_sessions_repository.dart';
import '../../sessions/domain/session_model.dart';

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  DateTime _focusedMonth = DateTime.now();
  DateTime? _selectedDay;

  @override
  Widget build(BuildContext context) {
    final sessionsAsync = ref.watch(adminSessionsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Padding(
        padding: EdgeInsets.all(Responsive.spacing(context, 24)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'التقويم',
              style: TextStyle(
                fontSize: Responsive.fontSize(context, 28),
                fontWeight: FontWeight.w900,
                color: AppColors.gold,
                fontFamily: 'Cairo',
              ),
            ),
            SizedBox(height: Responsive.spacing(context, 24)),
            sessionsAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.gold),
              ),
              error: (e, _) => AppErrorWidget(
                message: 'خطأ: $e',
                onRetry: () => ref.invalidate(adminSessionsProvider),
              ),
              data: (sessions) {
                // Group sessions by date
                final Map<String, List<AdminSessionModel>> sessionsByDate = {};
                for (final s in sessions) {
                  final key = DateFormat('yyyy-MM-dd').format(s.scheduledAt);
                  sessionsByDate.putIfAbsent(key, () => []).add(s);
                }

                final selectedKey = _selectedDay != null
                    ? DateFormat('yyyy-MM-dd').format(_selectedDay!)
                    : null;

                final selectedSessions = selectedKey != null
                    ? (sessionsByDate[selectedKey] ?? [])
                    : [];

                return Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Calendar
                      Expanded(
                        flex: 3,
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.cardBg,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppColors.divider),
                          ),
                          child: Column(
                            children: [
                              // Month Header
                              Padding(
                                padding: EdgeInsets.all(
                                    Responsive.spacing(context, 16)),
                                child: Row(
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.chevron_right,
                                          color: AppColors.gold),
                                      onPressed: () => setState(() {
                                        _focusedMonth = DateTime(
                                          _focusedMonth.year,
                                          _focusedMonth.month - 1,
                                        );
                                      }),
                                    ),
                                    Expanded(
                                      child: Text(
                                        DateFormat('MMMM yyyy', 'ar')
                                            .format(_focusedMonth),
                                        style: TextStyle(
                                          fontSize:
                                              Responsive.fontSize(context, 18),
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.gold,
                                          fontFamily: 'Cairo',
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.chevron_left,
                                          color: AppColors.gold),
                                      onPressed: () => setState(() {
                                        _focusedMonth = DateTime(
                                          _focusedMonth.year,
                                          _focusedMonth.month + 1,
                                        );
                                      }),
                                    ),
                                  ],
                                ),
                              ),

                              // Day Names
                              Padding(
                                padding: EdgeInsets.symmetric(
                                    horizontal: Responsive.spacing(context, 8)),
                                child: Row(
                                  children: ['ن', 'ث', 'ر', 'خ', 'ج', 'س', 'أ']
                                      .map((d) => Expanded(
                                            child: Text(d,
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                    color:
                                                        AppColors.textSecondary,
                                                    fontFamily: 'Cairo',
                                                    fontWeight:
                                                        FontWeight.w700)),
                                          ))
                                      .toList(),
                                ),
                              ),

                              SizedBox(height: Responsive.spacing(context, 8)),

                              // Days Grid
                              Expanded(
                                child:
                                    _buildCalendarGrid(context, sessionsByDate),
                              ),
                            ],
                          ),
                        ),
                      ),

                      SizedBox(width: Responsive.spacing(context, 16)),

                      // Sessions Panel
                      Expanded(
                        flex: 2,
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.cardBg,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppColors.divider),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: EdgeInsets.all(
                                    Responsive.spacing(context, 16)),
                                child: Text(
                                  _selectedDay != null
                                      ? DateFormat('d MMMM yyyy', 'ar')
                                          .format(_selectedDay!)
                                      : 'اختر يوماً',
                                  style: TextStyle(
                                    fontSize: Responsive.fontSize(context, 16),
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.gold,
                                    fontFamily: 'Cairo',
                                  ),
                                ),
                              ),
                              const Divider(color: AppColors.divider),
                              Expanded(
                                child: selectedSessions.isEmpty
                                    ? Center(
                                        child: Text(
                                          _selectedDay == null
                                              ? 'اضغط على يوم لعرض جلساته'
                                              : 'لا توجد جلسات هذا اليوم',
                                          style: TextStyle(
                                            color: AppColors.textSecondary,
                                            fontFamily: 'Cairo',
                                            fontSize: Responsive.fontSize(
                                                context, 13),
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      )
                                    : ListView.separated(
                                        padding: EdgeInsets.all(
                                            Responsive.spacing(context, 12)),
                                        itemCount: selectedSessions.length,
                                        separatorBuilder: (_, __) => SizedBox(
                                            height:
                                                Responsive.spacing(context, 8)),
                                        itemBuilder: (context, index) {
                                          final s = selectedSessions[index];
                                          Color statusColor;
                                          switch (s.status) {
                                            case 'open':
                                              statusColor = AppColors.success;
                                              break;
                                            case 'closed':
                                              statusColor = AppColors.error;
                                              break;
                                            default:
                                              statusColor = AppColors.warning;
                                          }

                                          return Container(
                                            padding: EdgeInsets.all(
                                                Responsive.spacing(
                                                    context, 12)),
                                            decoration: BoxDecoration(
                                              color:
                                                  statusColor.withValues(alpha: 0.08),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                  color: statusColor
                                                      .withValues(alpha: 0.3)),
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(s.courseName,
                                                    style: TextStyle(
                                                        fontSize:
                                                            Responsive.fontSize(
                                                                context, 14),
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: AppColors
                                                            .textPrimary,
                                                        fontFamily: 'Cairo')),
                                                Text(s.cohortName,
                                                    style: TextStyle(
                                                        fontSize:
                                                            Responsive.fontSize(
                                                                context, 12),
                                                        color: AppColors
                                                            .textSecondary,
                                                        fontFamily: 'Cairo')),
                                                SizedBox(
                                                    height: Responsive.spacing(
                                                        context, 4)),
                                                Row(
                                                  children: [
                                                    Text(
                                                      DateFormat('HH:mm')
                                                          .format(
                                                              s.scheduledAt),
                                                      style: TextStyle(
                                                          color: statusColor,
                                                          fontFamily: 'Cairo',
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.w700),
                                                    ),
                                                    const Spacer(),
                                                    Text(
                                                      'جلسة #${s.sessionNumber}',
                                                      style: TextStyle(
                                                          color: AppColors
                                                              .textSecondary,
                                                          fontFamily: 'Cairo',
                                                          fontSize: 11),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendarGrid(
    BuildContext context,
    Map<String, List<AdminSessionModel>> sessionsByDate,
  ) {
    final firstDay = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final lastDay = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0);
    final startWeekday = firstDay.weekday - 1;

    final List<DateTime?> days = [
      ...List.filled(startWeekday, null),
      ...List.generate(
          lastDay.day,
          (i) => DateTime(
                _focusedMonth.year,
                _focusedMonth.month,
                i + 1,
              )),
    ];

    return GridView.builder(
      padding: EdgeInsets.all(Responsive.spacing(context, 8)),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        childAspectRatio: 1,
      ),
      itemCount: days.length,
      itemBuilder: (context, index) {
        final day = days[index];
        if (day == null) return const SizedBox();

        final key = DateFormat('yyyy-MM-dd').format(day);
        final hasSessions = sessionsByDate.containsKey(key);
        final isSelected = _selectedDay != null &&
            DateFormat('yyyy-MM-dd').format(_selectedDay!) == key;
        final isToday = DateFormat('yyyy-MM-dd').format(DateTime.now()) == key;

        // Count sessions by status
        final daySessions = sessionsByDate[key] ?? [];
        final hasOpen = daySessions.any((s) => s.isOpen);
        final hasClosed = daySessions.any((s) => s.isClosed);
        // ignore: unused_local_variable
        final hasScheduled = daySessions.any((s) => s.isScheduled);

        Color dotColor = AppColors.warning;
        if (hasOpen)
          dotColor = AppColors.success;
        else if (hasClosed) dotColor = AppColors.error;

        return GestureDetector(
          onTap: () => setState(() => _selectedDay = day),
          child: Container(
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.gold.withValues(alpha: 0.2)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: isToday
                  ? Border.all(color: AppColors.gold, width: 1.5)
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${day.day}',
                  style: TextStyle(
                    color: isSelected
                        ? AppColors.gold
                        : isToday
                            ? AppColors.gold
                            : AppColors.textPrimary,
                    fontFamily: 'Cairo',
                    fontWeight: isSelected || isToday
                        ? FontWeight.w900
                        : FontWeight.w400,
                    fontSize: Responsive.fontSize(context, 13),
                  ),
                ),
                if (hasSessions)
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(top: 2),
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
