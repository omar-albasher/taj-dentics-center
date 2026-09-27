import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:admin_dashboard/core/widgets/app_error_widget.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/router/app_router.dart';
import '../../../core/utils/responsive.dart';
import '../data/trainees_repository.dart';
import '../domain/trainee_model.dart';
import 'add_trainee_dialog.dart';

class TraineesScreen extends ConsumerStatefulWidget {
  const TraineesScreen({super.key});

  @override
  ConsumerState<TraineesScreen> createState() => _TraineesScreenState();
}

class _TraineesScreenState extends ConsumerState<TraineesScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Watch all trainees and filter client-side for ultra-fast response
    final traineesAsync = ref.watch(traineesProvider(null));

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
                  'المتدربون',
                  style: TextStyle(
                    fontSize: Responsive.fontSize(context, 28),
                    fontWeight: FontWeight.w900,
                    color: AppColors.gold,
                    fontFamily: 'Cairo',
                  ),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: () async {
                    await showDialog(
                      context: context,
                      builder: (_) => AddTraineeDialog(
                        onAdded: () => ref.invalidate(traineesProvider),
                      ),
                    );
                  },
                  icon: const Icon(Icons.add),
                  label: const Text(
                    'إضافة متدرب',
                    style: TextStyle(fontFamily: 'Cairo'),
                  ),
                ),
              ],
            ),

            SizedBox(height: Responsive.spacing(context, 16)),

            // Fast Instant Search
            TextField(
              controller: _searchCtrl,
              onChanged: (val) {
                setState(() {
                  _searchQuery = val.trim().toLowerCase();
                });
              },
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'بحث بالاسم أو البريد الإلكتروني...',
                hintStyle: const TextStyle(
                  color: AppColors.textSecondary,
                  fontFamily: 'Cairo',
                ),
                prefixIcon: const Icon(Icons.search, color: AppColors.gold),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: AppColors.textSecondary),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() {
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
                filled: true,
                fillColor: AppColors.cardBg,
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
              ),
            ),

            SizedBox(height: Responsive.spacing(context, 16)),

            // List
            Expanded(
              child: traineesAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(color: AppColors.gold),
                ),
                error: (e, _) => AppErrorWidget(
                  message: 'حدث خطأ في تحميل البيانات: $e',
                  onRetry: () => ref.invalidate(traineesProvider),
                ),
                data: (allList) {
                  // Filter out broken / empty records
                  final validList = allList.where((t) => t.fullName.isNotEmpty).toList();

                  // Apply search query instantly
                  final list = _searchQuery.isEmpty
                      ? validList
                      : validList.where((t) {
                          final name = t.fullName.toLowerCase();
                          final email = t.email.toLowerCase();
                          final phone = t.phone.toLowerCase();
                          final code = (t.traineeCode ?? '').toLowerCase();
                          return name.contains(_searchQuery) ||
                              code.contains(_searchQuery) ||
                              email.contains(_searchQuery) ||
                              phone.contains(_searchQuery);
                        }).toList();

                  if (list.isEmpty) {
                    return Center(
                      child: Text(
                        _searchQuery.isEmpty
                            ? 'لا يوجد متدربون'
                            : 'لا توجد نتائج مطابقة للبحث',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontFamily: 'Cairo',
                          fontSize: Responsive.fontSize(context, 16),
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, __) =>
                        SizedBox(height: Responsive.spacing(context, 8)),
                    itemBuilder: (context, index) {
                      final t = list[index];
                      return _TraineeCard(
                        trainee: t,
                        onTap: () =>
                            context.push('${AppRouter.trainees}/${t.id}'),
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
}

class _TraineeCard extends StatelessWidget {
  final TraineeModel trainee;
  final VoidCallback onTap;

  const _TraineeCard({required this.trainee, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final displayName = trainee.fullName.isNotEmpty ? trainee.fullName : 'متدرب غير معروف';
    final initial = displayName.isNotEmpty ? displayName[0] : '?';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: EdgeInsets.all(Responsive.spacing(context, 16)),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: AppColors.gold.withValues(alpha: 0.15),
              radius: 24,
              child: Text(
                initial,
                style: const TextStyle(
                  color: AppColors.gold,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'Cairo',
                  fontSize: 18,
                ),
              ),
            ),
            SizedBox(width: Responsive.spacing(context, 16)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        displayName,
                        style: TextStyle(
                          fontSize: Responsive.fontSize(context, 15),
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          fontFamily: 'Cairo',
                        ),
                      ),
                      if (trainee.traineeCode != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.gold.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            trainee.traineeCode!,
                            style: const TextStyle(
                              color: AppColors.gold,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo',
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (trainee.email.isNotEmpty)
                    Text(
                      trainee.email,
                      style: TextStyle(
                        fontSize: Responsive.fontSize(context, 12),
                        color: AppColors.textSecondary,
                        fontFamily: 'Cairo',
                      ),
                    ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: trainee.isActive
                    ? AppColors.success.withValues(alpha: 0.15)
                    : AppColors.error.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                trainee.isActive ? 'نشط' : 'موقف',
                style: TextStyle(
                  fontSize: Responsive.fontSize(context, 12),
                  color: trainee.isActive ? AppColors.success : AppColors.error,
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            SizedBox(width: Responsive.spacing(context, 8)),
            const Icon(Icons.arrow_forward_ios,
                color: AppColors.gold, size: 16),
          ],
        ),
      ),
    );
  }
}
