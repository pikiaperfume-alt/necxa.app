-- HARDENING IDENTITY SHARDS FOR MODULAR VERIFICATION
-- This migration expands Step 3's backend to support standalone PII handling

-- 1. Expand identity_shards for detailed AI results
ALTER TABLE identity_shards 
ADD COLUMN IF NOT EXISTS extracted_name TEXT,
ADD COLUMN IF NOT EXISTS extracted_nin TEXT,
ADD COLUMN IF NOT EXISTS fraud_risk TEXT CHECK (fraud_risk IN ('low', 'medium', 'high')),
ADD COLUMN IF NOT EXISTS rejection_reason TEXT,
ADD COLUMN IF NOT EXISTS ai_metadata JSONB DEFAULT '{}'::jsonb,
ADD COLUMN IF NOT EXISTS attempt_count INT DEFAULT 1;

-- 2. Relax property_id constraint
-- This allows users to verify identity independently of a specific property listing
ALTER TABLE identity_shards ALTER COLUMN property_id DROP NOT NULL;

-- 3. Audit Logging for Security
CREATE TABLE IF NOT EXISTS identity_verification_audit (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id),
    shard_id UUID,
    status TEXT, -- 'success', 'failed_ai', 'rejected_fraud'
    fraud_risk TEXT,
    rejection_reason TEXT,
    ip_address TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- RLS for Audit Table (Admins only or restrict completely)
ALTER TABLE identity_verification_audit ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can see own audits" ON identity_verification_audit
FOR SELECT USING (auth.uid() = user_id);

-- 4. Sync Trigger: Auto-update profile on shard completion
CREATE OR REPLACE FUNCTION sync_identity_to_profile()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.verification_confidence >= 0.8 AND NEW.fraud_risk = 'low' THEN
        UPDATE profiles 
        SET 
            nin_verified = TRUE,
            nin_verified_at = NOW(),
            nin_number = COALESCE(NEW.extracted_nin, profiles.nin_number),
            full_name = COALESCE(NEW.extracted_name, profiles.full_name)
        WHERE id = NEW.user_id;
        
        -- Boost Trust Score
        PERFORM increment_trust_score(NEW.user_id, 15, 'identity_verified');
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS tr_sync_identity_to_profile ON identity_shards;
CREATE TRIGGER tr_sync_identity_to_profile
AFTER INSERT OR UPDATE ON identity_shards
FOR EACH ROW EXECUTE FUNCTION sync_identity_to_profile();
