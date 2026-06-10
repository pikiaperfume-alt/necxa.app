ALTER TABLE listings ADD COLUMN IF NOT EXISTS category TEXT;
ALTER TABLE listings ADD COLUMN IF NOT EXISTS photos JSONB DEFAULT '[]'::jsonb;
CREATE INDEX IF NOT EXISTS idx_listings_category ON listings(category);
