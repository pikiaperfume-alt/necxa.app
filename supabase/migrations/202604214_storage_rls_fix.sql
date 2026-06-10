-- ═══════════════════════════════════════════════════════════════════════════
-- NECXA PLATFORM – MIGRATION: Storage & RLS Hardening
-- File: 20260421_storage_rls_fix.sql
-- Goal: Fix "Broken Avatar" issue by ensuring public bucket access and RLS.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. ENSURE PROFILES BUCKET IS PUBLIC ────────────────────────────────────
-- This allows anyone to view profile pictures via the public URL.

INSERT INTO storage.buckets (id, name, public)
VALUES ('profiles', 'profiles', true)
ON CONFLICT (id) DO UPDATE SET public = true;


-- ── 2. STORAGE RLS POLICIES ────────────────────────────────────────────────
-- Ensure users can upload to their own folder but anyone can read.

-- Allow public read access to the profiles bucket
CREATE POLICY "Public Read Access"
ON storage.objects FOR SELECT
USING (bucket_id = 'profiles');

-- Allow authenticated users to upload their own avatar
CREATE POLICY "Users can upload their own avatar"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'profiles' AND 
  (storage.foldername(name))[1] = auth.uid()::text
);

-- Allow users to update/delete their own avatar
CREATE POLICY "Users can update their own avatar"
ON storage.objects FOR UPDATE
TO authenticated
USING (
  bucket_id = 'profiles' AND 
  (storage.foldername(name))[1] = auth.uid()::text
);


-- ── 3. PROFILES TABLE RLS ──────────────────────────────────────────────────
-- Ensure users can see each other's basic profile data (required for avatars).

ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public profiles are viewable by everyone" ON profiles;
CREATE POLICY "Public profiles are viewable by everyone"
ON profiles FOR SELECT
USING (true);

DROP POLICY IF EXISTS "Users can update own profile" ON profiles;
CREATE POLICY "Users can update own profile"
ON profiles FOR UPDATE
USING (auth.uid() = id);
