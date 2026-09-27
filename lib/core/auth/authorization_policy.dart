/// السياسة المركزية للتحكم بالوصول للوحة التحكم (RBAC Policy).
///
/// مصدر واحد للحقيقة لقائمة الأدوار المخوَّلة — يُستخدم من قِبل:
/// 1. شاشة تسجيل الدخول (لإظهار رسالة خطأ فورية وواضحة للمستخدم)
/// 2. حارس الراوتر (كطبقة دفاع ثانية ضد الروابط المباشرة والجلسات القديمة)
///
/// ⚠️ ملاحظة أمنية: هذا الكلاس يُستخدم فقط لقرارات العرض على مستوى
/// العميل (client-side UX decisions). لا يُغني بأي شكل عن Row Level
/// Security بقاعدة البيانات، والتي تبقى خط الدفاع الحقيقي والوحيد
/// الموثوق ضد الوصول غير المخوَّل للبيانات الفعلية.
class AuthorizationPolicy {
  AuthorizationPolicy._();

  static const Set<String> dashboardRoles = {'admin', 'reception'};

  static bool isDashboardRole(String? role) =>
      role != null && dashboardRoles.contains(role);
}
