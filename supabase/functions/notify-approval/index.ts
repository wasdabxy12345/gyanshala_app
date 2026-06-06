import { JWT } from "google-auth-library";
import { serve } from "std/http/server";

serve(async (req) => {
  try {
    const payload = await req.json();
    const { record } = payload;

    if (record.status !== "approved") {
      return new Response("Not approved", { status: 200 });
    }

    const secret = Deno.env.get("FIREBASE_SERVICE_ACCOUNT");
    if (!secret) throw new Error("Missing FIREBASE_SERVICE_ACCOUNT secret");

    console.log("Secret length:", secret.length);

    let serviceAccount;
    try {
      serviceAccount = JSON.parse(secret);
    } catch (_e) {
      console.log(
        "Failed to parse secret. First 20 chars:",
        secret.substring(0, 20),
      );
      throw new Error("Invalid JSON in FIREBASE_SERVICE_ACCOUNT secret");
    }

    console.log("Generating token...");
    const client = new JWT({
      email: serviceAccount.client_email,
      key: serviceAccount.private_key,
      scopes: ["https://www.googleapis.com/auth/firebase.messaging"],
    });

    const token = await client.getAccessToken();
    console.log("Token generated successfully!");

    const response = await fetch(
      `https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${token.token}`,
        },
        body: JSON.stringify({
          message: {
            token: record.push_token,
            notification: {
              title: "Account Approved!",
              body:
                `${record.first_name}, your signup request has been approved.`,
            },
            android: { priority: "high" },
            apns: { payload: { aps: { contentAvailable: true } } },
          },
        }),
      },
    );

    const result = await response.json();
    console.log("FIREBASE FINAL RESPONSE:", JSON.stringify(result));
    return new Response(JSON.stringify(result), { status: 200 });
  } catch (error: unknown) {
    const errorMessage = error instanceof Error
      ? error.message
      : "Unknown error";
    console.error("Error details:", errorMessage);
    return new Response(JSON.stringify({ error: errorMessage }), {
      status: 500,
    });
  }
});
