-- ═══════════════════════════════════════════════════════════════════════════
-- NECXA PLATFORM – MIGRATION: 20260420 – Virtual Sync Expansion
-- ═══════════════════════════════════════════════════════════════════════════

-- 1. ADD ARCHITECTURAL COLUMNS TO COMMUNITY_POSTS
-- These support TikTok-style Virtual Sync (Dual-Stream Playback)
ALTER TABLE community_posts 
ADD COLUMN IF NOT EXISTS media_type TEXT DEFAULT 'image',
ADD COLUMN IF NOT EXISTS audio_url TEXT,
ADD COLUMN IF NOT EXISTS media_asset_id UUID,
ADD COLUMN IF NOT EXISTS music_track_id UUID REFERENCES music_tracks(id);

-- 2. ADD VIRTUAL SYNC INDEXES
-- For fast lookup of posts using the same sound loop
CREATE INDEX IF NOT EXISTS idx_community_posts_music ON community_posts(music_track_id);
CREATE INDEX IF NOT EXISTS idx_community_posts_media_type ON community_posts(media_type);

-- 3. UPDATE RLS FOR SMART CONTENT DISCOVERY
-- Ensure audio_url is explicitly allowed in select policies
COMMENT ON COLUMN community_posts.audio_url IS 'URL for non-baked background audio (Virtual Sync Loop)';
COMMENT ON COLUMN community_posts.media_type IS 'Distinguishes between raw image, video, and synth_loop';
