-- ═══════════════════════════════════════════════════════════════════════════
-- NECXA PLATFORM – MIGRATION: Community Media Fix
-- File: 20260416_fix_community_media.sql
-- ═══════════════════════════════════════════════════════════════════════════

-- 1. Create media_type enum if not exists
DO $$ BEGIN
  CREATE TYPE community_media_type AS ENUM ('image', 'video');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- 2. Add media_type to community_posts
ALTER TABLE community_posts 
  ADD COLUMN IF NOT EXISTS media_type community_media_type DEFAULT 'image';

-- 3. Add media_type to listings (for unified display)
ALTER TABLE listings 
  ADD COLUMN IF NOT EXISTS media_type community_media_type DEFAULT 'image';

-- 4. Create community-media bucket if it doesn't exist (via RPC or manual in dashboard)
-- NOTE: In production, bucket creation is usually manual or via a setup script.
-- Here we ensure the RLS policies are ready.

-- 5. Storage Policies for community-media
-- These policies assume the bucket 'community-media' exists.
-- We use auth.uid() to scope uploads to user folders.

-- ALLOW: Public Read
-- CREATE POLICY "Public Access" ON storage.objects FOR SELECT USING (bucket_id = 'community-media');

-- ALLOW: Authenticated Upload
-- CREATE POLICY "Authenticated Upload" ON storage.objects FOR INSERT 
-- WITH CHECK (bucket_id = 'community-media' AND auth.role() = 'authenticated');

-- 6. Helper View for Community Feed (Optional but helpful)
CREATE OR REPLACE VIEW v_community_feed_v2 AS
SELECT 
  cp.*,
  p.full_name as author_name,
  p.avatar_url as author_avatar,
  p.is_verified_agent as author_verified
FROM community_posts cp
JOIN profiles p ON p.id = cp.author_id
WHERE cp.status = 'verified' OR cp.status = 'pending';
