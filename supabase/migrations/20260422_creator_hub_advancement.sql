-- ═══════════════════════════════════════════════════════════════════════════
-- NECXA PLATFORM – MIGRATION: Creator Hub Advancement & Data Saver
-- File: 20260422_creator_hub_advancement.sql
-- Goal: Support 5-step campaign flow and persistent user preferences.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. USER PREFERENCES: Data Saver ───────────────────────────────────────
-- Store the user's preference for data saving on the backend.

ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS data_saver_enabled BOOLEAN DEFAULT FALSE;

-- ── 2. ADVANCED CAMPAIGN METADATA ─────────────────────────────────────────
-- Support objectives and visibility levels for the 5-step flow.

ALTER TABLE community_posts
  ADD COLUMN IF NOT EXISTS objective TEXT DEFAULT 'awareness',
  ADD COLUMN IF NOT EXISTS visibility_level TEXT DEFAULT 'public', -- public, followers, private
  ADD COLUMN IF NOT EXISTS allow_comments BOOLEAN DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS ai_tagging_enabled BOOLEAN DEFAULT TRUE;

-- Create index for filtering by objective (useful for hub-specific feeds)
CREATE INDEX IF NOT EXISTS idx_posts_objective ON community_posts(objective);

-- ── 3. RESUME DRAFT PROTOCOL ──────────────────────────────────────────────
-- Allow users to resume their 5-step campaign from any device.

ALTER TABLE community_posts
  ADD COLUMN IF NOT EXISTS current_step INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS draft_metadata JSONB DEFAULT '{}';

CREATE OR REPLACE FUNCTION save_campaign_draft(
    p_objective TEXT,
    p_step INTEGER,
    p_metadata JSONB
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    v_draft_id UUID;
BEGIN
    -- Update existing draft if it exists, otherwise insert
    INSERT INTO community_posts (author_id, objective, current_step, draft_metadata, status)
    VALUES (auth.uid(), p_objective, p_step, p_metadata, 'draft')
    ON CONFLICT (author_id) WHERE status = 'draft'
    DO UPDATE SET 
        objective = EXCLUDED.objective,
        current_step = EXCLUDED.current_step,
        draft_metadata = EXCLUDED.draft_metadata,
        updated_at = NOW()
    RETURNING id INTO v_draft_id;

    RETURN v_draft_id;
END;
$$;

-- ── 4. REFINED VIRAL VIEW ─────────────────────────────────────────────────
-- Update the view to include the new metadata.

CREATE OR REPLACE VIEW v_viral_feed_v2 AS
SELECT 
    p.*,
    pr.full_name as author_name,
    pr.avatar_url as author_avatar,
    pr.trust_score_tier as author_trust_tier,
    pr.data_saver_enabled as author_data_saver
FROM community_posts p
LEFT JOIN profiles pr ON pr.id = p.author_id
WHERE p.status = 'verified' 
  AND p.visibility_level = 'public'
ORDER BY p.created_at DESC;

-- ── 5. SYSTEM LOG ─────────────────────────────────────────────────────────

INSERT INTO system_logs (category, message, metadata)
VALUES ('BACKEND', 'Creator Hub Advancement: 5-step campaign support and Data Saver preferences synchronized.', 
        '{"features": ["visibility_control", "objective_tracking", "data_saver_sync"], "version": "2026.04.22.v2"}');
