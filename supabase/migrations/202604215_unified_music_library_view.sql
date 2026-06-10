-- ═══════════════════════════════════════════════════════════════════════════
-- NECXA PLATFORM – MIGRATION: Unified Music Library Discovery View (V2)
-- File: 20260421_unified_music_library_view.sql
-- Goal: Unify official tracks (music bucket) and user original sounds.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. UNIFIED MUSIC LIBRARY VIEW ─────────────────────────────────────────
-- This view consolidates official studio tracks and user-generated recordings.

CREATE OR REPLACE VIEW v_unified_music_library AS
-- 1.1 Official Platform & Artist Music (Stored in 'music' bucket)
SELECT
  id::TEXT          AS sound_id,
  title             AS title,
  artist_name       AS artist,
  album_art_url     AS cover_url,
  audio_url         AS audio_url, -- Full URL or path in 'music' bucket
  duration          AS duration,
  genre             AS genre,
  mood              AS mood,
  license_type      AS license_type,
  'official'        AS sound_type,
  is_trending       AS is_trending,
  created_at        AS created_at
FROM music_tracks

UNION ALL

-- 1.2 User-Generated Original Sounds (Extracted from community_posts)
SELECT
  p.id::TEXT        AS sound_id,
  COALESCE(p.title, 'Original Sound') AS title,
  COALESCE(pr.full_name, 'Necxa Creator') AS artist,
  COALESCE(p.thumbnail_url, p.media_url)  AS cover_url,
  p.audio_url       AS audio_url,
  15                AS duration, -- Estimated length
  'Original'        AS genre,
  'Social'          AS mood,
  'user_sound'      AS license_type,
  'user_sound'      AS sound_type,
  false             AS is_trending,
  p.created_at      AS created_at
FROM community_posts p
LEFT JOIN profiles pr ON pr.id = p.author_id
WHERE p.audio_url IS NOT NULL 
  AND p.status = 'verified'
  AND p.visibility = 'public';


-- ── 2. TRENDING MUSIC VIEW (Performance Layer) ────────────────────────────
-- High-performance view for the "Trending" section of the discovery hub.

CREATE OR REPLACE VIEW v_trending_sounds AS
SELECT * FROM v_unified_music_library
WHERE is_trending = true OR sound_type = 'official'
ORDER BY is_trending DESC, created_at DESC
LIMIT 100;


-- ── 3. SEARCHABLE SOUND INDEX (RPC Function) ─────────────────────────────
-- Optimized for millisecond-fast searches across both sound catalogs.

CREATE OR REPLACE FUNCTION search_music_library(
  p_query TEXT DEFAULT '',
  p_license_type TEXT DEFAULT NULL,
  p_genre TEXT DEFAULT NULL,
  p_limit INT DEFAULT 50
)
RETURNS SETOF v_unified_music_library LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT * FROM v_unified_music_library
  WHERE 
    (p_query = '' OR title ILIKE '%' || p_query || '%' OR artist ILIKE '%' || p_query || '%') AND
    (p_license_type IS NULL OR license_type = p_license_type) AND
    (p_genre IS NULL OR genre ILIKE '%' || p_genre || '%')
  ORDER BY is_trending DESC, created_at DESC
  LIMIT p_limit;
$$;

-- ── 4. DOCUMENTATION ──────────────────────────────────────────────────────
COMMENT ON VIEW v_unified_music_library IS 'Unified discovery layer: Official tracks (music bucket) + User recordings.';
COMMENT ON FUNCTION search_music_library IS 'High-speed discovery search for the mobile music picker.';
