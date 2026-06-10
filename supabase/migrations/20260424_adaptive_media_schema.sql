-- ═══════════════════════════════════════════════════════════════════════════
-- NECXA PLATFORM – MIGRATION: Adaptive Media Schema
-- File: 20260424_adaptive_media_schema.sql
-- Goal: Add HLS/DASH support and versioning for CDN optimization.
-- ═══════════════════════════════════════════════════════════════════════════

-- 1. Update Community Posts to support adaptive streams
ALTER TABLE community_posts 
ADD COLUMN IF NOT EXISTS hls_url TEXT,
ADD COLUMN IF NOT EXISTS dash_url TEXT,
ADD COLUMN IF NOT EXISTS media_version INTEGER DEFAULT 1;

-- 2. Update Listings to support adaptive streams
ALTER TABLE listings 
ADD COLUMN IF NOT EXISTS hls_url TEXT,
ADD COLUMN IF NOT EXISTS dash_url TEXT,
ADD COLUMN IF NOT EXISTS media_version INTEGER DEFAULT 1;

-- 3. Update Chat Messages for ephemeral adaptive media
ALTER TABLE chat_messages 
ADD COLUMN IF NOT EXISTS hls_url TEXT,
ADD COLUMN IF NOT EXISTS media_version INTEGER DEFAULT 1;

-- 4. Create index for faster sync of active media
CREATE INDEX IF NOT EXISTS idx_posts_hls ON community_posts(hls_url) WHERE hls_url IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_listings_hls ON listings(hls_url) WHERE hls_url IS NOT NULL;

-- 5. Helper function to get CDN-ready URL with versioning
CREATE OR REPLACE FUNCTION get_cdn_url(base_url TEXT, version INTEGER)
RETURNS TEXT AS $$
BEGIN
  IF base_url IS NULL THEN RETURN NULL; END IF;
  RETURN base_url || '?v=' || version;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Update system log
INSERT INTO system_logs (category, message, metadata)
VALUES ('MEDIA', 'Adaptive Media Schema (HLS/DASH) initialized.', 
        '{"version": 1, "protocol": "HLS"}');
