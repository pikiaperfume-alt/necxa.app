-- PRODUCTION HARDENING: IDENTITY & UTILITY VERIFICATION SCHEMA (FIXED)
-- Ensures all shard tables have high-security metadata and user linkage

-- 1. Hardening Identity Shards (Add columns if they exist from legacy migrations)
DO $$ 
BEGIN
    ALTER TABLE identity_shards ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE;
    ALTER TABLE identity_shards ADD COLUMN IF NOT EXISTS doc_type TEXT;
    ALTER TABLE identity_shards ADD COLUMN IF NOT EXISTS doc_number TEXT;
    ALTER TABLE identity_shards ADD COLUMN IF NOT EXISTS id_front_url TEXT;
    ALTER TABLE identity_shards ADD COLUMN IF NOT EXISTS id_back_url TEXT;
    ALTER TABLE identity_shards ADD COLUMN IF NOT EXISTS id_holding_url TEXT;
    ALTER TABLE identity_shards ADD COLUMN IF NOT EXISTS face_scan_url TEXT;
    ALTER TABLE identity_shards ADD COLUMN IF NOT EXISTS verified BOOLEAN DEFAULT FALSE;
    ALTER TABLE identity_shards ADD COLUMN IF NOT EXISTS verification_confidence DECIMAL(5,2);
    ALTER TABLE identity_shards ADD COLUMN IF NOT EXISTS extracted_name TEXT;
    ALTER TABLE identity_shards ADD COLUMN IF NOT EXISTS extracted_nin TEXT;
    ALTER TABLE identity_shards ADD COLUMN IF NOT EXISTS fraud_risk TEXT CHECK (fraud_risk IN ('low', 'medium', 'high'));
    ALTER TABLE identity_shards ADD COLUMN IF NOT EXISTS rejection_reason TEXT;
    ALTER TABLE identity_shards ADD COLUMN IF NOT EXISTS ai_metadata JSONB DEFAULT '{}'::jsonb;
END $$;

-- 2. Hardening Utility Shards (Rename authority_shards if it exists, or create new)
DO $$ 
BEGIN
    -- Rename legacy authority_shards to utility_shards for SDK consistency
    IF EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'authority_shards') THEN
        IF NOT EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'utility_shards') THEN
            ALTER TABLE authority_shards RENAME TO utility_shards;
        END IF;
    END IF;
END $$;

-- Ensure utility_shards exists and has all required columns
CREATE TABLE IF NOT EXISTS utility_shards (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

DO $$ 
BEGIN
    ALTER TABLE utility_shards ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE;
    ALTER TABLE utility_shards ADD COLUMN IF NOT EXISTS property_id UUID REFERENCES properties(id);
    ALTER TABLE utility_shards ADD COLUMN IF NOT EXISTS country TEXT DEFAULT 'Uganda';
    ALTER TABLE utility_shards ADD COLUMN IF NOT EXISTS utility_type TEXT;
    ALTER TABLE utility_shards ADD COLUMN IF NOT EXISTS umeme_meter_number TEXT;
    ALTER TABLE utility_shards ADD COLUMN IF NOT EXISTS nwsc_customer_number TEXT;
    ALTER TABLE utility_shards ADD COLUMN IF NOT EXISTS land_title_block TEXT;
    ALTER TABLE utility_shards ADD COLUMN IF NOT EXISTS land_title_plot TEXT;
    ALTER TABLE utility_shards ADD COLUMN IF NOT EXISTS bill_image_url TEXT;
    ALTER TABLE utility_shards ADD COLUMN IF NOT EXISTS stamp_image_url TEXT;
    ALTER TABLE utility_shards ADD COLUMN IF NOT EXISTS title_image_url TEXT;
    ALTER TABLE utility_shards ADD COLUMN IF NOT EXISTS verified BOOLEAN DEFAULT FALSE;
    ALTER TABLE utility_shards ADD COLUMN IF NOT EXISTS confidence_score DECIMAL(5,2);
    ALTER TABLE utility_shards ADD COLUMN IF NOT EXISTS extracted_meter_number TEXT;
    ALTER TABLE utility_shards ADD COLUMN IF NOT EXISTS rejection_reason TEXT;
END $$;

-- 3. Audit Logging
CREATE TABLE IF NOT EXISTS verification_audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id),
    shard_id UUID,
    shard_type TEXT,
    action TEXT,
    fraud_risk TEXT,
    metadata JSONB,
    ip_address TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 4. Unified Sync Trigger
CREATE OR REPLACE FUNCTION sync_verification_to_profile()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_TABLE_NAME = 'identity_shards' AND NEW.verified = TRUE AND NEW.fraud_risk = 'low' THEN
        UPDATE profiles 
        SET 
            nin_verified = TRUE,
            nin_verified_at = NOW(),
            nin_number = COALESCE(NEW.extracted_nin, profiles.nin_number),
            full_name = COALESCE(NEW.extracted_name, profiles.full_name)
        WHERE id = NEW.user_id;
        
        PERFORM increment_trust_score(NEW.user_id, 20, 'biometric_id_verified');
    END IF;
    
    IF TG_TABLE_NAME = 'utility_shards' AND NEW.verified = TRUE THEN
        PERFORM increment_trust_score(NEW.user_id, 10, 'utility_proof_verified');
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Re-attach triggers safely
DROP TRIGGER IF EXISTS tr_sync_identity_shard ON identity_shards;
CREATE TRIGGER tr_sync_identity_shard AFTER INSERT OR UPDATE ON identity_shards FOR EACH ROW EXECUTE FUNCTION sync_verification_to_profile();

DROP TRIGGER IF EXISTS tr_sync_utility_shard ON utility_shards;
CREATE TRIGGER tr_sync_utility_shard AFTER INSERT OR UPDATE ON utility_shards FOR EACH ROW EXECUTE FUNCTION sync_verification_to_profile();

-- 5. Hardened RLS Policies (Drop first to ensure clean application)
ALTER TABLE identity_shards ENABLE ROW LEVEL SECURITY;
ALTER TABLE utility_shards ENABLE ROW LEVEL SECURITY;
ALTER TABLE verification_audit_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own identity shards" ON identity_shards;
CREATE POLICY "Users can view own identity shards" ON identity_shards FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can view own utility shards" ON utility_shards;
CREATE POLICY "Users can view own utility shards" ON utility_shards FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own identity shards" ON identity_shards;
CREATE POLICY "Users can insert own identity shards" ON identity_shards FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own utility shards" ON utility_shards;
CREATE POLICY "Users can insert own utility shards" ON utility_shards FOR INSERT WITH CHECK (auth.uid() = user_id);
