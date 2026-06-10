-- ═══════════════════════════════════════════════════════════════════════════
-- NECXA PLATFORM – SEED: 20260421 – Initial Platform Music Catalog
-- ═══════════════════════════════════════════════════════════════════════════

-- 1. CLEAR EXISTING SEED (OPTIONAL)
-- DELETE FROM public.music_tracks WHERE license_type = 'platform_owned';

-- 2. INSERT AFROLIFE & TRENDING BUNDLE
INSERT INTO public.music_tracks (
    title, artist_name, album_name, duration, genre, mood, 
    audio_url, album_art_url, license_type, source, is_royalty_free, 
    is_trending, is_featured
) VALUES 
(
    'Vibe Check (Necxa Original)', 'AfroBeat Kings', 'Summer Heat', 120, 'Afrobeat', 'Energetic',
    'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3', 
    'https://images.unsplash.com/photo-1514525253361-bee438d0edff?w=400',
    'platform_owned', 'ncx_owned', true, true, true
),
(
    'Amapiano Sunset', 'DJ Fusion', 'Piano Lounge', 180, 'Amapiano', 'Chill',
    'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3', 
    'https://images.unsplash.com/photo-1493225255756-d9584f8606e9?w=400',
    'platform_owned', 'ncx_owned', true, true, false
),
(
    'Kampala Nights', 'Enlightenment', 'City Lights', 95, 'Hip Hop', 'Vibrant',
    'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3', 
    'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=400',
    'platform_owned', 'ncx_owned', true, false, true
),
(
    'Digital Safari', 'Cyber Pulse', 'Neon Jungle', 110, 'Electronic', 'High Intensity',
    'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-4.mp3', 
    'https://images.unsplash.com/photo-1508700115892-45ecd05ae2ad?w=400',
    'platform_owned', 'ncx_owned', true, true, true
),
(
    'Pearl of Africa', 'Nile Spirit', 'Majestic', 210, 'Gospel', 'Inspirational',
    'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-5.mp3', 
    'https://images.unsplash.com/photo-1459749411177-5424296aa25b?w=400',
    'platform_owned', 'ncx_owned', true, false, false
);

-- 3. REFRESH TRENDING MATERIALIZED VIEW
-- This ensures the seeded music shows up in the "Trending" sections immediately.
REFRESH MATERIALIZED VIEW trending_music;

COMMENT ON TABLE music_tracks IS 'Master catalog for all music used in the Necxa social reel system.';
