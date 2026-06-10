-- ==============================================================================
-- 🚀 Necxa Clever-Processor & Account Manager Alignment
-- Date: 2026-04-27
-- Description: Aligns DB schema with the latest Edge Function requirements.
-- ==============================================================================

-- 1. Profiles Table Updates (Account Lifecycle)
ALTER TABLE public.profiles 
ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'active',
ADD COLUMN IF NOT EXISTS scheduled_deletion_at TIMESTAMPTZ DEFAULT NULL;

-- 2. Community Posts Updates (Viral Feed Logic)
ALTER TABLE public.community_posts 
ADD COLUMN IF NOT EXISTS visibility TEXT DEFAULT 'public',
ADD COLUMN IF NOT EXISTS media_type TEXT DEFAULT 'video',
ADD COLUMN IF NOT EXISTS hls_url TEXT,
ADD COLUMN IF NOT EXISTS dash_url TEXT,
ADD COLUMN IF NOT EXISTS thumbnail_url TEXT;

-- Index for high-performance feed filtering
CREATE INDEX IF NOT EXISTS idx_posts_visibility_status ON public.community_posts (visibility, status);

-- 3. Media Usage Tracking (Viral Loop)
CREATE TABLE IF NOT EXISTS public.media_usage (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    asset_id TEXT NOT NULL, -- Logical ID from clever-processor
    post_id UUID REFERENCES public.community_posts(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    usage_type TEXT DEFAULT 'reuse', -- 'view', 'reuse', 'share'
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for trending calculations
CREATE INDEX IF NOT EXISTS idx_media_usage_asset_time ON public.media_usage (asset_id, created_at DESC);

-- 4. RLS for Media Usage
ALTER TABLE public.media_usage ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can view usage stats" 
    ON public.media_usage FOR SELECT USING (true);

CREATE POLICY "Authenticated users can record usage" 
    ON public.media_usage FOR INSERT 
    WITH CHECK (auth.uid() = user_id);
