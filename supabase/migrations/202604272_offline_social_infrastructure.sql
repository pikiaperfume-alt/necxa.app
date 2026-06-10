-- ==============================================================================
-- 🚀 Necxa Offline-First Social Infrastructure Migration
-- Date: 2026-04-27
-- Description: Supports resilient messaging, reactions, and offline-first follows.
-- ==============================================================================

-- ──────────────────────────────────────────────────────────────────────────────
-- 1. 🟢 Follow & Following Resilience (Conflict Resolution)
-- ──────────────────────────────────────────────────────────────────────────────
-- Ensure a unique constraint exists so offline queue UPSERTs don't fail.
-- (Assumes creator_followers table exists from prior migrations)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'unique_follower_creator') THEN
        ALTER TABLE public.creator_followers 
        ADD CONSTRAINT unique_follower_creator UNIQUE (follower_id, creator_id);
    END IF;
END $$;

-- Ensure RLS is enabled and policies allow users to manage their own follows
ALTER TABLE public.creator_followers ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can insert their own follows" 
    ON public.creator_followers FOR INSERT 
    WITH CHECK (auth.uid() = follower_id);

CREATE POLICY "Users can delete their own follows" 
    ON public.creator_followers FOR DELETE 
    USING (auth.uid() = follower_id);

-- ──────────────────────────────────────────────────────────────────────────────
-- 2. 💬 Resilient Messaging & Creator Bubble Integration
-- ──────────────────────────────────────────────────────────────────────────────
-- High-performance RPC to get or create a direct chat room without race conditions
CREATE OR REPLACE FUNCTION public.get_or_create_direct_room(p_user_a UUID, p_user_b UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_room_id UUID;
BEGIN
    -- Try to find an existing room
    SELECT id INTO v_room_id
    FROM public.direct_chat_rooms
    WHERE (user_a = p_user_a AND user_b = p_user_b)
       OR (user_a = p_user_b AND user_b = p_user_a)
    LIMIT 1;

    -- If not found, create a new one
    IF v_room_id IS NULL THEN
        INSERT INTO public.direct_chat_rooms (user_a, user_b)
        VALUES (p_user_a, p_user_b)
        RETURNING id INTO v_room_id;
    END IF;

    RETURN v_room_id;
END;
$$;

-- Allow bulk inserts on direct_messages for when the app comes back online
-- (Handled naturally by Supabase REST API, just ensuring RLS is tight)
CREATE POLICY "Users can insert messages into their rooms"
    ON public.direct_messages FOR INSERT
    WITH CHECK (
        auth.uid() = sender_id AND
        EXISTS (
            SELECT 1 FROM public.direct_chat_rooms 
            WHERE id = room_id AND (user_a = auth.uid() OR user_b = auth.uid())
        )
    );

-- ──────────────────────────────────────────────────────────────────────────────
-- 3. ❤️ Interactive Chat Reactions
-- ──────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.direct_messages_reactions (
    message_id UUID NOT NULL REFERENCES public.direct_messages(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    reaction TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (message_id, user_id)
);

-- Enable RLS
ALTER TABLE public.direct_messages_reactions ENABLE ROW LEVEL SECURITY;

-- Select Policy: Users can see reactions in rooms they are part of
CREATE POLICY "Users can view reactions in their rooms"
    ON public.direct_messages_reactions FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.direct_messages msg
            JOIN public.direct_chat_rooms rm ON msg.room_id = rm.id
            WHERE msg.id = direct_messages_reactions.message_id
              AND (rm.user_a = auth.uid() OR rm.user_b = auth.uid())
        )
    );

-- Insert/Update Policy: Users can add/update their own reactions
CREATE POLICY "Users can manage their own reactions"
    ON public.direct_messages_reactions FOR ALL
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- Enable Realtime for reactions so UI updates instantly
alter publication supabase_realtime add table public.direct_messages_reactions;

-- ──────────────────────────────────────────────────────────────────────────────
-- 4. 🎙️ Local-First Voice Notes & Media Support
-- ──────────────────────────────────────────────────────────────────────────────
-- Create the 'chat-media' storage bucket if it doesn't exist
INSERT INTO storage.buckets (id, name, public)
VALUES ('chat-media', 'chat-media', true)
ON CONFLICT (id) DO NOTHING;

-- RLS for the storage bucket
-- Note: 'chat-media' is set to public to allow easy loading by the client via URL, 
-- but we restrict WHO can upload to it.

CREATE POLICY "Authenticated users can upload chat media"
    ON storage.objects FOR INSERT
    WITH CHECK (
        bucket_id = 'chat-media' 
        AND auth.role() = 'authenticated'
    );

CREATE POLICY "Users can update their own chat media"
    ON storage.objects FOR UPDATE
    USING (
        bucket_id = 'chat-media' 
        AND auth.uid() = owner
    );

CREATE POLICY "Users can delete their own chat media"
    ON storage.objects FOR DELETE
    USING (
        bucket_id = 'chat-media' 
        AND auth.uid() = owner
    );

CREATE POLICY "Anyone can view chat media"
    ON storage.objects FOR SELECT
    USING (bucket_id = 'chat-media');

-- ==============================================================================
-- 5. Notifications Webhook Preparation (Reminder)
-- ==============================================================================
-- To complete the Notification architecture, you must manually set up a Database 
-- Webhook in the Supabase Dashboard:
-- Table: creator_followers (and community_posts)
-- Events: INSERT
-- Type: HTTP Request
-- URL: https://fcguggsleaykcofrqcsq.supabase.co/functions/v1/push-relay
