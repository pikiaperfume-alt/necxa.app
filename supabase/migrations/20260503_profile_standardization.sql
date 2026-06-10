-- ═══════════════════════════════════════════════════════════════════════════
-- NECXA PLATFORM – MIGRATION: Profile Standardization
-- File: 20260503_profile_standardization.sql
-- Goal: Unify profile data and add missing verification fields for Shield SDK.
-- ═══════════════════════════════════════════════════════════════════════════

-- 1. Add missing fields to profiles
ALTER TABLE profiles 
  ADD COLUMN IF NOT EXISTS shield_session_id TEXT,
  ADD COLUMN IF NOT EXISTS face_verified BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS ea_country TEXT DEFAULT 'Uganda',
  ADD COLUMN IF NOT EXISTS verified_at TIMESTAMP WITH TIME ZONE;

-- 2. Ensure RLS allows the service role to manage all profiles (for webhooks)
-- (This is usually true by default for service_role, but we ensure policies are clear)

-- 3. Log the standardization
INSERT INTO system_logs (category, message, metadata)
VALUES ('IDENTITY', 'Profiles standardized for Shield SDK & Unified Backend.', 
        '{"version": "2.1", "unified": true}');
