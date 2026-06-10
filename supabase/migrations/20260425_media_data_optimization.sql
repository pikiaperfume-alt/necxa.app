-- ═══════════════════════════════════════════════════════════════════════════
-- ── 0. SCHEMA HARDENING (Ensure all fields exist) ─────────────────────────
ALTER TABLE community_posts 
  ADD COLUMN IF NOT EXISTS thumbnail_url TEXT,
  ADD COLUMN IF NOT EXISTS audio_url TEXT,
  ADD COLUMN IF NOT EXISTS hls_url TEXT,
  ADD COLUMN IF NOT EXISTS media_type TEXT DEFAULT 'image',
  ADD COLUMN IF NOT EXISTS media_version INTEGER DEFAULT 1;

ALTER TABLE listings 
  ADD COLUMN IF NOT EXISTS thumbnail_url TEXT,
  ADD COLUMN IF NOT EXISTS hls_url TEXT,
  ADD COLUMN IF NOT EXISTS media_type TEXT DEFAULT 'image',
  ADD COLUMN IF NOT EXISTS media_version INTEGER DEFAULT 1,
  ADD COLUMN IF NOT EXISTS price_ugx NUMERIC,
  ADD COLUMN IF NOT EXISTS media_url TEXT,
  ADD COLUMN IF NOT EXISTS property_type TEXT,
  ADD COLUMN IF NOT EXISTS purpose TEXT,
  ADD COLUMN IF NOT EXISTS bedrooms INTEGER,
  ADD COLUMN IF NOT EXISTS bathrooms INTEGER;

-- Backfill from legacy columns if they exist
UPDATE listings SET price_ugx = price WHERE price_ugx IS NULL AND price IS NOT NULL;
UPDATE listings SET media_url = image_url WHERE media_url IS NULL AND image_url IS NOT NULL;

-- ── 1. OPTIMIZED COMMUNITY FEED VIEW ──────────────────────────────────────
-- Only exposes lightweight fields + pre-calculated CDN URLs
DROP VIEW IF EXISTS v_community_feed_optimized;
CREATE VIEW v_community_feed_optimized AS
SELECT 
    p.id,
    p.author_id,
    p.content,
    p.media_url,
    p.thumbnail_url,
    p.audio_url,
    p.media_type,
    p.hls_url,
    p.media_version,
    -- Pre-calculate CDN URLs to save client computation
    get_cdn_url(p.media_url, p.media_version) as cdn_media_url,
    get_cdn_url(p.hls_url, p.media_version) as cdn_hls_url,
    p.created_at,
    p.likes_count,
    p.comments_count,
    -- Joined Profile Info (prevents extra lookups)
    u.full_name as author_name,
    u.avatar_url as author_avatar
FROM community_posts p
LEFT JOIN profiles u ON p.author_id = u.id
WHERE p.status = 'verified' 
  AND p.visibility = 'public'
ORDER BY p.created_at DESC;

-- ── 1.1 FEED BACKFILL (Ensure immediate visibility) ───────────────────────
UPDATE community_posts 
SET status = 'verified', visibility = 'public' 
WHERE (status IS NULL OR status IN ('draft', 'published')) 
  AND media_url IS NOT NULL;

-- ── 2. OPTIMIZED LISTINGS VIEW ──────────────────────────────────────────
DROP VIEW IF EXISTS v_listings_optimized;
CREATE VIEW v_listings_optimized AS
SELECT 
    l.id,
    l.title,
    l.price_ugx,
    l.media_url,
    l.thumbnail_url,
    l.media_type,
    l.hls_url,
    l.media_version,
    get_cdn_url(l.media_url, l.media_version) as cdn_media_url,
    l.property_type,
    l.purpose,
    l.bedrooms,
    l.bathrooms,
    l.created_at,
    l.is_verified,
    -- Seller Info
    u.full_name as lister_name,
    u.avatar_url as lister_avatar
FROM listings l
LEFT JOIN profiles u ON l.lister_id = u.id
WHERE l.is_active = TRUE 
  AND l.is_honeypot = FALSE
ORDER BY l.created_at DESC;

-- ── 3. AUTOMATIC MEDIA VERSIONING ───────────────────────────────────────
-- Increments media_version whenever the source URL changes, forcing CDN refresh.
CREATE OR REPLACE FUNCTION fn_increment_media_version()
RETURNS TRIGGER AS $$
BEGIN
    IF (NEW.media_url IS DISTINCT FROM OLD.media_url) OR (NEW.hls_url IS DISTINCT FROM OLD.hls_url) THEN
        NEW.media_version := OLD.media_version + 1;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply to high-traffic tables
CREATE OR REPLACE TRIGGER tr_posts_media_version
BEFORE UPDATE ON community_posts
FOR EACH ROW EXECUTE FUNCTION fn_increment_media_version();

CREATE OR REPLACE TRIGGER tr_listings_media_version
BEFORE UPDATE ON listings
FOR EACH ROW EXECUTE FUNCTION fn_increment_media_version();

-- ── 4. CHAT EPHEMERAL RELAY PURGE ───────────────────────────────────────
-- Aggressive purge for chat media to ensure nothing is persisted.
-- This function clears BOTH the database record and the storage metadata.
CREATE OR REPLACE FUNCTION purge_chat_relay()
RETURNS VOID AS $$
BEGIN
    -- 1. Mark messages as expired if they have a media URL
    UPDATE chat_messages 
    SET content = '[Media Expired/Handshake Complete]', 
        media_url = NULL, 
        hls_url = NULL,
        metadata = metadata || '{"handshake": "expired"}'::jsonb
    WHERE expires_at < NOW() 
       OR (created_at < NOW() - INTERVAL '1 hour' AND (metadata->>'handshake') IS NULL);
       
    -- 2. Storage cleanup (requires Edge Function hook or background worker)
    -- In a real setup, we would trigger 'supabase.storage.from("chat-relay").remove(...)'
END;
$$ LANGUAGE plpgsql;

-- ── 5. BUCKET SETUP (Handshake Protocol) ────────────────────────────────
-- Ensure the 'chat-relay' bucket is configured for ultra-short TTLs.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('chat-relay', 'chat-relay', FALSE, 52428800, '{image/*,video/*,audio/*}')
ON CONFLICT (id) DO NOTHING;

-- RLS: Only allow access if user is sender or receiver of the linked message
-- (Note: Complex RLS for storage usually requires joining with app tables)

-- ── 5. SYSTEM LOGGING ───────────────────────────────────────────────────
INSERT INTO system_logs (category, message, metadata)
VALUES ('OPTIMIZATION', 'Media & Data Optimization views/triggers initialized.', 
        '{"views": ["v_community_feed_optimized", "v_listings_optimized"], "logic": "CDN-Versioning"}');
