import 'dart:math';

/// كلمة مرور مؤقتة سهلة النقل شفهياً/كتابياً: `Taj@` + 6 أرقام عشوائية.
/// تُستخدم فقط في نافذة إعادة التعيين الإدارية، ويُجبر المتدرب على تغييرها
/// عند أول دخول.
String generateTemporaryPassword({Random? random}) {
  final rng = random ?? Random.secure();
  final digits = List.generate(6, (_) => rng.nextInt(10)).join();
  return 'Taj@$digits';
}
