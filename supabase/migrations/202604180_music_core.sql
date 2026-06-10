-- ================================================================
-- NECXA MUSIC LICENSING SYSTEM
-- File: 20260418_music_licensing.sql
-- ================================================================

-- 1. MUSIC TRACKS (Unified with licensing info)
CREATE TABLE IF NOT EXISTS public.music_tracks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    -- Track metadata
    title TEXT NOT NULL,
    artist_name TEXT NOT NULL,
    album_name TEXT,
    duration INTEGER NOT NULL,  -- seconds
    genre TEXT,
    bpm INTEGER,                -- beats per minute
    mood TEXT,                  -- Added: 'Energetic', 'Chill', 'Vibrant'
    
    -- Audio files
    audio_url TEXT NOT NULL,
    preview_url TEXT,           -- 30-second preview
    waveform_data JSONB,        -- Added: Normalized waveform points for visualization
    album_art_url TEXT,
    
    -- Licensing
    license_type TEXT NOT NULL CHECK (license_type IN ('platform_owned', 'licensed', 'artist_upload', 'user_generated')),
    source TEXT,                -- 'ncx_owned', 'music_distributor', 'artist_name', 'community'
    royalty_rate NUMERIC(5,4) DEFAULT 0,  -- For artist revenue share
    is_royalty_free BOOLEAN DEFAULT false,
    requires_attribution BOOLEAN DEFAULT true,
    
    -- Usage tracking (TikTok-style)
    usage_count INTEGER DEFAULT 0,
    video_count INTEGER DEFAULT 0,
    like_count INTEGER DEFAULT 0,
    
    -- Status
    is_active BOOLEAN DEFAULT true,
    is_trending BOOLEAN DEFAULT false,
    is_featured BOOLEAN DEFAULT false,
    
    -- Artist relationship (if artist upload)
    artist_id UUID REFERENCES public.profiles(id),
    
    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    last_used_at TIMESTAMPTZ,
    
    -- Metadata
    metadata JSONB DEFAULT '{}'::jsonb
);

-- 2. MUSIC CATEGORIES/GENRES
CREATE TABLE IF NOT EXISTS public.music_genres (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT UNIQUE NOT NULL,
    icon TEXT,
    color TEXT,
    display_order INTEGER DEFAULT 0,
    is_active BOOLEAN DEFAULT true
);

-- 3. PLAYLISTS (Curated collections)
CREATE TABLE IF NOT EXISTS public.music_playlists (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    description TEXT,
    cover_url TEXT,
    created_by UUID REFERENCES public.profiles(id),
    is_official BOOLEAN DEFAULT false,
    track_count INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. PLAYLIST TRACKS
CREATE TABLE IF NOT EXISTS public.playlist_tracks (
    playlist_id UUID REFERENCES public.music_playlists(id) ON DELETE CASCADE,
    track_id UUID REFERENCES public.music_tracks(id) ON DELETE CASCADE,
    position INTEGER DEFAULT 0,
    added_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (playlist_id, track_id)
);

-- 5. USER SAVED MUSIC (Favorites)
CREATE TABLE IF NOT EXISTS public.user_saved_music (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    track_id UUID REFERENCES public.music_tracks(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, track_id)
);

-- 6. VIDEO MUSIC USAGE (When user adds music to video)
CREATE TABLE IF NOT EXISTS public.video_music_usage (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    video_post_id UUID REFERENCES public.community_posts(id) ON DELETE CASCADE,
    track_id UUID REFERENCES public.music_tracks(id),
    user_id UUID REFERENCES public.profiles(id),
    start_time NUMERIC(5,2) DEFAULT 0,  -- Start position in seconds
    duration NUMERIC(5,2),             -- Duration used
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 7. MUSIC TRENDING VIEW (Materialized)
DROP MATERIALIZED VIEW IF EXISTS trending_music;
CREATE MATERIALIZED VIEW trending_music AS
SELECT 
    mt.id,
    mt.title,
    mt.artist_name,
    mt.album_art_url,
    mt.duration,
    mt.license_type,
    mt.genre,
    COUNT(vmu.id) as total_uses,
    COUNT(DISTINCT vmu.user_id) as unique_users,
    (COUNT(vmu.id) * 3 + COUNT(DISTINCT usm.user_id)) as trending_score,
    ROW_NUMBER() OVER (ORDER BY COUNT(vmu.id) DESC) as rank
FROM music_tracks mt
LEFT JOIN video_music_usage vmu ON mt.id = vmu.track_id AND vmu.created_at > NOW() - INTERVAL '7 days'
LEFT JOIN user_saved_music usm ON mt.id = usm.track_id AND usm.created_at > NOW() - INTERVAL '7 days'
WHERE mt.is_active = true
GROUP BY mt.id
HAVING COUNT(vmu.id) > 0
ORDER BY trending_score DESC;

-- 8. SEARCH FUNCTION
CREATE OR REPLACE FUNCTION search_music(
    p_query TEXT,
    p_license_type TEXT DEFAULT NULL,
    p_genre TEXT DEFAULT NULL,
    p_limit INTEGER DEFAULT 50
)
RETURNS TABLE(
    id UUID,
    title TEXT,
    artist_name TEXT,
    album_art_url TEXT,
    duration INTEGER,
    license_type TEXT,
    usage_count INTEGER,
    relevance NUMERIC
)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        mt.id,
        mt.title,
        mt.artist_name,
        mt.album_art_url,
        mt.duration,
        mt.license_type,
        mt.usage_count,
        CASE 
            WHEN mt.title ILIKE '%' || p_query || '%' THEN 10.0
            WHEN mt.artist_name ILIKE '%' || p_query || '%' THEN 8.0
            ELSE 5.0
        END as relevance
    FROM music_tracks mt
    WHERE mt.is_active = true
        AND (p_license_type IS NULL OR mt.license_type = p_license_type)
        AND (p_genre IS NULL OR mt.genre = p_genre)
        AND (p_query IS NULL OR p_query = '' OR 
             mt.title ILIKE '%' || p_query || '%' OR 
             mt.artist_name ILIKE '%' || p_query || '%')
    ORDER BY relevance DESC, mt.usage_count DESC
    LIMIT p_limit;
END;
$$;

-- 9. SEED DATA
INSERT INTO music_genres (name, icon, color, display_order) VALUES
    ('Amapiano', '🎹', '#E67E22', 1),
    ('Afrobeat', '🌍', '#27AE60', 2),
    ('Hip Hop', '🔥', '#4ECDC4', 3),
    ('Gospel', '⛪', '#3498DB', 4),
    ('Pop', '🎤', '#FF6B6B', 5)
ON CONFLICT (name) DO NOTHING;
