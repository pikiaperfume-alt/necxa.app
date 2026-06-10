-- ================================================================
-- PLATFORM MUSIC MANAGEMENT (Backend/Admin)
-- File: 20260418_music_admin.sql
-- ================================================================

-- 1. ADMIN MUSIC MANAGEMENT TABLES
CREATE TABLE IF NOT EXISTS public.music_uploads (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    uploaded_by UUID REFERENCES public.profiles(id),
    upload_status TEXT DEFAULT 'pending' CHECK (upload_status IN ('pending', 'processing', 'completed', 'failed')),
    upload_batch_id UUID DEFAULT gen_random_uuid(),
    original_filename TEXT,
    file_size BIGINT,
    file_hash TEXT UNIQUE,
    processing_log TEXT,
    error_message TEXT,
    uploaded_at TIMESTAMPTZ DEFAULT NOW(),
    processed_at TIMESTAMPTZ,
    metadata JSONB DEFAULT '{}'::jsonb
);

CREATE TABLE IF NOT EXISTS public.music_licenses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    track_id UUID REFERENCES public.music_tracks(id) ON DELETE CASCADE,
    license_type TEXT CHECK (license_type IN ('exclusive', 'non_exclusive', 'royalty_free', 'sync')),
    license_provider TEXT,
    license_agreement_url TEXT,
    territory TEXT[] DEFAULT '{"worldwide"}',
    start_date DATE,
    end_date DATE,
    is_perpetual BOOLEAN DEFAULT false,
    advance_paid NUMERIC(12,2) DEFAULT 0,
    royalty_rate NUMERIC(5,4),
    currency TEXT DEFAULT 'UGX',
    contract_number TEXT,
    signed_by UUID REFERENCES public.profiles(id),
    signed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.music_catalog_imports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    import_name TEXT NOT NULL,
    import_source TEXT,
    total_tracks INTEGER DEFAULT 0,
    successful_imports INTEGER DEFAULT 0,
    failed_imports INTEGER DEFAULT 0,
    import_status TEXT DEFAULT 'pending',
    import_log TEXT,
    imported_by UUID REFERENCES public.profiles(id),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    completed_at TIMESTAMPTZ
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_music_uploads_status ON public.music_uploads(upload_status);
CREATE INDEX IF NOT EXISTS idx_music_licenses_track ON public.music_licenses(track_id);

-- 2. ADMIN RPC FUNCTIONS
CREATE OR REPLACE FUNCTION admin_add_platform_music(
    p_title TEXT,
    p_artist_name TEXT,
    p_audio_url TEXT,
    p_duration INTEGER,
    p_genre TEXT DEFAULT NULL,
    p_album_art_url TEXT DEFAULT NULL,
    p_album_name TEXT DEFAULT NULL,
    p_isrc_code TEXT DEFAULT NULL,
    p_upc_code TEXT DEFAULT NULL,
    p_royalty_rate NUMERIC DEFAULT 0,
    p_license_type TEXT DEFAULT 'platform_owned'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_track_id UUID;
    v_admin_id UUID;
BEGIN
    v_admin_id := auth.uid();
    
    INSERT INTO public.music_tracks (
        title, artist_name, audio_url, duration, genre, album_art_url,
        album_name, license_type, source, royalty_rate, is_royalty_free,
        requires_attribution, is_active, metadata
    ) VALUES (
        p_title, p_artist_name, p_audio_url, p_duration, p_genre, p_album_art_url,
        p_album_name, p_license_type, 'platform_upload', p_royalty_rate,
        CASE WHEN p_royalty_rate = 0 THEN true ELSE false END,
        true, true,
        jsonb_build_object(
            'isrc', p_isrc_code,
            'upc', p_upc_code,
            'added_by', v_admin_id,
            'added_at', NOW()
        )
    ) RETURNING id INTO v_track_id;
    
    INSERT INTO public.music_uploads (
        uploaded_by, upload_status, processed_at, metadata
    ) VALUES (
        v_admin_id, 'completed', NOW(),
        jsonb_build_object('track_id', v_track_id, 'title', p_title, 'artist', p_artist_name)
    );
    
    RETURN v_track_id;
END;
$$;

-- 2.1 UPDATE MUSIC METADATA
CREATE OR REPLACE FUNCTION admin_update_music(
    p_track_id UUID,
    p_title TEXT DEFAULT NULL,
    p_artist_name TEXT DEFAULT NULL,
    p_genre TEXT DEFAULT NULL,
    p_album_art_url TEXT DEFAULT NULL,
    p_is_active BOOLEAN DEFAULT NULL,
    p_is_trending BOOLEAN DEFAULT NULL,
    p_is_featured BOOLEAN DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    UPDATE public.music_tracks
    SET 
        title = COALESCE(p_title, title),
        artist_name = COALESCE(p_artist_name, artist_name),
        genre = COALESCE(p_genre, genre),
        album_art_url = COALESCE(p_album_art_url, album_art_url),
        is_active = COALESCE(p_is_active, is_active),
        is_trending = COALESCE(p_is_trending, is_trending),
        is_featured = COALESCE(p_is_featured, is_featured),
        updated_at = NOW()
    WHERE id = p_track_id;
    
    RETURN FOUND;
END;
$$;

-- 2.2 REMOVE MUSIC TRACK
CREATE OR REPLACE FUNCTION admin_remove_music(
    p_track_id UUID,
    p_hard_delete BOOLEAN DEFAULT false
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF p_hard_delete THEN
        DELETE FROM public.music_tracks WHERE id = p_track_id;
    ELSE
        UPDATE public.music_tracks 
        SET is_active = false, 
            metadata = metadata || jsonb_build_object('deactivated_at', NOW())
        WHERE id = p_track_id;
    END IF;
    
    RETURN FOUND;
END;
$$;

-- 2.3 ADD LICENSE TO TRACK
CREATE OR REPLACE FUNCTION admin_add_license(
    p_track_id UUID,
    p_license_type TEXT,
    p_license_provider TEXT,
    p_territory TEXT[] DEFAULT '{worldwide}',
    p_start_date DATE DEFAULT CURRENT_DATE,
    p_end_date DATE DEFAULT NULL,
    p_royalty_rate NUMERIC DEFAULT 0.70,
    p_contract_number TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_license_id UUID;
BEGIN
    INSERT INTO public.music_licenses (
        track_id, license_type, license_provider, territory,
        start_date, end_date, royalty_rate, contract_number,
        signed_by, signed_at
    ) VALUES (
        p_track_id, p_license_type, p_license_provider, p_territory,
        p_start_date, p_end_date, p_royalty_rate, p_contract_number,
        auth.uid(), NOW()
    ) RETURNING id INTO v_license_id;
    
    -- Update track license info
    UPDATE public.music_tracks
    SET license_type = p_license_type,
        royalty_rate = p_royalty_rate,
        updated_at = NOW()
    WHERE id = p_track_id;
    
    RETURN v_license_id;
END;
$$;

-- 2.4 BULK IMPORT MUSIC
CREATE OR REPLACE FUNCTION admin_bulk_import_music(
    p_import_name TEXT,
    p_tracks_data JSONB,
    p_import_source TEXT DEFAULT 'api'
)
RETURNS TABLE(
    total_tracks INTEGER,
    successful INTEGER,
    failed INTEGER,
    import_id UUID
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_import_id UUID;
    v_track JSONB;
    v_successful INTEGER := 0;
    v_failed INTEGER := 0;
    v_total INTEGER := jsonb_array_length(p_tracks_data);
BEGIN
    INSERT INTO public.music_catalog_imports (
        import_name, import_source, total_tracks, import_status, imported_by
    ) VALUES (
        p_import_name, p_import_source, v_total, 'processing', auth.uid()
    ) RETURNING id INTO v_import_id;
    
    FOR v_track IN SELECT * FROM jsonb_array_elements(p_tracks_data)
    LOOP
        BEGIN
            PERFORM admin_add_platform_music(
                v_track->>'title',
                v_track->>'artist_name',
                v_track->>'audio_url',
                (v_track->>'duration')::INTEGER,
                v_track->>'genre',
                v_track->>'album_art_url',
                v_track->>'album_name',
                v_track->>'isrc_code',
                v_track->>'upc_code',
                COALESCE((v_track->>'royalty_rate')::NUMERIC, 0),
                COALESCE(v_track->>'license_type', 'platform_owned')
            );
            v_successful := v_successful + 1;
        EXCEPTION WHEN OTHERS THEN
            v_failed := v_failed + 1;
            INSERT INTO public.music_uploads (
                uploaded_by, upload_status, error_message, metadata
            ) VALUES (
                auth.uid(), 'failed', SQLERRM,
                jsonb_build_object('track_data', v_track, 'import_id', v_import_id)
            );
        END;
    END LOOP;
    
    UPDATE public.music_catalog_imports
    SET successful_imports = v_successful,
        failed_imports = v_failed,
        import_status = 'completed',
        completed_at = NOW()
    WHERE id = v_import_id;
    
    RETURN QUERY SELECT v_total, v_successful, v_failed, v_import_id;
END;
$$;

-- 3. STORAGE BUCKET SETUP
-- Note: Requires storage schema access. Handled via standard SQL in Supabase.
INSERT INTO storage.buckets (id, name, public) 
VALUES ('music', 'music', true)
ON CONFLICT (id) DO NOTHING;

-- RLS for Storage
CREATE POLICY "Allow public music read access" ON storage.objects
  FOR SELECT USING (bucket_id = 'music');

CREATE POLICY "Allow authenticated music upload" ON storage.objects
  FOR INSERT WITH CHECK (bucket_id = 'music' AND auth.role() = 'authenticated');
