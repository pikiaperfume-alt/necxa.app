-- ═══════════════════════════════════════════════════════════════════════════
-- NECXA PLATFORM – MIGRATION: Live Social Follow Sync
-- File: 20260422_social_follow_sync.sql
-- Goal: Replace dummy numbers with real-time denormalized counts on profiles.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. SCHEMA UPGRADE: PROFILES ───────────────────────────────────────────
-- Add columns for denormalized follower/following counts.

ALTER TABLE profiles 
  ADD COLUMN IF NOT EXISTS followers_count INT DEFAULT 0,
  ADD COLUMN IF NOT EXISTS following_count INT DEFAULT 0;

-- ── 2. INITIAL SEED: SYNC EXISTING DATA ────────────────────────────────────
-- Calculate and seed counts for all existing users to ensure consistency.

UPDATE profiles p SET 
  followers_count = (SELECT COUNT(*) FROM creator_followers WHERE creator_id = p.id),
  following_count = (SELECT COUNT(*) FROM creator_followers WHERE follower_id = p.id);

-- ── 3. AUTOMATED SYNC TRIGGERS ─────────────────────────────────────────────
-- Ensure that counts are always updated instantly when relationships change.

CREATE OR REPLACE FUNCTION denormalize_follow_counts()
RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = 'INSERT') THEN
        -- Increment the one being followed
        UPDATE profiles SET followers_count = followers_count + 1 WHERE id = NEW.creator_id;
        -- Increment the one who is following
        UPDATE profiles SET following_count = following_count + 1 WHERE id = NEW.follower_id;
    ELSIF (TG_OP = 'DELETE') THEN
        -- Decrement the one being followed (ensure non-negative)
        UPDATE profiles SET followers_count = GREATEST(followers_count - 1, 0) WHERE id = OLD.creator_id;
        -- Decrement the one who is following (ensure non-negative)
        UPDATE profiles SET following_count = GREATEST(following_count - 1, 0) WHERE id = OLD.follower_id;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── 4. ATTACH TRIGGER ─────────────────────────────────────────────────────

DROP TRIGGER IF EXISTS tr_denormalize_follow_counts ON creator_followers;
CREATE TRIGGER tr_denormalize_follow_counts
    AFTER INSERT OR DELETE ON creator_followers
    FOR EACH ROW EXECUTE FUNCTION denormalize_follow_counts();

-- ── 5. SYSTEM LOG ─────────────────────────────────────────────────────────

INSERT INTO system_logs (category, message, metadata)
VALUES ('SOCIAL', 'Social Follow Sync Activated: Profiles now track real-time denormalized counts.', 
        '{"version": "2026.04.22", "synced_tables": ["profiles", "creator_followers"]}');
