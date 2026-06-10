-- [ignoring loop detection]
-- ==============================================================================
-- 🚀 Necxa Public Social Feed & Market Hardening
-- Date: 2026-05-04
-- Description: Ensures Community Feed and Shop are fully public by relaxing RLS
--              and standardizing the visibility/status checks.
-- ==============================================================================

-- 1. COMMUNITY POSTS - Relaxing RLS for Discovery
DROP POLICY IF EXISTS "Anyone can see verified posts" ON public.community_posts;
DROP POLICY IF EXISTS "Anyone can view verified community posts" ON public.community_posts;
DROP POLICY IF EXISTS "Strict artist distribution policy" ON public.community_posts;

CREATE POLICY "Anyone can view public and verified posts" 
ON public.community_posts 
FOR SELECT 
USING (
  (status IN ('verified', 'pending') AND (visibility = 'public' OR visibility IS NULL))
  OR auth.uid() = author_id
);

-- 2. LISTINGS - Relaxing RLS for Market
DROP POLICY IF EXISTS "Anyone can view active listings" ON public.listings;

CREATE POLICY "Anyone can view active listings" 
ON public.listings 
FOR SELECT 
USING (
  status = 'active' OR auth.uid() = user_id
);

-- 3. ENSURE DATA CONSISTENCY
-- Mark all existing posts with NULL visibility as 'public' to be safe
UPDATE public.community_posts SET visibility = 'public' WHERE visibility IS NULL;
UPDATE public.community_posts SET status = 'verified' WHERE status IS NULL;
UPDATE public.listings SET status = 'active' WHERE status IS NULL;

-- 4. SEARCH OPTIMIZATION
-- Ensure we have indexes for the common filters used by the Edge Functions
CREATE INDEX IF NOT EXISTS idx_com_posts_visibility_status ON public.community_posts(visibility, status);
CREATE INDEX IF NOT EXISTS idx_listings_status_active ON public.listings(status) WHERE status = 'active';
