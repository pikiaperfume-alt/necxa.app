-- ═══════════════════════════════════════════════════════════════════════════
-- NECXA PLATFORM – MIGRATION: Viral Discovery Hardening
-- File: 20260419_viral_stats.sql
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. VIRAL VELOCITY ENGINE ──────────────────────────────────────────────
-- tiktok-style sliding window for trending assets.
-- This function recalculates 'daily_usage_velocity' based on actual usage logs.

CREATE OR REPLACE FUNCTION refresh_viral_trends() 
RETURNS void AS $$
BEGIN
  -- 1. Update velocity for all active assets
  UPDATE media_assets ma 
  SET daily_usage_velocity = (
    SELECT count(*) 
    FROM media_usage mu 
    WHERE mu.asset_id = ma.id 
    AND mu.created_at > NOW() - INTERVAL '24 hours'
  );

  -- 2. Refresh the trending discovery view
  REFRESH MATERIALIZED VIEW CONCURRENTLY trending_media;
  
  -- 3. Cleanup old usage logs (Optional: Keep last 30 days for analytics)
  DELETE FROM media_usage WHERE created_at < NOW() - INTERVAL '30 days';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── 2. RANKING HELPERS ───────────────────────────────────────────────────
-- Calculates a weighted viral score for a post or asset.
-- Score = (UsageVelocity * 10) + (PostRecencyWeight)

CREATE OR REPLACE FUNCTION calculate_viral_score(
  p_velocity INT,
  p_created_at TIMESTAMPTZ
) 
RETURNS FLOAT AS $$
DECLARE
  v_age_hours FLOAT;
  v_recency_score FLOAT;
BEGIN
  v_age_hours := EXTRACT(EPOCH FROM (NOW() - p_created_at)) / 3600;
  -- Recency decay: e^(-age/48) -> halved every 48 hours
  v_recency_score := EXP(-v_age_hours / 48);
  
  RETURN (p_velocity * 10.0) + (v_recency_score * 100.0);
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- ── 3. AUTOMATION ────────────────────────────────────────────────────────
-- Note: In a production Supabase environment, you would schedule 'refresh_viral_trends()' 
-- using pg_cron. Example:
-- SELECT cron.schedule('*/15 * * * *', 'SELECT refresh_viral_trends()');
