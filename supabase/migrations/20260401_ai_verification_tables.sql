-- ── ADDITIONAL TABLES FOR AI VERIFICATION & MARKETPLACE ────────
-- Table for Identity, Property, and Media Verifications
CREATE TABLE IF NOT EXISTS verifications (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id TEXT NOT NULL,
  status TEXT NOT NULL, -- 'verified', 'rejected', 'flagged'
  details JSONB, -- Stores AI analysis, extracted data, and confidence scores
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Table for Marketplace Listings
CREATE TABLE IF NOT EXISTS listings (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id TEXT NOT NULL,
  title TEXT NOT NULL,
  description TEXT,
  price NUMERIC,
  image_url TEXT,
  ai_verification JSONB, -- Stores Gemini's quality and authenticity check
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Enable RLS
ALTER TABLE verifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE listings ENABLE ROW LEVEL SECURITY;

-- Policies for verifications
CREATE POLICY "Users can see their own verifications" ON verifications
  FOR SELECT USING (auth.uid()::text = user_id);

CREATE POLICY "System can insert verifications" ON verifications
  FOR INSERT WITH CHECK (true);

-- Policies for listings
CREATE POLICY "Anyone can see listings" ON listings
  FOR SELECT USING (true);

CREATE POLICY "Users can manage their own listings" ON listings
  FOR ALL USING (auth.uid()::text = user_id);
