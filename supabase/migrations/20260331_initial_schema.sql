-- NECXA PLATFORM – COMPLETE INTEGRATED SUPABASE BACKEND
-- Version 2.0 | Property Container Logic + Financial Flow + Escrow System
-- Project: https://rfoykeibwxosxpxlqlfc.supabase.co

-- ── 1.1 ENABLE EXTENSIONS ──────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "postgis";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "vector";

-- ── 1.2 PROFILES TABLE ───────────────────────────────────────────
CREATE TABLE profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name TEXT,
    email TEXT UNIQUE,
    phone TEXT UNIQUE,
    avatar_url TEXT,
    country TEXT NOT NULL DEFAULT 'Uganda',
    city TEXT,
    district TEXT,
    is_agent BOOLEAN DEFAULT FALSE,
    is_verified_agent BOOLEAN DEFAULT FALSE,
    agent_verified_at TIMESTAMP WITH TIME ZONE,
    nin_number TEXT UNIQUE,
    nin_verified BOOLEAN DEFAULT FALSE,
    nin_verified_at TIMESTAMP WITH TIME ZONE,
    face_scan_url TEXT,
    trust_score INT DEFAULT 50,
    trust_score_tier TEXT GENERATED ALWAYS AS (
        CASE
            WHEN trust_score >= 90 THEN 'titan_trust'
            WHEN trust_score >= 70 THEN 'verified'
            WHEN trust_score >= 50 THEN 'standard'
            ELSE 'limited'
        END
    ) STORED,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_profiles_email ON profiles(email);
CREATE INDEX idx_profiles_phone ON profiles(phone);
CREATE INDEX idx_profiles_is_agent ON profiles(is_agent);
CREATE INDEX idx_profiles_trust_score ON profiles(trust_score);

CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_profiles_updated_at
    BEFORE UPDATE ON profiles
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ── 1.3 WALLETS TABLE ───────────────────────────────────────────
CREATE TABLE wallets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID UNIQUE REFERENCES profiles(id) ON DELETE CASCADE,
    fiat_balance BIGINT DEFAULT 0 NOT NULL,      -- UGX/KES - withdrawable
    escrow_balance BIGINT DEFAULT 0 NOT NULL,    -- Locked funds
    coin_balance BIGINT DEFAULT 0 NOT NULL,      -- NCX Coins
    staked_balance BIGINT DEFAULT 0 NOT NULL,    -- Staked for trust boost
    total_earned BIGINT DEFAULT 0,
    total_spent BIGINT DEFAULT 0,
    daily_withdrawal_limit BIGINT DEFAULT 5000000, -- 5M UGX default
    is_frozen BOOLEAN DEFAULT FALSE,
    freeze_reason TEXT,
    frozen_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_wallets_user_id ON wallets(user_id);

CREATE TRIGGER update_wallets_updated_at
    BEFORE UPDATE ON wallets
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ── 1.4 WALLET TRANSACTIONS TABLE ──────────────────────────────
CREATE TABLE wallet_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    wallet_id UUID REFERENCES wallets(id) ON DELETE CASCADE,
    user_id UUID REFERENCES profiles(id),
    transaction_type TEXT NOT NULL CHECK (transaction_type IN (
        'unlock_payment', 'escrow_deposit', 'escrow_refund', 'commission_earned',
        'sale_proceeds', 'coin_purchase', 'coin_withdrawal', 'dispute_penalty',
        'stake_deposit', 'stake_withdrawal'
    )),
    amount BIGINT NOT NULL,
    balance_after BIGINT NOT NULL,
    reference_id UUID,          -- References unlocks.id, escrow_reservations.id, etc.
    reference_type TEXT,        -- 'unlock', 'escrow', 'commission', 'sale'
    status TEXT DEFAULT 'completed',
    description TEXT,
    metadata JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_wallet_transactions_wallet_id ON wallet_transactions(wallet_id);
CREATE INDEX idx_wallet_transactions_user_id ON wallet_transactions(user_id);
CREATE INDEX idx_wallet_transactions_reference ON wallet_transactions(reference_id);

-- Handle new user signup (moved here after wallets table is created)
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.profiles (id, email, phone, country, full_name)
    VALUES (
        NEW.id, 
        NEW.email, 
        NEW.phone, 
        COALESCE(NEW.raw_user_meta_data->>'country', 'Uganda'),
        COALESCE(NEW.raw_user_meta_data->>'full_name', '')
    );
    
    INSERT INTO public.wallets (user_id, fiat_balance, coin_balance, escrow_balance)
    VALUES (NEW.id, 0, 0, 0);
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- ── 1.5 AGENT VERIFICATIONS TABLE ──────────────────────────────
CREATE TABLE agent_verifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    status TEXT DEFAULT 'pending', -- pending, approved, rejected, suspended
    
    business_license_url TEXT NOT NULL,
    tax_id_url TEXT NOT NULL,
    agency_permit_url TEXT NOT NULL,
    lead_agent_id_url TEXT NOT NULL,
    
    business_license_number TEXT,
    tax_id_number TEXT,
    agency_permit_number TEXT,
    lead_agent_nin TEXT,
    
    phone_verified BOOLEAN DEFAULT FALSE,
    whatsapp_verified BOOLEAN DEFAULT FALSE,
    google_meet_provided BOOLEAN DEFAULT FALSE,
    
    submitted_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    reviewed_by UUID REFERENCES profiles(id),
    reviewed_at TIMESTAMP WITH TIME ZONE,
    rejection_reason TEXT,
    
    agent_commission_rate DECIMAL(5,2) DEFAULT 5.0,
    necxa_commission_rate DECIMAL(5,2) DEFAULT 2.0,
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_agent_verifications_user_id ON agent_verifications(user_id);
CREATE INDEX idx_agent_verifications_status ON agent_verifications(status);

-- ── 1.6 AGENT CONTACT METHODS TABLE ────────────────────────────
CREATE TABLE agent_contact_methods (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    agent_id UUID UNIQUE REFERENCES profiles(id) ON DELETE CASCADE,
    
    phone_country_code TEXT DEFAULT '256',
    phone_number TEXT NOT NULL,
    phone_verified BOOLEAN DEFAULT FALSE,
    phone_verified_at TIMESTAMP WITH TIME ZONE,
    
    whatsapp_number TEXT,
    whatsapp_verified BOOLEAN DEFAULT FALSE,
    whatsapp_business_account BOOLEAN DEFAULT FALSE,
    
    google_meet_link TEXT,
    google_meet_enabled BOOLEAN DEFAULT FALSE,
    virtual_tour_available BOOLEAN DEFAULT FALSE,
    
    preferred_contact_method TEXT DEFAULT 'whatsapp',
    response_time_avg_minutes INT,
    last_active_at TIMESTAMP WITH TIME ZONE,
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_agent_contact_agent_id ON agent_contact_methods(agent_id);

-- ── 1.7 PROPERTIES TABLE (Core) ─────────────────────────────────
CREATE TABLE properties (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    lister_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    agent_id UUID REFERENCES profiles(id),
    
    title TEXT NOT NULL,
    description TEXT,
    property_type TEXT NOT NULL CHECK (property_type IN (
        'apartment', 'house', 'villa', 'commercial', 'townhouse', 'travelersuite', 'campsite'
    )),
    listing_type TEXT NOT NULL CHECK (listing_type IN ('sale', 'rent', 'short_term')),
    
    price BIGINT NOT NULL,
    price_type TEXT DEFAULT 'monthly' CHECK (price_type IN ('monthly', 'nightly')),
    unlock_cost BIGINT GENERATED ALWAYS AS (price * 0.1) STORED,
    escrow_deposit BIGINT GENERATED ALWAYS AS (price * 0.1) STORED,
    
    bedrooms INT,
    bathrooms INT,
    size_sqft INT,
    
    address TEXT,
    city TEXT,
    district TEXT,
    country TEXT NOT NULL,
    latitude DECIMAL(10,8),
    longitude DECIMAL(11,8),
    location GEOMETRY(POINT, 4326),
    
    images TEXT[],
    bathroom_image_urls TEXT[],
    authority_stamp_url TEXT,
    
    is_verified BOOLEAN DEFAULT FALSE,
    trust_status TEXT DEFAULT 'standard',
    verification_score INT,
    
    umeme_meter_number TEXT,
    nwsc_customer_number TEXT,
    kplc_meter_number TEXT,
    tanesco_meter_number TEXT,
    land_title_block TEXT,
    land_title_plot TEXT,
    
    lc1_letter_url TEXT,
    lc1_chairman_name TEXT,
    lc1_stamp_date DATE,
    
    gps_locked_at TIMESTAMP WITH TIME ZONE,
    gps_locked_by UUID REFERENCES profiles(id),
    is_physically_verified BOOLEAN DEFAULT FALSE,
    gps_latitude DECIMAL(10,8),
    gps_longitude DECIMAL(11,8),
    gps_distance_meters DECIMAL(10,2),
    
    escrow_status TEXT DEFAULT 'available' CHECK (escrow_status IN (
        'available', 'pending_escrow', 'disputed', 'sold'
    )),
    escrow_timestamp TIMESTAMP WITH TIME ZONE,
    escrow_expires_at TIMESTAMP WITH TIME ZONE,
    active_escrow_tx_id UUID,
    
    views_count INT DEFAULT 0,
    unlocks_count INT DEFAULT 0,
    reservations_count INT DEFAULT 0,
    
    ai_relevance_score DECIMAL(5,2),
    is_honeypot BOOLEAN DEFAULT FALSE,
    honeypot_redirected_at TIMESTAMP WITH TIME ZONE,
    
    is_active BOOLEAN DEFAULT TRUE,
    is_sold BOOLEAN DEFAULT FALSE,
    sold_at TIMESTAMP WITH TIME ZONE,
    final_buyer_id UUID REFERENCES profiles(id),
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    published_at TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_properties_lister_id ON properties(lister_id);
CREATE INDEX idx_properties_agent_id ON properties(agent_id);
CREATE INDEX idx_properties_type ON properties(property_type);
CREATE INDEX idx_properties_price ON properties(price);
CREATE INDEX idx_properties_escrow_status ON properties(escrow_status);
CREATE INDEX idx_properties_verified ON properties(is_verified);
CREATE INDEX idx_properties_active ON properties(is_active) WHERE is_active = true;
CREATE INDEX idx_properties_location ON properties USING GIST(location);
CREATE INDEX idx_properties_escrow_expires ON properties(escrow_expires_at) WHERE escrow_status = 'pending_escrow';

CREATE TRIGGER update_properties_updated_at
    BEFORE UPDATE ON properties
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ── 1.8 UNLOCKS TABLE (10% Coins) ───────────────────────────────
CREATE TABLE unlocks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    property_id UUID REFERENCES properties(id) ON DELETE CASCADE,
    buyer_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    seller_id UUID REFERENCES profiles(id),
    agent_id UUID REFERENCES profiles(id),
    
    unlock_amount BIGINT NOT NULL,
    unlock_cost BIGINT NOT NULL,
    status TEXT DEFAULT 'completed',
    
    address_revealed_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    contact_revealed_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    transaction_id TEXT,
    payment_method TEXT,
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    expires_at TIMESTAMP WITH TIME ZONE DEFAULT (NOW() + INTERVAL '30 days')
);

CREATE INDEX idx_unlocks_property_id ON unlocks(property_id);
CREATE INDEX idx_unlocks_buyer_id ON unlocks(buyer_id);

-- ── 1.9 ESCROW RESERVATIONS TABLE (10% Cash) ────────────────────
CREATE TABLE escrow_reservations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    property_id UUID REFERENCES properties(id) ON DELETE CASCADE,
    buyer_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    seller_id UUID REFERENCES profiles(id),
    agent_id UUID REFERENCES profiles(id),
    
    property_value BIGINT NOT NULL,
    deposit_amount BIGINT NOT NULL,
    agent_commission BIGINT GENERATED ALWAYS AS (property_value * 0.05) STORED,
    necxa_fee BIGINT GENERATED ALWAYS AS (property_value * 0.02) STORED,
    
    status TEXT DEFAULT 'pending' CHECK (status IN (
        'pending', 'completed', 'expired', 'disputed', 'refunded'
    )),
    
    deposit_paid_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    deposit_released_at TIMESTAMP WITH TIME ZONE,
    reservation_expires_at TIMESTAMP WITH TIME ZONE, -- NOW() + 72 hours
    
    dispute_initiated_at TIMESTAMP WITH TIME ZONE,
    dispute_resolved_at TIMESTAMP WITH TIME ZONE,
    dispute_winner TEXT,
    dispute_reason TEXT,
    dispute_evidence_urls TEXT[],
    ai_confidence_score DECIMAL(5,2),
    
    deposit_transaction_id TEXT,
    release_transaction_id TEXT,
    refund_transaction_id TEXT,
    
    qr_code TEXT,
    qr_scanned_at TIMESTAMP WITH TIME ZONE,
    qr_scanned_latitude DECIMAL(10,8),
    qr_scanned_longitude DECIMAL(11,8),
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_escrow_property_id ON escrow_reservations(property_id);
CREATE INDEX idx_escrow_buyer_id ON escrow_reservations(buyer_id);
CREATE INDEX idx_escrow_status ON escrow_reservations(status);
CREATE INDEX idx_escrow_expires ON escrow_reservations(reservation_expires_at) WHERE status = 'pending';

CREATE TRIGGER update_escrow_reservations_updated_at
    BEFORE UPDATE ON escrow_reservations
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ── 1.10 IDENTITY SHARDS TABLE (Restricted) ─────────────────────
CREATE TABLE identity_shards (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    property_id UUID UNIQUE REFERENCES properties(id) ON DELETE CASCADE,
    user_id UUID REFERENCES profiles(id),
    face_scan_url TEXT,
    face_match_confidence DECIMAL(5,2),
    nin_verification_id TEXT,
    id_document_url TEXT,
    id_document_type TEXT,
    verification_confidence DECIMAL(5,2),
    encrypted_nin_data BYTEA,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_identity_shards_property_id ON identity_shards(property_id);

-- ── 1.11 AUTHORITY SHARDS TABLE (Restricted) ────────────────────
CREATE TABLE authority_shards (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    property_id UUID UNIQUE REFERENCES properties(id) ON DELETE CASCADE,
    lc1_letter_url TEXT,
    lc1_chairman_name TEXT,
    lc1_stamp_date DATE,
    umeme_verification_response JSONB,
    nwsc_verification_response JSONB,
    kplc_verification_response JSONB,
    tanesco_verification_response JSONB,
    land_title_verification JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_authority_shards_property_id ON authority_shards(property_id);

-- ── 1.12 CHAT CONVERSATIONS TABLE ───────────────────────────────
CREATE TABLE chat_conversations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    property_id UUID REFERENCES properties(id) ON DELETE CASCADE,
    
    buyer_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    seller_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    agent_id UUID REFERENCES profiles(id),
    
    status TEXT DEFAULT 'active',
    
    unlocked_by_buyer BOOLEAN DEFAULT FALSE,
    unlocked_at TIMESTAMP WITH TIME ZONE,
    unlock_transaction_id UUID REFERENCES unlocks(id),
    
    last_message TEXT,
    last_message_at TIMESTAMP WITH TIME ZONE,
    last_message_sender_id UUID REFERENCES profiles(id),
    
    buyer_unread_count INT DEFAULT 0,
    seller_unread_count INT DEFAULT 0,
    agent_unread_count INT DEFAULT 0,
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_conversations_property ON chat_conversations(property_id);
CREATE INDEX idx_conversations_buyer ON chat_conversations(buyer_id);
CREATE INDEX idx_conversations_agent ON chat_conversations(agent_id);

-- ── 1.13 CHAT MESSAGES TABLE ────────────────────────────────────
CREATE TABLE in_app_chat_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID REFERENCES chat_conversations(id) ON DELETE CASCADE,
    property_id UUID REFERENCES properties(id) ON DELETE CASCADE,
    
    sender_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    receiver_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    
    message TEXT,
    message_type TEXT DEFAULT 'text',
    media_url TEXT,
    
    is_read BOOLEAN DEFAULT FALSE,
    read_at TIMESTAMP WITH TIME ZONE,
    
    is_system_message BOOLEAN DEFAULT FALSE,
    is_agent_response BOOLEAN DEFAULT FALSE,
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_chat_conversation ON in_app_chat_messages(conversation_id);
CREATE INDEX idx_chat_sender ON in_app_chat_messages(sender_id);
CREATE INDEX idx_chat_receiver ON in_app_chat_messages(receiver_id);
CREATE INDEX idx_chat_unread ON in_app_chat_messages(receiver_id, is_read) WHERE is_read = false;

-- ── 1.14 VIRTUAL TOUR BOOKINGS TABLE ────────────────────────────
CREATE TABLE virtual_tour_bookings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    property_id UUID REFERENCES properties(id) ON DELETE CASCADE,
    agent_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    buyer_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    
    meet_link TEXT NOT NULL,
    scheduled_for TIMESTAMP WITH TIME ZONE NOT NULL,
    duration_minutes INT DEFAULT 30,
    
    status TEXT DEFAULT 'scheduled',
    
    buyer_confirmed BOOLEAN DEFAULT FALSE,
    agent_confirmed BOOLEAN DEFAULT FALSE,
    
    tour_completed_at TIMESTAMP WITH TIME ZONE,
    buyer_rating INT CHECK (buyer_rating BETWEEN 1 AND 5),
    buyer_feedback TEXT,
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_tours_agent ON virtual_tour_bookings(agent_id);
CREATE INDEX idx_tours_buyer ON virtual_tour_bookings(buyer_id);
CREATE INDEX idx_tours_scheduled ON virtual_tour_bookings(scheduled_for);

-- ── 1.15 NOTIFICATIONS TABLE ────────────────────────────────────
CREATE TABLE notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    
    notification_type TEXT NOT NULL CHECK (notification_type IN (
        'listing_verified', 'property_unlocked', 'escrow_created', 'escrow_completed',
        'escrow_expired', 'dispute_initiated', 'dispute_resolved', 'commission_earned',
        'new_buyer_alert', 'listing_viewed', 'trust_score_changed', 'wallet_credited',
        'new_message', 'virtual_tour_scheduled', 'reservation_reminder'
    )),
    
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    metadata JSONB,
    
    is_read BOOLEAN DEFAULT FALSE,
    is_sent BOOLEAN DEFAULT FALSE,
    sent_at TIMESTAMP WITH TIME ZONE,
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_notifications_user_id ON notifications(user_id);
CREATE INDEX idx_notifications_unread ON notifications(user_id, is_read) WHERE is_read = false;

-- ── 1.16 AI FLAGS TABLE (Honeypot System) ────────────────────────
CREATE TABLE ai_flags (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES profiles(id),
    property_id UUID REFERENCES properties(id),
    
    flag_type TEXT NOT NULL CHECK (flag_type IN (
        'fake_id', 'recycled_meter', 'gps_mismatch', 'stolen_photos', 
        'suspicious_pattern', 'authority_stamp_fake', 'fake_listing'
    )),
    
    confidence_score DECIMAL(5,2),
    is_honeypot_redirected BOOLEAN DEFAULT FALSE,
    honeypot_view_url TEXT,
    
    reviewed_by_ai BOOLEAN DEFAULT TRUE,
    reviewed_by_human BOOLEAN DEFAULT FALSE,
    human_review_notes TEXT,
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    resolved_at TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_ai_flags_user_id ON ai_flags(user_id);
CREATE INDEX idx_ai_flags_property_id ON ai_flags(property_id);

-- ── 1.17 TRUST_SCORE_HISTORY TABLE ──────────────────────────────
CREATE TABLE trust_score_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    previous_score INT,
    new_score INT,
    change_amount INT,
    change_reason TEXT NOT NULL,
    property_id UUID REFERENCES properties(id),
    escrow_id UUID REFERENCES escrow_reservations(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_trust_history_user_id ON trust_score_history(user_id);

-- ── 2. ROW LEVEL SECURITY (RLS) POLICIES ─────────────────────────
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE wallets ENABLE ROW LEVEL SECURITY;
ALTER TABLE wallet_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE agent_verifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE agent_contact_methods ENABLE ROW LEVEL SECURITY;
ALTER TABLE properties ENABLE ROW LEVEL SECURITY;
ALTER TABLE unlocks ENABLE ROW LEVEL SECURITY;
ALTER TABLE escrow_reservations ENABLE ROW LEVEL SECURITY;
ALTER TABLE identity_shards ENABLE ROW LEVEL SECURITY;
ALTER TABLE authority_shards ENABLE ROW LEVEL SECURITY;
ALTER TABLE chat_conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE in_app_chat_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE virtual_tour_bookings ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE trust_score_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view any profile" ON profiles FOR SELECT USING (true);
CREATE POLICY "Users can update own profile" ON profiles FOR UPDATE USING (auth.uid() = id);
CREATE POLICY "Users can insert own profile" ON profiles FOR INSERT WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can view own wallet" ON wallets FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can update own wallet" ON wallets FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can view own transactions" ON wallet_transactions FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Anyone can view active properties" ON properties FOR SELECT 
    USING (is_active = true AND is_verified = true AND is_honeypot = false AND escrow_status = 'available');
CREATE POLICY "Lister can view own properties" ON properties FOR SELECT USING (auth.uid() = lister_id);
CREATE POLICY "Agent can view managed properties" ON properties FOR SELECT USING (auth.uid() = agent_id);
CREATE POLICY "Lister can update own properties" ON properties FOR UPDATE USING (auth.uid() = lister_id);
CREATE POLICY "Lister can insert properties" ON properties FOR INSERT WITH CHECK (auth.uid() = lister_id);

CREATE POLICY "Users can view own unlocks" ON unlocks FOR SELECT USING (auth.uid() = buyer_id);
CREATE POLICY "Users can insert unlocks" ON unlocks FOR INSERT WITH CHECK (auth.uid() = buyer_id);

CREATE POLICY "Participants can view escrow" ON escrow_reservations FOR SELECT USING (auth.uid() IN (buyer_id, seller_id, agent_id));
CREATE POLICY "Buyer can insert escrow" ON escrow_reservations FOR INSERT WITH CHECK (auth.uid() = buyer_id);

CREATE POLICY "Agents can view own contact" ON agent_contact_methods FOR SELECT USING (auth.uid() = agent_id);
CREATE POLICY "Agents can update own contact" ON agent_contact_methods FOR UPDATE USING (auth.uid() = agent_id);

CREATE POLICY "Participants can view conversations" ON chat_conversations FOR SELECT USING (auth.uid() IN (buyer_id, seller_id, agent_id));
CREATE POLICY "Participants can view messages" ON in_app_chat_messages FOR SELECT 
    USING (EXISTS (SELECT 1 FROM chat_conversations c WHERE c.id = conversation_id AND auth.uid() IN (c.buyer_id, c.seller_id, c.agent_id)));

CREATE POLICY "Users can view own notifications" ON notifications FOR SELECT USING (auth.uid() = user_id);

-- ── 3. DATABASE FUNCTIONS & TRIGGERS ────────────────────────────

-- 3.1 72-Hour Escrow Expiry Check
CREATE OR REPLACE FUNCTION check_escrow_expiry()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    WITH expired AS (
        UPDATE escrow_reservations er
        SET status = 'expired'
        FROM properties p
        WHERE er.property_id = p.id AND er.status = 'pending' AND er.reservation_expires_at < NOW()
          AND NOT EXISTS (SELECT 1 FROM escrow_reservations e2 WHERE e2.property_id = er.property_id AND e2.status = 'disputed')
        RETURNING er.*
    )
    UPDATE properties p
    SET escrow_status = 'available', active_escrow_tx_id = NULL, escrow_timestamp = NULL, escrow_expires_at = NULL
    FROM expired e WHERE p.id = e.property_id;
    
    INSERT INTO notifications (user_id, notification_type, title, body, metadata)
    SELECT er.buyer_id, 'escrow_expired', 'Reservation Expired', 'Your reservation has expired. The property has been relisted.',
           jsonb_build_object('escrow_id', er.id, 'property_id', er.property_id)
    FROM escrow_reservations er WHERE er.status = 'expired' AND er.updated_at > NOW() - INTERVAL '1 minute';
END;
$$;

-- 3.2 Increment Trust Score
CREATE OR REPLACE FUNCTION increment_trust_score(p_user_id UUID, p_points INT, p_reason TEXT)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    old_score INT;
    new_score INT;
BEGIN
    SELECT trust_score INTO old_score FROM profiles WHERE id = p_user_id;
    new_score := LEAST(old_score + p_points, 100);
    UPDATE profiles SET trust_score = new_score, updated_at = NOW() WHERE id = p_user_id;
    INSERT INTO trust_score_history (user_id, previous_score, new_score, change_amount, change_reason)
    VALUES (p_user_id, old_score, new_score, p_points, p_reason);
END;
$$;

-- 3.3 Decrement Trust Score
CREATE OR REPLACE FUNCTION decrement_trust_score(p_user_id UUID, p_points INT, p_reason TEXT)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    old_score INT;
    new_score INT;
BEGIN
    SELECT trust_score INTO old_score FROM profiles WHERE id = p_user_id;
    new_score := GREATEST(old_score - p_points, 0);
    UPDATE profiles SET trust_score = new_score, updated_at = NOW() WHERE id = p_user_id;
    INSERT INTO trust_score_history (user_id, previous_score, new_score, change_amount, change_reason)
    VALUES (p_user_id, old_score, new_score, -p_points, p_reason);
END;
$$;

-- 3.4 Process Unlock Payment
CREATE OR REPLACE FUNCTION process_unlock(p_property_id UUID, p_buyer_id UUID)
RETURNS TABLE (success BOOLEAN, unlock_id UUID, message TEXT) LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    v_property RECORD;
    v_wallet RECORD;
    v_unlock_cost BIGINT;
    v_unlock_id UUID;
BEGIN
    SELECT * INTO v_property FROM properties WHERE id = p_property_id AND is_active = true;
    IF NOT FOUND THEN RETURN QUERY SELECT false, NULL::UUID, 'Property not found'; RETURN; END IF;
    v_unlock_cost := v_property.price * 0.1;
    SELECT * INTO v_wallet FROM wallets WHERE user_id = p_buyer_id;
    IF NOT FOUND THEN RETURN QUERY SELECT false, NULL::UUID, 'Wallet not found'; RETURN; END IF;
    IF v_wallet.coin_balance < v_unlock_cost THEN RETURN QUERY SELECT false, NULL::UUID, 'Insufficient NCX Coins'; RETURN; END IF;
    
    UPDATE wallets SET coin_balance = coin_balance - v_unlock_cost, total_spent = total_spent + v_unlock_cost, updated_at = NOW() WHERE user_id = p_buyer_id;
    
    INSERT INTO unlocks (property_id, buyer_id, seller_id, agent_id, unlock_amount, unlock_cost)
    VALUES (p_property_id, p_buyer_id, v_property.lister_id, v_property.agent_id, v_unlock_cost, v_unlock_cost)
    RETURNING id INTO v_unlock_id;
    
    UPDATE properties SET unlocks_count = unlocks_count + 1 WHERE id = p_property_id;
    
    INSERT INTO chat_conversations (property_id, buyer_id, seller_id, agent_id, unlocked_by_buyer, unlocked_at, unlock_transaction_id)
    VALUES (p_property_id, p_buyer_id, v_property.lister_id, v_property.agent_id, true, NOW(), v_unlock_id)
    ON CONFLICT (property_id, buyer_id) DO UPDATE SET unlocked_by_buyer = true, unlocked_at = NOW(), unlock_transaction_id = v_unlock_id;
    
    RETURN QUERY SELECT true, v_unlock_id, 'Property unlocked successfully';
END;
$$;

-- 3.5 Process Escrow Reservation
CREATE OR REPLACE FUNCTION process_escrow_reservation(p_property_id UUID, p_buyer_id UUID)
RETURNS TABLE (success BOOLEAN, escrow_id UUID, expires_at TIMESTAMP WITH TIME ZONE, message TEXT) LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    v_property RECORD;
    v_wallet RECORD;
    v_escrow_deposit BIGINT;
    v_escrow_id UUID;
    v_expires_at TIMESTAMP WITH TIME ZONE;
BEGIN
    SELECT * INTO v_property FROM properties WHERE id = p_property_id AND is_active = true AND escrow_status = 'available';
    IF NOT FOUND THEN RETURN QUERY SELECT false, NULL::UUID, NULL::TIMESTAMP, 'Property not available'; RETURN; END IF;
    v_escrow_deposit := v_property.price * 0.1;
    v_expires_at := NOW() + INTERVAL '72 hours';
    SELECT * INTO v_wallet FROM wallets WHERE user_id = p_buyer_id;
    IF v_wallet.fiat_balance < v_escrow_deposit THEN RETURN QUERY SELECT false, NULL::UUID, NULL::TIMESTAMP, 'Insufficient funds'; RETURN; END IF;
    
    UPDATE wallets SET fiat_balance = fiat_balance - v_escrow_deposit, escrow_balance = escrow_balance + v_escrow_deposit, updated_at = NOW() WHERE user_id = p_buyer_id;
    
    INSERT INTO escrow_reservations (property_id, buyer_id, seller_id, agent_id, property_value, deposit_amount, deposit_paid_at, reservation_expires_at, status)
    VALUES (p_property_id, p_buyer_id, v_property.lister_id, v_property.agent_id, v_property.price, v_escrow_deposit, NOW(), v_expires_at, 'pending')
    RETURNING id INTO v_escrow_id;
    
    UPDATE properties SET escrow_status = 'pending_escrow', active_escrow_tx_id = v_escrow_id, escrow_expires_at = v_expires_at, reservations_count = reservations_count + 1 WHERE id = p_property_id;
    
    RETURN QUERY SELECT true, v_escrow_id, v_expires_at, 'Property reserved successfully';
END;
$$;

-- 3.6 Process QR Handshake
CREATE OR REPLACE FUNCTION process_qr_handshake(p_escrow_id UUID, p_buyer_id UUID, p_qr_scanned_latitude DECIMAL, p_qr_scanned_longitude DECIMAL)
RETURNS TABLE (success BOOLEAN, message TEXT, agent_commission BIGINT, necxa_fee BIGINT, net_to_seller BIGINT) LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    v_escrow RECORD;
    v_property RECORD;
BEGIN
    SELECT * INTO v_escrow FROM escrow_reservations WHERE id = p_escrow_id AND status = 'pending';
    IF NOT FOUND THEN RETURN QUERY SELECT false, 'Escrow not found', NULL::BIGINT, NULL::BIGINT, NULL::BIGINT; RETURN; END IF;
    IF v_escrow.buyer_id != p_buyer_id THEN RETURN QUERY SELECT false, 'Not authorized', NULL::BIGINT, NULL::BIGINT, NULL::BIGINT; RETURN; END IF;
    
    SELECT * INTO v_property FROM properties WHERE id = v_escrow.property_id;
    
    UPDATE escrow_reservations SET status = 'completed', deposit_released_at = NOW(), qr_scanned_at = NOW(), qr_scanned_latitude = p_qr_scanned_latitude, qr_scanned_longitude = p_qr_scanned_longitude WHERE id = p_escrow_id;
    UPDATE wallets SET escrow_balance = escrow_balance - v_escrow.deposit_amount WHERE user_id = p_buyer_id;
    UPDATE wallets SET fiat_balance = fiat_balance + v_escrow.agent_commission, total_earned = total_earned + v_escrow.agent_commission WHERE user_id = v_escrow.agent_id;
    UPDATE wallets SET fiat_balance = fiat_balance + v_escrow.deposit_amount, total_earned = total_earned + v_escrow.deposit_amount WHERE user_id = v_escrow.seller_id;
    
    UPDATE properties SET escrow_status = 'sold', is_active = false, is_sold = true, sold_at = NOW(), final_buyer_id = p_buyer_id WHERE id = v_escrow.property_id;
    
    PERFORM increment_trust_score(v_escrow.seller_id, 5, 'successful_sale');
    IF v_escrow.agent_id IS NOT NULL THEN PERFORM increment_trust_score(v_escrow.agent_id, 3, 'successful_sale'); END IF;
    
    RETURN QUERY SELECT true, 'Handshake completed', v_escrow.agent_commission, v_escrow.necxa_fee, v_escrow.deposit_amount;
END;
$$;


