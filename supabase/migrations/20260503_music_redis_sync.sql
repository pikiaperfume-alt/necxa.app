-- ═══════════════════════════════════════════════════════════════════════════
-- NECXA PLATFORM – MIGRATION: Music Redis Sync
-- File: 20260503_music_redis_sync.sql
-- Goal: Automatically sync music changes to Redis via clever-processor.
-- ═══════════════════════════════════════════════════════════════════════════

-- 1. TRIGGER FUNCTION: Notify clever-processor on track changes
CREATE OR REPLACE FUNCTION tr_sync_music_to_redis()
RETURNS TRIGGER AS $$
BEGIN
  -- We use pg_net or http extension if available, or just rely on a daily/manual sync for now
  -- but a 'Realtime' approach is better.
  -- For this implementation, we will use a dedicated system log that the edge function can poll,
  -- OR we can invoke the edge function directly using net.http_post.
  
  -- For robustness in this environment, we'll use a system_logs entry that acts as a signal.
  INSERT INTO system_logs (category, message, metadata)
  VALUES ('MUSIC_SYNC', 'Track updated: ' || NEW.id, 
          jsonb_build_object('track_id', NEW.id, 'action', 'sync-track'));
          
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 2. APPLY TRIGGER
CREATE TRIGGER sync_music_to_redis
AFTER INSERT OR UPDATE ON music_tracks
FOR EACH ROW EXECUTE FUNCTION tr_sync_music_to_redis();

-- 3. INITIAL SYNC SIGNAL
INSERT INTO system_logs (category, message, metadata)
VALUES ('MUSIC_SYNC', 'Full music library sync requested.', 
        '{"action": "sync-music-library"}');
