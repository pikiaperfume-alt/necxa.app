-- ═══════════════════════════════════════════════════════════════════════════
-- NECXA PLATFORM – MIGRATION: 20260418 – Reusable Media & Viral Loops
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. MEDIA ASSETS (The Canonical Source) ──────────────────────────────────
-- Assets can be videos, audio tracks, or templates that are reusable.
CREATE TABLE IF NOT EXISTS media_assets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    creator_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    
    asset_type TEXT NOT NULL, -- 'video', 'audio', 'template', 'original_sound'
    url TEXT NOT NULL,
    thumbnail_url TEXT,
    
    title TEXT,               -- e.g., "Original Sound - @username"
    description TEXT,
    
    metadata JSONB DEFAULT '{}', -- Duration, bitrate, bpm, mood, etc.
    
    -- Viral Tracking
    usage_count INT DEFAULT 0,
    daily_usage_velocity FLOAT DEFAULT 0, -- Usage speed (7-day exponential moving average)
    
    is_verified BOOLEAN DEFAULT false,    -- Professional/Artist tracks
    is_public BOOLEAN DEFAULT true,
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_media_assets_creator ON media_assets(creator_id);
CREATE INDEX IF NOT EXISTS idx_media_assets_type ON media_assets(asset_type);
CREATE INDEX IF NOT EXISTS idx_media_assets_velocity ON media_assets(daily_usage_velocity DESC);

-- ── 2. MEDIA USAGE RECORDING ────────────────────────────────────────────────
-- Tracks which post uses which asset.
CREATE TABLE IF NOT EXISTS media_usage (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    asset_id UUID NOT NULL REFERENCES media_assets(id) ON DELETE CASCADE,
    post_id UUID NOT NULL, -- References community_posts(id) or listings(id)
    user_id UUID NOT NULL REFERENCES profiles(id),
    
    usage_type TEXT DEFAULT 'reuse', -- 'reuse', 'duet', 'stitch'
    
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_media_usage_asset ON media_usage(asset_id);
CREATE INDEX IF NOT EXISTS idx_media_usage_post ON media_usage(post_id);

-- ── 3. SAVED MEDIA (User Library) ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS saved_media (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    asset_id UUID NOT NULL REFERENCES media_assets(id) ON DELETE CASCADE,
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, asset_id)
);

-- ── 4. TRENDING MEDIA VIEW ──────────────────────────────────────────────────
-- Materialized view for fast discovery.
CREATE MATERIALIZED VIEW IF NOT EXISTS trending_media AS
SELECT 
    ma.*,
    p.full_name as creator_name,
    p.avatar_url as creator_photo
FROM media_assets ma
JOIN profiles p ON ma.creator_id = p.id
WHERE ma.is_public = true
ORDER BY ma.daily_usage_velocity DESC, ma.usage_count DESC
LIMIT 100;

CREATE UNIQUE INDEX IF NOT EXISTS idx_trending_media_id ON trending_media(id);

-- ── 5. UPDATE EXISTING POSTS ───────────────────────────────────────────────
ALTER TABLE community_posts ADD COLUMN IF NOT EXISTS media_asset_id UUID REFERENCES media_assets(id);

-- ── 6. ROW LEVEL SECURITY ──────────────────────────────────────────────────
ALTER TABLE media_assets ENABLE ROW LEVEL SECURITY;
ALTER TABLE media_usage ENABLE ROW LEVEL SECURITY;
ALTER TABLE saved_media ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can view public media assets" ON media_assets FOR SELECT USING (is_public = true);
CREATE POLICY "Creators can manage own assets" ON media_assets FOR ALL USING (auth.uid() = creator_id);

CREATE POLICY "Anyone can view media usage" ON media_usage FOR SELECT USING (true);
CREATE POLICY "Users can record usage" ON media_usage FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can manage saved media" ON saved_media FOR ALL USING (auth.uid() = user_id);

-- ── 7. TRIGGERS FOR USAGE COUNTING ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION handle_media_usage_stats() RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE media_assets 
        SET usage_count = usage_count + 1,
            daily_usage_velocity = daily_usage_velocity + 1 -- Simple increment for velocity, usually managed by cron
        WHERE id = NEW.asset_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_media_usage_added
    AFTER INSERT ON media_usage
    FOR EACH ROW EXECUTE FUNCTION handle_media_usage_stats();
