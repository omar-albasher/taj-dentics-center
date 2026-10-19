import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

Deno.serve(async (req) => {
  // 1. Only allow POST requests
  if (req.method !== 'POST') {
    return json({ error: 'طريقة غير مدعومة' }, 405)
  }

  // 2. Safe JSON body parsing
  let qr_token: string | undefined
  try {
    const body = await req.json()
    qr_token = body.qr_token
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

  // 5. Verify open session with matching QR token
  const { data: session } = await supabase
    .from('sessions')
    .select('id, status')
    .eq('qr_token', qr_token)
    .eq('status', 'open')
    .single()

  if (!session) {
    return json({ error: 'رمز الـ QR غير صالح أو أن الجلسة التدريبية مغلقة' }, 400)
  }

  // 6. Verify trainee record exists
  const { data: trainee } = await supabase
    .from('trainees')
    .select('id')
    .eq('user_id', user.id)
    .single()

  if (!trainee) {
    return json({ error: 'المستخدم ليس متدرباً مسجلاً في المركز' }, 403)
  }

  // 7. Record attendance
  const { error } = await supabase.from('attendance').insert({
    session_id:   session.id,
    trainee_id:   trainee.id,
    method:       'qr',
    performed_by: user.id
  })

  if (error?.code === '23505') {
    return json({ error: 'تم تسجيل حضورك مسبقاً في هذه الجلسة' }, 409)
  }
  if (error) {
    console.error('Attendance recording error:', error)
    return json({ error: 'حدث خطأ أثناء تسجيل الحضور، يرجى المحاولة لاحقاً' }, 500)
  }

  return json({ success: true, message: 'تم تسجيل حضورك بنجاح ✓' }, 200)
})

const json = (body: object, status: number) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' }
  })
