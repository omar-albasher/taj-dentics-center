import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const ALLOWED_ROLES = ['trainee', 'reception', 'admin']

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }
  if (req.method !== 'POST') {
    return json({ error: 'Method Not Allowed' }, 405)
  }

  try {
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) return json({ error: 'Unauthorized' }, 401)

    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SERVICE_ROLE_KEY')!
    )
    const supabaseAuth = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authHeader } } }
    )

    const { data: { user }, error: authError } = await supabaseAuth.auth.getUser()
    if (authError || !user) return json({ error: 'Unauthorized' }, 401)

    // التحقق من صلاحية ونشاط المُستدعي
    const { data: caller } = await supabaseAdmin
      .from('users')
      .select('role, is_active')
      .eq('id', user.id)
      .single()

    if (!caller || !['admin', 'reception'].includes(caller.role) || caller.is_active !== true) {
      return json({ error: 'صلاحيات غير كافية أو الحساب معطل' }, 403)
    }

    const { full_name, email, phone, password, role } = await req.json()

    if (!full_name || !email || !password) {
      return json({ error: 'الحقول الإلزامية ناقصة' }, 400)
    }

    // سياسة كلمة المرور (8 أحرف على الأقل)
    if (typeof password !== 'string' || password.length < 8) {
      return json({ error: 'كلمة المرور يجب أن لا تقل عن 8 أحرف' }, 400)
    }

    // تحديد الدور المطلوب بأمان
    let requestedRole = 'trainee'
    if (role && ALLOWED_ROLES.includes(role)) {
      // فقط الـ Admin يستطيع إنشاء admin أو reception
      if (['admin', 'reception'].includes(role)) {
        if (caller.role !== 'admin') {
          return json({ error: 'فقط المدير يمكنه تعيين أدوار إدارية' }, 403)
        }
        requestedRole = role
      }
    }

    // إنشاء المستخدم في Auth
    const { data: newUser, error: createError } = await supabaseAdmin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: { role: requestedRole }
    })

    if (createError || !newUser.user) {
      return json({ error: createError?.message ?? 'فشل إنشاء المستخدم' }, 400)
    }

    const userId = newUser.user.id

    // إدراج المستخدم في جدول public.users
    const { error: userInsertError } = await supabaseAdmin.from('users').insert({
      id: userId,
      email,
      full_name,
      phone: phone ?? null,
      role: requestedRole,
      is_active: true
    })

    if (userInsertError) {
      console.error('users insert failed:', userInsertError.message)
      await supabaseAdmin.auth.admin.deleteUser(userId).catch((e) => console.error('cleanup failed:', e))
      return json({ error: 'تعذر إكمال إنشاء المستخدم' }, 400)
    }

    // إنشاء ملف تدريبي في جدول trainees فقط إذا كان الدور متدرباً
    if (requestedRole === 'trainee') {
      const { error: traineeInsertError } = await supabaseAdmin.from('trainees').insert({
        user_id: userId,
        created_by: user.id,
      })

      if (traineeInsertError) {
        console.error('trainees insert failed:', traineeInsertError.message)
        await supabaseAdmin.from('users').delete().eq('id', userId)
        await supabaseAdmin.auth.admin.deleteUser(userId).catch((e) => console.error('cleanup failed:', e))
        return json({ error: 'تعذر إكمال إنشاء الملف التدريبي' }, 400)
      }
    }

    return json({ success: true, user_id: userId, role: requestedRole }, 200)

  } catch (e) {
    console.error('quick-endpoint unexpected:', e)
    return json({ error: 'خطأ غير متوقع في السيرفر' }, 500)
  }
})

const json = (body: object, status: number) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
