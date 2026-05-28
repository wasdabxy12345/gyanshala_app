import { serve } from "std/server";

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers":
          "authorization, x-client-info, apikey, content-type, x-supabase-signature",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
      },
    });
  }

  try {
    const msg91AuthKey = Deno.env.get("MSG91_AUTH_KEY");
    const msg91TemplateId = Deno.env.get("MSG91_TEMPLATE_ID");

    if (!msg91AuthKey || !msg91TemplateId) {
      throw new Error(
        "Missing structural MSG91 configuration credentials in Edge Secrets.",
      );
    }
    const body = await req.json();
    const phone = body.phone;
    const token = body.sms_data?.token || body.token;

    if (!phone) {
      throw new Error("Missing required delivery phone metadata parameter.");
    }
    if (!token) {
      console.log(
        `Auth event intercepted for phone: ${phone}. No OTP token found, passing through successfully.`,
      );
      return new Response(
        JSON.stringify({ success: true, message: "Pass-through safe." }),
        {
          headers: {
            "Access-Control-Allow-Origin": "*",
            "Content-Type": "application/json",
          },
          status: 200,
        },
      );
    }

    console.log(`Intercepted phone payload target string: ${phone}`);
    const sanitizedPhone = phone.replace("+", "").trim();
    const msg91Url =
      `https://control.msg91.com/api/v5/otp/send?template_id=${msg91TemplateId}&mobile=${sanitizedPhone}&authkey=${msg91AuthKey}`;
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 4000);
    console.log(
      "Despatching fetch thread execution over to MSG91 routing rails...",
    );
    const response = await fetch(msg91Url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        "OTP": token,
      }),
      signal: controller.signal,
    });
    clearTimeout(timeoutId);
    const responseText = await response.text();
    console.log("MSG91 terminal response feedback data:", responseText);
    if (!response.ok) {
      throw new Error(
        `MSG91 API endpoint returned failing status flag: ${response.status}`,
      );
    }
    return new Response(JSON.stringify({ success: true }), {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Content-Type": "application/json",
      },
      status: 200,
    });
  } catch (error: unknown) {
    const err = error instanceof Error ? error : new Error(String(error));
    console.error("Hook Thread Error Handler caught:", err.message);
    return new Response(JSON.stringify({ error: err.message }), {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Content-Type": "application/json",
      },
      status: 400,
    });
  }
});
