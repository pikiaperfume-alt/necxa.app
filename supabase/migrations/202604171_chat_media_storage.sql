-- ================================================================
-- CHAT MEDIA STORAGE BUCKET
-- File: 20260417_chat_media_storage.sql
-- ================================================================

BEGIN;

-- 1. Create the bucket
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'chat-media', 
    'chat-media', 
    true, 
    52428800, -- 50MB
    ARRAY['image/jpeg', 'image/png', 'image/gif', 'image/webp', 'video/mp4', 'video/webm', 'video/quicktime']
)
ON CONFLICT (id) DO UPDATE SET 
    public = EXCLUDED.public,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

-- 2. Drop existing policies if they exist (for idempotency)
DROP POLICY IF EXISTS "Public View Chat Media" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated Users Insert Chat Media" ON storage.objects;
DROP POLICY IF EXISTS "Users Update Own Chat Media" ON storage.objects;
DROP POLICY IF EXISTS "Users Delete Own Chat Media" ON storage.objects;

-- 3. Read Access (Public)
CREATE POLICY "Public View Chat Media" 
    ON storage.objects FOR SELECT 
    USING (bucket_id = 'chat-media');

-- 4. Write Access (Authenticated Users Only)
CREATE POLICY "Authenticated Users Insert Chat Media" 
    ON storage.objects FOR INSERT 
    WITH CHECK (
        bucket_id = 'chat-media' 
        AND auth.role() = 'authenticated'
    );

-- 5. Update Access (Owner only)
CREATE POLICY "Users Update Own Chat Media" 
    ON storage.objects FOR UPDATE 
    USING (
        bucket_id = 'chat-media' 
        AND auth.uid() = owner
    );

-- 6. Delete Access (Owner only)
CREATE POLICY "Users Delete Own Chat Media" 
    ON storage.objects FOR DELETE 
    USING (
        bucket_id = 'chat-media' 
        AND auth.uid() = owner
    );

COMMIT;
