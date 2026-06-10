-- ================================================================
-- PRODUCT MINIATURES (LISTING-PHOTOS) STORAGE BUCKET
-- File: 20260517_listing_photos_bucket.sql
-- Fixes: Product miniatures failing to upload due to missing bucket in backend
-- ================================================================

BEGIN;

-- 1. Create the listing-photos bucket (public = true so getPublicUrl() works)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'listing-photos',
    'listing-photos',
    true,          -- Public so product photo links render in feed and shop
    20971520,      -- 20MB limit (optimized miniatures are compressed client-side)
    ARRAY[
      'image/jpeg', 'image/jpg', 'image/png', 'image/webp'
    ]
)
ON CONFLICT (id) DO UPDATE SET
    public = true,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

-- 2. Drop existing policies (idempotent)
DROP POLICY IF EXISTS "Public View Listing Photos"       ON storage.objects;
DROP POLICY IF EXISTS "Authenticated Upload Listing Photos"    ON storage.objects;
DROP POLICY IF EXISTS "Owner Update Listing Photos"      ON storage.objects;
DROP POLICY IF EXISTS "Owner Delete Listing Photos"      ON storage.objects;

-- 3. Public Read (anyone can view product images)
CREATE POLICY "Public View Listing Photos"
    ON storage.objects FOR SELECT
    USING (bucket_id = 'listing-photos');

-- 4. Authenticated Upload
CREATE POLICY "Authenticated Upload Listing Photos"
    ON storage.objects FOR INSERT
    WITH CHECK (
        bucket_id = 'listing-photos'
        AND auth.role() = 'authenticated'
    );

-- 5. Owner Update
CREATE POLICY "Owner Update Listing Photos"
    ON storage.objects FOR UPDATE
    USING (
        bucket_id = 'listing-photos'
        AND auth.uid() = owner
    );

-- 6. Owner Delete
CREATE POLICY "Owner Delete Listing Photos"
    ON storage.objects FOR DELETE
    USING (
        bucket_id = 'listing-photos'
        AND auth.uid() = owner
    );

COMMIT;
