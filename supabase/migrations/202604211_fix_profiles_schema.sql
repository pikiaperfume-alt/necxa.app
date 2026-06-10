-- ═══════════════════════════════════════════════════════════════════════════
-- NECXA PLATFORM – MIGRATION: Profiles Schema Patch
-- File: 20260421_fix_profiles_schema.sql
-- Goal: Fix "Profile Not Found" by adding missing required model fields.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. ADD MISSING COLUMNS ────────────────────────────────────────────────

ALTER TABLE profiles 
  ADD COLUMN IF NOT EXISTS username    TEXT UNIQUE,
  ADD COLUMN IF NOT EXISTS ai_verified BOOLEAN DEFAULT FALSE;


-- ── 2. SEED USERNAMES FOR EXISTING USERS ──────────────────────────────────
-- Generate a unique username from the email if it currently lacks one.

UPDATE profiles 
SET username = split_part(email, '@', 1)
WHERE username IS NULL;

-- Ensure handles are lowercase and sanitized
UPDATE profiles 
SET username = LOWER(TRIM(username));


-- ── 3. REFRESH SEARCH VIEW ────────────────────────────────────────────────
-- Ensure public views pick up the new verified status.

COMMENT ON COLUMN profiles.username IS 'Public handle used for mentions and profile URLs.';
COMMENT ON COLUMN profiles.ai_verified IS 'Whether the users identity has been verified via Necxa Shield AI.';
