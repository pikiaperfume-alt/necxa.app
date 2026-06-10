-- ═══════════════════════════════════════════════════════════════════════════
-- NECXA PLATFORM – MIGRATION: Separate Chat Views
-- File: 20260423_separate_chat_views.sql
-- Goal: Create a dedicated view for Property/Business chats (Main Chat).
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE VIEW v_main_property_chats AS
SELECT
  r.id                   AS room_id,
  r.updated_at,
  r.latest_message       AS last_message,
  r.latest_message_at    AS last_message_at,
  r.status,
  r.property_id,
  r.escrow_id,
  r.room_type,
  FALSE                  AS is_secure, -- Property chats not yet encrypted
  'none'                 AS security_status,

  -- Unread count (fallback calculation)
  (SELECT COUNT(*)::INT FROM chat_messages m WHERE m.room_id = r.id AND m.sender_id != auth.uid() AND m.is_read = FALSE) AS my_unread,

  -- Other user's info (If current user is client, other is agent; vice versa)
  CASE WHEN r.client_id = auth.uid() THEN r.agent_id ELSE r.client_id END AS other_user_id,
  op.full_name           AS other_name,
  op.avatar_url          AS other_avatar,
  op.is_agent            AS other_is_agent,
  op.trust_score         AS other_trust_score

FROM chat_rooms r
JOIN profiles op ON op.id = CASE WHEN r.client_id = auth.uid() THEN r.agent_id ELSE r.client_id END
WHERE auth.uid() IN (r.client_id, r.agent_id)
  AND r.status = 'active'
ORDER BY r.latest_message_at DESC;

-- ── 2. FUNCTION: get or create a business chat room ──────────────────────
CREATE OR REPLACE FUNCTION get_or_create_business_room(
    p_property_id UUID,
    p_agent_id UUID,
    p_client_id UUID,
    p_room_type TEXT DEFAULT 'inquiry'
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_room_id UUID;
BEGIN
  SELECT id INTO v_room_id
  FROM chat_rooms
  WHERE property_id = p_property_id 
    AND agent_id = p_agent_id 
    AND client_id = p_client_id;

  IF NOT FOUND THEN
    INSERT INTO chat_rooms (property_id, agent_id, client_id, room_type)
    VALUES (p_property_id, p_agent_id, p_client_id, p_room_type)
    RETURNING id INTO v_room_id;
  END IF;

  RETURN v_room_id;
END;
$$;

-- Update system log
INSERT INTO system_logs (category, message, metadata)
VALUES ('CHAT', 'Main Property Chat view created for separation of Business and Social contexts.', 
        '{"view": "v_main_property_chats", "version": "2026.04.23"}');
