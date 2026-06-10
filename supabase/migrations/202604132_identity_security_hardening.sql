-- ── IDENTITY SECURITY HARDENING ──────────────────────────────────────────

-- 1. Provision Storage Bucket securely
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types) 
VALUES ('identity-shards', 'identity-shards', false, 10485760, ARRAY['image/jpeg', 'image/png']) -- 10MB limit
ON CONFLICT (id) DO NOTHING;

-- 2. Storage Policies for identity-shards
-- Clear existing to avoid conflicts
DROP POLICY IF EXISTS "Service Role Full Access" ON storage.objects;
DROP POLICY IF EXISTS "Users can view own identity assets" ON storage.objects;

-- Only service_role (Edge Functions) can upload
CREATE POLICY "Service Role Full Access" ON storage.objects
FOR ALL TO service_role
USING (bucket_id = 'identity-shards');

-- Owners can view their own identity assets (if needed for profile page)
CREATE POLICY "Users can view own identity assets" ON storage.objects
FOR SELECT TO authenticated
USING (bucket_id = 'identity-shards' AND (storage.foldername(name))[1] = auth.uid()::text);

-- 3. Table RLS for identity_shards
-- Ensure RLS is enabled (already done in initial schema but good to be explicit)
ALTER TABLE identity_shards ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own identity shard" ON identity_shards;
DROP POLICY IF EXISTS "Service Role can manage identity shards" ON identity_shards;

-- Allow users to see their own verification status
CREATE POLICY "Users can view own identity shard" ON identity_shards
FOR SELECT TO authenticated
USING (auth.uid() = user_id);

-- Restrict mutations to service_role
CREATE POLICY "Service Role can manage identity shards" ON identity_shards
FOR ALL TO service_role
USING (true)
WITH CHECK (true);
