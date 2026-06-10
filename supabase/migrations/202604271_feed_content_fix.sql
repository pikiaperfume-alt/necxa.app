-- [ignoring loop detection]
-- ==============================================================================
-- 🚀 Necxa Social Content Fix & Seed (v2 - Video Support)
-- Date: 2026-04-27
-- Description: Ensures existing posts have correct visibility and seeds both Photos AND Videos.
-- ==============================================================================

-- 1. Ensure all existing posts are public and verified if they have media
UPDATE public.community_posts 
SET visibility = 'public', 
    status = 'verified'
WHERE media_url IS NOT NULL;

-- 2. Seed High-Quality Discovery Posts
DO $$
DECLARE
    v_author_id UUID;
BEGIN
    SELECT id INTO v_author_id FROM public.profiles LIMIT 1;
    
    IF v_author_id IS NOT NULL THEN
        -- Delete old seed data to avoid duplicates if re-run
        DELETE FROM public.community_posts WHERE title IN ('Welcome to the Necxa Social Hub!', 'Necxa Real Estate Spotlight', 'The Sound Hub is Live 🎵', 'Premium Property Walkthrough 🎥');

        INSERT INTO public.community_posts 
        (author_id, title, content, media_url, media_type, status, visibility, created_at)
        VALUES 
        -- VIDEO POST
        (v_author_id, 'Premium Property Walkthrough 🎥', 'Experience the future of property discovery with immersive video walkthroughs.', 'https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4', 'video', 'verified', 'public', NOW()),
        
        -- IMAGE POSTS
        (v_author_id, 'Welcome to the Necxa Social Hub!', 'Explore the latest in property, music, and community vibes.', 'https://images.unsplash.com/photo-1516245834210-c4c142787335', 'image', 'verified', 'public', NOW() - INTERVAL '1 hour'),
        (v_author_id, 'Necxa Real Estate Spotlight', 'Verified property listings now integrated into your social feed.', 'https://images.unsplash.com/photo-1560518883-ce09059eeffa', 'image', 'verified', 'public', NOW() - INTERVAL '2 hours'),
        (v_author_id, 'The Sound Hub is Live 🎵', 'Record, share, and remix original sounds natively.', 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745', 'image', 'verified', 'public', NOW() - INTERVAL '3 hours');
    END IF;
END $$;
