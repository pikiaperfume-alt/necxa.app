-- ═══════════════════════════════════════════════════════════════════════════
-- NECXA PLATFORM – MIGRATION: Add SKU to Listings
-- Goal: Provide a unique internal inventory identifier at sale.
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE listings 
ADD COLUMN IF NOT EXISTS sku TEXT;

CREATE INDEX IF NOT EXISTS idx_listings_sku ON listings(sku) WHERE sku IS NOT NULL;
