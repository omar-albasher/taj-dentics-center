import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../domain/activity_event.dart';
import '../live_feed_controller.dart';

class LiveActivityFeedWidget extends ConsumerWidget {
  const LiveActivityFeedWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liveState = ref.watch(liveFeedProvider);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                const Icon(Icons.bolt, color: AppColors.gold, size: 22),
                const SizedBox(width: 8),
                const Text(
                  'شريط النشاط اللحظي (Live Feed)',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: AppColors.gold,
                  ),
                ),
                const Spacer(),

                // Live status pulsing badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: liveState.isConnected
                        ? AppColors.success.withValues(alpha: 0.15)
                        : AppColors.warning.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: liveState.isConnected
                          ? AppColors.success.withValues(alpha: 0.4)
                          : AppColors.warning.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: liveState.isConnected ? AppColors.success : AppColors.warning,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        liveState.isConnected ? 'متصل لحظياً' : 'إعادة الاتصال...',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: liveState.isConnected ? AppColors.success : AppColors.warning,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // Refresh button
                IconButton(
                  icon: const Icon(Icons.refresh, size: 18, color: AppColors.textSecondary),
                  tooltip: 'تحديث النشاطات',
                  onPressed: () => ref.read(liveFeedProvider.notifier).refresh(),
                ),
              ],
            ),
          ),
          const Divider(color: AppColors.divider, height: 1),

          // Events list
          if (liveState.isLoading && liveState.events.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.gold, strokeWidth: 2),
              ),
            )
          else if (liveState.events.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text(
                  'لا توجد نشاطات مسجلة مؤخراً',
                  style: TextStyle(color: AppColors.textSecondary, fontFamily: 'Cairo', fontSize: 13),
                ),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 380),
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shrinkWrap: true,
                itemCount: liveState.events.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final event = liveState.events[index];
                  return _ActivityItemTile(event: event);
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _ActivityItemTile extends StatelessWidget {
  final ActivityEvent event;

  const _ActivityItemTile({required this.event});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          // Event Type Icon
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: event.accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: event.accentColor.withValues(alpha: 0.3)),
            ),
            child: Icon(event.icon, size: 18, color: event.accentColor),
          ),
          const SizedBox(width: 12),

          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: event.accentColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        event.typeLabel,
                        style: TextStyle(
                          color: event.accentColor,
                          fontFamily: 'Cairo',
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        event.subtitle,
                        style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'Cairo',
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                if (event.detail != null)
                  Text(
                    event.detail!,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontFamily: 'Cairo',
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),

          // Right side: Amount & Time
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (event.amountDisplay != null)
                Text(
                  event.amountDisplay!,
                  style: TextStyle(
                    color: event.accentColor,
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
              Text(
                event.timeAgo,
                style: const TextStyle(
                  color: Colors.white38,
                  fontFamily: 'Cairo',
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
