-- ================================================================
-- NECXA VERIFICATION SHARDS (Native Auth Architecture)
-- File: 20260417_add_verification_shards.sql
-- ================================================================

BEGIN;

-- 1) Identity Shards Table
CREATE TABLE IF NOT EXISTS public.identity_shards (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  country TEXT,
  doc_type TEXT,
  doc_number TEXT,
  id_front_url TEXT,
  id_back_url TEXT,
  id_holding_url TEXT,
  face_photo_url TEXT,
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'verified', 'rejected')),
  verified_at TIMESTAMPTZ,
  audit_metadata JSONB NOT NULL DEFAULT '{}'::JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2) Utility Shards Table
CREATE TABLE IF NOT EXISTS public.utility_shards (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  country TEXT,
  
  -- Utility Trackers
  umeme_meter TEXT,
  nwsc_account TEXT,
  kplc_meter TEXT,
  tanesco_meter TEXT,
  
  -- Local Properties/Land
  land_block TEXT,
  land_plot TEXT,
  property_id TEXT, -- Optional strict relation to a specific node/listing
  property_type TEXT,
  
  -- Uploaded Blob URLs
  lc1_stamp_url TEXT,
  land_title_url TEXT,
  business_license_url TEXT,
  
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'verified', 'rejected')),
  verified_at TIMESTAMPTZ,
  audit_metadata JSONB NOT NULL DEFAULT '{}'::JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3) Enable Row Level Security (RLS)
ALTER TABLE public.identity_shards ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.utility_shards ENABLE ROW LEVEL SECURITY;

-- 4) Identity Shards Policies
-- Users can read their own shards
CREATE POLICY "identity_shards_read_own" ON public.identity_shards 
  FOR SELECT TO authenticated 
  USING (user_id = auth.uid());

-- Users can insert their own shards (Edge functions do this natively since we auto-inject the exact Auth Bearer)
CREATE POLICY "identity_shards_insert_own" ON public.identity_shards 
  FOR INSERT TO authenticated 
  WITH CHECK (user_id = auth.uid());

-- Users can update metadata/status on their own shards
CREATE POLICY "identity_shards_update_own" ON public.identity_shards 
  FOR UPDATE TO authenticated 
  USING (user_id = auth.uid()) 
  WITH CHECK (user_id = auth.uid());


-- 5) Utility Shards Policies
-- Users can read their own utility shards
CREATE POLICY "utility_shards_read_own" ON public.utility_shards 
  FOR SELECT TO authenticated 
  USING (user_id = auth.uid());

-- Users can insert their own utility shards
CREATE POLICY "utility_shards_insert_own" ON public.utility_shards 
  FOR INSERT TO authenticated 
  WITH CHECK (user_id = auth.uid());

-- Users can update metadata/status on their own utility shards
CREATE POLICY "utility_shards_update_own" ON public.utility_shards 
  FOR UPDATE TO authenticated 
  USING (user_id = auth.uid()) 
  WITH CHECK (user_id = auth.uid());

-- Trigger for updated_at timestamps
CREATE OR REPLACE FUNCTION update_modified_column() 
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Attach trigger
DROP TRIGGER IF EXISTS update_identity_shards_modtime ON public.identity_shards;
CREATE TRIGGER update_identity_shards_modtime
  BEFORE UPDATE ON public.identity_shards
  FOR EACH ROW EXECUTE PROCEDURE update_modified_column();

DROP TRIGGER IF EXISTS update_utility_shards_modtime ON public.utility_shards;
CREATE TRIGGER update_utility_shards_modtime
  BEFORE UPDATE ON public.utility_shards
  FOR EACH ROW EXECUTE PROCEDURE update_modified_column();

COMMIT;
