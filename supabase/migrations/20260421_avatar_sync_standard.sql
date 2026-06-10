-- ═══════════════════════════════════════════════════════════════════════════
-- NECXA PLATFORM – MIGRATION: Avatar Synchronization Standard
-- File: 20260421_avatar_sync_standard.sql
-- Goal: Ensure the profiles table and related views use the standardized avatar_url.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. ENSURE COLUMNS EXIST ────────────────────────────────────────────────
-- Ensure avatar_url is present (it should be, but this guarantees it).
-- We also ensure 'bio' is present as the Flutter model expects it.

ALTER TABLE profiles 
  ADD COLUMN IF NOT EXISTS avatar_url TEXT,
  ADD COLUMN IF NOT EXISTS bio TEXT;


-- ── 2. DATA MIGRATION (IF NECESSARY) ───────────────────────────────────────
-- If any accidental 'photo_url' column exists from previous iterations, 
-- migrate its data to the standardized 'avatar_url' and then remove it.

DO $$ 
BEGIN 
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='profiles' AND column_name='photo_url') THEN
        -- Migrate data
        UPDATE profiles SET avatar_url = photo_url WHERE avatar_url IS NULL;
        -- Optional: Drop the legacy column
        -- ALTER TABLE profiles DROP COLUMN photo_url;
    END IF;
END $$;


-- ── 3. REFRESH CHAT VIEW ───────────────────────────────────────────────────
-- Ensure the v_my_chats view correctly maps avatar_url to other_avatar.
-- This part is usually in the chat migration, but we ensure it here.

DROP VIEW IF EXISTS v_my_chats;
CREATE OR REPLACE VIEW v_my_chats AS
SELECT 
    cr.id,
    cr.last_message,
    cr.last_message_at,
    cr.created_at,
    cr.user_a AS participant1_id,
    cr.user_b AS participant2_id,
    p_other.id AS other_id,
    p_other.full_name AS other_name,
    p_other.avatar_url AS other_avatar,
    p_other.username AS other_username
FROM direct_chat_rooms cr
JOIN profiles p_other ON (
    (cr.user_a = auth.uid() AND cr.user_b = p_other.id) OR
    (cr.user_b = auth.uid() AND cr.user_a = p_other.id)
);


-- ── 4. PERMISSIONS ────────────────────────────────────────────────────────
-- Ensure avatars are publicly readable in the profiles bucket if not already.

-- NOTE: This assumes a bucket named 'profiles' exists.
-- The RLS for that bucket should allow public read access for avatars.

COMMENT ON COLUMN profiles.avatar_url IS 'Public URL for the user profile picture.';
COMMENT ON COLUMN profiles.bio IS 'User-provided biography or status message.';
