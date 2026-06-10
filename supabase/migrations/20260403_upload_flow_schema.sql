-- NECXA PLATFORM – Content Upload & Release 2.0 Schema
-- This schema supports the new TikTok-style upload flow for Community Posts and simplified Market Listings.

-- ── 1. CREATOR POSTS (Community Feed) ───────────────────────────
DROP TABLE IF EXISTS creator_posts CASCADE;
CREATE TABLE creator_posts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    creator_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    category TEXT DEFAULT 'Community',
    content TEXT, -- Note: Corresponds to description in upload_screen payload
    media_url TEXT,
    type TEXT DEFAULT 'post',
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'verified', 'flagged', 'archived')),
    likes_count INT DEFAULT 0,
    views_count INT DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_creator_posts_creator ON creator_posts(creator_id);
CREATE INDEX idx_creator_posts_status ON creator_posts(status);

-- ── 2. NEW LISTINGS TABLE (Release 2.0 Audit) ───────────────────
DROP TABLE IF EXISTS listings CASCADE;
CREATE TABLE listings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT,
    price DOUBLE PRECISION DEFAULT 0,
    currency TEXT DEFAULT 'UGX',
    image_url TEXT,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'active', 'sold', 'flagged')),
    ai_verification JSONB,
    is_active BOOLEAN GENERATED ALWAYS AS (status = 'active') STORED,
    is_verified BOOLEAN DEFAULT FALSE,
    is_honeypot BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_listings_user ON listings(user_id);
CREATE INDEX idx_listings_status ON listings(status);

-- ── 3. VERIFICATIONS AUDIT TABLE ────────────────────────────────
DROP TABLE IF EXISTS verifications CASCADE;
CREATE TABLE verifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    status TEXT DEFAULT 'pending',
    details JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_verifications_user ON verifications(user_id);

-- ── 4. ROW LEVEL SECURITY (RLS) POLICIES ────────────────────────
ALTER TABLE creator_posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE listings ENABLE ROW LEVEL SECURITY;
ALTER TABLE verifications ENABLE ROW LEVEL SECURITY;

-- Broadcasters (Read access)
CREATE POLICY "Anyone can view verified creator posts" ON creator_posts FOR SELECT 
    USING (status = 'verified' OR auth.uid() = creator_id);

CREATE POLICY "Anyone can view active listings" ON listings FOR SELECT 
    USING (status = 'active' OR auth.uid() = user_id);

-- Authors (Write access)
CREATE POLICY "Creators can insert own posts" ON creator_posts FOR INSERT WITH CHECK (auth.uid() = creator_id);
CREATE POLICY "Creators can update own posts" ON creator_posts FOR UPDATE USING (auth.uid() = creator_id);

CREATE POLICY "Users can insert own listings" ON listings FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update own listings" ON listings FOR UPDATE USING (auth.uid() = user_id);

-- Triggers for updated_at
CREATE TRIGGER update_creator_posts_updated_at
    BEFORE UPDATE ON creator_posts
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER update_listings_updated_at
    BEFORE UPDATE ON listings
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
