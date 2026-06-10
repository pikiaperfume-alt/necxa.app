-- ================================================================
-- NECXA STORAGE BUCKET POLICIES (Corrected)
-- Run AFTER 001_listing_system.sql
-- ================================================================

-- -------------------------
-- listing-photos (PUBLIC)
-- -------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'listing-photos', 'listing-photos', true,
  20971520,
  array['image/jpeg','image/png','image/webp','image/heic','video/mp4']
)
on conflict (id) do update set public = true;

-- Public downloads (bucket is public, but keep policy explicit for SELECT)
create policy "public_read_listing_photos"
  on storage.objects
  for select
  using (bucket_id = 'listing-photos');

-- ✅ IMPORTANT FIX:
-- Enforce the same folder ownership rule for INSERT as you do for DELETE
create policy "agents_upload_listing_photos"
  on storage.objects
  for insert
  with check (
    bucket_id = 'listing-photos'
    and auth.role() = 'authenticated'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

-- Delete only within the agent’s own prefix
create policy "agents_delete_own_listing_photos"
  on storage.objects
  for delete
  using (
    bucket_id = 'listing-photos'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

-- -------------------------
-- identity-shards (PRIVATE)
-- -------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'identity-shards', 'identity-shards', false,
  10485760,
  array['image/jpeg','image/png','image/webp','image/heic']
)
on conflict (id) do update set public = false;

create policy "identity_owner_upload"
  on storage.objects
  for insert
  with check (
    bucket_id = 'identity-shards'
    and auth.role() = 'authenticated'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

create policy "identity_owner_read"
  on storage.objects
  for select
  using (
    bucket_id = 'identity-shards'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

create policy "service_read_identity_shards"
  on storage.objects
  for select
  using (
    bucket_id = 'identity-shards'
    and auth.role() = 'service_role'
  );

create policy "identity_owner_delete"
  on storage.objects
  for delete
  using (
    bucket_id = 'identity-shards'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

-- -------------------------
-- utility-shards (PRIVATE)
-- -------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'utility-shards', 'utility-shards', false,
  10485760,
  array['image/jpeg','image/png','image/webp','image/heic','application/pdf']
)
on conflict (id) do update set public = false;

create policy "utility_owner_upload"
  on storage.objects
  for insert
  with check (
    bucket_id = 'utility-shards'
    and auth.role() = 'authenticated'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

create policy "utility_owner_read"
  on storage.objects
  for select
  using (
    bucket_id = 'utility-shards'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

create policy "service_read_utility"
  on storage.objects
  for select
  using (
    bucket_id = 'utility-shards'
    and auth.role() = 'service_role'
  );

create policy "utility_owner_delete"
  on storage.objects
  for delete
  using (
    bucket_id = 'utility-shards'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

-- -------------------------
-- agent-documents (PRIVATE)
-- -------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'agent-documents', 'agent-documents', false,
  20971520,
  array['image/jpeg','image/png','image/webp','application/pdf']
)
on conflict (id) do update set public = false;

create policy "agent_docs_upload"
  on storage.objects
  for insert
  with check (
    bucket_id = 'agent-documents'
    and auth.role() = 'authenticated'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

create policy "agent_docs_read_own"
  on storage.objects for select using (
    bucket_id = 'agent-documents' and
    auth.uid()::text = (storage.foldername(name))[1]
  );

create policy "service_read_agent_docs"
  on storage.objects
  for select
  using (
    bucket_id = 'agent-documents' and auth.role() = 'service_role'
  );

create policy "agent_docs_delete"
  on storage.objects
  for delete
  using (
    bucket_id = 'agent-documents' and
    auth.uid()::text = (storage.foldername(name))[1]
  );
