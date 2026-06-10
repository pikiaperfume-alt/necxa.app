-- ═══════════════════════════════════════════════════════════════════════════
-- NECXA SOCIAL BACKEND COMPLETION
-- ═══════════════════════════════════════════════════════════════════════════

-- CLEAN SLATE (Optional: Remove if you want to keep existing test data)
DROP TABLE IF EXISTS user_preferences CASCADE;
DROP TABLE IF EXISTS reports CASCADE;
DROP TABLE IF EXISTS saved_posts CASCADE;
DROP TABLE IF EXISTS community_comments CASCADE;
DROP TABLE IF EXISTS community_likes CASCADE;
-- DROP TABLE IF EXISTS community_posts CASCADE; -- Careful with the main posts table

-- ── 1. COMMUNITY CORE TABLES ───────────────────────────────────────────────

-- Ensure community_posts exists (authoritative)
CREATE TABLE IF NOT EXISTS community_posts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    author_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    
    title TEXT,
    content TEXT,
    media_url TEXT,
    thumbnail_url TEXT,
    media_type TEXT DEFAULT 'image', -- 'image', 'video', 'gallery', 'audio'
    
    tags TEXT[] DEFAULT '{}',
    
    likes_count INT DEFAULT 0,
    comments_count INT DEFAULT 0,
    shares_count INT DEFAULT 0,
    
    status TEXT DEFAULT 'verified', -- 'draft', 'pending', 'verified', 'flagged'
    visibility TEXT DEFAULT 'public', -- 'public', 'private', 'followers'
    
    metadata JSONB DEFAULT '{}',
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Likes Tracking
CREATE TABLE IF NOT EXISTS community_likes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id UUID NOT NULL REFERENCES community_posts(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(post_id, user_id)
);

-- Comments Tracking
CREATE TABLE IF NOT EXISTS community_comments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id UUID NOT NULL REFERENCES community_posts(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    parent_id UUID REFERENCES community_comments(id) ON DELETE CASCADE, -- For threaded replies
    
    content TEXT NOT NULL,
    likes_count INT DEFAULT 0,
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Saved Posts (Bookmarks)
CREATE TABLE IF NOT EXISTS saved_posts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    post_id UUID NOT NULL REFERENCES community_posts(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, post_id)
);

-- Reports & Moderation
CREATE TABLE IF NOT EXISTS reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES profiles(id), -- Standardized to user_id
    target_id UUID NOT NULL, -- post_id, comment_id, or user_id
    target_type TEXT NOT NULL, -- 'post', 'comment', 'user'
    
    reason TEXT NOT NULL,
    status TEXT DEFAULT 'pending', -- 'pending', 'reviewed', 'action_taken', 'dismissed'
    
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- User Interaction Preferences
CREATE TABLE IF NOT EXISTS user_preferences (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    target_id UUID NOT NULL,
    content_type TEXT NOT NULL, -- 'post', 'creator'
    preference_type TEXT NOT NULL, -- 'not_interested', 'blocked'
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, target_id)
);

-- ── 2. AUTOMATIC COUNTER SYNCHRONIZATION ──────────────────────────────────

-- Trigger Function for Post Likes
CREATE OR REPLACE FUNCTION fn_sync_post_likes()
RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = 'INSERT') THEN
        UPDATE community_posts SET likes_count = likes_count + 1 WHERE id = NEW.post_id;
    ELSIF (TG_OP = 'DELETE') THEN
        UPDATE community_posts SET likes_count = GREATEST(likes_count - 1, 0) WHERE id = OLD.post_id;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER tr_sync_likes
AFTER INSERT OR DELETE ON community_likes
FOR EACH ROW EXECUTE FUNCTION fn_sync_post_likes();

-- Trigger Function for Post Comments
CREATE OR REPLACE FUNCTION fn_sync_post_comments()
RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = 'INSERT') THEN
        UPDATE community_posts SET comments_count = comments_count + 1 WHERE id = NEW.post_id;
    ELSIF (TG_OP = 'DELETE') THEN
        UPDATE community_posts SET comments_count = GREATEST(comments_count - 1, 0) WHERE id = OLD.post_id;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER tr_sync_comments
AFTER INSERT OR DELETE ON community_comments
FOR EACH ROW EXECUTE FUNCTION fn_sync_post_comments();

-- ── 3. SOCIAL NOTIFICATIONS ───────────────────────────────────────────────

-- Notify author when their post is liked
CREATE OR REPLACE FUNCTION fn_notify_post_like()
RETURNS TRIGGER AS $$
DECLARE
    v_author_id UUID;
BEGIN
    SELECT author_id INTO v_author_id FROM community_posts WHERE id = NEW.post_id;
    
    IF v_author_id != NEW.user_id THEN
        -- Safely check if notifications table exists before inserting
        IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'notifications') THEN
            INSERT INTO notifications (user_id, notification_type, title, body, metadata)
            VALUES (
                v_author_id,
                'listing_viewed', 
                'Someone liked your post!',
                'A user liked your community post.',
                jsonb_build_object('post_id', NEW.post_id, 'liker_id', NEW.user_id)
            );
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER tr_notify_like
AFTER INSERT ON community_likes
FOR EACH ROW EXECUTE FUNCTION fn_notify_post_like();

-- ── 4. SEARCH & DISCOVERY HELPERS ───────────────────────────────────────────

-- Optimized function to check if following
CREATE OR REPLACE FUNCTION is_following(p_follower_id UUID, p_creator_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM creator_followers 
        WHERE follower_id = p_follower_id AND creator_id = p_creator_id
    );
END;
$$ LANGUAGE plpgsql STABLE;

-- ── 5. PERFORMANCE INDEXES ───────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_likes_post ON community_likes(post_id);
CREATE INDEX IF NOT EXISTS idx_likes_user ON community_likes(user_id);
CREATE INDEX IF NOT EXISTS idx_comments_post ON community_comments(post_id);
CREATE INDEX IF NOT EXISTS idx_saved_user ON saved_posts(user_id);
CREATE INDEX IF NOT EXISTS idx_posts_author ON community_posts(author_id);
CREATE INDEX IF NOT EXISTS idx_reports_target ON reports(target_id);

ALTER TABLE community_posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE community_likes ENABLE ROW LEVEL SECURITY;
ALTER TABLE community_comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE saved_posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_preferences ENABLE ROW LEVEL SECURITY;

-- Community Posts Policies
DROP POLICY IF EXISTS "Anyone can see verified posts" ON community_posts;
CREATE POLICY "Anyone can see verified posts" ON community_posts FOR SELECT USING (status = 'verified' OR auth.uid() = author_id);

DROP POLICY IF EXISTS "Users can create posts" ON community_posts;
CREATE POLICY "Users can create posts" ON community_posts FOR INSERT WITH CHECK (auth.uid() = author_id);

DROP POLICY IF EXISTS "Authors can update posts" ON community_posts;
CREATE POLICY "Authors can update posts" ON community_posts FOR UPDATE USING (auth.uid() = author_id);

CREATE POLICY "Anyone can see likes" ON community_likes FOR SELECT USING (true);
CREATE POLICY "Users can like posts" ON community_likes FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can unlike posts" ON community_likes FOR DELETE USING (auth.uid() = user_id);

CREATE POLICY "Anyone can see comments" ON community_comments FOR SELECT USING (true);
CREATE POLICY "Users can comment" ON community_comments FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can see own saves" ON saved_posts FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can save posts" ON saved_posts FOR ALL USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can report content" ON reports;
CREATE POLICY "Users can report content" ON reports FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Preferences Policies
DROP POLICY IF EXISTS "Users can manage own preferences" ON user_preferences;
CREATE POLICY "Users can manage own preferences" ON user_preferences FOR ALL USING (auth.uid() = user_id);
