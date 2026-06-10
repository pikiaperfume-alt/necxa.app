-- ═══════════════════════════════════════════════════════════════════════════
-- NECXA PLATFORM – MIGRATION: Social Follow Engine Hardening
-- File: 20260421_social_follow_logic.sql
-- Goal: Ensure every profile can be followed and sync counts via triggers.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. CREATOR SAFETY LAYER ──────────────────────────────────────────────
-- Every profile must have a basic 'creator' record to support follower counts.

INSERT INTO creators (id, display_name)
SELECT p.id, COALESCE(p.full_name, p.username)
FROM profiles p
LEFT JOIN creators c ON c.id = p.id
WHERE c.id IS NULL
ON CONFLICT (id) DO NOTHING;


-- ── 2. FOLLOWERS TABLE ALIGNMENT ─────────────────────────────────────────
-- Ensure the followers table uses the correct verified naming and constraints.

DO $$ BEGIN
  CREATE TABLE IF NOT EXISTS creator_followers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    creator_id UUID REFERENCES creators(id) ON DELETE CASCADE,
    follower_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    notification_level TEXT DEFAULT 'all' CHECK (notification_level IN ('all', 'live_only', 'none')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(creator_id, follower_id)
  );
EXCEPTION WHEN duplicate_table THEN NULL; END $$;


-- ── 3. AUTOMATED FOLLOWER COUNT TRIGGERS ─────────────────────────────────
-- High-performance triggers to denormalize counts on the creators table.

CREATE OR REPLACE FUNCTION sync_follower_count()
RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = 'INSERT') THEN
        UPDATE creators SET total_followers = total_followers + 1 WHERE id = NEW.creator_id;
    ELSIF (TG_OP = 'DELETE') THEN
        UPDATE creators SET total_followers = GREATEST(total_followers - 1, 0) WHERE id = OLD.creator_id;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS tr_sync_follower_count ON creator_followers;
CREATE TRIGGER tr_sync_follower_count
    AFTER INSERT OR DELETE ON creator_followers
    FOR EACH ROW EXECUTE FUNCTION sync_follower_count();
