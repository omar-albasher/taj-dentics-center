import '../../../../core/utils/jwt_utils.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/app_error_handler.dart';
import '../../domain/course_model.dart';
import '../../domain/course_material_model.dart';
import '../../data/course_materials_repository.dart';

class CourseMaterialsDialog extends ConsumerStatefulWidget {
  final CourseModel course;

  const CourseMaterialsDialog({super.key, required this.course});

  @override
  ConsumerState<CourseMaterialsDialog> createState() => _CourseMaterialsDialogState();
}

class _CourseMaterialsDialogState extends ConsumerState<CourseMaterialsDialog> {
  bool _isUploading = false;
  String? _uploadStatusText;

  Future<void> _pickAndUploadFile() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg', 'webp', 'ppt', 'pptx'],
      );

      if (files.isEmpty) return;
      final file = files.first;
      final bytes = await file.readAsBytes();

      // Check max file size (20 MB)
      if (bytes.length > 20 * 1024 * 1024) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('حجم الملف يتجاوز الحد الأقصى المسموح (20 ميغابايت)'),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }

      final ext = file.extension?.toLowerCase() ?? '';
      String mimeType = 'application/octet-stream';
      if (ext == 'pdf') {
        mimeType = 'application/pdf';
      } else if (ext == 'png') {
        mimeType = 'image/png';
      } else if (ext == 'jpg' || ext == 'jpeg') {
        mimeType = 'image/jpeg';
      } else if (ext == 'webp') {
        mimeType = 'image/webp';
      } else if (ext == 'ppt') {
        mimeType = 'application/vnd.ms-powerpoint';
      } else if (ext == 'pptx') {
        mimeType = 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      }

      if (!mounted) return;

      // Ask for Title and description
      final meta = await _showFileMetaDialog(
        defaultTitle: file.name.replaceAll('.$ext', ''),
        fileSize: bytes.length,
      );

      if (meta == null) return;

      setState(() {
        _isUploading = true;
        _uploadStatusText = 'جاري رفع الملف وحفظ البيانات...';
      });

      await ref.read(courseMaterialsRepositoryProvider).uploadFile(
        courseId: widget.course.id,
        title: meta['title'] as String,
        description: meta['description'] as String?,
        bytes: bytes,
        fileName: file.name,
        mimeType: mimeType,
        isPublished: meta['is_published'] as bool? ?? true,
      );

      ref.invalidate(courseMaterialsProvider(widget.course.id));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم رفع وإضافة المادة التعليمية بنجاح ✓'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppErrorHandler.friendlyMessage(e)),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadStatusText = null;
        });
      }
    }
  }

  Future<Map<String, dynamic>?> _showFileMetaDialog({
    required String defaultTitle,
    required int fileSize,
  }) async {
    final titleCtrl = TextEditingController(text: defaultTitle);
    final descCtrl = TextEditingController();
    bool isPublished = true;

    return await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.cardBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('تفاصيل الملف المرفق', style: TextStyle(color: AppColors.gold, fontFamily: 'Cairo')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'عنوان المادة التعليمية *',
                    hintText: 'مثال: سلايدات المحاضرة الأولى',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'وصف مختصر (اختياري)',
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('نشر للمتدربين فوراً', style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 14)),
                  value: isPublished,
                  activeThumbColor: AppColors.gold,
                  onChanged: (v) => setDialogState(() => isPublished = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('إلغاء', style: TextStyle(color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.gold, foregroundColor: Colors.black),
              onPressed: () {
                if (titleCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx, {
                  'title': titleCtrl.text.trim(),
                  'description': descCtrl.text.trim(),
                  'is_published': isPublished,
                });
              },
              child: const Text('متابعة الرفع', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddLinkDialog() async {
    final titleCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    bool isPublished = true;

    final data = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.cardBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('إضافة رابط فيديو / مرجع خارجي', style: TextStyle(color: AppColors.gold, fontFamily: 'Cairo')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'عنوان الرابط *',
                    hintText: 'مثال: تسجيل شرح EXOCAD العملي',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: urlCtrl,
                  decoration: const InputDecoration(
                    labelText: 'رابط يوتيوب أو غوغل درايف *',
                    hintText: 'https://...',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظات وتفاصيل إضافية',
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('نشر للمتدربين فوراً', style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 14)),
                  value: isPublished,
                  activeThumbColor: AppColors.gold,
                  onChanged: (v) => setDialogState(() => isPublished = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('إلغاء', style: TextStyle(color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.gold, foregroundColor: Colors.black),
              onPressed: () {
                final url = urlCtrl.text.trim();
                if (titleCtrl.text.trim().isEmpty || url.isEmpty) return;
                if (!url.startsWith('http://') && !url.startsWith('https://')) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('يرجى إدخال رابط يبدأ بـ https://'), backgroundColor: AppColors.error),
                  );
                  return;
                }
                Navigator.pop(ctx, {
                  'title': titleCtrl.text.trim(),
                  'url': url,
                  'description': descCtrl.text.trim(),
                  'is_published': isPublished,
                });
              },
              child: const Text('إضافة الرابط', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );

    if (data == null) return;

    try {
      await ref.read(courseMaterialsRepositoryProvider).addExternalLink(
        courseId: widget.course.id,
        title: data['title'] as String,
        url: data['url'] as String,
        description: data['description'] as String?,
        isPublished: data['is_published'] as bool? ?? true,
      );

      ref.invalidate(courseMaterialsProvider(widget.course.id));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تمت إضافة الرابط بنجاح ✓'), backgroundColor: AppColors.success),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppErrorHandler.friendlyMessage(e)), backgroundColor: AppColors.error),
      );
    }
  }

  Future<void> _openOrDownload(CourseMaterial material) async {
    try {
      if (material.isLink && material.externalUrl != null) {
        final uri = Uri.parse(material.externalUrl!);
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else if (material.isFile && material.filePath != null) {
        final signedUrl = await ref
            .read(courseMaterialsRepositoryProvider)
            .getSignedUrl(material.filePath!);
        final uri = Uri.parse(signedUrl);
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر فتح الرابط: $e'), backgroundColor: AppColors.error),
      );
    }
  }

  Future<void> _confirmDelete(CourseMaterial material) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBg,
        title: const Text('تأكيد الحذف', style: TextStyle(color: AppColors.error, fontFamily: 'Cairo')),
        content: Text('هل أنت متأكد من حذف "${material.title}"؟', style: const TextStyle(color: Colors.white, fontFamily: 'Cairo')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await ref.read(courseMaterialsRepositoryProvider).deleteMaterial(material);
        ref.invalidate(courseMaterialsProvider(widget.course.id));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حذف المادة بنجاح'), backgroundColor: AppColors.success),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppErrorHandler.friendlyMessage(e)), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final materialsAsync = ref.watch(courseMaterialsProvider(widget.course.id));
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    final role = JwtUtils.extractRole(token);
    final isAdmin = role == 'admin';

    return Dialog(
      backgroundColor: AppColors.background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 850, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.gold.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.folder_shared_outlined, color: AppColors.gold, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'مواد ومرفقات: ${widget.course.name}',
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const Text(
                          'رفع ملفات PDF والمستندات والروابط التعليمية المتاحة للمتدربين',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppColors.textSecondary),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(color: AppColors.divider, height: 28),

              // Action Toolbar
              Row(
                children: [
                  if (isAdmin) ...[
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.gold,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      onPressed: _isUploading ? null : _pickAndUploadFile,
                      icon: const Icon(Icons.upload_file, size: 20),
                      label: const Text('رفع ملف (PDF / صورة / PPTX)', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.gold,
                        side: const BorderSide(color: AppColors.gold),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      onPressed: _isUploading ? null : _showAddLinkDialog,
                      icon: const Icon(Icons.link, size: 20),
                      label: const Text('إضافة رابط خارجي (فيديو / درايف)', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                    ),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.textSecondary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.lock_outline, size: 16, color: AppColors.textSecondary),
                          SizedBox(width: 6),
                          Text('وضع العرض فقط (الاستقبال)', style: TextStyle(color: AppColors.textSecondary, fontFamily: 'Cairo', fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.refresh, color: AppColors.gold),
                    tooltip: 'تحديث المواد',
                    onPressed: () => ref.invalidate(courseMaterialsProvider(widget.course.id)),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              if (_isUploading)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: AppColors.cardBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.gold.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gold)),
                      const SizedBox(width: 12),
                      Text(
                        _uploadStatusText ?? 'جاري الرفع...',
                        style: const TextStyle(color: AppColors.gold, fontFamily: 'Cairo', fontSize: 13),
                      ),
                    ],
                  ),
                ),

              // Content List
              Expanded(
                child: materialsAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator(color: AppColors.gold)),
                  error: (e, _) => Center(
                    child: Text(AppErrorHandler.friendlyMessage(e), style: const TextStyle(color: AppColors.error, fontFamily: 'Cairo')),
                  ),
                  data: (list) {
                    if (list.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.folder_open, size: 64, color: AppColors.textSecondary),
                            SizedBox(height: 12),
                            Text(
                              'لا توجد مواد أو مرفقات تعليمية مضافة لهذا الكورس بعد',
                              style: TextStyle(color: AppColors.textSecondary, fontFamily: 'Cairo', fontSize: 14),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.separated(
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final item = list[index];
                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.cardBg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.divider),
                          ),
                          child: Row(
                            children: [
                              // Type icon
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: item.iconColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(item.icon, color: item.iconColor, size: 24),
                              ),
                              const SizedBox(width: 14),

                              // Info
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          item.title,
                                          style: const TextStyle(
                                            fontFamily: 'Cairo',
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: item.isPublished
                                                ? AppColors.success.withValues(alpha: 0.15)
                                                : AppColors.warning.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            item.isPublished ? 'منشور' : 'مسودة',
                                            style: TextStyle(
                                              fontFamily: 'Cairo',
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: item.isPublished ? AppColors.success : AppColors.warning,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      item.isFile
                                          ? 'ملف: ${item.fileSizeDisplay}'
                                          : 'رابط خارجي: ${item.externalUrl}',
                                      style: const TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 11,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                    if (item.description != null && item.description!.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(
                                          item.description!,
                                          style: const TextStyle(
                                            fontFamily: 'Cairo',
                                            fontSize: 11,
                                            color: Colors.white70,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),

                              // Actions
                              IconButton(
                                icon: const Icon(Icons.open_in_new, color: AppColors.gold, size: 20),
                                tooltip: item.isFile ? 'تحميل ومعاينة' : 'فتح الرابط',
                                onPressed: () => _openOrDownload(item),
                              ),
                              if (isAdmin) ...[
                                IconButton(
                                  icon: Icon(
                                    item.isPublished ? Icons.visibility : Icons.visibility_off,
                                    color: item.isPublished ? AppColors.success : AppColors.textSecondary,
                                    size: 20,
                                  ),
                                  tooltip: item.isPublished ? 'تحويل لمسودة' : 'نشر للمتدربين',
                                  onPressed: () async {
                                    await ref.read(courseMaterialsRepositoryProvider).togglePublish(item.id, !item.isPublished);
                                    ref.invalidate(courseMaterialsProvider(widget.course.id));
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: AppColors.error, size: 20),
                                  tooltip: 'حذف',
                                  onPressed: () => _confirmDelete(item),
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
          ),
        ),
      ),
    );
  }
}
