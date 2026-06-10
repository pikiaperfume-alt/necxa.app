-- ═══════════════════════════════════════════════════════════════════════════
-- NECXA SOCIAL ENGINE EXPANSION
-- Supporting Clever-Processor (Redis Sync) and Media Reuse Loops
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. EXPAND COMMUNITY POSTS ──────────────────────────────────────────────

ALTER TABLE community_posts 
ADD COLUMN IF NOT EXISTS media_asset_id UUID,
ADD COLUMN IF NOT EXISTS audio_url TEXT,
ADD COLUMN IF NOT EXISTS creator_mode TEXT DEFAULT 'unified',
ADD COLUMN IF NOT EXISTS is_fast_sync BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS gallery_urls TEXT[] DEFAULT '{}',
ADD COLUMN IF NOT EXISTS editing_metadata JSONB DEFAULT '{}',
ADD COLUMN IF NOT EXISTS artist_metadata JSONB DEFAULT '{}';

-- ── 2. MEDIA USAGE TRACKING (VIRAL LOOP) ───────────────────────────────────

CREATE TABLE IF NOT EXISTS media_usage (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    asset_id UUID NOT NULL, -- References media_assets.id or internal logic
    post_id UUID NOT NULL REFERENCES community_posts(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    usage_type TEXT DEFAULT 'reuse', -- 'reuse', 'remix', 'duet'
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexing for fast aggregation (e.g., "Most used sound")
CREATE INDEX IF NOT EXISTS idx_media_usage_asset ON media_usage(asset_id);
CREATE INDEX IF NOT EXISTS idx_media_usage_user ON media_usage(user_id);

-- ── 3. PROFILE SYNC (SOCIAL VIEW) ──────────────────────────────────────────

-- Add compatibility columns to profiles if they don't exist
ALTER TABLE profiles 
ADD COLUMN IF NOT EXISTS display_name TEXT,
ADD COLUMN IF NOT EXISTS photo_url TEXT;

-- Trigger to keep display_name/photo_url in sync with full_name/avatar_url
CREATE OR REPLACE FUNCTION fn_sync_social_profile_fields()
RETURNS TRIGGER AS $$
BEGIN
    NEW.display_name := COALESCE(NEW.display_name, NEW.full_name);
    NEW.photo_url := COALESCE(NEW.photo_url, NEW.avatar_url);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS tr_sync_social_fields ON profiles;
CREATE TRIGGER tr_sync_social_fields
BEFORE INSERT OR UPDATE ON profiles
FOR EACH ROW EXECUTE FUNCTION fn_sync_social_profile_fields();

-- Update existing profiles
UPDATE profiles SET display_name = full_name, photo_url = avatar_url WHERE display_name IS NULL;

-- ── 4. RLS POLICIES ─────────────────────────────────────────────────────────

ALTER TABLE media_usage ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can see media usage" ON media_usage;
CREATE POLICY "Anyone can see media usage" ON media_usage FOR SELECT USING (true);

DROP POLICY IF EXISTS "Users can log media usage" ON media_usage;
CREATE POLICY "Users can log media usage" ON media_usage FOR INSERT WITH CHECK (auth.uid() = user_id);

-- ── 5. PERFORMANCE OPTIMIZATION ────────────────────────────────────────────

-- Index for the feed query (status + visibility + created_at)
CREATE INDEX IF NOT EXISTS idx_posts_feed_v3 
ON community_posts (status, visibility, created_at DESC);

-- ── 6. VIEW FOR SOCIAL FEED (CLEANER QUERIES) ──────────────────────────────

CREATE OR REPLACE VIEW v_social_feed AS
SELECT 
    p.*,
    u.display_name as author_name,
    u.photo_url as author_photo,
    u.trust_score as author_trust,
    (u.trust_score >= 70) as is_verified
FROM community_posts p
JOIN profiles u ON p.author_id = u.id
WHERE p.visibility = 'public' AND p.status IN ('verified', 'pending');
