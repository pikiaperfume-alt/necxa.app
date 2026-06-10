// supabase/functions/payment-webhook/index.ts
// NECXA – Unified Payment Webhook Handler
// Receives callbacks from MTN MoMo & Airtel Money
// Verifies HMAC signature → updates listing_unlocks.payment_status → reveals contact

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-mtn-signature, x-airtel-signature",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

// ── HMAC-SHA256 Verification ────────────────────────────────────
async function verifyHmac(
  body: string,
  signature: string,
  secret: string
): Promise<boolean> {
  try {
    const enc = new TextEncoder();
    const key = await crypto.subtle.importKey(
      "raw",
      enc.encode(secret),
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["sign", "verify"]
    );
    // Signature may be hex or base64 — normalise to Uint8Array
    let sigBytes: Uint8Array;
    if (/^[0-9a-fA-F]+$/.test(signature) && signature.length % 2 === 0) {
      sigBytes = new Uint8Array(
        signature.match(/.{1,2}/g)!.map((b) => parseInt(b, 16))
      );
    } else {
      const bin = atob(signature);
      sigBytes = new Uint8Array(bin.length);
      for (let i = 0; i < bin.length; i++) sigBytes[i] = bin.charCodeAt(i);
    }
    return await crypto.subtle.verify("HMAC", key, sigBytes, enc.encode(body));
  } catch {
    return false;
  }
}

// ── Map provider status → our enum ──────────────────────────────
function mapStatus(providerStatus: string): "COMPLETED" | "FAILED" | null {
  const s = providerStatus?.toUpperCase();
  if (["SUCCESSFUL", "SUCCESS", "COMPLETED"].includes(s)) return "COMPLETED";
  if (["FAILED", "FAILURE", "REJECTED", "CANCELLED", "EXPIRED"].includes(s)) return "FAILED";
  return null; // still PENDING – ignore
}

// ── Reveal contact details on successful unlock ──────────────────
async function revealContact(
  supabase: ReturnType<typeof createClient>,
  unlockId: string,
  listingId: string
) {
  const { data: listing } = await supabase
    .from("listings")
    .select("owner_phone, owner_whatsapp, owner_meet_link, address, gps_lat, gps_lng, owner_email")
    .eq("id", listingId)
    .single();

  if (!listing) return;

  await supabase
    .from("listing_unlocks")
    .update({
      revealed_address:   listing.address,
      revealed_gps_lat:   listing.gps_lat,
      revealed_gps_lng:   listing.gps_lng,
      revealed_phone:     listing.owner_phone,
      revealed_whatsapp:  listing.owner_whatsapp,
      revealed_meet:      listing.owner_meet_link,
      revealed_email:     listing.owner_email,
      unlocked_at:        new Date().toISOString(),
    })
    .eq("id", unlockId);

  // Bump unlock_count on listing
  await supabase.rpc("increment_unlock_count", { p_listing_id: listingId });
}

// ── Main handler ────────────────────────────────────────────────
Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const rawBody = await req.text();

  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { autoRefreshToken: false, persistSession: false } }
    );

    // ── Detect provider by header ────────────────────────────────
    const mtnSig    = req.headers.get("x-mtn-signature");
    const airtelSig = req.headers.get("x-airtel-signature");

    let provider: "MTN_MOMO" | "AIRTEL_MONEY" | null = null;
    let verified = false;

    if (mtnSig) {
      provider = "MTN_MOMO";
      const secret = Deno.env.get("MTN_WEBHOOK_SECRET") ?? "";
      verified = secret ? await verifyHmac(rawBody, mtnSig, secret) : true; // skip if no secret (sandbox)
    } else if (airtelSig) {
      provider = "AIRTEL_MONEY";
      const secret = Deno.env.get("AIRTEL_WEBHOOK_SECRET") ?? "";
      verified = secret ? await verifyHmac(rawBody, airtelSig, secret) : true;
    } else {
      // No signature header – accept only if in sandbox mode
      const sandbox = Deno.env.get("PAYMENT_SANDBOX_MODE") === "true";
      if (!sandbox) return json({ error: "Missing provider signature" }, 401);
      verified = true;
    }

    if (!verified) {
      console.error("[payment-webhook] HMAC verification failed");
      return json({ error: "Signature verification failed" }, 401);
    }

    const payload = JSON.parse(rawBody);

    // ── Normalise across providers ───────────────────────────────
    //
    // MTN callback shape:
    // { financialTransactionId, externalId, status, payer, amount, currency }
    //
    // Airtel callback shape:
    // { transaction: { id, status }, ... }
    //
    let providerRef: string;
    let rawStatus: string;

    if (provider === "MTN_MOMO") {
      providerRef = payload.externalId ?? payload.financialTransactionId;
      rawStatus   = payload.status;
    } else if (provider === "AIRTEL_MONEY") {
      providerRef = payload.transaction?.id ?? payload.reference;
      rawStatus   = payload.transaction?.status ?? payload.status;
    } else {
      // Sandbox/testing – expect { payment_id, status }
      providerRef = payload.payment_id;
      rawStatus   = payload.status;
    }

    if (!providerRef) return json({ error: "Cannot identify payment reference" }, 400);

    const newStatus = mapStatus(rawStatus);
    if (!newStatus) {
      // Still in-flight – acknowledge without acting
      return json({ ok: true, message: "Payment still pending, no action taken" });
    }

    // ── Look up the unlock row by payment_ref ───────────────────
    // payment_ref = our unlock.id (MTN) or airtel transaction id
    const { data: unlock, error: findErr } = await supabase
      .from("listing_unlocks")
      .select("id, listing_id, payment_status")
      .or(`id.eq.${providerRef},payment_ref.eq.${providerRef}`)
      .maybeSingle();

    if (findErr || !unlock) {
      console.warn("[payment-webhook] No unlock row for ref:", providerRef);
      return json({ ok: true, message: "Reference not found – possibly test callback" });
    }

    // Idempotency – don't update an already-final row
    if (unlock.payment_status === "COMPLETED" || unlock.payment_status === "FAILED") {
      return json({ ok: true, message: "Already finalised" });
    }

    // ── B) Update payment_status = COMPLETED / FAILED ────────────
    await supabase
      .from("listing_unlocks")
      .update({ payment_status: newStatus })
      .eq("id", unlock.id);

    // ── On success → reveal agent/lister contact details ─────────
    if (newStatus === "COMPLETED") {
      await revealContact(supabase, unlock.id, unlock.listing_id);
    }

    console.log(`[payment-webhook] ${provider} → ${newStatus} for unlock ${unlock.id}`);
    return json({ ok: true, status: newStatus });

  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error("[payment-webhook] error:", msg);
    return json({ error: msg }, 500);
  }
});
