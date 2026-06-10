-- ═══════════════════════════════════════════════════════════════════════════
-- NECXA PLATFORM – MIGRATION: Community Social Feed & Native Micro-Economy
-- File: 20260412_community_feed.sql
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. COMMUNITY POSTS TABLE ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS community_posts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  author_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  title TEXT,
  content TEXT,
  media_url TEXT,
  status TEXT DEFAULT 'verified', -- pending, verified, flagged
  
  -- Aggregations for fast reads
  likes_count INT DEFAULT 0,
  comments_count INT DEFAULT 0,
  gifts_count INT DEFAULT 0,
  gifts_fiat_value BIGINT DEFAULT 0, 

  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_community_posts_author ON community_posts(author_id);
CREATE INDEX IF NOT EXISTS idx_community_posts_created ON community_posts(created_at DESC);

-- ── 2. LIKES TABLE ───────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS community_likes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id UUID NOT NULL REFERENCES community_posts(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(post_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_com_likes_post ON community_likes(post_id);

-- ── 3. COMMENTS TABLE ────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS community_comments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id UUID NOT NULL REFERENCES community_posts(id) ON DELETE CASCADE,
  author_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_com_comments_post ON community_comments(post_id);

-- ── 4. SOCIAL GIFTING TRANSACTIONS (Micro-Economy) ───────────────────────
CREATE TABLE IF NOT EXISTS community_gifts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id UUID NOT NULL REFERENCES community_posts(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL REFERENCES profiles(id),
  receiver_id UUID NOT NULL REFERENCES profiles(id),
  
  gift_type TEXT NOT NULL,         -- rose, heart, diamond, crown
  coin_amount INT NOT NULL,        -- Sender pays this many NCX Coins (1, 10, 100, 1000)
  
  fiat_value_generated BIGINT,     -- Total fiat value generated (coin_amount * 100)
  creator_fiat_cut BIGINT,         -- 60% going to the creator's fiat_balance
  necxa_fiat_fee BIGINT,           -- 40% going to platform

  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_com_gifts_post ON community_gifts(post_id);


-- ── 5. RLS POLICIES ──────────────────────────────────────────────────────
ALTER TABLE community_posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE community_likes ENABLE ROW LEVEL SECURITY;
ALTER TABLE community_comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE community_gifts ENABLE ROW LEVEL SECURITY;

-- Posts
CREATE POLICY "Anyone can view verified community posts" ON community_posts FOR SELECT USING (status = 'verified' OR auth.uid() = author_id);
CREATE POLICY "Users can create posts" ON community_posts FOR INSERT WITH CHECK (auth.uid() = author_id);
CREATE POLICY "Users can delete own posts" ON community_posts FOR DELETE USING (auth.uid() = author_id);

-- Likes
CREATE POLICY "Anyone can view likes" ON community_likes FOR SELECT USING (true);
CREATE POLICY "Users can like" ON community_likes FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can unlike" ON community_likes FOR DELETE USING (auth.uid() = user_id);

-- Comments
CREATE POLICY "Anyone can view comments" ON community_comments FOR SELECT USING (true);
CREATE POLICY "Users can comment" ON community_comments FOR INSERT WITH CHECK (auth.uid() = author_id);
CREATE POLICY "Users can delete own comments" ON community_comments FOR DELETE USING (auth.uid() = author_id);

-- Gifts
CREATE POLICY "Anyone can view gifts" ON community_gifts FOR SELECT USING (true);
-- INSERT policy handled inherently by the RPC function we will create to process the gift securely.


-- ── 6. AUTONOMOUS AGGREGATION TRIGGERS ───────────────────────────────────

-- Likes Trigger
CREATE OR REPLACE FUNCTION handle_community_like() RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE community_posts SET likes_count = likes_count + 1 WHERE id = NEW.post_id;
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE community_posts SET likes_count = GREATEST(likes_count - 1, 0) WHERE id = OLD.post_id;
    RETURN OLD;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_community_like ON community_likes;
CREATE TRIGGER on_community_like
  AFTER INSERT OR DELETE ON community_likes
  FOR EACH ROW EXECUTE FUNCTION handle_community_like();

-- Comments Trigger
CREATE OR REPLACE FUNCTION handle_community_comment() RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE community_posts SET comments_count = comments_count + 1 WHERE id = NEW.post_id;
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE community_posts SET comments_count = GREATEST(comments_count - 1, 0) WHERE id = OLD.post_id;
    RETURN OLD;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_community_comment ON community_comments;
CREATE TRIGGER on_community_comment
  AFTER INSERT OR DELETE ON community_comments
  FOR EACH ROW EXECUTE FUNCTION handle_community_comment();


-- ── 7. NATIVE MICRO-ECONOMY TRANSACTION LOGIC ────────────────────────────
-- 1 NCX Coin = 100 Fiat Local Currency (dynamically localized equivalent)
-- 40% Necxa Network Fee, 60% Creator Withdrawble Cashout Value

CREATE OR REPLACE FUNCTION send_social_gift(
  p_post_id UUID, 
  p_sender_id UUID, 
  p_gift_type TEXT, 
  p_coin_amount INT
)
RETURNS TABLE (success BOOLEAN, message TEXT, creator_gained BIGINT) LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_post RECORD;
  v_sender_wallet RECORD;
  v_receiver_wallet RECORD;
  
  -- BASE LOGIC ACROSS ALL CURRENCIES: 1 Coin generates 100 units of standard fractional fiat
  v_fiat_exchange_rate CONSTANT INT := 100; 
  
  v_total_fiat BIGINT;
  v_creator_cut BIGINT;
  v_necxa_cut BIGINT;
BEGIN
  -- 1. Validate Post & Receiver
  SELECT * INTO v_post FROM community_posts WHERE id = p_post_id;
  IF NOT FOUND THEN 
    RETURN QUERY SELECT false, 'Post not found', 0::BIGINT; RETURN; 
  END IF;
  
  -- Prevent gifting oneself to avoid infinite loop economics
  IF v_post.author_id = p_sender_id THEN
    RETURN QUERY SELECT false, 'Cannot gift your own post', 0::BIGINT; RETURN;
  END IF;

  -- 2. Validate Sender's Wallet (Coin Balance)
  SELECT * INTO v_sender_wallet FROM wallets WHERE user_id = p_sender_id;
  IF NOT FOUND THEN 
    RETURN QUERY SELECT false, 'Sender wallet not found', 0::BIGINT; RETURN; 
  END IF;
  
  IF v_sender_wallet.coin_balance < p_coin_amount THEN
    RETURN QUERY SELECT false, 'Insufficient NCX coins', 0::BIGINT; RETURN;
  END IF;

  -- 3. Calculate 60/40 Fiat Split Model
  v_total_fiat := p_coin_amount * v_fiat_exchange_rate;
  v_creator_cut := (v_total_fiat * 60) / 100;
  v_necxa_cut := (v_total_fiat * 40) / 100;

  -- 4. Execute Financial Deductions & Deposits natively (Atomic Transaction)
  
  -- Sender loses Coins
  UPDATE wallets 
  SET coin_balance = coin_balance - p_coin_amount, 
      total_spent = total_spent + v_total_fiat, 
      updated_at = NOW() 
  WHERE user_id = p_sender_id;

  -- Receiver gains Fiat Cash (60% cut added directly to withdrawable fiat_balance)
  UPDATE wallets 
  SET fiat_balance = fiat_balance + v_creator_cut, 
      total_earned = total_earned + v_creator_cut, 
      updated_at = NOW() 
  WHERE user_id = v_post.author_id;

  -- 5. Record the Micro-Economy Ledger
  INSERT INTO community_gifts (
    post_id, sender_id, receiver_id, gift_type, coin_amount, 
    fiat_value_generated, creator_fiat_cut, necxa_fiat_fee
  ) VALUES (
    p_post_id, p_sender_id, v_post.author_id, p_gift_type, p_coin_amount,
    v_total_fiat, v_creator_cut, v_necxa_cut
  );
  
  -- 6. Log Double-Entry Audits on the primary Wallet Transactions system
  INSERT INTO wallet_transactions (
    wallet_id, user_id, transaction_type, amount, balance_after, status, description
  ) VALUES (
    v_sender_wallet.id, p_sender_id, 'coin_withdrawal', p_coin_amount, 
    (v_sender_wallet.coin_balance - p_coin_amount), 'completed', 'Sent ' || p_gift_type || ' gift on community content'
  );
  
  SELECT id, fiat_balance INTO v_receiver_wallet FROM wallets WHERE user_id = v_post.author_id;
  INSERT INTO wallet_transactions (
    wallet_id, user_id, transaction_type, amount, balance_after, status, description
  ) VALUES (
    v_receiver_wallet.id, v_post.author_id, 'commission_earned', v_creator_cut, 
    v_receiver_wallet.fiat_balance, 'completed', 'Earned ' || p_gift_type || ' creator payout via community feed'
  );

  -- 7. Update Post Aggregations metrics
  UPDATE community_posts 
  SET gifts_count = gifts_count + 1, 
      gifts_fiat_value = gifts_fiat_value + v_total_fiat 
  WHERE id = p_post_id;

  RETURN QUERY SELECT true, 'Gift processed securely: deducted NCX coins and distributed Fiat value.', v_creator_cut;
END;
$$;
