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
 * Synced to both Firestore (legacy/fast read) and Supabase (cryptographic ledger).
 */
async function recordLedgerEntry(userId, { type, amount, currency, direction, metadata, reference_id }, tx = null) {
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

// dual-write mapper
  const typeMap = {
    "buy_coins": "COIN_PURCHASE",
    "listing_unlock": "LISTING_UNLOCK",
    "gift_sent": "GIFT_SENT",
    "gift_received": "GIFT_RECEIVED",
    "gift_fee": "PLATFORM_FEE",
    "withdraw_fiat": "WITHDRAWAL",
    "liquidation_in": "WITHDRAWAL",
    "liquidation_out": "WITHDRAWAL",
    "shop_purchase": "SHOP_PURCHASE",
    "delivery_fee": "DELIVERY_FEE",
    "escrow_deposit": "ESCROW_DEPOSIT",
    "escrow_release": "ESCROW_RELEASE",
    "escrow_refund": "ESCROW_REFUND"
  };
  const supabaseType = typeMap[type] || type.toUpperCase();

  // Dual-Write to Supabase Immutable Ledger
  try {
    const supabaseUrl = process.env.SUPABASE_URL;
    const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
    if (supabaseUrl && supabaseKey) {
      axios.post(`${supabaseUrl}/rest/v1/immutable_financial_ledger`, {
        user_id: userId,
        entry_type: supabaseType,
        amount: Math.round(amount), // Ensure integer for bigint
        currency: currency,
        direction: direction,
        balance_after: 0, // Supabase calculates this via trigger in the future, or we just supply 0 for now
        reference_id: reference_id || null,
        metadata: { ...metadata, firestore_audit_id: ref.id }
      }, {
        headers: {
          'apikey': supabaseKey,
          'Authorization': `Bearer ${supabaseKey}`,
          'Content-Type': 'application/json',
          'Prefer': 'return=minimal'
        }
      }).catch(err => {
        console.error("Supabase Ledger Sync Error:", err.response?.data || err.message);
      });
    } else {
      console.warn("SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY missing. Skipping Supabase ledger sync.");
    }
  } catch (e) {
    console.error("Failed to initiate Supabase sync:", e.message);
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
// SHOP E-COMMERCE & LOGISTICS PAYMENT (INTERNAL WALLET)
// ═══════════════════════════════════════════════════════════════════════════

exports.processShopPurchase = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Auth required.");
  const userId = context.auth.uid;
  const { orderId, listingId, vendorId, sku, itemsTotalUgx, deliveryFeeUgx, quantity } = data;

  if (!orderId || !listingId || !vendorId || itemsTotalUgx == null || deliveryFeeUgx == null) {
    throw new functions.https.HttpsError("invalid-argument", "Missing required shop parameters.");
  }

  const rates = await getCachedRates();
  const ugxPerNcx = NCX_PRICE_USD * rates.USD_TO_UGX; // ~100 UGX
  const ncxItemsCost = Math.ceil(itemsTotalUgx / ugxPerNcx);
  const ncxDeliveryCost = Math.ceil(deliveryFeeUgx / ugxPerNcx);
  const totalNcxCost = ncxItemsCost + ncxDeliveryCost;

  return await db.runTransaction(async (tx) => {
    const walletRef = db.collection("wallets").doc(userId);
    const walletDoc = await tx.get(walletRef);

    if (!walletDoc.exists) throw new functions.https.HttpsError("not-found", "Wallet not found.");
    const currentBalance = walletDoc.data().coin_balance || 0;

    if (currentBalance < totalNcxCost) {
      throw new functions.https.HttpsError("resource-exhausted", "Insufficient NCX balance for shop purchase.");
    }

    // Deduct total balance
    tx.update(walletRef, {
      coin_balance: admin.firestore.FieldValue.increment(-totalNcxCost)
    });

    const vendorPlatformFee = Math.floor(ncxItemsCost * 0.03);
    const vendorNetEarned = ncxItemsCost - vendorPlatformFee;

    // Credit Vendor for the item (minus 3% platform fee)
    const vendorWalletRef = db.collection("wallets").doc(vendorId);
    tx.set(vendorWalletRef, {
      coin_balance: admin.firestore.FieldValue.increment(vendorNetEarned)
    }, { merge: true });

    // Mark Order Paid and save NCX costs for future driver payout
    const orderRef = db.collection("orders").doc(orderId);
    tx.update(orderRef, {
      status: "paid",
      payment_method: "balance",
      items_ncx: ncxItemsCost,
      delivery_ncx: ncxDeliveryCost,
      paid_at: admin.firestore.FieldValue.serverTimestamp()
    });

    // 1. Ledger Entry for Shop Purchase (Goods)
    await recordLedgerEntry(userId, {
      type: "shop_purchase",
      amount: ncxItemsCost,
      currency: "NCX",
      direction: "out",
      reference_id: orderId,
      metadata: { sku: sku, listing_id: listingId, quantity, ugx_value: itemsTotalUgx }
    }, tx);

    await recordLedgerEntry(vendorId, {
      type: "shop_purchase",
      amount: vendorNetEarned,
      currency: "NCX",
      direction: "in",
      reference_id: orderId,
      metadata: { sku: sku, listing_id: listingId, quantity, ugx_value: itemsTotalUgx, fee_deducted: vendorPlatformFee }
    }, tx);

    if (vendorPlatformFee > 0) {
      await recordLedgerEntry("platform_revenue", {
        type: "gift_fee", // Translates to PLATFORM_FEE
        amount: vendorPlatformFee,
        currency: "NCX",
        direction: "in",
        reference_id: orderId,
        metadata: { source: "shop_vendor_commission", sku: sku }
      }, tx);
    }

    // 2. Ledger Entry for Delivery/Logistics Trip
    if (ncxDeliveryCost > 0) {
      const tripId = `TRIP-${orderId.split('-')[1] || Date.now()}`;
      await recordLedgerEntry(userId, {
        type: "delivery_fee",
        amount: ncxDeliveryCost,
        currency: "NCX",
        direction: "out",
        reference_id: orderId,
        metadata: { trip_id: tripId, ugx_value: deliveryFeeUgx }
      }, tx);
      
      // Update order with trip ID
      tx.update(orderRef, { trip_id: tripId });
    }

    return { success: true, message: "Shop purchase completed successfully." };
  });
});

exports.completeDeliveryTrip = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Auth required.");
  const driverId = context.auth.uid;
  const { orderId } = data;

  if (!orderId) throw new functions.https.HttpsError("invalid-argument", "Missing orderId.");

  return await db.runTransaction(async (tx) => {
    const orderRef = db.collection("orders").doc(orderId);
    const orderDoc = await tx.get(orderRef);

    if (!orderDoc.exists) throw new functions.https.HttpsError("not-found", "Order not found.");
    const orderData = orderDoc.data();

    if (orderData.driver_id !== driverId) {
      throw new functions.https.HttpsError("permission-denied", "You are not assigned to this trip.");
    }
    if (orderData.driver_paid) {
      throw new functions.https.HttpsError("already-exists", "Driver has already been paid for this trip.");
    }
    if (orderData.status !== "paid" && orderData.status !== "completed") {
      throw new functions.https.HttpsError("failed-precondition", "Order must be paid before trip completion.");
    }

    // Determine the delivery value in NCX
    let ncxDeliveryValue = orderData.delivery_ncx;
    if (!ncxDeliveryValue && orderData.metadata?.delivery_ugx) {
       // Convert UGX to NCX if paying via pesapal
       const rates = await getCachedRates();
       const ugxPerNcx = NCX_PRICE_USD * rates.USD_TO_UGX;
       ncxDeliveryValue = Math.ceil(orderData.metadata.delivery_ugx / ugxPerNcx);
    }
    if (!ncxDeliveryValue) {
       ncxDeliveryValue = 0; // fallback if no fee
    }

    // Calculate 4% Platform Fee
    const platformFee = Math.floor(ncxDeliveryValue * 0.04);
    const driverNetEarned = ncxDeliveryValue - platformFee;

    if (driverNetEarned > 0) {
      // Credit Driver
      const driverWalletRef = db.collection("wallets").doc(driverId);
      tx.set(driverWalletRef, {
        coin_balance: admin.firestore.FieldValue.increment(driverNetEarned)
      }, { merge: true });

      // Record Ledger Entries
      await recordLedgerEntry(driverId, {
        type: "commission_payout", // translates to COMMISSION_PAYOUT
        amount: driverNetEarned,
        currency: "NCX",
        direction: "in",
        reference_id: orderId,
        metadata: { trip_id: orderData.trip_id, source: "delivery", fee_deducted: platformFee }
      }, tx);

      if (platformFee > 0) {
        await recordLedgerEntry("platform_revenue", {
          type: "gift_fee", // translates to PLATFORM_FEE
          amount: platformFee,
          currency: "NCX",
          direction: "in",
          reference_id: orderId,
          metadata: { trip_id: orderData.trip_id, source: "delivery_driver_commission" }
        }, tx);
      }
    }

    // Update order status
    tx.update(orderRef, {
      status: "completed",
      driver_paid: true,
      delivered_at: admin.firestore.FieldValue.serverTimestamp()
    });

    return { success: true, message: "Delivery completed and driver credited." };
  });
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
    const senderAuditRef = db.collection("audit_logs").doc(senderId).collection("live_gifts").doc(giftRef.id);
    const receiverAuditRef = db.collection("audit_logs").doc(receiverId).collection("live_gifts").doc(giftRef.id);

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

      tx.set(senderAuditRef, {
        user_id: senderId,
        counterparty_id: receiverId,
        gift_id: giftRef.id,
        event_type: "live_gift_sent",
        gift_name: giftName,
        gift_emoji: giftEmoji,
        ncx_amount: ncxAmount,
        receiver_ncx: receiverNcx,
        platform_fee_ncx: platformFeeNcx,
        context_type: contextType,
        context_id: contextId || null,
        created_at: admin.firestore.FieldValue.serverTimestamp(),
      });

      tx.set(receiverAuditRef, {
        user_id: receiverId,
        counterparty_id: isAnonymous ? null : senderId,
        gift_id: giftRef.id,
        event_type: "live_gift_received",
        gift_name: giftName,
        gift_emoji: giftEmoji,
        ncx_amount: receiverNcx,
        gross_ncx_amount: ncxAmount,
        platform_fee_ncx: platformFeeNcx,
        context_type: contextType,
        context_id: contextId || null,
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

// ═══════════════════════════════════════════════════════════════════════════
// PESAPAL PAYMENT INTEGRATION (LIVE)
// ═══════════════════════════════════════════════════════════════════════════
const PESAPAL_BASE_URL = "https://pay.pesapal.com/v3";
// To use secrets in v1, we configure runWith:
const pesapalConfig = { secrets: ["PESAPAL_CONSUMER_KEY", "PESAPAL_CONSUMER_SECRET"] };

/**
 * Helper to get Pesapal Bearer Token
 */
async function getPesapalToken() {
  const consumerKey = process.env.PESAPAL_CONSUMER_KEY;
  const consumerSecret = process.env.PESAPAL_CONSUMER_SECRET;
  
  if (!consumerKey || !consumerSecret) {
    throw new Error("Pesapal credentials not found in Secret Manager.");
  }

  const response = await axios.post(`${PESAPAL_BASE_URL}/api/Auth/RequestToken`, {
    consumer_key: consumerKey,
    consumer_secret: consumerSecret
  }, {
    headers: { 'Content-Type': 'application/json', 'Accept': 'application/json' }
  });

  return response.data.token;
}

/**
 * Helper to register IPN if not exists. 
 * We will cache the IPN ID in Firestore to avoid registering it every time.
 */
async function getOrRegisterIPN(token) {
  // Use Firebase hosting or functions URL
  const ipnUrl = `https://us-central1-${process.env.GCLOUD_PROJECT}.cloudfunctions.net/pesapalWebhook`;
  
  const ipnConfigRef = db.collection("system_config").doc("pesapal_ipn");
  const doc = await ipnConfigRef.get();
  if (doc.exists && doc.data().ipn_id) {
    return doc.data().ipn_id;
  }

  // Register IPN
  const response = await axios.post(`${PESAPAL_BASE_URL}/api/URLSetup/RegisterIPN`, {
    url: ipnUrl,
    ipn_notification_type: "POST"
  }, {
    headers: { 
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json',
      'Accept': 'application/json' 
    }
  });

  if (response.data && response.data.ipn_id) {
    await ipnConfigRef.set({ ipn_id: response.data.ipn_id, url: ipnUrl });
    return response.data.ipn_id;
  }
  
  throw new Error("Failed to register IPN with Pesapal.");
}

/**
 * initiatePesapalPayment (Callable)
 * Generates an order and returns the redirect URL for checkout.
 */
exports.initiatePesapalPayment = require("firebase-functions/v1").runWith(pesapalConfig).https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "User must be logged in.");

  const { amount, currency = "UGX", description, type, packId, listingId, email, phone } = data;
  const userId = context.auth.uid;
  const userEmail = email || context.auth.token.email || "no-reply@necxa.uk";
  
  if (!amount || amount <= 0) {
    throw new functions.https.HttpsError("invalid-argument", "Invalid amount.");
  }

  try {
    const token = await getPesapalToken();
    const ipnId = await getOrRegisterIPN(token);

    // Create a local order reference
    const orderRef = db.collection("pesapal_orders").doc();
    const orderId = orderRef.id;

    // Submit Order to Pesapal
    const orderData = {
      id: orderId,
      currency: currency,
      amount: parseFloat(amount).toFixed(2),
      description: description || "Necxa Payment",
      callback_url: `https://necxa.uk/payment-callback?orderId=${orderId}`,
      notification_id: ipnId,
      billing_address: {
        email_address: userEmail,
        phone_number: phone || "",
        country_code: "UG",
        first_name: "Necxa",
        last_name: "User",
        line_1: "Kampala",
        city: "Kampala"
      }
    };

    const response = await axios.post(`${PESAPAL_BASE_URL}/api/Transactions/SubmitOrderRequest`, orderData, {
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json',
        'Accept': 'application/json'
      }
    });

    if (response.data && response.data.redirect_url) {
      const pesapalOrderTrackingId = response.data.order_tracking_id;

      // Save pending order
      await orderRef.set({
        user_id: userId,
        type: type, // 'buy_coins' or 'unlock_listing'
        amount: amount,
        currency: currency,
        pack_id: packId || null,
        listing_id: listingId || null,
        status: "PENDING",
        pesapal_tracking_id: pesapalOrderTrackingId,
        redirect_url: response.data.redirect_url,
        created_at: admin.firestore.FieldValue.serverTimestamp()
      });

      return {
        success: true,
        redirect_url: response.data.redirect_url,
        order_tracking_id: pesapalOrderTrackingId,
        order_id: orderId
      };
    } else {
      throw new Error("Invalid response from Pesapal SubmitOrderRequest.");
    }
  } catch (error) {
    console.error("Pesapal Initiate Error:", error.response?.data || error.message);
    throw new functions.https.HttpsError("internal", "Failed to initiate payment with Pesapal.");
  }
});

/**
 * pesapalWebhook (HTTP)
 * Receives IPNs from Pesapal, verifies the transaction, and fulfills the order.
 */
exports.pesapalWebhook = require("firebase-functions/v1").runWith(pesapalConfig).https.onRequest(async (req, res) => {
  // Pesapal sends OrderTrackingId and OrderNotificationType in query params or body
  const orderTrackingId = req.query.OrderTrackingId || req.body.OrderTrackingId;
  const orderMerchantReference = req.query.OrderMerchantReference || req.body.OrderMerchantReference;
  
  if (!orderTrackingId) {
    res.status(400).send("Missing OrderTrackingId");
    return;
  }

  try {
    const token = await getPesapalToken();
    
    // Check status with Pesapal
    const statusRes = await axios.get(`${PESAPAL_BASE_URL}/api/Transactions/GetTransactionStatus?orderTrackingId=${orderTrackingId}`, {
      headers: {
        'Authorization': `Bearer ${token}`,
        'Accept': 'application/json'
      }
    });

    const paymentStatus = statusRes.data.payment_status_description; // "COMPLETED", "FAILED", "INVALID"
    
    // Find the order in Firestore
    const orderRef = db.collection("pesapal_orders").doc(orderMerchantReference);
    const orderDoc = await orderRef.get();

    if (!orderDoc.exists) {
      console.warn(`Pesapal IPN for unknown order: ${orderMerchantReference}`);
      res.status(200).send({ status: "success", message: "Order not found locally, ignored." });
      return;
    }

    if (orderDoc.data().status === "COMPLETED") {
      res.status(200).send({ status: "success", message: "Already fulfilled." });
      return;
    }

    // Update order status
    await orderRef.update({
      status: paymentStatus,
      pesapal_status_code: statusRes.data.payment_status_code,
      updated_at: admin.firestore.FieldValue.serverTimestamp()
    });

    // Fulfill if COMPLETED
    if (paymentStatus === "COMPLETED") {
      const orderData = orderDoc.data();
      const userId = orderData.user_id;

      if (orderData.type === "buy_coins" && orderData.pack_id) {
        // Find pack
        const packDoc = await db.collection("coin_packs").doc(orderData.pack_id).get();
        if (packDoc.exists) {
          const ncxAmount = packDoc.data().ncx_amount;
          
          await db.runTransaction(async (tx) => {
            const walletRef = db.collection("wallets").doc(userId);
            const walletDoc = await tx.get(walletRef);
            
            if (walletDoc.exists) {
              tx.update(walletRef, {
                coin_balance: admin.firestore.FieldValue.increment(ncxAmount),
                last_topup_at: admin.firestore.FieldValue.serverTimestamp()
              });
            } else {
              tx.set(walletRef, {
                user_id: userId,
                coin_balance: ncxAmount,
                fiat_balance: 0,
                created_at: admin.firestore.FieldValue.serverTimestamp()
              });
            }

            // Ledger
            await recordLedgerEntry(userId, {
              type: "buy_coins",
              amount: ncxAmount,
              currency: "NCX",
              direction: "in",
              metadata: { method: "pesapal", tracking_id: orderTrackingId }
            }, tx);
          });
        }
      } else if (orderData.type === "unlock_listing" && orderData.listing_id) {
        // Unlock listing logic (similar to necxaPaymentGateway)
        await db.runTransaction(async (tx) => {
          const paymentRef = db.collection("listing_unlocks").doc(orderMerchantReference);
          tx.set(paymentRef, {
            buyer_id: userId,
            listing_id: orderData.listing_id,
            method: "PESAPAL",
            amount: orderData.amount,
            payment_status: "COMPLETED",
            timestamp: admin.firestore.FieldValue.serverTimestamp()
          });

          // Independent Audit
          await recordLedgerEntry(userId, {
            type: "listing_unlock",
            amount: orderData.amount,
            currency: "UGX",
            direction: "out",
            metadata: { listing_id: orderData.listing_id, method: "pesapal", tracking_id: orderTrackingId }
          }, tx);
        });
      } else if (orderData.type === "shop_purchase" && orderData.order_id) {
        // Shop E-commerce fulfillment logic
        await db.runTransaction(async (tx) => {
          const shopOrderRef = db.collection("orders").doc(orderData.order_id);
          const shopOrderDoc = await tx.get(shopOrderRef);

          if (shopOrderDoc.exists) {
            tx.update(shopOrderRef, {
              status: "paid",
              payment_method: "pesapal",
              paid_at: admin.firestore.FieldValue.serverTimestamp()
            });
            
            const { items_ugx = orderData.amount, delivery_ugx = 0, vendor_id, sku, quantity, listing_id } = orderData;

            const vendorPlatformFeeUgx = Math.floor(items_ugx * 0.03);
            const vendorNetUgx = items_ugx - vendorPlatformFeeUgx;

            // Goods Purchase Ledger Entry
            if (items_ugx > 0) {
              await recordLedgerEntry(userId, {
                type: "shop_purchase",
                amount: items_ugx,
                currency: "UGX",
                direction: "out",
                reference_id: orderData.order_id,
                metadata: { sku: sku, listing_id: listing_id, quantity: quantity, method: "pesapal", tracking_id: orderTrackingId }
              }, tx);
              
              if (vendor_id) {
                await recordLedgerEntry(vendor_id, {
                  type: "shop_purchase",
                  amount: vendorNetUgx,
                  currency: "UGX",
                  direction: "in",
                  reference_id: orderData.order_id,
                  metadata: { sku: sku, listing_id: listing_id, quantity: quantity, method: "pesapal", fee_deducted: vendorPlatformFeeUgx }
                }, tx);

                if (vendorPlatformFeeUgx > 0) {
                  await recordLedgerEntry("platform_revenue", {
                    type: "gift_fee", // Maps to PLATFORM_FEE
                    amount: vendorPlatformFeeUgx,
                    currency: "UGX",
                    direction: "in",
                    reference_id: orderData.order_id,
                    metadata: { source: "shop_vendor_commission", sku: sku, method: "pesapal" }
                  }, tx);
                }
              }
            }

            // Logistics Ledger Entry
            if (delivery_ugx > 0) {
              const tripId = `TRIP-${orderData.order_id.split('-')[1] || Date.now()}`;
              tx.update(shopOrderRef, { trip_id: tripId });

              await recordLedgerEntry(userId, {
                type: "delivery_fee",
                amount: delivery_ugx,
                currency: "UGX",
                direction: "out",
                reference_id: orderData.order_id,
                metadata: { trip_id: tripId, method: "pesapal", tracking_id: orderTrackingId }
              }, tx);
            }
          }
        });
      }
    }

    // Acknowledge the IPN
    res.status(200).json({
      orderNotificationType: req.query.OrderNotificationType || req.body.OrderNotificationType,
      orderTrackingId: orderTrackingId,
      orderMerchantReference: orderMerchantReference,
      status: 200
    });

  } catch (error) {
    console.error("Pesapal Webhook Error:", error.message);
    res.status(500).send("Webhook processing failed.");
  }
});
