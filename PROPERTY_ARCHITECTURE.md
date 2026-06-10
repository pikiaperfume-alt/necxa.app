# NECXA PLATFORM – PROPERTY CONTAINER LOGIC ARCHITECTURE
## Complete Integration: Data Structure + Financial Flow + UI Design

---

# TABLE OF CONTENTS

**Part 1:** Property Container – Core Data Structure  
**Part 2:** Property Lifecycle State Machine  
**Part 3:** Financial Logic & Escrow Flow  
**Part 4:** Agent vs. Owner Wallet Architecture  
**Part 5:** UI Component Design & Layout  
**Part 6:** Complete Integration Flow Diagram  
**Part 7:** Database Schema Summary  

---

# PART 1: PROPERTY CONTAINER – CORE DATA STRUCTURE

## What is a Property Container?

A **Property Container** is the complete digital representation of a real estate asset on the Necxa platform. It contains four logical layers:

| Layer | Purpose |
|-------|---------|
| **Core Identity** | Physical attributes of the property |
| **Financial Logic** | Pricing, commissions, economic rules |
| **Escrow State** | Transaction status and lifecycle management |
| **Shadow Logic** | Offline resilience and privacy controls |

---

## 1.1 Core Identity Layer

```typescript
interface PropertyCore {
    // Unique identifiers
    id: string;                    // UUID primary key
    listerId: string;              // Person who listed (owner or agent)
    agentId: string | null;        // Verified agent if applicable
    
    // Physical attributes
    title: string;                 // Property name/title
    description: string;           // Full description
    propertyType: PropertyType;    // apartment, house, villa, commercial, townhouse, travelersuite, campsite
    listingType: ListingType;      // sale, rent, short_term
    
    // Specifications
    bedrooms: number;
    bathrooms: number;
    sizeSqft: number;
    
    // Location
    address: string;               // Human-readable address
    city: string;
    district: string;
    country: string;               // Uganda, Kenya, Tanzania, Rwanda
    latitude: number;              // Hidden until unlock
    longitude: number;             // Hidden until unlock
    
    // Media
    images: string[];              // Property photos
    bathroomImageUrls: string[];   // Mandatory bathroom verification
    authorityStampUrl: string;     // LC1/Chief letter photo
}
```

---

## 1.2 Financial Logic Layer

```typescript
interface PropertyFinancial {
    // Pricing
    price: number;                 // Monthly rent or total sale price
    priceType: PriceType;          // MONTHLY or NIGHTLY
    
    // Derived values (10% Rule)
    unlockCost: number;            // price * 0.1 (paid in NCX Coins)
    escrowDeposit: number;         // price * 0.1 (paid in Cash)
    
    // Commission structure
    agentCommissionRate: number;   // 5% default
    necxaCommissionRate: number;   // 2% fixed
    
    // Calculated commissions
    agentCommissionAmount: number; // price * 0.05
    necxaCommissionAmount: number; // price * 0.02
    
    // Trust metrics
    isVerified: boolean;           // Passed East Africa Algorithm
    trustStatus: TrustStatus;      // standard, verified, titan_trust
    verificationScore: number;     // 0-100
}
```

---

## 1.3 Escrow State Layer (The "Smart" Layer)

```typescript
interface PropertyEscrowState {
    // Status management
    escrowStatus: EscrowStatus;     // AVAILABLE, PENDING_ESCROW, SOLD, DISPUTED
    escrowTimestamp: string | null; // When reservation started
    escrowExpiresAt: string | null; // 72 hours after escrowTimestamp
    
    // Transaction tracking
    activeEscrowTxId: string | null; // Link to transaction record
    unlockCount: number;             // How many people unlocked this property
    reservationCount: number;        // How many times it was reserved
    
    // Dispute handling
    disputeActive: boolean;          // Is there an active dispute?
    disputeId: string | null;        // Link to dispute record
    disputeReason: string | null;
    
    // Completion
    soldAt: string | null;           // When property was sold/rented
    finalBuyerId: string | null;     // Who completed the transaction
}
```

---

## 1.4 Shadow Logic Layer (Offline & Privacy)

```typescript
interface PropertyShadowLogic {
    // Privacy controls
    isUnlockedByCurrentUser: boolean;  // Has current user paid unlock?
    addressRevealedAt: string | null;  // When address was unlocked
    
    // Offline resilience
    isShadow: boolean;                  // Cached for offline use
    shadowSyncedAt: string | null;      // Last sync time
    shadowSourceNode: string | null;    // Peer that provided this data
    
    // Verification anchors
    gpsLocked: boolean;                 // Was GPS verified at listing?
    gpsLatitude: number | null;         // Actual pin location
    gpsLongitude: number | null;
    gpsDistanceMeters: number | null;   // Distance between reported and actual
    
    // Utility verification
    umemeMeterNumber: string | null;    // Uganda
    nwscCustomerNumber: string | null;  // Uganda
    kplcMeterNumber: string | null;     // Kenya
    tanescoMeterNumber: string | null;  // Tanzania
    
    // Authority verification
    lc1ChairmanName: string | null;     // Local leader who signed
    lc1StampDate: string | null;
    authorityStampVerified: boolean;
}
```

---

# PART 2: PROPERTY LIFECYCLE STATE MACHINE

## 2.1 State Transitions

1.  **AVAILABLE**: Address hidden, anyone can Unlock (10% Coins) or Reserve (10% Cash).
2.  **PENDING_ESCROW**: Hidden from search, 72-hour timer starts, funds locked in escrow.
3.  **SOLD**: QR Handshake scanned within 72h, funds released to Agent/Seller.
4.  **DISPUTED**: Buyer raises flag, timer paused, AI/Human review activated.
5.  **EXPIRED**: 72h passes without Handshake or Dispute, funds refunded to buyer, property relisted as AVAILABLE.

---

# PART 3: FINANCIAL LOGIC & ESCROW FLOW

| Step | Action | Cost | Currency | Purpose |
|------|--------|------|----------|---------|
| **1** | **Unlock** | 10% of rent | NCX Coins | Reveal address & agent contact |
| **2** | **Reserve (Escrow)** | 10% of rent | Cash (UGX/KES) | Lock the property for 72 hours |
| **3** | **Handshake** | - | - | On-site scan releases deposit & commissions |

---

# PART 4: AGENT VS. OWNER WALLET ARCHITECTURE

Both agents and owners share the same wallet structure but with different permissions:
- **Fiat Balance**: Withdrawable cash.
- **Escrow Balance**: Locked funds pending fulfillment.
- **Coin Balance**: Used for unlocks.

---

# PART 5: UI DESIGN (RELEASE 2.0)

- **Property Card**: Show blurred location and "Unlock" trigger.
- **Detail Screen**: Persistent state machine (Unlocked -> Reserved -> Handshake).
- **QR Terminal**: Agent displays QR code, Buyer scans via mobile app.

---

# PART 6: COMPLETE INTEGRATION FLOW

1.  **Discovery**: Unified feed with verified listings.
2.  **Commitment**: Unlock (Coins) filters for serious leads.
3.  **Scarcity**: Reserve (Escrow) creates 72-hour exclusive viewing window.
4.  **Fulfillment**: QR Handshake releases funds instantly.

---

# PART 7: DATABASE SCHEMA SUMMARY

- `properties`: The central node.
- `identity_shards`: Encrypted biometric data.
- `authority_shards`: Verified utility/government data.
- `escrow_reservations`: Financial state tracking.
- `unlocks`: Commingled coin transaction logs.

---

# PART 8: SHIELD VERIFICATION SYNC PROTOCOL (V2.0)

To ensure **Titan Trust** status, every listing must survive the 4-stage background sync protocol powered by the `NecxShieldSDK`.

| Stage | Data Object | Sync Method | Verification Trigger |
|-------|-------------|-------------|----------------------|
| **1. Identity** | National ID + Selfie | `submitIdentityShard` | Biometric Face Match (98% confidence) |
| **2. Utility** | Umeme/NWSC + Chief Stamp | `submitUtilityShard` | AI OCR + Chief Handshake Verification |
| **3. GPS Lock** | Active Geofence Data | `submitGpsLock` | Real-time Satellite Triangulation |
| **4. Neural Synthesis** | Full Property Matrix | `submitNeuralSynthesis` | Final Consolidation & Blockchain Pinning |

## 8.1 The "Cross-Check" Handshake
The SDK executes a **Cross-Check** during Stage 1:
-   **OCR Cross-Check**: Data extracted from the physical ID is programmatically compared against the current authenticated user's session data.
-   **Biometric Cross-Check**: The live selfie stream is compared against the high-resolution ID crop.

## 8.2 Background Persistence
Unlike standard uploads, Shield Sync happens in a **decoupled background state**. The UI displays `aiChecking` heartbeats while the `ListingSyncService` synchronizes encrypted shards to the Necxa Edge Functions.
