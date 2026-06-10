-- ═══════════════════════════════════════════════════════════════════════════
-- NECXA PLATFORM – MIGRATION: Unified Creators & Artist Infrastructure
-- File: 20260419_backend_unification.sql
-- Goal: Unify community_posts and creator_posts into a single source of truth.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. MODERNISED ENUMS ───────────────────────────────────────────────────

-- Content Creation Mode
DO $$ BEGIN
  CREATE TYPE creator_mode AS ENUM ('unified', 'artist');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Pro Metadata Media Types
DO $$ BEGIN
  CREATE TYPE detailed_media_type AS ENUM ('video', 'image', 'sequence', 'pro_edit');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;


-- ── 2. HARMONIZE community_posts TABLE ───────────────────────────────────
-- We use community_posts as the primary table since it's already integrated with the feed.

ALTER TABLE community_posts
  ADD COLUMN IF NOT EXISTS creator_mode      creator_mode DEFAULT 'unified',
  ADD COLUMN IF NOT EXISTS is_fast_sync      BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS gallery_urls      TEXT[],        -- Support for multi-media tiles
  ADD COLUMN IF NOT EXISTS editing_metadata  JSONB,         -- Sequencer, Trims, FX, Overlays
  ADD COLUMN IF NOT EXISTS artist_metadata   JSONB,         -- Distributor links, Legal details
  ADD COLUMN IF NOT EXISTS thumbnail_url      TEXT,          -- Instant-load preview
  ADD COLUMN IF NOT EXISTS audio_url         TEXT,          -- Non-baked background audio
  ADD COLUMN IF NOT EXISTS media_type        TEXT DEFAULT 'image', -- image, video, synth_loop
  ADD COLUMN IF NOT EXISTS music_track_id    UUID,          -- Reference to music_tracks (if applicable)
  ADD COLUMN IF NOT EXISTS tags              TEXT[],        -- Unified tags
  ADD COLUMN IF NOT EXISTS media_asset_id    UUID;          -- Link to reusable media asset

-- Migrate tags from the legacy array if needed
-- UPDATE community_posts SET tags = metadata->'tags' WHERE tags IS NULL;


-- ── 3. CLEANUP LEGACY MESS ────────────────────────────────────────────────

-- Drop legacy views first to resolve dependencies
DROP VIEW IF EXISTS v_creator_feed;
DROP VIEW IF EXISTS v_trending_tags;

-- Drop the redundant creator_posts infrastructure
DROP TABLE IF EXISTS creator_post_tags;
DROP TABLE IF EXISTS creator_post_reactions;
DROP TABLE IF EXISTS creator_post_saves;
DROP TABLE IF EXISTS creator_audio_tracks;
DROP TABLE IF EXISTS creator_posts;


-- ── 4. ARTIST DISTRIBUTION LEDGER ────────────────────────────────────────

CREATE TABLE IF NOT EXISTS artist_payout_ledger (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  artist_id       UUID NOT NULL REFERENCES profiles(id),
  post_id         UUID NOT NULL REFERENCES community_posts(id),
  
  fee_amount      INT DEFAULT 150,     -- Necxa Coins
  currency        TEXT DEFAULT 'NCX',
  
  distributor_ref TEXT,                -- e.g. "DistroKid-TX-9981"
  status          TEXT DEFAULT 'paid', -- paid, pending, failed
  
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_payout_artist ON artist_payout_ledger(artist_id);
CREATE INDEX IF NOT EXISTS idx_payout_post   ON artist_payout_ledger(post_id);


-- ── 5. UPDATE RLS POLICIES FOR UNIFIED TABLE ─────────────────────────────

-- Ensure artists can only post distribution content if verified (simplified logic)
-- Drop existing insert policy if it conflicts or use CREATE POLICY IF NOT EXISTS (note: Supabase doesn't have IF NOT EXISTS for policies, so we drop first)
DROP POLICY IF EXISTS "Strict artist distribution policy" ON community_posts;
CREATE POLICY "Strict artist distribution policy" ON community_posts
  FOR INSERT WITH CHECK (
    (creator_mode = 'unified') OR
    (creator_mode = 'artist' AND EXISTS (
      SELECT 1 FROM profiles 
      WHERE id = auth.uid() 
      AND trust_score_tier IN ('verified', 'titan_trust')
    ))
  );


-- ── 6. REALTIME REGISTRATION ──────────────────────────────────────────────
-- Ensure community_posts is still in the publication
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' AND tablename = 'community_posts'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE community_posts;
  END IF;
END $$;


-- ── 7. MODERNIZED VIEWS (Unified) ─────────────────────────────────────────

-- Recreate v_creator_feed pointing to the unified community_posts table
CREATE OR REPLACE VIEW v_creator_feed AS
SELECT
  p.id,
  p.created_at,
  p.author_id      AS creator_id,
  pr.full_name     AS creator_name,
  pr.avatar_url    AS creator_avatar,
  p.title,
  p.content,
  p.creator_mode,
  p.media_url,
  p.audio_url,
  p.gallery_urls,
  p.editing_metadata,
  p.artist_metadata,
  p.thumbnail_url,
  p.tags,
  p.likes_count,
  p.status,
  p.visibility
FROM community_posts p
JOIN profiles pr ON pr.id = p.author_id
WHERE p.status IN ('verified', 'pending')
  AND p.visibility = 'public';

-- ═══════════════════════════════════════════════════════════════════════════
-- END OF MODERNIZATION
-- ═══════════════════════════════════════════════════════════════════════════
