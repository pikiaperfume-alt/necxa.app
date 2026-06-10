// supabase/functions/initiate-airtel/index.ts
// NECXA – Airtel Money Payment Initiator
// Flow: Insert PENDING row → Call Airtel API → Return payment_id to client

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { initiateAirtelPayment } from "../_shared/payments.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { autoRefreshToken: false, persistSession: false } }
    );

    // ── Authenticate caller ──────────────────────────────────────
    const authHeader = req.headers.get("Authorization") ?? "";
    const { data: { user }, error: authErr } = await supabase.auth.getUser(
      authHeader.replace("Bearer ", "")
    );
    if (authErr || !user) return json({ error: "Unauthorized" }, 401);

    // ── Parse body ───────────────────────────────────────────────
    const { listing_id, phone, amount } = await req.json() as {
      listing_id: string;
      phone: string;
      amount: number;
    };

    if (!listing_id || !phone || !amount) {
      return json({ error: "Missing required fields: listing_id, phone, amount" }, 400);
    }

    // ── Validate listing exists ──────────────────────────────────
    const { data: listing, error: listingErr } = await supabase
      .from("listings")
      .select("id, unlock_cost_ugx, lister_id")
      .eq("id", listing_id)
      .single();

    if (listingErr || !listing) {
      return json({ error: "Listing not found" }, 404);
    }

    // ── Check for duplicate pending unlock ───────────────────────
    const { data: existing } = await supabase
      .from("listing_unlocks")
      .select("id, payment_status")
      .eq("listing_id", listing_id)
      .eq("buyer_agent_id", user.id)
      .in("payment_status", ["PENDING", "COMPLETED"])
      .maybeSingle();

    if (existing?.payment_status === "COMPLETED") {
      return json({ error: "You have already unlocked this listing" }, 409);
    }

    // ── A) Insert PENDING row into listing_unlocks ───────────────
    const { data: unlock, error: insertErr } = await supabase
      .from("listing_unlocks")
      .insert({
        listing_id,
        buyer_agent_id: user.id,
        buyer_email: user.email ?? "",
        buyer_phone: phone,
        amount_ugx: amount,
        payment_method: "AIRTEL_MONEY",
        payment_status: "PENDING",
      })
      .select()
      .single();

    if (insertErr) throw new Error(`DB insert failed: ${insertErr.message}`);

    // ── B) Call Airtel helper – use unlock.id as the reference ───
    const airtelRes = await initiateAirtelPayment({
      amount: Number(amount),
      phone,
      reference: unlock.id,                  // our DB id == provider reference
      callbackUrl: `${Deno.env.get("SUPABASE_URL")}/functions/v1/payment-webhook`,
    });

    // ── Store provider's transaction id back in our row ──────────
    await supabase
      .from("listing_unlocks")
      .update({ payment_ref: airtelRes.transaction.id })
      .eq("id", unlock.id);

    // ── C) Return payment_id to client ───────────────────────────
    return json({
      success: true,
      payment_id: unlock.id,              // client polls /rest/v1/payments?id=eq.this
      provider_ref: airtelRes.transaction.id,
    });

  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error("[initiate-airtel] error:", msg);
    return json({ error: msg }, 500);
  }
});
