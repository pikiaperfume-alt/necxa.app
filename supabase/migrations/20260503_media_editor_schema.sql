-- ═══════════════════════════════════════════════════════════════════════════
-- NECXA PLATFORM – MIGRATION: Media Editor & Commerce Schema
-- File: 20260503_media_editor_schema.sql
-- Goal: Support Shop Reel shadow posts, music linking, and rich post metadata
-- ═══════════════════════════════════════════════════════════════════════════

-- 1. Add listing_id to link community posts back to their source listing
--    (Used by "Shop Reel" shadow posts created by clever-processor)
ALTER TABLE public.community_posts
  ADD COLUMN IF NOT EXISTS listing_id UUID REFERENCES public.listings(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS music_track_id UUID REFERENCES public.music_tracks(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS audio_url TEXT,
  ADD COLUMN IF NOT EXISTS tags TEXT[] DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS metadata JSONB DEFAULT '{}'::jsonb;

-- 2. Index for shop reel lookups (listing → post)
CREATE INDEX IF NOT EXISTS idx_posts_listing_id ON public.community_posts(listing_id);
CREATE INDEX IF NOT EXISTS idx_posts_music_track ON public.community_posts(music_track_id);

-- 3. Index for tag-based discovery
CREATE INDEX IF NOT EXISTS idx_posts_tags ON public.community_posts USING GIN(tags);

-- 4. Add photos array to listings for multi-photo support
ALTER TABLE public.listings
  ADD COLUMN IF NOT EXISTS photos TEXT[] DEFAULT '{}';

-- 5. Update v_viral_feed to expose shop reel metadata
DROP VIEW IF EXISTS v_viral_feed;
CREATE OR REPLACE VIEW v_viral_feed AS
SELECT 
    p.*,
    pr.full_name    AS author_name,
    pr.avatar_url   AS author_avatar,
    pr.trust_score_tier AS author_trust_tier,
    -- Embed basic listing data inline so the client doesn't need a second query
    l.title         AS listing_title,
    l.price_ugx     AS listing_price,
    l.category      AS listing_category
FROM community_posts p
LEFT JOIN profiles pr ON pr.id = p.author_id
LEFT JOIN listings  l  ON l.id  = p.listing_id
WHERE p.status = 'verified' 
  AND p.visibility = 'public'
ORDER BY p.created_at DESC;

-- 6. Log
INSERT INTO system_logs (category, message, metadata)
VALUES (
  'SCHEMA', 
  'Media editor commerce schema applied: listing_id, music_track_id, photos, tags, metadata columns added.',
  '{"tables": ["community_posts", "listings"], "version": "20260503"}'
);
