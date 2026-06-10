-- ═══════════════════════════════════════════════════════════════════════════
-- NECXA PLATFORM – MIGRATION: Post Privacy & Lifecycle Management
-- File: 20260419_post_privacy_schema.sql
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. POST VISIBILITY ENUM ───────────────────────────────────────────────
DO $$ BEGIN
  CREATE TYPE post_visibility AS ENUM ('public', 'private');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ── 2. EXTEND community_posts ──────────────────────────────────────────────
ALTER TABLE community_posts
  ADD COLUMN IF NOT EXISTS visibility post_visibility DEFAULT 'public';

-- ── 3. UPDATE FEED VIEWS ──────────────────────────────────────────────────
-- Ensure only public, verified posts show up in the global discovery feed
CREATE OR REPLACE VIEW v_viral_feed AS
SELECT * FROM community_posts
WHERE status = 'verified' 
  AND visibility = 'public'
ORDER BY created_at DESC;

-- ── 4. BATCH MANAGEMENT FUNCTIONS ─────────────────────────────────────────

-- Bulk Delete (Soft Delete)
CREATE OR REPLACE FUNCTION bulk_delete_posts(p_post_ids UUID[])
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE community_posts
  SET status = 'archived', updated_at = NOW()
  WHERE id = ANY(p_post_ids) AND author_id = auth.uid();
END;
$$;

-- Bulk Update Privacy
CREATE OR REPLACE FUNCTION bulk_update_post_privacy(p_post_ids UUID[], p_visibility post_visibility)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE community_posts
  SET visibility = p_visibility, updated_at = NOW()
  WHERE id = ANY(p_post_ids) AND author_id = auth.uid();
END;
$$;
