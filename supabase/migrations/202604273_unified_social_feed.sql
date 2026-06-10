-- [ignoring loop detection]
-- ==============================================================================
-- 🚀 Necxa Unified Social Feed Engine
-- Date: 2026-04-27
-- Description: Intelligently blends followed content with discovery to avoid "No Posts" screens.
-- ==============================================================================

-- 1. High-Performance Feed Retrieval Function
CREATE OR REPLACE FUNCTION public.get_social_feed(p_viewer_id UUID, p_limit INT DEFAULT 20, p_offset INT DEFAULT 0)
RETURNS TABLE (
    post_id UUID,
    author_id UUID,
    author_name TEXT,
    author_avatar TEXT,
    post_title TEXT,
    post_content TEXT,
    post_media_url TEXT,
    likes_count INT,
    comments_count INT,
    is_liked_by_viewer BOOLEAN,
    is_followed_by_viewer BOOLEAN,
    created_at TIMESTAMPTZ,
    feed_rank FLOAT
) 
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    WITH followed_creators AS (
        SELECT creator_id FROM public.creator_followers WHERE follower_id = p_viewer_id
    ),
    feed_pool AS (
        SELECT 
            p.id as post_id,
            p.author_id,
            prof.full_name as author_name,
            prof.avatar_url as author_avatar,
            p.title as post_title,
            p.content as post_content,
            p.media_url as post_media_url,
            p.likes_count,
            p.comments_count,
            EXISTS (SELECT 1 FROM public.community_likes l WHERE l.post_id = p.id AND l.user_id = p_viewer_id) as is_liked_by_viewer,
            EXISTS (SELECT 1 FROM followed_creators fc WHERE fc.creator_id = p.author_id) as is_followed_by_viewer,
            p.created_at,
            -- Ranking Logic: Followed content gets a massive boost (+1000), verified content (+100), then recency
            (CASE WHEN EXISTS (SELECT 1 FROM followed_creators fc WHERE fc.creator_id = p.author_id) THEN 1000 ELSE 0 END) +
            (CASE WHEN p.status = 'verified' THEN 100 ELSE 0 END) +
            (EXTRACT(EPOCH FROM p.created_at) / 1000000) as rank_score
        FROM public.community_posts p
        JOIN public.profiles prof ON p.author_id = prof.id
        WHERE p.status = 'verified' OR p.author_id = p_viewer_id
    )
    SELECT * FROM feed_pool
    ORDER BY rank_score DESC, created_at DESC
    LIMIT p_limit
    OFFSET p_offset;
END;
$$;

-- 2. Seed Data to avoid "No Posts Yet" for new users
-- (Only inserts if the table is currently empty or very low)
DO $$
DECLARE
    v_admin_id UUID;
    v_post_count INT;
BEGIN
    SELECT count(*) INTO v_post_count FROM public.community_posts;
    
    -- If feed is empty, seed 3 high-quality onboarding posts
    IF v_post_count < 3 THEN
        -- Try to find an existing admin/creator or use the first available profile
        SELECT id INTO v_admin_id FROM public.profiles LIMIT 1;
        
        IF v_admin_id IS NOT NULL THEN
            INSERT INTO public.community_posts (author_id, title, content, media_url, status)
            VALUES 
            (v_admin_id, 'Welcome to Necxa Social! 🌟', 'Start sharing your creative journey with the community today.', 'https://images.unsplash.com/photo-1516245834210-c4c142787335', 'verified'),
            (v_admin_id, 'Necxa Financial Tips 💰', 'Did you know you can earn NCX coins by sharing high-quality property insights?', 'https://images.unsplash.com/photo-1554224155-6726b3ff858f', 'verified'),
            (v_admin_id, 'Property Spotlight 🏠', 'Explore premium listings with verified GPS locations directly in your feed.', 'https://images.unsplash.com/photo-1560518883-ce09059eeffa', 'verified');
        END IF;
    END IF;
END $$;
