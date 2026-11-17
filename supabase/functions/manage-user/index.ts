import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const BAN_FOREVER = '876000h' // ~100 years: blocks login and token refresh until unbanned
const MANAGED_ROLES = ['admin', 'reception']

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

    // فقط مدير نشط يستطيع إدارة الحسابات الإدارية
    const { data: caller } = await supabaseAdmin
      .from('users')
      .select('role, is_active')
      .eq('id', user.id)
      .single()

    if (!caller || caller.role !== 'admin' || caller.is_active !== true) {
      return json({ error: 'صلاحيات غير كافية أو الحساب معطل' }, 403)
    }

    const { action, user_id, role, is_active } = await req.json()
    if (!action || !user_id) return json({ error: 'الحقول الإلزامية ناقصة' }, 400)

    // نفس منع الحارس في القاعدة، مع رسالة أوضح لمسار الواجهة
    if (user_id === user.id) {
      return json({ error: 'لا يمكنك تعديل حسابك الخاص من هذه الشاشة' }, 400)
    }

    const { data: target } = await supabaseAdmin
      .from('users')
      .select('id, role, is_active')
      .eq('id', user_id)
      .maybeSingle()

    if (!target) return json({ error: 'المستخدم غير موجود' }, 404)
    if (!MANAGED_ROLES.includes(target.role)) {
      return json({ error: 'هذه الشاشة مخصصة لحسابات الإدارة والاستقبال فقط' }, 400)
    }

    if (action === 'set_role') {
      if (!MANAGED_ROLES.includes(role)) return json({ error: 'الدور غير صالح' }, 400)
      if (role === target.role) return json({ success: true })

      // الحارس في القاعدة يمنع تحويل آخر مدير نشط ويرجع رسالة عربية (P0001)
      const { error } = await supabaseAdmin
        .from('users')
        .update({ role })
        .eq('id', user_id)

      if (error) return json({ error: error.message || 'تعذر تحديث الدور' }, 400)
      return json({ success: true, user_id, role }, 200)
    }

    if (action === 'set_active') {
      if (typeof is_active !== 'boolean') {
        return json({ error: 'قيمة التفعيل غير صالحة' }, 400)
      }
      if (is_active === target.is_active) return json({ success: true })

      if (is_active === false) {
        // 1) القاعدة أولاً: تمنع تعطيل آخر مدير نشط
        const { error: dbError } = await supabaseAdmin
          .from('users')
          .update({ is_active: false })
          .eq('id', user_id)

        if (dbError) return json({ error: dbError.message || 'تعذر تعطيل الحساب' }, 400)

        // 2) GoTrue: منع الدخول وإعادة إصدار التوكنات
        const { error: banError } = await supabaseAdmin.auth.admin.updateUserById(
          user_id,
          { ban_duration: BAN_FOREVER }
        )

        if (banError) {
          // تراجع best-effort حتى لا يبقى الحساب نصف معطّل
          await supabaseAdmin.from('users').update({ is_active: true }).eq('id', user_id)
          return json({ error: banError.message || 'تعذر تعطيل تسجيل الدخول' }, 400)
        }

        return json({ success: true, user_id, is_active: false }, 200)
      }

      // إعادة التفعيل: فك الحظر أولاً ثم تفعيل الصف
      const { error: unbanError } = await supabaseAdmin.auth.admin.updateUserById(
        user_id,
        { ban_duration: 'none' }
      )
      if (unbanError) {
        return json({ error: unbanError.message || 'تعذر إعادة تفعيل تسجيل الدخول' }, 400)
      }

      const { error: dbError } = await supabaseAdmin
        .from('users')
        .update({ is_active: true })
        .eq('id', user_id)

      if (dbError) {
        await supabaseAdmin.auth.admin
          .updateUserById(user_id, { ban_duration: BAN_FOREVER })
          .catch((e) => console.error('re-ban failed:', e))
        return json({ error: dbError.message || 'تعذر تفعيل الحساب' }, 400)
      }

      return json({ success: true, user_id, is_active: true }, 200)
    }

    return json({ error: 'إجراء غير معروف' }, 400)
  } catch (e) {
    console.error('manage-user unexpected:', e)
    return json({ error: 'خطأ غير متوقع في السيرفر' }, 500)
  }
})

const json = (body: object, status: number) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
