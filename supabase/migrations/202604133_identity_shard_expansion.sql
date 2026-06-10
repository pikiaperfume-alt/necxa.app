-- Expand identity_shards to support 4-image verification
ALTER TABLE identity_shards 
ADD COLUMN IF NOT EXISTS id_back_url TEXT,
ADD COLUMN IF NOT EXISTS id_holding_url TEXT;

-- Update RLS policies if necessary (usually inherited from parent table)
