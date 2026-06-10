-- ═══════════════════════════════════════════════════════════════════════════
-- NECXA PLATFORM – MIGRATION: Creator Upload Hub v2
-- File: 20260410_creator_hub_schema.sql
-- Supports: Picture · Video · Audio · Synthesizer · Video+Music · Picture+Music
-- Run in Supabase SQL Editor
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. ENUMS ─────────────────────────────────────────────────────────────

-- Creator content type (maps 1:1 to CreatorType enum in Flutter)
DO $$ BEGIN
  CREATE TYPE creator_content_type AS ENUM (
    'picture',        -- 🖼️  Image only
    'video',          -- 🎬  Video only
    'audio',          -- 🎵  Audio + cover art
    'synth',          -- 🎛️  Visual mood + beat track
    'video_music',    -- 🎬🎵 Video + music layer
    'picture_music'   -- 🖼️🎵 Picture + music layer
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Synthesizer mood presets
DO $$ BEGIN
  CREATE TYPE synth_mood AS ENUM (
    'dark_pulse',
    'vibrant_city',
    'cosmic',
    'neon_grid',
    'golden_hour',
    'deep_sea'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Post moderation status
DO $$ BEGIN
  CREATE TYPE content_status AS ENUM (
    'pending',      -- just uploaded, pending AI review
    'verified',     -- AI approved, visible to all
    'flagged',      -- flagged for human review
    'archived'      -- soft deleted
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;


-- ── 2. EXTEND creator_posts TABLE ────────────────────────────────────────
-- These are ALTER TABLE statements so they're safe to run on existing tables.

ALTER TABLE creator_posts
  ADD COLUMN IF NOT EXISTS creator_type    creator_content_type DEFAULT 'picture',
  ADD COLUMN IF NOT EXISTS audio_url       TEXT,          -- audio track URL (for audio/synth/music types)
  ADD COLUMN IF NOT EXISTS synth_mood      synth_mood,    -- which mood was selected (synth type only)
  ADD COLUMN IF NOT EXISTS tags            TEXT[],        -- hashtags/tags array
  ADD COLUMN IF NOT EXISTS duration_secs   INTEGER,       -- audio/video duration in seconds
  ADD COLUMN IF NOT EXISTS thumbnail_url   TEXT,          -- video thumbnail / audio cover art
  ADD COLUMN IF NOT EXISTS plays_count     BIGINT DEFAULT 0,
  ADD COLUMN IF NOT EXISTS shares_count    INT    DEFAULT 0,
  ADD COLUMN IF NOT EXISTS saves_count     INT    DEFAULT 0,
  ADD COLUMN IF NOT EXISTS community_id    TEXT   DEFAULT 'global_node',
  ADD COLUMN IF NOT EXISTS is_ai_reviewed  BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS ai_score        FLOAT,         -- 0-1 content trust score
  ADD COLUMN IF NOT EXISTS ai_notes        JSONB;

-- Rename type → creator_type if old 'type' column exists
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'creator_posts' AND column_name = 'type'
  ) THEN
    -- migrate existing data
    UPDATE creator_posts SET creator_type = 'picture' WHERE creator_type IS NULL;
  END IF;
END $$;


-- ── 3. AUDIO TRACKS TABLE ─────────────────────────────────────────────────
-- Dedicated table for uploaded/recorded audio assets to avoid bloating posts.

CREATE TABLE IF NOT EXISTS creator_audio_tracks (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at      TIMESTAMPTZ DEFAULT NOW(),

  creator_id      UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  post_id         UUID REFERENCES creator_posts(id) ON DELETE CASCADE,

  -- Storage
  audio_url       TEXT NOT NULL,                -- Supabase Storage URL
  cover_art_url   TEXT,                         -- cover image URL (required for 'audio' type)
  storage_path    TEXT,                         -- internal path e.g. audio/uid/filename.m4a

  -- Metadata
  title           TEXT,
  duration_secs   INTEGER,
  mime_type       TEXT DEFAULT 'audio/mp4',     -- audio/mp4 | audio/mpeg | audio/ogg
  file_size_bytes BIGINT,
  waveform_data   FLOAT[],                      -- array of amplitude values (for waveform UI)

  -- Synth specific
  synth_mood      synth_mood,                   -- if this is a synth beat
  bpm             INTEGER,                      -- beats per minute (optional)
  key_signature   TEXT,                         -- e.g. 'Am', 'C#maj'

  -- Stats
  plays_count     BIGINT DEFAULT 0,

  status          content_status DEFAULT 'pending'
);

CREATE INDEX IF NOT EXISTS idx_audio_creator   ON creator_audio_tracks(creator_id);
CREATE INDEX IF NOT EXISTS idx_audio_post      ON creator_audio_tracks(post_id);
CREATE INDEX IF NOT EXISTS idx_audio_mood      ON creator_audio_tracks(synth_mood);
CREATE INDEX IF NOT EXISTS idx_audio_status    ON creator_audio_tracks(status);


-- ── 4. POST TAGS TABLE ────────────────────────────────────────────────────
-- Normalised tag table for efficient filtering and trending discovery.

CREATE TABLE IF NOT EXISTS creator_tags (
  id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name      TEXT UNIQUE NOT NULL,               -- e.g. 'afrobeats', 'kampala'
  use_count BIGINT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_tags_name      ON creator_tags(name);
CREATE INDEX IF NOT EXISTS idx_tags_use_count ON creator_tags(use_count DESC);

-- Many-to-many: post ↔ tags
CREATE TABLE IF NOT EXISTS creator_post_tags (
  post_id  UUID REFERENCES creator_posts(id) ON DELETE CASCADE,
  tag_id   UUID REFERENCES creator_tags(id)  ON DELETE CASCADE,
  PRIMARY KEY (post_id, tag_id)
);

CREATE INDEX IF NOT EXISTS idx_post_tags_post ON creator_post_tags(post_id);
CREATE INDEX IF NOT EXISTS idx_post_tags_tag  ON creator_post_tags(tag_id);


-- ── 5. POST REACTIONS TABLE ──────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS creator_post_reactions (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id    UUID NOT NULL REFERENCES creator_posts(id) ON DELETE CASCADE,
  user_id    UUID NOT NULL REFERENCES profiles(id)       ON DELETE CASCADE,
  emoji      TEXT NOT NULL DEFAULT '❤️',                  -- reaction emoji
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(post_id, user_id)                               -- one reaction per user per post
);

CREATE INDEX IF NOT EXISTS idx_reactions_post ON creator_post_reactions(post_id);
CREATE INDEX IF NOT EXISTS idx_reactions_user ON creator_post_reactions(user_id);


-- ── 6. POST SAVES TABLE ───────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS creator_post_saves (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id    UUID NOT NULL REFERENCES creator_posts(id) ON DELETE CASCADE,
  user_id    UUID NOT NULL REFERENCES profiles(id)       ON DELETE CASCADE,
  saved_at   TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(post_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_saves_post ON creator_post_saves(post_id);
CREATE INDEX IF NOT EXISTS idx_saves_user ON creator_post_saves(user_id);


-- ── 7. STORAGE BUCKETS POLICY ─────────────────────────────────────────────
-- Run these via Supabase Dashboard → Storage → New Bucket if not already set up.
-- Listed here as documentation / idempotent SQL comments.

-- Bucket: 'creator-audio'    (public: false, file size limit: 50MB)
-- Bucket: 'creator-media'    (public: true,  file size limit: 200MB)
-- Bucket: 'creator-covers'   (public: true,  file size limit: 5MB)


-- ── 8. RLS POLICIES ──────────────────────────────────────────────────────

ALTER TABLE creator_audio_tracks  ENABLE ROW LEVEL SECURITY;
ALTER TABLE creator_tags          ENABLE ROW LEVEL SECURITY;
ALTER TABLE creator_post_tags     ENABLE ROW LEVEL SECURITY;
ALTER TABLE creator_post_reactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE creator_post_saves    ENABLE ROW LEVEL SECURITY;

-- Audio tracks
CREATE POLICY "Creators can insert own audio"  ON creator_audio_tracks FOR INSERT WITH CHECK (auth.uid() = creator_id);
CREATE POLICY "Creators can view own audio"    ON creator_audio_tracks FOR SELECT USING (auth.uid() = creator_id OR status = 'verified');
CREATE POLICY "Creators can update own audio"  ON creator_audio_tracks FOR UPDATE USING (auth.uid() = creator_id);
CREATE POLICY "Creators can delete own audio"  ON creator_audio_tracks FOR DELETE USING (auth.uid() = creator_id);

-- Tags (read-only for users, insert allowed for track references)
CREATE POLICY "Anyone can view tags"           ON creator_tags FOR SELECT USING (true);
CREATE POLICY "Authenticated can insert tags"  ON creator_tags FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

-- Post tags
CREATE POLICY "Anyone can view post tags"      ON creator_post_tags FOR SELECT USING (true);
CREATE POLICY "Creators can tag own posts"     ON creator_post_tags FOR INSERT
  WITH CHECK (EXISTS (SELECT 1 FROM creator_posts WHERE id = post_id AND creator_id = auth.uid()));

-- Reactions
CREATE POLICY "Anyone can view reactions"      ON creator_post_reactions FOR SELECT USING (true);
CREATE POLICY "Users can react"                ON creator_post_reactions FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can remove own reaction"  ON creator_post_reactions FOR DELETE USING (auth.uid() = user_id);

-- Saves
CREATE POLICY "Users can view own saves"       ON creator_post_saves FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can save posts"           ON creator_post_saves FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can unsave posts"         ON creator_post_saves FOR DELETE USING (auth.uid() = user_id);


-- ── 9. TRIGGERS & FUNCTIONS ───────────────────────────────────────────────

-- Auto-update plays/likes counts on posts
CREATE OR REPLACE FUNCTION increment_post_plays(p_post_id UUID)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE creator_posts SET plays_count = plays_count + 1 WHERE id = p_post_id;
  UPDATE creator_audio_tracks SET plays_count = plays_count + 1 WHERE post_id = p_post_id;
END;
$$;

-- Auto-increment likes_count when reaction inserted
CREATE OR REPLACE FUNCTION handle_reaction_insert()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE creator_posts SET likes_count = likes_count + 1 WHERE id = NEW.post_id;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER on_reaction_insert
  AFTER INSERT ON creator_post_reactions
  FOR EACH ROW EXECUTE FUNCTION handle_reaction_insert();

-- Auto-decrement when reaction removed
CREATE OR REPLACE FUNCTION handle_reaction_delete()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE creator_posts SET likes_count = GREATEST(likes_count - 1, 0) WHERE id = OLD.post_id;
  RETURN OLD;
END;
$$;

CREATE OR REPLACE TRIGGER on_reaction_delete
  AFTER DELETE ON creator_post_reactions
  FOR EACH ROW EXECUTE FUNCTION handle_reaction_delete();

-- Auto-increment saves_count
CREATE OR REPLACE FUNCTION handle_save_insert()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE creator_posts SET saves_count = saves_count + 1 WHERE id = NEW.post_id;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER on_save_insert
  AFTER INSERT ON creator_post_saves
  FOR EACH ROW EXECUTE FUNCTION handle_save_insert();

CREATE OR REPLACE FUNCTION handle_save_delete()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE creator_posts SET saves_count = GREATEST(saves_count - 1, 0) WHERE id = OLD.post_id;
  RETURN OLD;
END;
$$;

CREATE OR REPLACE TRIGGER on_save_delete
  AFTER DELETE ON creator_post_saves
  FOR EACH ROW EXECUTE FUNCTION handle_save_delete();

-- Auto-increment tag use_count when a tag is attached to a post
CREATE OR REPLACE FUNCTION handle_post_tag_insert()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE creator_tags SET use_count = use_count + 1 WHERE id = NEW.tag_id;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER on_post_tag_insert
  AFTER INSERT ON creator_post_tags
  FOR EACH ROW EXECUTE FUNCTION handle_post_tag_insert();


-- ── 10. VIEWS ─────────────────────────────────────────────────────────────

-- Full post view for the community feed
CREATE OR REPLACE VIEW v_creator_feed AS
SELECT
  p.id,
  p.created_at,
  p.creator_id,
  pr.full_name     AS creator_name,
  pr.avatar_url    AS creator_avatar,
  p.title,
  p.content,
  p.creator_type,
  p.media_url,
  p.audio_url,
  p.thumbnail_url,
  p.synth_mood,
  p.tags,
  p.duration_secs,
  p.likes_count,
  p.plays_count,
  p.shares_count,
  p.saves_count,
  p.community_id,
  p.status,
  p.ai_score,
  -- Aggregate tags as array of names
  ARRAY(
    SELECT ct.name
    FROM creator_post_tags cpt
    JOIN creator_tags ct ON ct.id = cpt.tag_id
    WHERE cpt.post_id = p.id
  ) AS tag_names
FROM creator_posts p
JOIN profiles pr ON pr.id = p.creator_id
WHERE p.status IN ('verified', 'pending');

-- Trending tags (last 7 days)
CREATE OR REPLACE VIEW v_trending_tags AS
SELECT
  ct.name,
  ct.use_count,
  COUNT(cpt.post_id) AS recent_uses
FROM creator_tags ct
JOIN creator_post_tags cpt ON cpt.tag_id = ct.id
JOIN creator_posts p ON p.id = cpt.post_id
  AND p.created_at > NOW() - INTERVAL '7 days'
GROUP BY ct.id, ct.name, ct.use_count
ORDER BY recent_uses DESC
LIMIT 30;


-- ── 11. REALTIME BROADCAST GRANTS ────────────────────────────────────────
-- Enable Realtime on posts table for live feed updates
ALTER PUBLICATION supabase_realtime ADD TABLE creator_posts;
ALTER PUBLICATION supabase_realtime ADD TABLE creator_post_reactions;

-- ═══════════════════════════════════════════════════════════════════════════
-- END OF MIGRATION
-- ═══════════════════════════════════════════════════════════════════════════
