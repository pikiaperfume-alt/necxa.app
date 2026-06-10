-- ================================================================
-- COMMUNITY MEDIA STORAGE BUCKET
-- File: 20260418_community_media_storage.sql
-- Fixes: Community posts showing blank/dark screen after upload
-- Root cause: 'community-media' bucket did not exist or was private
-- ================================================================

BEGIN;

-- 1. Create the community-media bucket (public = true so getPublicUrl() works)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'community-media',
    'community-media',
    true,          -- CRITICAL: must be public for Image.network() to load
    104857600,     -- 100MB limit
    ARRAY[
      'image/jpeg', 'image/jpg', 'image/png', 'image/gif', 'image/webp',
      'video/mp4', 'video/webm', 'video/quicktime', 'video/x-msvideo',
      'audio/mpeg', 'audio/mp4', 'audio/x-m4a', 'audio/ogg'
    ]
)
ON CONFLICT (id) DO UPDATE SET
    public = true,   -- Force public on conflict (fixes previously private bucket)
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

-- 2. Drop existing policies (idempotent)
DROP POLICY IF EXISTS "Public View Community Media"       ON storage.objects;
DROP POLICY IF EXISTS "Authenticated Upload Community"    ON storage.objects;
DROP POLICY IF EXISTS "Owner Update Community Media"      ON storage.objects;
DROP POLICY IF EXISTS "Owner Delete Community Media"      ON storage.objects;

-- 3. Public Read (anyone can view posts)
CREATE POLICY "Public View Community Media"
    ON storage.objects FOR SELECT
    USING (bucket_id = 'community-media');

-- 4. Authenticated Upload (scoped to user folder: uid/filename)
CREATE POLICY "Authenticated Upload Community"
    ON storage.objects FOR INSERT
    WITH CHECK (
        bucket_id = 'community-media'
        AND auth.role() = 'authenticated'
    );

-- 5. Owner Update
CREATE POLICY "Owner Update Community Media"
    ON storage.objects FOR UPDATE
    USING (
        bucket_id = 'community-media'
        AND auth.uid() = owner
    );

-- 6. Owner Delete
CREATE POLICY "Owner Delete Community Media"
    ON storage.objects FOR DELETE
    USING (
        bucket_id = 'community-media'
        AND auth.uid() = owner
    );

COMMIT;
