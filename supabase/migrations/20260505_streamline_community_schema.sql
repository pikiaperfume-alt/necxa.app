-- ═══════════════════════════════════════════════════════════════════════════
-- NECXA PLATFORM – MIGRATION: Streamline Community & Profile Performance
-- File: 20260505_streamline_community_schema.sql
-- Goal: Optimize for lazy-loaded profiles and decoupled media pipelines.
-- ═══════════════════════════════════════════════════════════════════════════

-- 1. Explicit Media Pipeline for Listings
-- Support for high-fidelity video storage separated from product miniatures
ALTER TABLE public.listings
  ADD COLUMN IF NOT EXISTS film_hub_content TEXT;

-- 2. Performance Indexes for Lazy-Loaded Profile Grids
-- These composite indexes allow for O(1) or O(log n) lookups for user-specific content
-- sorted by time, which is the primary hot path for the Profile and Public Profile screens.

-- Index for Community Posts (Profile Grid)
CREATE INDEX IF NOT EXISTS idx_posts_author_created 
  ON public.community_posts(author_id, created_at DESC);

-- Index for Listings (Showcase Grid)
CREATE INDEX IF NOT EXISTS idx_listings_user_created 
  ON public.listings(user_id, created_at DESC);

-- 3. Optimized View for Streamlined Feed
-- Updating v_viral_feed to include the explicit film_hub_content and support deep-linking
DROP VIEW IF EXISTS v_viral_feed;
CREATE OR REPLACE VIEW v_viral_feed AS
SELECT 
    p.*,
    pr.full_name    AS author_name,
    pr.avatar_url   AS author_avatar,
    pr.trust_score_tier AS author_trust_tier,
    l.title         AS listing_title,
    l.price_ugx     AS listing_price,
    l.category      AS listing_category,
    l.film_hub_content AS listing_film_hub_content,
    l.photos        AS listing_photos
FROM community_posts p
LEFT JOIN profiles pr ON pr.id = p.author_id
LEFT JOIN listings  l  ON l.id  = p.listing_id
WHERE p.status = 'verified' 
  AND p.visibility = 'public'
ORDER BY p.created_at DESC;

-- 4. Record the migration
INSERT INTO system_logs (category, message, metadata)
VALUES (
  'SCHEMA', 
  'Streamline Community applied: Added film_hub_content and composite performance indexes.',
  '{"version": "20260505", "optimized_tables": ["community_posts", "listings"]}'
);
