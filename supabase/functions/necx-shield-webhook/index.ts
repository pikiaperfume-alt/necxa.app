import { createClient } from "npm:@supabase/supabase-js@2.45.4";

/**
 * NECX Shield Webhook Handler (RECTIFIED)
 * Endpoint: /functions/v1/necx-shield-webhook
 * 
 * Flow: Webhook ONLY updates global profile trust scores.
 * ALL Listing/Property logic has been retired to ensure App-First integrity.
 */

type Payload = {
  sessionId: string;
  verificationId: string;
  external_reference?: string | null;
  status: "success" | "failed" | "pending";
  verification_type: "document" | "anchor" | "biometric";
  metadata: {
    agent_id: string;
    listing_id: string;
    property_id: string;
  };
  result?: {
    outcome?: "approved" | "rejected" | "manual_review" | string;
    score?: number;
    reason?: string | null;
  };
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-necx-signature",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function signatureToBytes(signature: string): Uint8Array {
  const s = signature.trim();
  if (/^[0-9a-fA-F]+$/.test(s) && s.length % 2 === 0) {
    return new Uint8Array(s.match(/.{1,2}/g)!.map((byte) => parseInt(byte, 16)));
  }
  const binStr = atob(s);
  const bytes = new Uint8Array(binStr.length);
  for (let i = 0; i < binStr.length; i++) bytes[i] = binStr.charCodeAt(i);
  return bytes;
}

async function verifySignature(body: string, signature: string, secret: string) {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    enc.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["verify"]
  );
  const sigBuf = signatureToBytes(signature);
  return await crypto.subtle.verify("HMAC", key, sigBuf, enc.encode(body));
}

function mapTrustScore(outcome?: string, status?: string): number {
  const o = (outcome ?? "").toLowerCase();
  const s = (status ?? "").toLowerCase();
  if (o === "approved" || s === "success") return 95;
  if (o === "rejected") return 20;
  if (o === "manual_review" || s === "pending") return 75;
  return 50;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { status: 200, headers: corsHeaders });

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const webhookSecret = Deno.env.get("SHIELD_WEBHOOK_SECRET") || "whsec_36uaoc";
    const supabase = createClient(supabaseUrl, serviceRoleKey);

    const signature = req.headers.get("x-necx-signature");
    const bodyText = await req.text();

    if (!signature || !(await verifySignature(bodyText, signature, webhookSecret))) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), { 
        status: 401, 
        headers: { ...corsHeaders, "Content-Type": "application/json" } 
      });
    }

    const payload: Payload = JSON.parse(bodyText);
    const { sessionId, status, verification_type, metadata } = payload;
    const trustScore = mapTrustScore(payload.result?.outcome, status);

    console.log(`Processing ${verification_type} webhook for sessionId: ${sessionId}`);

    // ── IDENTITY PATH ONLY ──────────────────────────────────────────────────
    // We only update the profile's global trust state. 
    // Property/Listing activation is now strictly handled by the app's synthesis call.
    if (verification_type === "document" || verification_type === "biometric") {
      const { error } = await supabase
        .from("profiles")
        .update({
          nin_verified: status === "success",
          face_verified: status === "success",
          trust_score: trustScore,
          shield_session_id: sessionId,
          verified_at: status === "success" ? new Date().toISOString() : null,
        })
        .eq("id", metadata.agent_id);

      if (error) throw error;
    }

    // 🛡️ RECTIFIED: 'anchor' logic removed to prevent risky direct server-to-server listing updates.
    // 🛡️ RECTIFIED: Redis cache invalidation removed.

    return new Response(JSON.stringify({ ok: true, sessionId }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("Webhook Processing Error:", err.message);
    return new Response(JSON.stringify({ error: err.message }), { 
      status: 500, 
      headers: { ...corsHeaders, "Content-Type": "application/json" } 
    });
  }
});