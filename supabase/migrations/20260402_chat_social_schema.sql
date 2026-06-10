-- NECXA PLATFORM – Supabase Migration for Chat, Social & Agent Integration
-- ── 1. AGENT ENGAGEMENT & ESCROW CHAT SCHEMA ────────────────────

-- Chat Rooms linking Agents, Clients, and Escrow Transactions
CREATE TABLE chat_rooms (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    property_id UUID REFERENCES properties(id) ON DELETE SET NULL,
    escrow_id UUID, -- Assuming escrow_reservations(id) exists in your initial schema
    agent_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    client_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    room_type TEXT NOT NULL CHECK (room_type IN ('inquiry', 'escrow_active', 'support', 'creator_dm')),
    status TEXT DEFAULT 'active' CHECK (status IN ('active', 'locked', 'archived')),
    latest_message TEXT,
    latest_message_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(agent_id, client_id, property_id) -- Prevent duplicate rooms for the same deal
);

-- Chat Messages with deep interaction types (e.g. Wallet/Escrow alerts inline)
CREATE TABLE chat_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    room_id UUID REFERENCES chat_rooms(id) ON DELETE CASCADE,
    sender_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    message_type TEXT DEFAULT 'text' CHECK (message_type IN (
        'text', 
        'image', 
        'system_escrow_deposit', 
        'system_wallet_refund', 
        'system_qr_scan', 
        'location_pin'
    )),
    content TEXT,
    media_url TEXT,
    metadata JSONB, -- stores extra data like amount deposited or GPS coords
    is_read BOOLEAN DEFAULT FALSE,
    read_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_chat_rooms_agent ON chat_rooms(agent_id);
CREATE INDEX idx_chat_rooms_client ON chat_rooms(client_id);
CREATE INDEX idx_chat_messages_room ON chat_messages(room_id);

-- ── 2. CREATOR CONFIGURATION SCHEMA ──────────────────────────────────

-- Extensions to profiles for users acting in "Creator/Agent Mode"
CREATE TABLE creators (
    id UUID PRIMARY KEY REFERENCES profiles(id) ON DELETE CASCADE,
    display_name TEXT,
    bio TEXT,
    content_niche TEXT DEFAULT 'real_estate',
    total_followers INT DEFAULT 0,
    total_likes INT DEFAULT 0,
    is_live BOOLEAN DEFAULT FALSE,
    agora_channel_token TEXT, -- Integration for live streams
    tier TEXT DEFAULT 'rising' CHECK (tier IN ('rising', 'established', 'titan')),
    wallet_split_percentage INT DEFAULT 80, -- % of earnings they keep
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Followers mapping table
CREATE TABLE creator_followers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    creator_id UUID REFERENCES creators(id) ON DELETE CASCADE,
    follower_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    notification_level TEXT DEFAULT 'all' CHECK (notification_level IN ('all', 'live_only', 'none')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(creator_id, follower_id)
);

CREATE INDEX idx_followers_creator ON creator_followers(creator_id);
CREATE INDEX idx_followers_follower ON creator_followers(follower_id);

-- ── 3. CREATOR COMMUNITY & BROADCAST CHAT SCHEMA ───────────────────

-- Mass broadcast rooms for a creator to ping all their followers
CREATE TABLE creator_broadcast_channels (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    creator_id UUID UNIQUE REFERENCES creators(id) ON DELETE CASCADE,
    channel_name TEXT,
    is_subscriber_only BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Messages sent securely into the broadcast feed
CREATE TABLE creator_broadcast_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    channel_id UUID REFERENCES creator_broadcast_channels(id) ON DELETE CASCADE,
    content TEXT,
    media_url TEXT,
    likes_count INT DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Automatic Triggers for updating Chat Room logic
CREATE OR REPLACE FUNCTION update_chat_room_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE chat_rooms 
    SET latest_message_at = NEW.created_at,
        latest_message = NEW.content,
        updated_at = NOW()
    WHERE id = NEW.room_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER on_new_chat_message
    AFTER INSERT ON chat_messages
    FOR EACH ROW EXECUTE FUNCTION update_chat_room_timestamp();

-- Automatic trigger for incrementing follower counts
CREATE OR REPLACE FUNCTION increment_follower_count()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE creators
    SET total_followers = total_followers + 1
    WHERE id = NEW.creator_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER on_new_follower
    AFTER INSERT ON creator_followers
    FOR EACH ROW EXECUTE FUNCTION increment_follower_count();

CREATE OR REPLACE FUNCTION decrement_follower_count()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE creators
    SET total_followers = GREATEST(total_followers - 1, 0)
    WHERE id = OLD.creator_id;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER on_unfollow
    AFTER DELETE ON creator_followers
    FOR EACH ROW EXECUTE FUNCTION decrement_follower_count();
