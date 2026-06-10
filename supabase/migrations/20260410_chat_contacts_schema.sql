-- ═══════════════════════════════════════════════════════════════════════════
-- NECXA PLATFORM – MIGRATION: Chat Contacts & Direct Messaging
-- File: 20260410_chat_contacts_schema.sql
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. DIRECT MESSAGE ROOMS ──────────────────────────────────────────────
-- These are person-to-person chats (not tied to a property/escrow)
CREATE TABLE IF NOT EXISTS direct_chat_rooms (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at   TIMESTAMPTZ DEFAULT NOW(),
  updated_at   TIMESTAMPTZ DEFAULT NOW(),

  user_a       UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  user_b       UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  initiated_by UUID REFERENCES profiles(id),

  last_message      TEXT,
  last_message_at   TIMESTAMPTZ,
  last_sender_id    UUID REFERENCES profiles(id),

  user_a_unread     INT DEFAULT 0,
  user_b_unread     INT DEFAULT 0,

  status       TEXT DEFAULT 'active' CHECK (status IN ('active', 'blocked', 'archived')),

  UNIQUE(user_a, user_b)  -- one room per pair
);

CREATE INDEX IF NOT EXISTS idx_dchat_user_a ON direct_chat_rooms(user_a);
CREATE INDEX IF NOT EXISTS idx_dchat_user_b ON direct_chat_rooms(user_b);
CREATE INDEX IF NOT EXISTS idx_dchat_updated ON direct_chat_rooms(updated_at DESC);

-- ── 2. DIRECT MESSAGES ───────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS direct_messages (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id      UUID NOT NULL REFERENCES direct_chat_rooms(id) ON DELETE CASCADE,
  sender_id    UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,

  message_type TEXT DEFAULT 'text' CHECK (message_type IN (
    'text', 'image', 'audio', 'video', 'file', 'location', 'contact_card', 'system'
  )),
  content      TEXT,
  media_url    TEXT,
  metadata     JSONB,

  is_read      BOOLEAN DEFAULT FALSE,
  read_at      TIMESTAMPTZ,
  is_deleted   BOOLEAN DEFAULT FALSE,
  deleted_at   TIMESTAMPTZ,

  created_at   TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_dmsg_room     ON direct_messages(room_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_dmsg_sender   ON direct_messages(sender_id);
CREATE INDEX IF NOT EXISTS idx_dmsg_unread   ON direct_messages(room_id, is_read) WHERE is_read = false;

-- ── 3. SAVED / FAVOURITE CONTACTS ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS saved_contacts (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  contact_id   UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  nickname     TEXT,
  saved_at     TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, contact_id)
);

CREATE INDEX IF NOT EXISTS idx_saved_user    ON saved_contacts(user_id);
CREATE INDEX IF NOT EXISTS idx_saved_contact ON saved_contacts(contact_id);

-- ── 4. TRIGGER: update room last_message on new DM ───────────────────────
CREATE OR REPLACE FUNCTION update_direct_room_on_message()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_room direct_chat_rooms%ROWTYPE;
BEGIN
  SELECT * INTO v_room FROM direct_chat_rooms WHERE id = NEW.room_id;

  UPDATE direct_chat_rooms SET
    last_message    = LEFT(NEW.content, 120),
    last_message_at = NEW.created_at,
    last_sender_id  = NEW.sender_id,
    updated_at      = NOW(),
    -- Increment unread for the OTHER person
    user_a_unread = CASE WHEN v_room.user_a != NEW.sender_id THEN user_a_unread + 1 ELSE user_a_unread END,
    user_b_unread = CASE WHEN v_room.user_b != NEW.sender_id THEN user_b_unread + 1 ELSE user_b_unread END
  WHERE id = NEW.room_id;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER on_direct_message_insert
  AFTER INSERT ON direct_messages
  FOR EACH ROW EXECUTE FUNCTION update_direct_room_on_message();

-- ── 5. TRIGGER: reset unread count when user reads messages ──────────────
CREATE OR REPLACE FUNCTION mark_room_read(p_room_id UUID, p_user_id UUID)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE direct_chat_rooms SET
    user_a_unread = CASE WHEN user_a = p_user_id THEN 0 ELSE user_a_unread END,
    user_b_unread = CASE WHEN user_b = p_user_id THEN 0 ELSE user_b_unread END
  WHERE id = p_room_id;

  UPDATE direct_messages SET is_read = true, read_at = NOW()
  WHERE room_id = p_room_id AND sender_id != p_user_id AND is_read = false;
END;
$$;

-- ── 6. FUNCTION: find or create a direct chat room ───────────────────────
CREATE OR REPLACE FUNCTION get_or_create_direct_room(p_user_a UUID, p_user_b UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_room_id UUID;
  -- Always store user_a < user_b to satisfy UNIQUE constraint
  v_a UUID := LEAST(p_user_a, p_user_b);
  v_b UUID := GREATEST(p_user_a, p_user_b);
BEGIN
  SELECT id INTO v_room_id
  FROM direct_chat_rooms
  WHERE user_a = v_a AND user_b = v_b;

  IF NOT FOUND THEN
    INSERT INTO direct_chat_rooms (user_a, user_b, initiated_by)
    VALUES (v_a, v_b, p_user_a)
    RETURNING id INTO v_room_id;
  END IF;

  RETURN v_room_id;
END;
$$;

-- ── 7. VIEW: enriched conversation list for a user ───────────────────────
CREATE OR REPLACE VIEW v_my_chats AS
SELECT
  r.id                   AS room_id,
  r.updated_at,
  r.last_message,
  r.last_message_at,
  r.status,

  -- Current user's unread (resolved at query time via RLS + auth.uid())
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

-- ── 8. RLS ────────────────────────────────────────────────────────────────
ALTER TABLE direct_chat_rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE direct_messages   ENABLE ROW LEVEL SECURITY;
ALTER TABLE saved_contacts    ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Participants can view own rooms"
  ON direct_chat_rooms FOR SELECT
  USING (auth.uid() IN (user_a, user_b));

CREATE POLICY "Users can create rooms"
  ON direct_chat_rooms FOR INSERT
  WITH CHECK (auth.uid() IN (user_a, user_b));

CREATE POLICY "Participants can update own rooms"
  ON direct_chat_rooms FOR UPDATE
  USING (auth.uid() IN (user_a, user_b));

CREATE POLICY "Participants can view messages"
  ON direct_messages FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM direct_chat_rooms r
    WHERE r.id = room_id AND auth.uid() IN (r.user_a, r.user_b)
  ));

CREATE POLICY "Participants can send messages"
  ON direct_messages FOR INSERT
  WITH CHECK (
    auth.uid() = sender_id AND
    EXISTS (
      SELECT 1 FROM direct_chat_rooms r
      WHERE r.id = room_id AND auth.uid() IN (r.user_a, r.user_b)
    )
  );

CREATE POLICY "Senders can soft-delete own messages"
  ON direct_messages FOR UPDATE
  USING (auth.uid() = sender_id);

CREATE POLICY "Users can manage own saved contacts"
  ON saved_contacts FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- ── 9. REALTIME ───────────────────────────────────────────────────────────
ALTER PUBLICATION supabase_realtime ADD TABLE direct_messages;
ALTER PUBLICATION supabase_realtime ADD TABLE direct_chat_rooms;

-- ═══════════════════════════════════════════════════════════════════════════
-- END
-- ═══════════════════════════════════════════════════════════════════════════
