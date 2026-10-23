import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

Deno.serve(async (req) => {
  // 1. Only allow POST requests
  if (req.method !== 'POST') {
    return json({ error: 'طريقة غير مدعومة' }, 405)
  }

  // 2. Safe JSON body parsing
  let qr_token: string | undefined
  let scanned_at: string | undefined
  try {
    const body = await req.json()
    qr_token = body.qr_token
    scanned_at = body.scanned_at
  } catch {
    return json({ error: 'طلب غير صالح، تنسيق البيانات خاطئ' }, 400)
  }

  if (!qr_token || typeof qr_token !== 'string') {
    return json({ error: 'رمز QR مطلوب' }, 400)
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SERVICE_ROLE_KEY')!
  )

  // 3. Authenticate user
  const authHeader = req.headers.get('Authorization')
  if (!authHeader) {
    return json({ error: 'غير مصرح' }, 401)
  }

  const { data: { user }, error: authError } = await supabase.auth.getUser(
    authHeader.replace('Bearer ', '')
  )
  if (authError || !user) {
    return json({ error: 'غير مصرح' }, 401)
  }

  // 4. Verify user is active
  const { data: userData, error: userError } = await supabase
    .from('users')
    .select('is_active')
    .eq('id', user.id)
    .single()

  if (userError || !userData || !userData.is_active) {
    return json({ error: 'حسابك معطل أو غير مفعل، يرجى مراجعة الإدارة' }, 403)
  }

  // 5. Verify trainee record exists
  const { data: trainee } = await supabase
    .from('trainees')
    .select('id')
    .eq('user_id', user.id)
    .single()

  if (!trainee) {
    return json({ error: 'المستخدم ليس متدرباً مسجلاً في المركز' }, 403)
  }

  // 6. Verify session by qr_token (without hardcoded status = 'open')
  const { data: session } = await supabase
    .from('sessions')
    .select('id, cohort_id, status, opened_at, closed_at, duration_minutes')
    .eq('qr_token', qr_token)
    .maybeSingle()

  if (!session) {
    return json({ error: 'رمز الـ QR غير صالح أو منتهي الصلاحية' }, 400)
  }

  // 7. Verify Trainee is enrolled in this session cohort
  const { data: enrollment } = await supabase
    .from('enrollments')
    .select('id, status')
    .eq('cohort_id', session.cohort_id)
    .eq('trainee_id', trainee.id)
    .maybeSingle()

  if (!enrollment || enrollment.status === 'dropped') {
    return json({ error: 'غير مصرح: أنت لست مقيداً في هذه الدورة التدريبية' }, 403)
  }

  // 8. Grace Period (30 minutes) & Clock drift validation
  const now = new Date()

  if (scanned_at && typeof scanned_at === 'string') {
    const scannedTime = new Date(scanned_at)
    if (isNaN(scannedTime.getTime())) {
      return json({ error: 'صيغة توقيت المسح غير صالحة' }, 400)
    }
    // Reject clock drift in the future (> 5 mins)
    if (scannedTime.getTime() > now.getTime() + 5 * 60 * 1000) {
      return json({ error: 'توقيت المسح يسبق التوقيت الحالي، يرجى التحقق من ساعة جهازك' }, 400)
    }
  }

  if (session.status === 'open') {
    // Session is actively open -> allowed
  } else if (session.status === 'closed') {
    // Session closed: check grace period (30 minutes)
    const closeTime = session.closed_at 
      ? new Date(session.closed_at)
      : (session.opened_at ? new Date(new Date(session.opened_at).getTime() + (session.duration_minutes || 120) * 60 * 1000) : null)

    if (!closeTime) {
      return json({ error: 'الجلسة التدريبية مغلقة' }, 400)
    }

    const graceLimit = new Date(closeTime.getTime() + 30 * 60 * 1000)
    if (now.getTime() > graceLimit.getTime()) {
      return json({ error: 'انتهت نافذة تسجيل الحضور (30 دقيقة بعد إغلاق الجلسة)' }, 400)
    }
  } else {
    return json({ error: 'الجلسة التدريبية ليست متاحة لتسجيل الحضور' }, 400)
  }

  // 9. Record attendance with idempotency (23505 -> 200 with already_recorded: true)
  const insertPayload: Record<string, unknown> = {
    session_id:   session.id,
    trainee_id:   trainee.id,
    method:       'qr',
    performed_by: user.id,
  }

  if (scanned_at) {
    insertPayload.captured_at = scanned_at
  }

  const { error: insertError } = await supabase.from('attendance').insert(insertPayload)

  if (insertError?.code === '23505') {
    // Idempotent retry: Return 200 so offline queue removes item safely
    return json({
      success: true,
      already_recorded: true,
      message: 'تم تسجيل حضورك مسبقاً في هذه الجلسة ✓'
    }, 200)
  }

  if (insertError) {
    console.error('Attendance recording error:', insertError)
    return json({ error: 'حدث خطأ أثناء تسجيل الحضور، يرجى المحاولة لاحقاً' }, 500)
  }

  return json({
    success: true,
    already_recorded: false,
    message: 'تم تسجيل حضورك بنجاح ✓'
  }, 200)
})

const json = (body: object, status: number) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' }
  })
