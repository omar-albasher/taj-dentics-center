import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:admin_dashboard/core/widgets/app_error_widget.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/responsive.dart';
import '../data/users_repository.dart';

class UsersScreen extends ConsumerWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(usersProvider);

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
                  'المستخدمون',
                  style: TextStyle(
                    fontSize: Responsive.fontSize(context, 28),
                    fontWeight: FontWeight.w900,
                    color: AppColors.gold,
                    fontFamily: 'Cairo',
                  ),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: () => _showAddUserDialog(context, ref),
                  icon: const Icon(Icons.person_add),
                  label: const Text('إضافة مستخدم',
                      style: TextStyle(fontFamily: 'Cairo')),
                ),
              ],
            ),
            SizedBox(height: Responsive.spacing(context, 24)),
            Expanded(
              child: usersAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(color: AppColors.gold),
                ),
                error: (e, _) => AppErrorWidget(
                  message: 'خطأ: $e',
                  onRetry: () => ref.invalidate(usersProvider),
                ),
                data: (users) {
                  if (users.isEmpty) {
                    return Center(
                      child: Text('لا يوجد مستخدمون',
                          style: TextStyle(
                              color: AppColors.textSecondary,
                              fontFamily: 'Cairo',
                              fontSize: Responsive.fontSize(context, 16))),
                    );
                  }

                  return ListView.separated(
                    itemCount: users.length,
                    separatorBuilder: (_, __) =>
                        SizedBox(height: Responsive.spacing(context, 8)),
                    itemBuilder: (context, index) {
                      final u = users[index];
                      return _UserCard(
                        user: u,
                        onToggle: (isActive) async {
                          await ref
                              .read(usersRepositoryProvider)
                              .toggleUserStatus(u['id'], isActive);
                          ref.invalidate(usersProvider);
                        },
                        onRoleChange: (role) async {
                          await ref
                              .read(usersRepositoryProvider)
                              .updateUserRole(u['id'], role);
                          ref.invalidate(usersProvider);
                        },
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

  void _showAddUserDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => _AddUserDialog(
        onAdded: () => ref.invalidate(usersProvider),
      ),
    );
  }
}

class _UserCard extends StatefulWidget {
  final Map<String, dynamic> user;
  final Function(bool) onToggle;
  final Function(String) onRoleChange;

  const _UserCard({
    required this.user,
    required this.onToggle,
    required this.onRoleChange,
  });

  @override
  State<_UserCard> createState() => _UserCardState();
}

class _UserCardState extends State<_UserCard> {
  bool _isLoading = false;

  Future<void> _handleAction(Future<void> Function() action) async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
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

  @override
  Widget build(BuildContext context) {
    final isActive = widget.user['is_active'] ?? true;
    final role = widget.user['role'] ?? 'reception';
    final date = DateTime.tryParse(widget.user['created_at'] ?? '');

    return Container(
      padding: EdgeInsets.all(Responsive.spacing(context, 16)),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive ? AppColors.gold.withValues(alpha: 0.3) : AppColors.divider,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: role == 'admin'
                ? AppColors.gold.withValues(alpha: 0.15)
                : AppColors.darkGreen.withValues(alpha: 0.5),
            radius: 24,
            child: Text(
              (widget.user['full_name'] as String? ?? '?').isNotEmpty
                  ? (widget.user['full_name'] as String)[0]
                  : '?',
              style: TextStyle(
                color: role == 'admin' ? AppColors.gold : Colors.white,
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
                Text(
                  widget.user['full_name'] ?? '',
                  style: TextStyle(
                    fontSize: Responsive.fontSize(context, 15),
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    fontFamily: 'Cairo',
                  ),
                ),
                Text(
                  widget.user['email'] ?? '',
                  style: TextStyle(
                    fontSize: Responsive.fontSize(context, 12),
                    color: AppColors.textSecondary,
                    fontFamily: 'Cairo',
                  ),
                ),
                if (date != null)
                  Text(
                    'أُضيف: ${DateFormat('yyyy/MM/dd').format(date)}',
                    style: TextStyle(
                      fontSize: Responsive.fontSize(context, 11),
                      color: AppColors.textSecondary,
                      fontFamily: 'Cairo',
                    ),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.all(12.0),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.gold,
                    ),
                  ),
                )
              else ...[
                // Role Dropdown
                DropdownButton<String>(
                  value: role,
                  dropdownColor: AppColors.cardBg,
                  underline: const SizedBox(),
                  style: const TextStyle(
                      color: AppColors.gold, fontFamily: 'Cairo', fontSize: 13),
                  items: const [
                    DropdownMenuItem(
                      value: 'admin',
                      child: Text('مدير',
                          style: TextStyle(
                              color: AppColors.gold, fontFamily: 'Cairo')),
                    ),
                    DropdownMenuItem(
                      value: 'reception',
                      child: Text('استقبال',
                          style: TextStyle(
                              color: AppColors.textPrimary, fontFamily: 'Cairo')),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      _handleAction(() async => widget.onRoleChange(v));
                    }
                  },
                ),

                // Active Toggle
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isActive ? 'نشط' : 'موقوف',
                      style: TextStyle(
                        fontSize: Responsive.fontSize(context, 12),
                        color: isActive ? AppColors.success : AppColors.error,
                        fontFamily: 'Cairo',
                      ),
                    ),
                    Switch(
                      value: isActive,
                      onChanged: (v) {
                        _handleAction(() async => widget.onToggle(v));
                      },
                      activeColor: AppColors.gold,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _AddUserDialog extends ConsumerStatefulWidget {
  final VoidCallback onAdded;
  const _AddUserDialog({required this.onAdded});

  @override
  ConsumerState<_AddUserDialog> createState() => _AddUserDialogState();
}

class _AddUserDialogState extends ConsumerState<_AddUserDialog> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  String _role = 'reception';
  bool _obscure = true;
  bool _loading = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_nameCtrl.text.isEmpty ||
        _emailCtrl.text.isEmpty ||
        _passwordCtrl.text.isEmpty) {
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
      await ref.read(usersRepositoryProvider).addUser(
            fullName: _nameCtrl.text.trim(),
            email: _emailCtrl.text.trim(),
            phone: _phoneCtrl.text.trim(),
            password: _passwordCtrl.text,
            role: _role,
          );

      if (!mounted) return;
      Navigator.pop(context);
      widget.onAdded();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم إضافة المستخدم بنجاح ✓'),
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
                  const Icon(Icons.manage_accounts, color: AppColors.gold),
                  SizedBox(width: Responsive.spacing(context, 8)),
                  Text('إضافة مستخدم جديد',
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

              _buildField(_nameCtrl, 'الاسم الكامل *', Icons.person_outline),
              SizedBox(height: Responsive.spacing(context, 12)),
              _buildField(
                  _emailCtrl, 'البريد الإلكتروني *', Icons.email_outlined,
                  isLtr: true),
              SizedBox(height: Responsive.spacing(context, 12)),
              _buildField(_phoneCtrl, 'رقم الهاتف', Icons.phone_outlined),
              SizedBox(height: Responsive.spacing(context, 12)),

              // Password
              TextField(
                controller: _passwordCtrl,
                obscureText: _obscure,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  labelText: 'كلمة المرور *',
                  labelStyle: const TextStyle(
                      color: AppColors.textSecondary, fontFamily: 'Cairo'),
                  prefixIcon:
                      const Icon(Icons.lock_outlined, color: AppColors.gold),
                  suffixIcon: IconButton(
                    icon: Icon(
                        _obscure ? Icons.visibility_off : Icons.visibility,
                        color: AppColors.textSecondary),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
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

              // Role
              DropdownButtonFormField<String>(
                value: _role,
                dropdownColor: AppColors.cardBg,
                decoration: InputDecoration(
                  labelText: 'الدور',
                  labelStyle: const TextStyle(
                      color: AppColors.textSecondary, fontFamily: 'Cairo'),
                  prefixIcon:
                      const Icon(Icons.badge_outlined, color: AppColors.gold),
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
                    value: 'admin',
                    child: Text('مدير',
                        style: TextStyle(
                            color: AppColors.textPrimary, fontFamily: 'Cairo')),
                  ),
                  DropdownMenuItem(
                    value: 'reception',
                    child: Text('استقبال',
                        style: TextStyle(
                            color: AppColors.textPrimary, fontFamily: 'Cairo')),
                  ),
                ],
                onChanged: (v) => setState(() => _role = v ?? 'reception'),
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
                          : const Text('إضافة',
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

  Widget _buildField(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    bool isLtr = false,
  }) {
    return TextField(
      controller: ctrl,
      textDirection: isLtr ? ui.TextDirection.ltr : ui.TextDirection.rtl,
      style: const TextStyle(color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
            color: AppColors.textSecondary, fontFamily: 'Cairo'),
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
      ),
    );
  }
}
