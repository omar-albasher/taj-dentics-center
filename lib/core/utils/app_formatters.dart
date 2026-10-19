import 'package:intl/intl.dart';

/// منسقات مشتركة تُنشأ مرة واحدة فقط — إنشاء DateFormat/NumberFormat
/// داخل itemBuilder مكلف لأنه يفك نمط التنسيق ويبحث عن بيانات الـ locale
/// في كل استدعاء.
class AppFormatters {
  AppFormatters._();

  static final DateFormat dateOnly = DateFormat('yyyy/MM/dd');
  static final DateFormat timeOnly = DateFormat('HH:mm');
  static final DateFormat dateTime = DateFormat('yyyy/MM/dd — HH:mm');
  static final DateFormat dayKey = DateFormat('yyyy-MM-dd');
  static final DateFormat monthYearAr = DateFormat('MMMM yyyy', 'ar');
  static final DateFormat monthShortAr = DateFormat('MMM yyyy', 'ar');
  static final DateFormat dayFullAr = DateFormat('EEEE، d MMMM yyyy', 'ar');
  static final DateFormat dateLongAr = DateFormat('d MMMM yyyy', 'ar');
  static final NumberFormat amount = NumberFormat('#,###');
}
