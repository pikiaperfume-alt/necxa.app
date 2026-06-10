-- ================================================================
-- FIX: community_posts media_type column (PGRST204 Schema Cache Fix)
-- File: 20260416_fix_community_media_v2.sql
-- 
-- ROOT CAUSE: Previous migration used a custom ENUM (community_media_type)
-- which PostgREST does not always reflect in its schema cache, causing
-- "Could not find column 'media_type'" errors (PGRST204).
--
-- FIX: Drop ENUM-typed column (if it exists) and replace with TEXT + CHECK.
-- TEXT columns are always visible in PostgREST's schema cache.
-- ================================================================

-- Step 1: Drop the old ENUM-typed column if it exists
ALTER TABLE public.community_posts DROP COLUMN IF EXISTS media_type;
ALTER TABLE public.listings      DROP COLUMN IF EXISTS media_type;

-- Step 2: Drop the ENUM type if it exists (clean slate)
DROP TYPE IF EXISTS community_media_type;

-- Step 3: Re-add as TEXT with CHECK constraint (PostgREST-safe)
ALTER TABLE public.community_posts
  ADD COLUMN IF NOT EXISTS media_type TEXT NOT NULL DEFAULT 'image'
    CHECK (media_type IN ('image', 'video', 'audio'));

ALTER TABLE public.listings
  ADD COLUMN IF NOT EXISTS media_type TEXT NOT NULL DEFAULT 'image'
    CHECK (media_type IN ('image', 'video', 'audio'));

-- Step 4: Index for feed filtering by type
CREATE INDEX IF NOT EXISTS idx_community_posts_media_type
  ON public.community_posts(media_type);

-- Step 5: Backfill any existing rows to 'image' (default)
UPDATE public.community_posts SET media_type = 'image' WHERE media_type IS NULL;
UPDATE public.listings          SET media_type = 'image' WHERE media_type IS NULL;

-- Step 6: Refresh PostgREST schema cache
-- This tells PostgREST to reload its schema immediately without a restart.
NOTIFY pgrst, 'reload schema';
