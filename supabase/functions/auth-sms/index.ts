import { serve } from "https://deno.land/std@0.131.0/http/server.ts"
import { Webhook } from "https://esm.sh/standardwebhooks@1.0.0"

serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response('Method Not Allowed', { status: 405 })
  }

  try {
    // 1. Get the signature headers and raw body
    const payload = await req.text()
    const headers = Object.fromEntries(req.headers)
    
    // 2. Get the secret we set in Step 1 (stripping the prefix)
    const hookSecret = Deno.env.get('SEND_SMS_HOOK_SECRET')?.replace('v1,whsec_', '')
    if (!hookSecret) throw new Error("Missing hook secret")

    // 3. Verify the webhook signature
    const wh = new Webhook(hookSecret)
    const verifiedPayload = wh.verify(payload, headers) as {
      user: { phone: string },
      sms: { otp: string }
    }

    const { user, sms } = verifiedPayload
    const phone = user.phone
    const code = sms.otp
    
    // 4. Your 2Factor Details
    const API_KEY = "edcfdc83-33df-11f1-bfb4-0200cd936042"
    const TEMPLATE_NAME = "YOUR_TEMPLATE_NAME" 
    const cleanPhone = phone.replace('+', '')

    const url = `https://2factor.in/API/V1/${API_KEY}/SMS/${cleanPhone}/${code}/${TEMPLATE_NAME}`

    const response = await fetch(url, { method: 'GET' })
    const result = await response.json()

    // 5. Return success to Supabase
    return new Response(JSON.stringify({ status: 'success', result }), { 
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    })

  } catch (error) {
    console.error("Webhook Verification Failed:", error.message)
    return new Response(JSON.stringify({ error: error.message }), { 
      status: 401,
      headers: { 'Content-Type': 'application/json' }
    })
  }
})