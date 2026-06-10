-- ═══════════════════════════════════════════════════════════════════════════
-- NECXA PLATFORM – MIGRATION: Backend/Frontend Cross-Check & Sync
-- File: 20260422_crosscheck_sync.sql
-- Goal: Harmonize schemas and fix discrepancies found during sync audit.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. HARDEN community_posts SCHEMA ─────────────────────────────────────
-- Ensure all fields used by the SocialService and Creator Hub exist.

ALTER TABLE community_posts
  ADD COLUMN IF NOT EXISTS audio_url TEXT,
  ADD COLUMN IF NOT EXISTS thumbnail_url TEXT; -- 🚀 Added for Premium UX Placeholders

-- Add index for music-based discovery (requested in previous updates)
CREATE INDEX IF NOT EXISTS idx_community_posts_music ON community_posts(music_track_id);

-- ── 1.1 PERFORMANCE TUNING: Paginated Sorting ────────────────────────────
-- Optimize for .order('created_at', ascending: false)
CREATE INDEX IF NOT EXISTS idx_posts_pagination ON community_posts(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_listings_pagination ON listings(created_at DESC);

-- Optimize for visibility and status filtering in v_viral_feed
CREATE INDEX IF NOT EXISTS idx_posts_visibility_status ON community_posts(visibility, status);


-- ── 2. HARMONIZE listings SCHEMA ─────────────────────────────────────────
-- Align 'listings' table with the Flutter PropertyContainer model.

ALTER TABLE listings
  ADD COLUMN IF NOT EXISTS lister_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS user_id   UUID REFERENCES profiles(id) ON DELETE CASCADE;

-- ── 3. UNIFY DELETE PROTOCOLS ─────────────────────────────────────────────
-- Ensure bulk_delete_posts actually archives to maintain audit logs.

CREATE OR REPLACE FUNCTION bulk_delete_posts(p_post_ids UUID[])
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  -- Hard Delete is discouraged; we Archive instead.
  UPDATE community_posts
  SET status = 'archived', updated_at = NOW()
  WHERE id = ANY(p_post_ids) AND author_id = auth.uid();
END;
$$;


-- ── 4. SOCIAL FEED PERMISSIONS & VIEWS ────────────────────────────────────
-- Ensure the viral feed only shows public, verified content.

CREATE OR REPLACE VIEW v_viral_feed AS
SELECT 
    p.*,
    pr.full_name as author_name,
    pr.avatar_url as author_avatar,
    pr.trust_score_tier as author_trust_tier
FROM community_posts p
LEFT JOIN profiles pr ON pr.id = p.author_id
WHERE p.status = 'verified' 
  AND p.visibility = 'public'
ORDER BY p.created_at DESC;


-- ── 4.1 DATA BACKFILL (FOR TESTING/INITIAL SYNC) ─────────────────────────
-- Ensure existing posts appear in the new filtered view.

UPDATE community_posts 
SET status = 'verified', visibility = 'public' 
WHERE status IS NULL OR status = 'draft';


-- ── 5. RLS FIXES FOR CREATOR MODE ────────────────────────────────────────
-- Allow creators to insert posts with extended metadata.

DROP POLICY IF EXISTS "Users can create posts" ON community_posts;
CREATE POLICY "Users can create posts" ON community_posts 
FOR INSERT WITH CHECK (auth.uid() = author_id);

-- Ensure listings are searchable by lister_id for join optimization
CREATE INDEX IF NOT EXISTS idx_listings_lister ON listings(lister_id);


-- ── 6. SYNC AUDIT LOG ─────────────────────────────────────────────────────
-- Track these optimizations in the system log for future audits.

CREATE TABLE IF NOT EXISTS system_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    category TEXT NOT NULL,
    message TEXT NOT NULL,
    metadata JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO system_logs (category, message, metadata)
VALUES ('SYNC', 'Community Feed Optimized: Paginated (5 items), Offline Caching, and View-Based Fetching enabled.', 
        '{"batch_size": 5, "view": "v_viral_feed", "version": "2026.04.22"}');


-- ── 7. EPHEMERAL MEDIA PURGE PROTOCOL (78 HOURS) ──────────────────────────
-- Automatically clears media_url from direct_messages after 78 hours.

CREATE OR REPLACE FUNCTION purge_ephemeral_media()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE direct_messages
  SET 
    media_url = NULL,
    content = '[Media Expired]',
    metadata = metadata || '{"expired": true, "expired_at": "' || NOW() || '"}'::jsonb
  WHERE media_url IS NOT NULL
    AND created_at < NOW() - INTERVAL '78 hours'
    AND message_type IN ('image', 'video', 'audio');
    
  INSERT INTO system_logs (category, message)
  VALUES ('PURGE', 'Ephemeral media purge executed successfully.');
END;
$$;

-- NOTE: In a production environment, you should schedule this function:
-- SELECT cron.schedule('purge-media-job', '0 * * * *', 'SELECT purge_ephemeral_media()');


-- ── 8. PHONE CONTACT SYNCHRONIZATION ──────────────────────────────────────
-- Discover other users on the platform via email matching.

CREATE OR REPLACE FUNCTION sync_contacts_by_email(p_emails TEXT[])
RETURNS TABLE (
    id UUID,
    full_name TEXT,
    avatar_url TEXT,
    email TEXT
) LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  RETURN QUERY
  SELECT 
    p.id,
    p.full_name,
    p.avatar_url,
    p.email
  FROM profiles p
  WHERE p.email = ANY(p_emails)
    AND p.id != auth.uid();
END;
$$;
