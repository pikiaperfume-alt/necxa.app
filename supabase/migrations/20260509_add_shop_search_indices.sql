-- ═══════════════════════════════════════════════════════════════════════════
-- NECXA PLATFORM – MIGRATION: Add Shop Search Indices
-- Goal: Enable fast searching of listings by word, tags, and price.
-- ═══════════════════════════════════════════════════════════════════════════

-- 1. Add tags column if it doesn't exist
ALTER TABLE listings 
ADD COLUMN IF NOT EXISTS tags TEXT[] DEFAULT '{}';

-- 2. Create an IMMUTABLE function to convert TEXT[] to TEXT
-- (array_to_string is STABLE because it accepts anyarray, so it blocks generated columns)
CREATE OR REPLACE FUNCTION text_array_to_string(arr TEXT[])
RETURNS TEXT
LANGUAGE SQL
IMMUTABLE
AS $$
  SELECT array_to_string(arr, ' ');
$$;

-- 3. Create the Generated Full-Text Search (FTS) Document
ALTER TABLE listings 
ADD COLUMN IF NOT EXISTS fts_doc tsvector GENERATED ALWAYS AS (
  setweight(to_tsvector('english'::regconfig, coalesce(title, '')), 'A') ||
  setweight(to_tsvector('english'::regconfig, coalesce(description, '')), 'B') ||
  setweight(to_tsvector('english'::regconfig, coalesce(category, '')), 'B') ||
  setweight(to_tsvector('english'::regconfig, coalesce(text_array_to_string(tags), '')), 'A')
) STORED;

-- 4. Create indices for performance
CREATE INDEX IF NOT EXISTS listings_fts_doc_idx ON listings USING GIN (fts_doc);
CREATE INDEX IF NOT EXISTS listings_tags_idx ON listings USING GIN (tags);
CREATE INDEX IF NOT EXISTS listings_price_idx ON listings (price_ugx);
