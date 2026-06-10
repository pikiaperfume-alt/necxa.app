-- ═══════════════════════════════════════════════════════════════════════════
-- NECXA PLATFORM – MIGRATION: Chat Initiation & Navigation Hardening
-- File: 20260426_chat_initiation_hardening.sql
-- Goal: High-performance user discovery and stable chat initiation.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. BATCH CONTACT MATCHING RPC ─────────────────────────────────────────
-- Takes a list of phone variations and returns matching Necxa profiles.
-- Optimized with GIN/B-Tree index lookups for O(1) performance.
CREATE OR REPLACE FUNCTION match_contacts_batch(p_phones TEXT[])
RETURNS TABLE (
    id UUID,
    full_name TEXT,
    avatar_url TEXT,
    phone TEXT,
    is_agent BOOLEAN,
    trust_score INTEGER
) LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  RETURN QUERY
  SELECT 
    p.id,
    p.full_name,
    p.avatar_url,
    p.phone,
    p.is_agent,
    p.trust_score
  FROM profiles p
  WHERE p.phone = ANY(p_phones)
    AND p.id != auth.uid();
END;
$$;

-- ── 2. UNIFIED USER SEARCH RPC ─────────────────────────────────────────────
-- Searches by Email OR @Username for intuitive discovery.
CREATE OR REPLACE FUNCTION search_necxa_users(p_query TEXT)
RETURNS TABLE (
    id UUID,
    full_name TEXT,
    avatar_url TEXT,
    email TEXT,
    is_agent BOOLEAN,
    trust_score INTEGER
) LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  RETURN QUERY
  SELECT 
    p.id,
    p.full_name,
    p.avatar_url,
    p.email,
    p.is_agent,
    p.trust_score
  FROM profiles p
  WHERE (p.email ILIKE p_query OR p.full_name ILIKE p_query OR p.id::text ILIKE p_query)
    AND p.id != auth.uid()
  LIMIT 10;
END;
$$;

-- ── 3. SYNC AUDIT LOG ─────────────────────────────────────────────────────
INSERT INTO system_logs (category, message, metadata)
VALUES ('CHAT_HARDENING', 'High-speed discovery RPCs (match_contacts_batch, search_necxa_users) initialized.', 
        '{"version": "2026.04.26", "discovery_mode": "unified"}');
