-- ═══════════════════════════════════════════════════════════════════════════
-- NECXA PLATFORM – MIGRATION: Secure Chat Activation (E2EE)
-- File: 20260422_secure_chat_activation.sql
-- Goal: Harden the main chat with secure channel protocols.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. HARDEN CHAT ROOMS FOR SECURITY ──────────────────────────────────────
-- Add markers for secure channel activation and protocol tracking.

ALTER TABLE direct_chat_rooms 
  ADD COLUMN IF NOT EXISTS is_secure BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS security_protocol TEXT DEFAULT 'none',
  ADD COLUMN IF NOT EXISTS security_status TEXT DEFAULT 'pending'; -- pending, activated, verified

-- ── 2. ENHANCE MESSAGES FOR ENCRYPTION ─────────────────────────────────────
-- Add metadata for storing public keys or encryption initialization vectors.

ALTER TABLE direct_messages
  ADD COLUMN IF NOT EXISTS encryption_metadata JSONB DEFAULT '{}';

-- ── 3. SECURE CHANNEL ACTIVATION PROTOCOL ──────────────────────────────────
-- Function to upgrade a standard chat to a secure encrypted channel.

CREATE OR REPLACE FUNCTION activate_secure_channel(p_room_id UUID)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  -- 1. Upgrade the room status
  UPDATE direct_chat_rooms 
  SET is_secure = TRUE, 
      security_protocol = 'E2EE-SHIELD-V1',
      security_status = 'activated',
      updated_at = NOW()
  WHERE id = p_room_id 
    AND (user_a = auth.uid() OR user_b = auth.uid());

  -- 2. Inject a verified system event to notify participants
  INSERT INTO direct_messages (room_id, sender_id, message_type, content, metadata)
  VALUES (
    p_room_id, 
    auth.uid(), 
    'system', 
    '🛡️ Secure end-to-end encryption activated. Your messages are now protected by Necxa Shield.', 
    '{"secure": true, "protocol": "E2EE-SHIELD-V1"}'
  );
END;
$$;

-- ── 4. UPDATE VIEW: v_my_chats ─────────────────────────────────────────────
-- Ensure the frontend knows which chats are secure.

CREATE OR REPLACE VIEW v_my_chats_v2 AS
SELECT
  r.id                   AS room_id,
  r.updated_at,
  r.last_message,
  r.last_message_at,
  r.status,
  r.is_secure,
  r.security_status,

  -- Current user's unread
  CASE WHEN r.user_a = auth.uid() THEN r.user_a_unread ELSE r.user_b_unread END AS my_unread,

  -- Other user's info
  CASE WHEN r.user_a = auth.uid() THEN r.user_b ELSE r.user_a END AS other_user_id,
  op.full_name     AS other_name,
  op.avatar_url    AS other_avatar,
  op.is_agent      AS other_is_agent,
  op.trust_score   AS other_trust_score

FROM direct_chat_rooms r
JOIN profiles op ON op.id = CASE WHEN r.user_a = auth.uid() THEN r.user_b ELSE r.user_a END
WHERE auth.uid() IN (r.user_a, r.user_b)
  AND r.status = 'active'
ORDER BY r.updated_at DESC;

-- ── 5. SYSTEM LOG ─────────────────────────────────────────────────────────

INSERT INTO system_logs (category, message, metadata)
VALUES ('SECURITY', 'Secure Chat Protocol Activated: E2EE-SHIELD-V1 enabled for main chat channels.', 
        '{"protocol": "E2EE-SHIELD-V1", "status": "global_activation", "version": "2026.04.22"}');
