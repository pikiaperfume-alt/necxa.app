-- ═══════════════════════════════════════════════════════════════════════════
-- NECXA PLATFORM – MIGRATION: Fix Business DM RPC
-- File: 20260426_fix_business_dm_rpc.sql
-- Goal: Allow get_or_create_business_room to handle NULL property IDs (Direct Business DMs).
-- ═══════════════════════════════════════════════════════════════════════════

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
  -- 🚀 FIX: Use IS NOT DISTINCT FROM to handle NULL property_id correctly
  SELECT id INTO v_room_id
  FROM chat_rooms
  WHERE property_id IS NOT DISTINCT FROM p_property_id 
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

-- Log the fix
INSERT INTO system_logs (category, message, metadata)
VALUES ('CHAT', 'Business DM RPC fixed to support NULL property contexts.', 
        '{"fix": "IS NOT DISTINCT FROM", "version": "2026.04.26"}');
