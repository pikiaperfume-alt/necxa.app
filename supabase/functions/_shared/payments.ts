// supabase/functions/_shared/payments.ts
// MTN MoMo + Airtel Money payment helpers

const MTN_BASE = Deno.env.get("_MOMO_BASE_URL") ?? "https://sandbox.momodeveloper.mtn.com";
const MTN_SUB_KEY = Deno.env.get("MTN_SUBSCRIPTION_KEY") ?? "";
const MTN_USER = Deno.env.get("MTN_API_USER") ?? "";
const MTN_KEY = Deno.env.get("MTN_API_KEY") ?? "";

const AIRTEL_BASE = Deno.env.get("AIRTEL_BASE_URL") ?? "https://openapiuat.airtel.africa";
const AIRTEL_ID = Deno.env.get("AIRTEL_CLIENT_ID") ?? "";
const AIRTEL_SECRET = Deno.env.get("AIRTEL_CLIENT_SECRET") ?? "";

function normalizeMsisdn(phone: string): string {
  const c = phone.replace(/\D/g, "");
  if (c.startsWith("256")) return c;
  if (c.startsWith("0")) return "256" + c.slice(1);
  return "256" + c;
}

async function getMTNToken(): Promise<string> {
  const res = await fetch(`${MTN_BASE}/collection/token/`, {
    method: "POST",
    headers: {
      "Authorization": `Basic ${btoa(`${MTN_USER}:${MTN_KEY}`)}`,
      "Ocp-Apim-Subscription-Key": MTN_SUB_KEY,
    },
  });
  const d = await res.json();
  return d.access_token;
}

export async function initiateMTNPayment(opts: {
  amount: number; currency?: string; phone: string;
  externalId: string; callbackUrl?: string; description: string;
}): Promise<{ referenceId: string }> {
  if (!MTN_SUB_KEY) {
    console.log("[MTN MOCK] Payment:", opts);
    return { referenceId: opts.externalId };
  }
  const token = await getMTNToken();
  const msisdn = normalizeMsisdn(opts.phone);
  await fetch(`${MTN_BASE}/collection/v1_0/requesttopay`, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${token}`,
      "X-Reference-Id": opts.externalId,
      "X-Target-Environment": "sandbox",
      "Ocp-Apim-Subscription-Key": MTN_SUB_KEY,
      "Content-Type": "application/json",
      ...(opts.callbackUrl ? { "X-Callback-Url": opts.callbackUrl } : {}),
    },
    body: JSON.stringify({
      amount: String(opts.amount),
      currency: opts.currency ?? "UGX",
      externalId: opts.externalId,
      payer: { partyIdType: "MSISDN", partyId: msisdn },
      payerMessage: opts.description,
      payeeNote: "NECXA Platform",
    }),
  });
  return { referenceId: opts.externalId };
}

export async function initiateAirtelPayment(opts: {
  amount: number; phone: string; reference: string; callbackUrl?: string;
}): Promise<{ transaction: { id: string } }> {
  if (!AIRTEL_ID) {
    console.log("[AIRTEL MOCK] Payment:", opts);
    return { transaction: { id: opts.reference } };
  }
  const tokenRes = await fetch(`${AIRTEL_BASE}/auth/oauth2/token`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ client_id: AIRTEL_ID, client_secret: AIRTEL_SECRET, grant_type: "client_credentials" }),
  });
  const { access_token } = await tokenRes.json();
  const msisdn = normalizeMsisdn(opts.phone);
  const res = await fetch(`${AIRTEL_BASE}/merchant/v1/payments/`, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${access_token}`,
      "Content-Type": "application/json",
      "X-Country": "UG", "X-Currency": "UGX",
    },
    body: JSON.stringify({
      reference: opts.reference,
      subscriber: { country: "UG", currency: "UGX", msisdn },
      transaction: { amount: opts.amount, country: "UG", currency: "UGX", id: opts.reference },
    }),
  });
  const d = await res.json();
  return { transaction: { id: d?.data?.transaction?.id ?? opts.reference } };
}

export async function initiateMTNDisbursement(opts: {
  amount: number; phone: string; externalId: string; description: string;
}): Promise<boolean> {
  if (!MTN_SUB_KEY) { console.log("[MTN DISBURSE MOCK]", opts); return true; }
  const token = await getMTNToken();
  const msisdn = normalizeMsisdn(opts.phone);
  const res = await fetch(`${MTN_BASE}/disbursement/v1_0/transfer`, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${token}`,
      "X-Reference-Id": opts.externalId,
      "X-Target-Environment": "sandbox",
      "Ocp-Apim-Subscription-Key": MTN_SUB_KEY,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      amount: String(opts.amount), currency: "UGX", externalId: opts.externalId,
      payee: { partyIdType: "MSISDN", partyId: msisdn },
      payerMessage: opts.description, payeeNote: "NECXA Creator/Agent Withdrawal",
    }),
  });
  return res.status === 202;
}
