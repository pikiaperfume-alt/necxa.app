const functions = require("firebase-functions");
const admin     = require("firebase-admin");
const speakeasy = require("speakeasy");
const qrcode    = require("qrcode");
const nodemailer = require("nodemailer");
const axios      = require("axios");

admin.initializeApp();
const db = admin.firestore();

// ── DYNAMIC FOREX CONFIG ───────────────────────────────────────────────────
let FOREX_RATES = {
  USD_TO_UGX: 3800, // Fallback
  last_updated: null
};

// Internal helper to get latest rates from Firestore
async function getCachedRates() {
  try {
    const doc = await db.collection("system_config").doc("forex").get();
    if (doc.exists) {
      FOREX_RATES = doc.data();
      return FOREX_RATES;
    }
  } catch (e) {
    console.error("Forex Cache Error:", e);
  }
  return FOREX_RATES;
}

// ── Economics ──
const NCX_PRICE_USD = 0.0263; // 1 NCX = ~0.0263 USD (equivalent to ~100 UGX at 3800 rate)
const BURN_RATE     = 0.11;   // 11% liquidation tax
const GIFT_PLATFORM_FEE = 0.20; // 20% platform cut on gifts

// ── Gift Items Catalogue (mirrors SQL seed) ──────────────────────────────────
const GIFT_CATALOGUE = [
  { id: "rose",        name: "Rose",         emoji: "🌹",  ncx_value: 1,     category: "standard",  sort_order: 1  },
  { id: "clap",        name: "Clap",         emoji: "👏",  ncx_value: 2,     category: "standard",  sort_order: 2  },
  { id: "heart",       name: "Heart",        emoji: "❤️",  ncx_value: 3,     category: "standard",  sort_order: 3  },
  { id: "coffee",      name: "Coffee",       emoji: "☕",  ncx_value: 5,     category: "standard",  sort_order: 4  },
  { id: "star",        name: "Star",         emoji: "⭐",  ncx_value: 5,     category: "standard",  sort_order: 5  },
  { id: "fire",        name: "Fire",         emoji: "🔥",  ncx_value: 10,    category: "standard",  sort_order: 6  },
  { id: "rocket",      name: "Rocket",       emoji: "🚀",  ncx_value: 20,    category: "rare",      sort_order: 10 },
  { id: "crown",       name: "Crown",        emoji: "👑",  ncx_value: 25,    category: "rare",      sort_order: 11 },
  { id: "diamond",     name: "Diamond",      emoji: "💎",  ncx_value: 50,    category: "rare",      sort_order: 12 },
  { id: "trophy",      name: "Trophy",       emoji: "🏆",  ncx_value: 50,    category: "rare",      sort_order: 13 },
  { id: "moneybag",    name: "Money Bag",    emoji: "💰",  ncx_value: 100,   category: "rare",      sort_order: 14 },
  { id: "sportscar",   name: "Sports Car",   emoji: "🏎️", ncx_value: 200,   category: "epic",      sort_order: 20 },
  { id: "yacht",       name: "Yacht",        emoji: "⛵",  ncx_value: 300,   category: "epic",      sort_order: 21 },
  { id: "villa",       name: "Villa",        emoji: "🏡",  ncx_value: 500,   category: "epic",      sort_order: 22 },
  { id: "jet",         name: "Private Jet",  emoji: "✈️",  ncx_value: 1000,  category: "legendary", sort_order: 30 },
  { id: "palace",      name: "NECXA Palace", emoji: "🏰",  ncx_value: 5000,  category: "legendary", sort_order: 31 },
  { id: "galaxy",      name: "Galaxy",       emoji: "🌌",  ncx_value: 10000, category: "legendary", sort_order: 32 },
];

// ── Seed gift_items on first call ────────────────────────────────────────────
async function ensureGiftCatalogue() {
  const snap = await db.collection("gift_items").limit(1).get();
  if (!snap.empty) return;
  const batch = db.batch();
  GIFT_CATALOGUE.forEach((item) => {
    const ref = db.collection("gift_items").doc(item.id);
    batch.set(ref, { ...item, ugx_value: item.ncx_value * 100, is_active: true });
  });
  await batch.commit();
}

/**
 * recordLedgerEntry
 * Creates an immutable record of balance changes for independent reconciliation.
 */
async function recordLedgerEntry(userId, { type, amount, currency, direction, metadata }, tx = null) {
  const ref = db.collection("ledger_entries").doc();
  const entry = {
    user_id: userId,
    type,
    amount,
    currency, // 'NCX' or 'UGX'
    direction, // 'in' or 'out'
    metadata: metadata || {},
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
    audit_id: ref.id
  };
  
  if (tx) {
    tx.set(ref, entry);
  } else {
    await ref.set(entry);
  }
}

/**
 * ensurePaymentMethod
 * Validates if a payment channel is active and supports the requested operation.
 */
async function ensurePaymentMethod(methodId, amount, type) {
  const ref = db.collection("system_config").doc("payment_methods");
  const doc = await ref.get();
  
  // Default fallback if config doesn't exist
  if (!doc.exists) return true; 

  const methods = doc.data().methods || {};
  const m = methods[methodId];

  if (!m) throw new functions.https.HttpsError("not-found", `Payment method ${methodId} not supported.`);
  if (m.status !== "active") throw new functions.https.HttpsError("unavailable", `Method ${methodId} is currently ${m.status}.`);
  if (m.type !== "both" && m.type !== type) throw new functions.https.HttpsError("permission-denied", `Method ${methodId} does not support ${type}.`);
  if (amount < m.min_amount) throw new functions.https.HttpsError("out-of-range", `Minimum amount for ${methodId} is ${m.min_amount}.`);
  if (amount > m.max_amount) throw new functions.https.HttpsError("out-of-range", `Maximum amount for ${methodId} is ${m.max_amount}.`);
  
  return true;
}

/**
 * initPaymentSystem
 * Seeds the initial payment method configuration.
 */
exports.initPaymentSystem = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Auth required.");
  
  const initialMethods = {
    methods: {
      mtn: { 
        id: "mtn", name: "MTN Mobile Money", status: "active", 
        type: "both", min_amount: 500, max_amount: 5000000 
      },
      airtel: { 
        id: "airtel", name: "Airtel Money", status: "active", 
        type: "both", min_amount: 500, max_amount: 5000000 
      },
      card: { 
        id: "card", name: "Bank / Card", status: "active", 
        type: "both", min_amount: 50000, max_amount: 20000000 
      }
    }
  };

  await db.collection("system_config").doc("payment_methods").set(initialMethods);
  return { success: true, message: "Payment system initialized with default methods." };
});

// ═══════════════════════════════════════════════════════════════════════════
// VAULT FUNCTIONS (existing)
// ═══════════════════════════════════════════════════════════════════════════

exports.buyCoins = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "User must be logged in.");
  const { packId, paymentMethod, securityMetadata } = data;
  const userId = context.auth.uid;

  if (!securityMetadata?.lat || !securityMetadata?.device_id)
    throw new functions.https.HttpsError("failed-precondition", "Missing security metadata.");

  // 1. Resolve pack and validate price
  const packDoc = await db.collection("coin_packs").doc(packId).get();
  if (!packDoc.exists) throw new functions.https.HttpsError("not-found", "Pack not found.");
  const { fiat_price } = packDoc.data();

  // 2. Validate availability
  await ensurePaymentMethod(paymentMethod, fiat_price, "collection");

  return await db.runTransaction(async (tx) => {
    const walletRef = db.collection("wallets").doc(userId);
    const packRef   = db.collection("coin_packs").doc(packId);
    const [walletDoc, packDoc] = await Promise.all([tx.get(walletRef), tx.get(packRef)]);
    if (!packDoc.exists) throw new functions.https.HttpsError("not-found", "Coin pack not found");
    const { ncx_amount, fiat_price } = packDoc.data();

    if (walletDoc.exists) {
      tx.update(walletRef, {
        coin_balance: admin.firestore.FieldValue.increment(ncx_amount),
        last_topup_at: admin.firestore.FieldValue.serverTimestamp(),
        last_topup_amount: ncx_amount,
        total_spent_fiat: admin.firestore.FieldValue.increment(fiat_price),
      });
    } else {
      tx.set(walletRef, {
        user_id: userId, coin_balance: ncx_amount, fiat_balance: 0.0,
        escrow_balance: 0.0, total_spent_fiat: fiat_price,
        created_at: admin.firestore.FieldValue.serverTimestamp(),
        last_topup_at: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
    const txRef = db.collection("vault_transactions").doc();
    tx.set(txRef, { user_id: userId, type: "buy_coins", pack_id: packId,
      ncx_added: ncx_amount, fiat_paid: fiat_price, payment_method: paymentMethod,
      status: "completed", timestamp: admin.firestore.FieldValue.serverTimestamp(),
      security: securityMetadata });

    // Independent Audit
    await recordLedgerEntry(userId, {
      type: "buy_coins",
      amount: ncx_amount,
      currency: "NCX",
      direction: "in",
      metadata: { pack_id: packId, fiat_paid: fiat_price }
    }, tx);

    return { success: true, message: `Purchased ${ncx_amount} NCX`, tx_id: txRef.id };
  });
});

exports.liquidateCoins = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "User must be logged in.");
  const { ncxAmount, securityMetadata } = data;
  const userId = context.auth.uid;
  if (!securityMetadata?.lat || !securityMetadata?.device_id)
    throw new functions.https.HttpsError("failed-precondition", "Missing security metadata.");

  return await db.runTransaction(async (tx) => {
    const walletRef = db.collection("wallets").doc(userId);
    const walletDoc = await tx.get(walletRef);
    if (!walletDoc.exists) throw new functions.https.HttpsError("not-found", "Wallet not found.");
    const { coin_balance: currentNcx, fiat_balance: currentFiat } = walletDoc.data();
    if (currentNcx < ncxAmount) throw new functions.https.HttpsError("failed-precondition", "Insufficient NCX.");
    const rates = await getCachedRates();
    const currentUgxPrice = rates.USD_TO_UGX * NCX_PRICE_USD;
    
    const ugxReceived = (ncxAmount * currentUgxPrice) * (1 - BURN_RATE);
    const ncxBurned   = ncxAmount * BURN_RATE;
    tx.update(walletRef, {
      coin_balance: admin.firestore.FieldValue.increment(-ncxAmount),
      fiat_balance: admin.firestore.FieldValue.increment(ugxReceived),
      last_liquidation_at: admin.firestore.FieldValue.serverTimestamp(),
    });
    const txRef = db.collection("vault_transactions").doc();
    tx.set(txRef, { user_id: userId, type: "liquidation", ncx_sold: ncxAmount,
      ncx_burned: ncxBurned, ugx_added: ugxReceived,
      exchange_rate: rates.USD_TO_UGX,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      status: "completed", security: securityMetadata });

    // Independent Audit (Double Entry)
    await recordLedgerEntry(userId, {
      type: "liquidation_out",
      amount: ncxAmount,
      currency: "NCX",
      direction: "out"
    }, tx);
    await recordLedgerEntry(userId, {
      type: "liquidation_in",
      amount: ugxReceived,
      currency: "UGX",
      direction: "in",
      metadata: { ncx_sold: ncxAmount, rate: rates.USD_TO_UGX }
    }, tx);

    return { success: true, ugxReceived, ncxBurned,
      newCoinBalance: currentNcx - ncxAmount, newFiatBalance: currentFiat + ugxReceived,
      txCommitHash: txRef.id, currentExchangeRate: rates.USD_TO_UGX, 
      message: `Liquidation successful at rate 1 USD = ${rates.USD_TO_UGX} UGX.` };
  });
});

// ── AML Limit Config ──────────────────────────────────────────────────────
const AML_MAX_USD  = 1000;

exports.withdrawFiat = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "User must be logged in.");

  const { amount, method, accountNumber, recipientName, totpToken, emailOtp, securityMetadata } = data;
  const userId = context.auth.uid;
  const email  = context.auth.token.email;

  const rates = await getCachedRates();
  const dynamicAmlLimitUgx = AML_MAX_USD * rates.USD_TO_UGX;

  // 1. Security metadata required
  if (!securityMetadata?.lat || !securityMetadata?.device_id)
    throw new functions.https.HttpsError("failed-precondition", "Missing security metadata.");

  // 2. Account number required
  if (!accountNumber || String(accountNumber).trim().length < 5)
    throw new functions.https.HttpsError("invalid-argument", "Valid account number is required.");

  // 3. ── AML Hard Cap ──
  if (!amount || amount <= 0)
    throw new functions.https.HttpsError("invalid-argument", "Invalid withdrawal amount.");
  
  if (amount > dynamicAmlLimitUgx)
    throw new functions.https.HttpsError("failed-precondition",
      `Withdrawal exceeds the maximum allowed limit of $${AML_MAX_USD} (UGX ${dynamicAmlLimitUgx.toLocaleString()}) based on current exchange rates.`);

  // 3.5 Validate Availability & Payout Limits
  await ensurePaymentMethod(method, amount, "disbursement");

  // 4. ── 2FA & Email Verification ──
  const securityRef = db.collection("wallets").doc(userId).collection("security").doc("config");
  const securityDoc = await securityRef.get();

  if (securityDoc.exists && securityDoc.data().is_2fa_enabled) {
    if (!totpToken) throw new functions.https.HttpsError("permission-denied", "2FA token required.");
    
    const verified = speakeasy.totp.verify({
      secret: securityDoc.data().two_factor_secret,
      encoding: "base32",
      token: totpToken,
      window: 1 // allow 30s drift
    });

    if (!verified) throw new functions.https.HttpsError("permission-denied", "Invalid 2FA token.");
  }

  // 5. ── Email OTP Check ──
  if (!emailOtp) throw new functions.https.HttpsError("permission-denied", "Email verification code required.");
  const otpRef = db.collection("internal_otps").doc(`${userId}_withdraw`);
  const otpDoc = await otpRef.get();

  if (!otpDoc.exists || otpDoc.data().code !== emailOtp) {
    throw new functions.https.HttpsError("permission-denied", "Invalid or expired email verification code.");
  }
  
  if (otpDoc.data().expires_at.toDate() < new Date()) {
    throw new functions.https.HttpsError("permission-denied", "Email verification code has expired.");
  }

  // Cleanup OTP after use
  await otpRef.delete();

  return await db.runTransaction(async (tx) => {
    const walletRef = db.collection("wallets").doc(userId);
    const walletDoc = await tx.get(walletRef);
    if (!walletDoc.exists) throw new functions.https.HttpsError("not-found", "Wallet not found.");
    const currentFiat = walletDoc.data().fiat_balance || 0;
    if (currentFiat < amount) throw new functions.https.HttpsError("failed-precondition", "Insufficient fiat balance.");
    tx.update(walletRef, {
      fiat_balance: admin.firestore.FieldValue.increment(-amount),
      total_withdrawn_fiat: admin.firestore.FieldValue.increment(amount),
      last_withdrawal_at: admin.firestore.FieldValue.serverTimestamp(),
    });
    const txRef = db.collection("vault_transactions").doc();
    tx.set(txRef, { 
      user_id: userId, 
      type: "withdraw_fiat", 
      amount_withdrawn: amount,
      disbursement_method: method, 
      account_number: accountNumber,
      recipient_name: recipientName,
      status: "processing",
      bank_processed: false,
      payout_status: "pending_bank_transfer",
      timestamp: admin.firestore.FieldValue.serverTimestamp(), 
      security: securityMetadata 
    });

    // Independent Audit
    await recordLedgerEntry(userId, {
      type: "withdraw_fiat",
      amount: amount,
      currency: "UGX",
      direction: "out",
      metadata: { method, account: accountNumber, recipient: recipientName }
    }, tx);

    return { success: true, message: `Withdrawal of UGX ${amount.toLocaleString()} via ${method} to ${accountNumber} initiated.`, tx_id: txRef.id };
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// SECURITY & 2FA FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════════

exports.request2FASetup = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "User must be logged in.");
  
  const secret = speakeasy.generateSecret({
    name: `Necxa Finance (${context.auth.token.email})`,
    issuer: "Necxa"
  });

  // Store temporary secret (not enabled yet)
  await db.collection("wallets").doc(context.auth.uid).collection("security").doc("config").set({
    temp_two_factor_secret: secret.base32,
    is_2fa_enabled: false
  }, { merge: true });

  const qrCodeData = await qrcode.toDataURL(secret.otpauth_url);
  return { secret: secret.base32, qrCode: qrCodeData };
});

exports.confirm2FASetup = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "User must be logged in.");
  const { token } = data;

  const securityRef = db.collection("wallets").doc(context.auth.uid).collection("security").doc("config");
  const securityDoc = await securityRef.get();

  if (!securityDoc.exists || !securityDoc.data().temp_two_factor_secret) {
    throw new functions.https.HttpsError("failed-precondition", "2FA setup not initiated.");
  }

  const verified = speakeasy.totp.verify({
    secret: securityDoc.data().temp_two_factor_secret,
    encoding: "base32",
    token: token
  });

  if (verified) {
    await securityRef.update({
      two_factor_secret: securityDoc.data().temp_two_factor_secret,
      temp_two_factor_secret: admin.firestore.FieldValue.delete(),
      is_2fa_enabled: true,
      enabled_at: admin.firestore.FieldValue.serverTimestamp()
    });
    return { success: true, message: "2FA successfully enabled." };
  } else {
    throw new functions.https.HttpsError("permission-denied", "Invalid verification token.");
  }
});

exports.sendWithdrawalOTP = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "User must be logged in.");
  const email = context.auth.token.email;
  if (!email) throw new functions.https.HttpsError("failed-precondition", "No email associated with account.");

  const otp = Math.floor(100000 + Math.random() * 900000).toString();
  
  await db.collection("internal_otps").doc(`${context.auth.uid}_withdraw`).set({
    code: otp,
    expires_at: admin.firestore.Timestamp.fromDate(new Date(Date.now() + 10 * 60 * 1000)), // 10 mins
    created_at: admin.firestore.FieldValue.serverTimestamp()
  });

  // TODO: Integrate with real SMTP. For now, we log it and return success.
  // In production, use nodemailer here.
  console.log(`[AUTH] Withdrawal OTP for ${email}: ${otp}`);
  
  return { success: true, message: "Verification code sent to your email." };
});

// ═══════════════════════════════════════════════════════════════════════════
// FOREX & SYSTEM CONFIG
// ═══════════════════════════════════════════════════════════════════════════

exports.refreshForexRates = functions.https.onCall(async (data, context) => {
  // Only allow admins or internal scheduled calls in production
  // For now, we allow any authenticated user to trigger a refresh for testing
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Auth required.");

  try {
    // Using ExchangeRate-API (Free Tier)
    const response = await axios.get("https://open.er-api.com/v6/latest/USD");
    const ugxRate = response.data.rates.UGX;

    if (!ugxRate) throw new Error("UGX rate not found in response.");

    const newRates = {
      USD_TO_UGX: ugxRate,
      all_rates: response.data.rates,
      last_updated: admin.firestore.FieldValue.serverTimestamp(),
      provider: "open.er-api.com"
    };

    await db.collection("system_config").doc("forex").set(newRates);
    
    return { success: true, newRate: ugxRate, message: `Exchange rates updated. 1 USD = ${ugxRate} UGX.` };
  } catch (e) {
    console.error("Forex Update Failed:", e);
    throw new functions.https.HttpsError("internal", `Failed to fetch rates: ${e.message}`);
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// GIFTING FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════════

/**
 * processGift
 * Atomic: debit sender → credit receiver (80%) → platform fee (20%)
 * → log ncx_gift → update streak → notify receiver
 */
exports.processGift = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "User must be logged in.");

  const {
    receiverId, giftItemId, ncxAmount,
    contextType, contextId, contextNote, isAnonymous,
  } = data;
  const senderId = context.auth.uid;

  // Validate context type
  const validContexts = ["creator_post","live_stream","property_listing","broadcast_message","direct"];
  if (!validContexts.includes(contextType))
    throw new functions.https.HttpsError("invalid-argument", "Invalid gift context.");
  if (!receiverId || !ncxAmount || ncxAmount < 1)
    throw new functions.https.HttpsError("invalid-argument", "Invalid gift parameters.");
  if (senderId === receiverId)
    throw new functions.https.HttpsError("invalid-argument", "Cannot gift yourself.");

  await ensureGiftCatalogue();

  // Resolve gift item
  let giftName = "Custom Gift", giftEmoji = "💎";
  if (giftItemId) {
    const itemDoc = await db.collection("gift_items").doc(giftItemId).get();
    if (itemDoc.exists) {
      giftName  = itemDoc.data().name;
      giftEmoji = itemDoc.data().emoji;
    }
  }

  // Split: 80% receiver, 20% platform
  const platformFeeNcx = Math.floor(ncxAmount * GIFT_PLATFORM_FEE);
  const receiverNcx    = ncxAmount - platformFeeNcx;
  
  const rates = await getCachedRates();
  const currentUgxPrice = rates.USD_TO_UGX * NCX_PRICE_USD;
  const ugxEquivalent  = ncxAmount * currentUgxPrice;
  const isHighlighted  = ncxAmount >= 500;

  try {
    const giftRef   = db.collection("ncx_gifts").doc();
    const senderTxRef = db.collection("vault_transactions").doc();
    const recvTxRef   = db.collection("vault_transactions").doc();
    const notifRef    = db.collection("notifications").doc();

    await db.runTransaction(async (tx) => {
      const senderWalletRef   = db.collection("wallets").doc(senderId);
      const receiverWalletRef = db.collection("wallets").doc(receiverId);
      const senderWalletDoc   = await tx.get(senderWalletRef);

      if (!senderWalletDoc.exists)
        throw new functions.https.HttpsError("not-found", "Sender wallet not found.");

      const senderBalance = senderWalletDoc.data().coin_balance || 0;
      if (senderBalance < ncxAmount)
        throw new functions.https.HttpsError("failed-precondition",
          `Insufficient NCX. Have: ${senderBalance}, Need: ${ncxAmount}`);

      // 1. Debit sender full amount
      tx.update(senderWalletRef, {
        coin_balance: admin.firestore.FieldValue.increment(-ncxAmount),
        total_gifts_sent_ncx: admin.firestore.FieldValue.increment(ncxAmount),
        last_gift_sent_at: admin.firestore.FieldValue.serverTimestamp(),
      });

      // 2. Credit receiver 80%
      tx.set(receiverWalletRef, {
        coin_balance: admin.firestore.FieldValue.increment(receiverNcx),
        total_gifts_received_ncx: admin.firestore.FieldValue.increment(receiverNcx),
        user_id: receiverId,
      }, { merge: true });

      // 3. Sender vault transaction
      tx.set(senderTxRef, {
        user_id: senderId, type: "gift_sent",
        ncx_amount: ncxAmount, ugx_equivalent: ugxEquivalent,
        platform_fee_ncx: platformFeeNcx,
        gift_name: giftName, gift_emoji: giftEmoji,
        receiver_id: receiverId, context_type: contextType,
        context_id: contextId || null, status: "completed",
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });

      // 4. Receiver vault transaction
      tx.set(recvTxRef, {
        user_id: receiverId, type: "gift_received",
        ncx_amount: receiverNcx, ugx_equivalent: receiverNcx * currentUgxPrice,
        gift_name: giftName, gift_emoji: giftEmoji,
        sender_id: isAnonymous ? null : senderId,
        context_type: contextType, context_id: contextId || null,
        status: "completed", timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });

      // 5. Immutable gift ledger record
      tx.set(giftRef, {
        sender_id: senderId, receiver_id: receiverId,
        gift_item_id: giftItemId || null,
        gift_name: giftName, gift_emoji: giftEmoji,
        ncx_amount: ncxAmount, ugx_equivalent: ugxEquivalent,
        platform_fee_ncx: platformFeeNcx, receiver_ncx: receiverNcx,
        context_type: contextType, context_id: contextId || null,
        context_note: contextNote || null,
        is_anonymous: isAnonymous || false, is_highlighted: isHighlighted,
        status: "completed",
        sender_txn_id: senderTxRef.id, receiver_txn_id: recvTxRef.id,
        created_at: admin.firestore.FieldValue.serverTimestamp(),
      });

      // 6. Notification for receiver
      tx.set(notifRef, {
        user_id: receiverId, type: "gift_received",
        title: `${giftEmoji} You received a gift!`,
        body: isAnonymous
          ? `Someone sent you ${giftName} (${receiverNcx} NCX)`
          : `Someone sent you ${giftEmoji} ${giftName} — ${receiverNcx} NCX`,
        metadata: {
          gift_id: giftRef.id, gift_emoji: giftEmoji,
          ncx_amount: receiverNcx,
          sender_id: isAnonymous ? null : senderId,
          context_type: contextType, context_id: contextId || null,
        },
        is_read: false,
        created_at: admin.firestore.FieldValue.serverTimestamp(),
      });

      // 6. Independent Audits (Inside Transaction)
      await recordLedgerEntry(senderId, {
        type: "gift_sent", amount: ncxAmount, currency: "NCX", direction: "out",
        metadata: { receiver_id: receiverId, platform_fee: platformFeeNcx }
      }, tx);
      
      await recordLedgerEntry(receiverId, {
        type: "gift_received", amount: receiverNcx, currency: "NCX", direction: "in",
        metadata: { sender_id: senderId, platform_fee: platformFeeNcx }
      }, tx);

      // Record Platform Revenue
      if (platformFeeNcx > 0) {
        await recordLedgerEntry("platform_revenue", {
          type: "gift_fee", amount: platformFeeNcx, currency: "NCX", direction: "in",
          metadata: { sender_id: senderId, receiver_id: receiverId, gift_id: giftRef.id }
        }, tx);
      }
    });

    // 7. Update streak (outside transaction — best-effort)
    await _updateGiftStreak(senderId, ncxAmount);

    return {
      success: true, giftId: giftRef.id,
      giftEmoji, giftName, ncxAmount, receiverNcx, platformFeeNcx,
      ugxEquivalent, isHighlighted,
      message: `${giftEmoji} Gift sent! ${receiverNcx} NCX delivered.`,
    };
  } catch (error) {
    console.error("🔥 processGift Error:", error);
    if (error instanceof functions.https.HttpsError) throw error;
    throw new functions.https.HttpsError("internal", error.message);
  }
});

/**
 * getContextGifts
 * Returns recent gifts for a given context (post, stream, listing…)
 */
exports.getContextGifts = functions.https.onCall(async (data, _context) => {
  const { contextId, contextType, limit = 20 } = data;
  if (!contextId || !contextType)
    throw new functions.https.HttpsError("invalid-argument", "contextId and contextType required.");

  const snap = await db.collection("ncx_gifts")
    .where("context_id", "==", contextId)
    .where("context_type", "==", contextType)
    .where("status", "==", "completed")
    .orderBy("ncx_amount", "desc")
    .orderBy("created_at", "desc")
    .limit(limit)
    .get();

  return snap.docs.map((doc) => {
    const d = doc.data();
    return {
      gift_id: doc.id,
      sender_id: d.is_anonymous ? null : d.sender_id,
      gift_emoji: d.gift_emoji, gift_name: d.gift_name,
      ncx_amount: d.ncx_amount, ugx_equivalent: d.ugx_equivalent,
      receiver_ncx: d.receiver_ncx,
      is_anonymous: d.is_anonymous, is_highlighted: d.is_highlighted,
      created_at: d.created_at?.toDate()?.toISOString() || null,
    };
  });
});

/**
 * getContextGiftTotals
 * Aggregated gift stats for a context.
 */
exports.getContextGiftTotals = functions.https.onCall(async (data, _context) => {
  const { contextId, contextType } = data;
  if (!contextId || !contextType)
    throw new functions.https.HttpsError("invalid-argument", "contextId and contextType required.");

  const snap = await db.collection("ncx_gifts")
    .where("context_id", "==", contextId)
    .where("context_type", "==", contextType)
    .where("status", "==", "completed")
    .get();

  if (snap.empty) return { total_gifts: 0, total_ncx: 0, total_ugx: 0, unique_gifters: 0, top_emoji: null };

  let totalNcx = 0, totalUgx = 0;
  const gifters = new Set();
  const emojiMap = {};

  snap.docs.forEach((doc) => {
    const d = doc.data();
    totalNcx += d.ncx_amount || 0;
    totalUgx += d.ugx_equivalent || 0;
    gifters.add(d.sender_id);
    emojiMap[d.gift_emoji] = (emojiMap[d.gift_emoji] || 0) + (d.ncx_amount || 0);
  });

  const topEmoji = Object.entries(emojiMap).sort((a, b) => b[1] - a[1])[0]?.[0] || null;

  return {
    total_gifts: snap.size, total_ncx: totalNcx, total_ugx: totalUgx,
    unique_gifters: gifters.size, top_emoji: topEmoji,
  };
});

/**
 * getTopGifters — leaderboard of top NCX senders
 */
exports.getTopGifters = functions.https.onCall(async (data, _context) => {
  const limit = data?.limit || 20;
  const snap = await db.collection("gift_streaks")
    .orderBy("total_ncx_sent", "desc")
    .limit(limit)
    .get();

  return snap.docs.map((doc) => ({
    user_id: doc.id,
    total_ncx_sent: doc.data().total_ncx_sent || 0,
    total_gifts_sent: doc.data().total_gifts_sent || 0,
    current_streak: doc.data().current_streak || 0,
    longest_streak: doc.data().longest_streak || 0,
  }));
});

/**
 * getTopReceivers — leaderboard of top NCX receivers
 */
exports.getTopReceivers = functions.https.onCall(async (data, _context) => {
  const limit = data?.limit || 20;
  const snap = await db.collection("wallets")
    .orderBy("total_gifts_received_ncx", "desc")
    .limit(limit)
    .get();

  return snap.docs.map((doc) => ({
    user_id: doc.id,
    total_ncx_received: doc.data().total_gifts_received_ncx || 0,
  }));
});

// ── Helpers ──────────────────────────────────────────────────────────────────

async function _updateGiftStreak(userId, ncxAmount) {
  try {
    const streakRef = db.collection("gift_streaks").doc(userId);
    const streakDoc = await streakRef.get();
    const today = new Date().toISOString().split("T")[0]; // YYYY-MM-DD

    if (!streakDoc.exists) {
      await streakRef.set({
        user_id: userId, current_streak: 1, longest_streak: 1,
        last_gift_date: today, total_gifts_sent: 1, total_ncx_sent: ncxAmount,
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      });
      return;
    }

    const d = streakDoc.data();
    const lastDate = d.last_gift_date;
    const yesterday = new Date(Date.now() - 86400000).toISOString().split("T")[0];
    let newStreak = 1;
    if (lastDate === yesterday) newStreak = (d.current_streak || 0) + 1;
    else if (lastDate === today)  newStreak = d.current_streak || 1;

    await streakRef.update({
      current_streak: newStreak,
      longest_streak: Math.max(d.longest_streak || 0, newStreak),
      last_gift_date: today,
      total_gifts_sent: admin.firestore.FieldValue.increment(1),
      total_ncx_sent: admin.firestore.FieldValue.increment(ncxAmount),
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
    });
  } catch (e) {
    console.error("Streak update failed (non-critical):", e);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PAYMENT GATEWAY
// ═══════════════════════════════════════════════════════════════════════════

exports.necxaPaymentGateway = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "User must be logged in.");
  
  const { listing_id, method, amount, buyer_id, buyer_email, buyer_phone } = data;
  
  if (!listing_id || !method || !amount) {
    throw new functions.https.HttpsError("invalid-argument", "Missing required payment fields.");
  }

  // Verify buyer_id matches authenticated user
  if (buyer_id !== context.auth.uid) {
    throw new functions.https.HttpsError("permission-denied", "Buyer ID mismatch.");
  }

  const paymentRef = db.collection("listing_unlocks").doc();
  const paymentId = paymentRef.id;

  if (method === 'NCX_COINS') {
    // Process with internal wallet
    return await db.runTransaction(async (tx) => {
      const walletRef = db.collection("wallets").doc(buyer_id);
      const walletDoc = await tx.get(walletRef);
      
      if (!walletDoc.exists) {
        throw new functions.https.HttpsError("not-found", "Wallet not found.");
      }
      
      const currentBalance = walletDoc.data().coin_balance || 0;
      if (currentBalance < amount) {
        throw new functions.https.HttpsError("failed-precondition", "Insufficient NCX Coins.");
      }
      
      // Deduct from wallet
      tx.update(walletRef, {
        coin_balance: admin.firestore.FieldValue.increment(-amount)
      });
      
      // Record payment completion
      tx.set(paymentRef, {
        buyer_id,
        listing_id,
        method,
        amount,
        payment_status: "COMPLETED",
        timestamp: admin.firestore.FieldValue.serverTimestamp()
      });

      // Record vault transaction
      const txRef = db.collection("vault_transactions").doc();
      tx.set(txRef, {
        user_id: buyer_id,
        type: "listing_unlock",
        ncx_paid: amount,
        listing_id,
        status: "completed",
        timestamp: admin.firestore.FieldValue.serverTimestamp()
      });

      // Independent Audit
      await recordLedgerEntry(buyer_id, {
        type: "listing_unlock",
        amount: amount,
        currency: "NCX",
        direction: "out",
        metadata: { listing_id }
      }, tx);

      return { success: true, payment_id: paymentId, status: "COMPLETED" };
    });
  } else {
    // External Mobile Money / Card Payment
    // Simulate initiation and create a PROCESSING record.
    
    await paymentRef.set({
      buyer_id,
      buyer_email,
      buyer_phone,
      listing_id,
      method,
      amount,
      payment_status: "PROCESSING", // A webhook or polling would update this
      timestamp: admin.firestore.FieldValue.serverTimestamp()
    });

    // Simulate webhook completion after a few seconds for testing purposes
    setTimeout(async () => {
      try {
        await paymentRef.update({ payment_status: "COMPLETED" });
      } catch (e) {
        console.error("Mock webhook update failed:", e);
      }
    }, 5000);

    return { success: true, payment_id: paymentId, status: "PROCESSING", message: "Payment initiated" };
  }
});
