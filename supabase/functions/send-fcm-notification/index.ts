import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// Token cache in memory for the edge function isolate
let cachedAccessToken: { token: string; expiresAt: number; projectId: string } | null = null

// Helper to convert base64url
function base64UrlEncode(str: string): string {
  return btoa(str).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

function base64UrlFromBytes(bytes: Uint8Array): string {
  let binary = ''
  for (let i = 0; i < bytes.byteLength; i++) {
    binary += String.fromCharCode(bytes[i])
  }
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

// Convert PEM private key to binary ArrayBuffer
function pemToArrayBuffer(pem: string): ArrayBuffer {
  const b64 = pem
    .replace(/-----BEGIN [A-Z ]+-----/g, '')
    .replace(/-----END [A-Z ]+-----/g, '')
    .replace(/\s+/g, '')
  const raw = atob(b64)
  const bytes = new Uint8Array(raw.length)
  for (let i = 0; i < raw.length; i++) {
    bytes[i] = raw.charCodeAt(i)
  }
  return bytes.buffer
}

// Generate Google OAuth2 Access Token for FCM HTTP v1 using Service Account JSON
async function getGoogleAccessToken(serviceAccountJson: string): Promise<{ accessToken: string; projectId: string }> {
  const sa = JSON.parse(serviceAccountJson)
  const now = Math.floor(Date.now() / 1000)

  // Use cached token if valid for at least 5 more minutes
  if (cachedAccessToken && cachedAccessToken.expiresAt > now + 300) {
    return {
      accessToken: cachedAccessToken.token,
      projectId: cachedAccessToken.projectId,
    }
  }

  const header = { alg: 'RS256', typ: 'JWT' }
  const claimSet = {
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    exp: now + 3600,
    iat: now,
  }

  const encodedHeader = base64UrlEncode(JSON.stringify(header))
  const encodedClaimSet = base64UrlEncode(JSON.stringify(claimSet))
  const signatureInput = `${encodedHeader}.${encodedClaimSet}`

  // Import RS256 private key via Web Crypto API
  const binaryKey = pemToArrayBuffer(sa.private_key)
  const cryptoKey = await crypto.subtle.importKey(
    'pkcs8',
    binaryKey,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign']
  )

  const signatureBytes = new Uint8Array(
    await crypto.subtle.sign('RSASSA-PKCS1-v1_5', cryptoKey, new TextEncoder().encode(signatureInput))
  )
  const signedJwt = `${signatureInput}.${base64UrlFromBytes(signatureBytes)}`

  // Exchange signed assertion JWT for Google OAuth2 Access Token
  const tokenRes = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: signedJwt,
    }),
  })

  if (!tokenRes.ok) {
    const errText = await tokenRes.text()
    throw new Error(`Failed to exchange Google OAuth2 token: ${tokenRes.status} ${errText}`)
  }

  const tokenData = await tokenRes.json()
  cachedAccessToken = {
    token: tokenData.access_token,
    expiresAt: now + (tokenData.expires_in || 3600),
    projectId: sa.project_id,
  }

  return {
    accessToken: cachedAccessToken.token,
    projectId: sa.project_id,
  }
}

function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}

Deno.serve(async (req) => {
  // 1. Only allow POST requests
  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405)
  }

  // 2. Strict Authentication: Fail-Closed validation
  // Accepts either matched CRON_SECRET or service_role Bearer authorization
  const expectedSecret = Deno.env.get('CRON_SECRET')?.trim()
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')?.trim()

  const providedSecret = req.headers.get('x-cron-secret')?.trim()
  const authHeader = req.headers.get('Authorization')?.trim()
  const providedBearer = authHeader?.startsWith('Bearer ') ? authHeader.slice(7).trim() : null

  const isCronAuthorized = Boolean(expectedSecret && providedSecret && providedSecret === expectedSecret)
  const isServiceRoleAuthorized = Boolean(serviceRoleKey && providedBearer && providedBearer === serviceRoleKey)

  if (!isCronAuthorized && !isServiceRoleAuthorized) {
    return jsonResponse({ error: 'Unauthorized: invalid or missing cron secret' }, 401)
  }

  // 3. Initialize Supabase Admin Client
  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  if (!supabaseUrl || !serviceRoleKey) {
    return jsonResponse({ error: 'Server misconfiguration: missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY' }, 500)
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey)

  // 4. Verify Firebase Service Account configuration
  const serviceAccountJson = Deno.env.get('FIREBASE_SERVICE_ACCOUNT')
  if (!serviceAccountJson) {
    return jsonResponse({
      error: 'FIREBASE_SERVICE_ACCOUNT secret is not configured in Supabase. Please add your Firebase Service Account JSON key to Supabase secrets.',
    }, 503)
  }

  // 5. Obtain Google OAuth2 token BEFORE claiming batch from outbox
  // This guarantees that if Google Auth fails or is down, ZERO attempts are burned on notifications
  let accessToken: string
  let projectId: string
  try {
    const authInfo = await getGoogleAccessToken(serviceAccountJson)
    accessToken = authInfo.accessToken
    projectId = authInfo.projectId
  } catch (err: any) {
    console.error('Google Auth failure:', err)
    return jsonResponse({ error: `Firebase Auth failed before claiming batch: ${err.message}` }, 500)
  }

  // 6. Claim batch from outbox (atomic SKIP LOCKED)
  const { data: batch, error: claimErr } = await supabase.rpc('claim_notification_batch', { p_limit: 50 })
  if (claimErr) {
    console.error('Error claiming outbox batch:', claimErr)
    return jsonResponse({ error: claimErr.message }, 500)
  }

  if (!batch || batch.length === 0) {
    return jsonResponse({
      status: 'idle',
      message: 'No pending notifications to process',
      claimed: 0,
      sent: 0,
    })
  }

  const fcmSendUrl = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`

  let sentCount = 0
  let skippedCount = 0
  let failedCount = 0

  // 7. Dispatch each notification in batch
  for (const item of batch) {
    const tokens: string[] = item.fcm_tokens || []

    if (tokens.length === 0) {
      // User has no registered active tokens
      if (item.attempt_number >= item.max_attempts) {
        await supabase
          .from('notification_outbox')
          .update({
            status: 'skipped',
            last_error: 'no_active_fcm_tokens',
            locked_at: null,
          })
          .eq('id', item.outbox_id)
      } else {
        await supabase
          .from('notification_outbox')
          .update({
            status: 'pending',
            last_error: 'no_active_fcm_tokens_waiting',
            locked_at: null,
            next_attempt_at: new Date(Date.now() + 5 * 60 * 1000).toISOString(),
          })
          .eq('id', item.outbox_id)
      }
      skippedCount++
      continue
    }

    // Flatten data payload to pure string key-values (FCM requirement)
    const rawData = item.notification_data || {}
    const stringData: Record<string, string> = {
      type: String(item.notification_type || ''),
      title: String(item.notification_title || ''),
      body: String(item.notification_body || ''),
    }
    for (const [k, v] of Object.entries(rawData)) {
      if (v !== undefined && v !== null) {
        stringData[k] = typeof v === 'object' ? JSON.stringify(v) : String(v)
      }
    }

    const isHighPriority = item.notification_type === 'session_reminder'
    let anyDelivered = false
    let lastErrorMsg = ''

    for (const token of tokens) {
      const messagePayload = {
        message: {
          token,
          notification: {
            title: item.notification_title,
            body: item.notification_body,
          },
          android: {
            priority: isHighPriority ? 'HIGH' : 'NORMAL',
            ttl: isHighPriority ? '3600s' : '86400s', // 1h for time-sensitive sessions, 24h for surveys/payments
            notification: {
              channel_id: 'taj_reminders',
              sound: 'default',
            },
          },
          data: stringData,
        },
      }

      try {
        const fcmRes = await fetch(fcmSendUrl, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${accessToken}`,
          },
          body: JSON.stringify(messagePayload),
        })

        if (fcmRes.ok) {
          anyDelivered = true
        } else {
          const resText = await fcmRes.text()
          lastErrorMsg = `FCM ${fcmRes.status}: ${resText}`

          // Deactivate dead tokens strictly on UNREGISTERED (do not deactivate on generic INVALID_ARGUMENT)
          if (
            resText.includes('UNREGISTERED') ||
            resText.includes('registration-token-not-registered')
          ) {
            console.log(`Deactivating dead FCM token: ${token.slice(0, 15)}...`)
            await supabase
              .from('user_fcm_tokens')
              .update({ is_active: false, updated_at: new Date().toISOString() })
              .eq('fcm_token', token)
          }
        }
      } catch (sendErr: any) {
        lastErrorMsg = `Network error sending to FCM: ${sendErr.message}`
      }
    }

    // Update outbox row status
    if (anyDelivered) {
      await supabase
        .from('notification_outbox')
        .update({
          status: 'sent',
          sent_at: new Date().toISOString(),
          locked_at: null,
          last_error: null,
        })
        .eq('id', item.outbox_id)
      sentCount++
    } else {
      if (item.attempt_number >= item.max_attempts) {
        await supabase
          .from('notification_outbox')
          .update({
            status: 'failed',
            last_error: lastErrorMsg || 'all_tokens_failed',
            locked_at: null,
          })
          .eq('id', item.outbox_id)
      } else {
        const backoffMinutes = item.attempt_number * 2
        await supabase
          .from('notification_outbox')
          .update({
            status: 'pending',
            last_error: lastErrorMsg || 'tokens_delivery_failed',
            locked_at: null,
            next_attempt_at: new Date(Date.now() + backoffMinutes * 60 * 1000).toISOString(),
          })
          .eq('id', item.outbox_id)
      }
      failedCount++
    }
  }

  return jsonResponse({
    status: 'success',
    claimed: batch.length,
    sent: sentCount,
    skipped: skippedCount,
    failed: failedCount,
  })
})
