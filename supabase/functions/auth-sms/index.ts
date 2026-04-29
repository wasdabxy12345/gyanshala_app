import { serve } from "https://deno.land/std@0.131.0/http/server.ts"
import { Webhook } from "https://esm.sh/standardwebhooks@1.0.0"

serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response('Method Not Allowed', { status: 405 })
  }

  try {
    const payload = await req.text()
    const headers = Object.fromEntries(req.headers)
    
    const hookSecret = Deno.env.get('SEND_SMS_HOOK_SECRET')?.replace('v1,whsec_', '')
    if (!hookSecret) throw new Error("Missing hook secret")

    const wh = new Webhook(hookSecret)
    const verifiedPayload = wh.verify(payload, headers) as {
      user: { phone: string },
      sms: { otp: string }
    }

    const { user, sms } = verifiedPayload
    const phone = user.phone
    const code = sms.otp
    
    const API_KEY = "edcfdc83-33df-11f1-bfb4-0200cd936042"
    const TEMPLATE_NAME = "YOUR_TEMPLATE_NAME" 
    const cleanPhone = phone.replace('+', '')

    const url = `https://2factor.in/API/V1/${API_KEY}/SMS/${cleanPhone}/${code}/${TEMPLATE_NAME}`

    const response = await fetch(url, { method: 'GET' })
    const result = await response.json()

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