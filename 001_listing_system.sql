-- ================================================================
-- NECXA LISTING SYSTEM — COMPLETE SUPABASE MIGRATION
-- East Africa Neural Grid
-- Run this in Supabase SQL Editor
-- ================================================================

create extension if not exists "pgcrypto";
create extension if not exists "pg_trgm";
create extension if not exists "unaccent";

-- ═══════════════════════════════════════════════════════════════
-- ENUMS
-- ═══════════════════════════════════════════════════════════════

do $$ begin
  create type property_type as enum (
    'APARTMENT','HOUSE','VILLA','COMMERCIAL','TOWNHOUSE','TRAVELER_SUITE','CAMP_SITE'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type listing_purpose as enum ('SALE','RENT','SHORT_STAY');
exception when duplicate_object then null; end $$;

do $$ begin
  create type listing_status as enum (
    'DRAFT','PENDING_VERIFICATION','ACTIVE','SUSPENDED','SOLD_RENTED',
    'EXPIRED','HONEYPOT','HIGH_RISK'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type titan_trust as enum ('TITAN_TRUST','VERIFIED','LIMITED','SHADOW_GRID');
exception when duplicate_object then null; end $$;

do $$ begin
  create type id_doc_type as enum ('NATIONAL_ID','PASSPORT','DRIVING_PERMIT','RESIDENCE_PERMIT');
exception when duplicate_object then null; end $$;

do $$ begin
  create type ea_country as enum ('UGANDA','KENYA','TANZANIA','RWANDA','ETHIOPIA','OTHER');
exception when duplicate_object then null; end $$;

do $$ begin
  create type agent_doc_type as enum (
    'BUSINESS_LICENSE','TAX_ID','AGENCY_PERMIT','LEAD_AGENT_ID'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type unlock_status as enum ('PENDING','COMPLETED','REFUNDED');
exception when duplicate_object then null; end $$;

do $$ begin
  create type reserve_status as enum ('PENDING','ACTIVE','RELEASED','FORFEITED','COMPLETED');
exception when duplicate_object then null; end $$;

do $$ begin
  create type payment_method as enum ('MTN_MOMO','AIRTEL_MONEY','NCX_COINS','VISA_MASTERCARD');
exception when duplicate_object then null; end $$;


-- ═══════════════════════════════════════════════════════════════
-- AGENTS / USERS
-- ═══════════════════════════════════════════════════════════════

create table if not exists agent_profiles (
  id                  uuid primary key default gen_random_uuid(),
  created_at          timestamptz default now(),
  updated_at          timestamptz default now(),

  auth_user_id        uuid unique references auth.users(id) on delete cascade,

  -- Identity
  full_name           text not null,
  email               text unique not null,
  phone               text,                       -- ← contact number (required)
  whatsapp            text,                       -- ← WhatsApp number
  google_meet_email   text,                       -- ← Google Meet email/link

  -- Verification status
  is_agent            boolean default false,
  agent_verified_at   timestamptz,
  nin                 text unique,                -- National ID Number
  nin_verified        boolean default false,
  face_verified       boolean default false,
  id_doc_type         id_doc_type,
  id_front_photo_path   text,                       -- storage: identity-shards bucket
  id_back_photo_path    text,                       -- storage: identity-shards bucket
  face_photo_path     text,                       -- storage: identity-shards bucket

  -- Trust system
  trust_score         int default 70 check (trust_score between 0 and 100),
  titan_trust_status  titan_trust default 'LIMITED',
  listings_count      int default 0,
  successful_txns     int default 0,

  -- NCX Coins wallet
  ncx_coins_balance   bigint default 0,           -- in smallest unit

  -- Agent commission tracking
  total_commission_earned bigint default 0,       -- UGX

  -- Agent documents (4 required for full agent status)
  business_license_path text,
  tax_id_path           text,
  agency_permit_path    text,
  lead_agent_id_path    text,

  -- Shard metadata
  ea_country          ea_country default 'UGANDA',
  is_active           boolean default true,
  shield_session_id   text                        -- Tracking for NECX Shield SDK
);

-- Auto-provision Agent Profile when User Signs Up
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  insert into public.agent_profiles (auth_user_id, email, full_name)
  values (new.id, new.email, split_part(new.email, '@', 1));
  return new;
end;
$$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ═══════════════════════════════════════════════════════════════
-- IDENTITY SHARDS (Secure, separated from listings)
-- ═══════════════════════════════════════════════════════════════

create table if not exists identity_shards (
  id                  uuid primary key default gen_random_uuid(),
  created_at          timestamptz default now(),

  agent_id            uuid not null references agent_profiles(id) on delete cascade,

  -- Identity document
  doc_type            id_doc_type not null,
  doc_number          text,                       -- NIN / Passport number
  country             ea_country not null,

  -- AI verification results
  id_front_photo_path  text not null,              -- storage: identity-shards bucket (private)
  id_back_photo_path   text not null,
  face_photo_path     text not null,
  face_match_score    float,                      -- 0-1 from Gemini Vision
  ai_verified         boolean default false,
  ai_notes            text,
  fraud_risk          text default 'unknown',     -- low / medium / high

  -- Timestamp
  verified_at         timestamptz
);

-- ═══════════════════════════════════════════════════════════════
-- UTILITY SHARDS (Physical property anchors)
-- ═══════════════════════════════════════════════════════════════

create table if not exists utility_shards (
  id                      uuid primary key default gen_random_uuid(),
  created_at              timestamptz default now(),

  agent_id                uuid not null references agent_profiles(id),
  listing_id              uuid,                   -- linked after listing created

  -- Uganda specific
  umeme_meter_number      text,                   -- 11-digit Yaka meter
  umeme_owner_name        text,                   -- returned from Umeme ping
  umeme_zone              text,
  umeme_verified          boolean default false,

  nwsc_account_number     text,                   -- National Water
  nwsc_verified           boolean default false,

  -- Kenya specific
  kplc_meter_number       text,
  water_company_account   text,

  -- Tanzania specific
  tanesco_meter_number    text,
  dawasa_account          text,

  -- Land title (all countries)
  land_block              text,
  land_plot               text,
  land_title_photo_path   text,                   -- storage: utility-shards (private)

  -- Local authority stamp
  lc1_stamp_photo_path    text,                   -- LC1 / Chief / Ward Officer stamp
  lc1_officer_name        text,
  lc1_verified            boolean default false,

  -- Business license (commercial properties)
  business_license_number text,

  -- Overall shard status
  shard_complete          boolean default false,
  verified_at             timestamptz,
  shield_session_id       text                        -- Tracking for NECX Shield SDK
);

-- ═══════════════════════════════════════════════════════════════
-- GPS NODES
-- ═══════════════════════════════════════════════════════════════

create table if not exists gps_nodes (
  id              uuid primary key default gen_random_uuid(),
  created_at      timestamptz default now(),

  agent_id        uuid not null references agent_profiles(id),
  listing_id      uuid,

  -- Coordinates captured at listing time
  latitude        double precision not null,
  longitude       double precision not null,
  accuracy_meters float,
  altitude        float,

  -- Reported vs captured comparison
  reported_address    text,
  reported_district   text,
  coordinate_match    boolean,                -- true if within acceptable radius
  distance_delta_km   float,                 -- km between reported and actual

  -- Risk assessment
  risk_flag       boolean default false,
  risk_reason     text,

  captured_at     timestamptz default now()
);

-- ═══════════════════════════════════════════════════════════════
-- LISTINGS (Property Shard — public marketplace)
-- ═══════════════════════════════════════════════════════════════

create table if not exists listings (
  id                  uuid primary key default gen_random_uuid(),
  created_at          timestamptz default now(),
  updated_at          timestamptz default now(),
  published_at        timestamptz,

  -- Ownership
  agent_id            uuid not null references agent_profiles(id),
  seller_id           uuid references agent_profiles(id),

  -- Verification shard links
  identity_shard_id   uuid references identity_shards(id),
  utility_shard_id    uuid references utility_shards(id),
  gps_node_id         uuid references gps_nodes(id),

  -- Agent contact details (unlocked with property details)
  agent_phone         text,                   -- ← contact number
  agent_whatsapp      text,                   -- ← WhatsApp link
  agent_google_meet   text,                   -- ← Google Meet email/link
  agent_email         text,

  -- Property basics
  title               text not null,
  description         text,
  property_type       property_type not null,
  purpose             listing_purpose not null,
  country             ea_country default 'UGANDA',
  district            text not null,
  address             text,                   -- HIDDEN until unlocked
  full_address_locked text,                   -- stored encrypted, revealed on unlock

  -- GPS (exact pin — hidden until unlocked)
  gps_lat             double precision,
  gps_lng             double precision,
  gps_display_lat     double precision,       -- slightly fuzzy public version
  gps_display_lng     double precision,

  -- Property specs
  price_ugx           bigint not null,        -- monthly rent or sale price
  price_period        text default '/month',  -- /month /night or blank
  bedrooms            int default 0,
  bathrooms           int default 1,
  sqft                int,
  floor_level         int,
  total_floors        int,
  is_furnished        boolean default false,
  amenities           text[] default '{}',

  -- Utility anchors summary (public trust signals)
  has_electricity     boolean default false,
  has_water           boolean default false,
  has_land_title      boolean default false,
  has_lc1_stamp       boolean default false,

  -- Media
  photos              text[] default '{}',    -- storage paths (public bucket)
  bathroom_photos     text[] default '{}',    -- mandatory bathroom shots
  lc1_stamp_photo     text,                   -- authority stamp photo
  video_path          text,

  -- Verification status
  status              listing_status default 'PENDING_VERIFICATION',
  titan_trust_status  titan_trust default 'LIMITED',
  is_ai_verified      boolean default false,
  ai_score            float,                  -- 0-1 overall trust score
  ai_notes            jsonb,

  -- Economics
  unlock_cost_ugx     bigint,                -- 10% of price_ugx auto-calculated
  unlock_cost_ncx     bigint,                -- in NCX coins
  unlock_count        int default 0,
  view_count          bigint default 0,
  save_count          int default 0,
  reserve_count       int default 0,

  -- MINT event tracking
  minted_at           timestamptz,           -- when listing entered the ledger
  mint_event_id       text,                  -- unique asset ID on grid

  -- Moderation
  honeypot_flagged    boolean default false,
  fraud_flags         text[] default '{}'
);

-- ═══════════════════════════════════════════════════════════════
-- LISTING PHOTOS (detailed media records)
-- ═══════════════════════════════════════════════════════════════

create table if not exists listing_photos (
  id              uuid primary key default gen_random_uuid(),
  created_at      timestamptz default now(),
  listing_id      uuid not null references listings(id) on delete cascade,
  storage_path    text not null,
  photo_category  text default 'EXTERIOR',    -- EXTERIOR INTERIOR BATHROOM AUTHORITY_STAMP
  is_primary      boolean default false,
  sort_order      int default 0,
  ai_analyzed     boolean default false,
  ai_description  text                         -- Gemini Vision description
);

-- ═══════════════════════════════════════════════════════════════
-- UNLOCKS (10% coordination logic)
-- ═══════════════════════════════════════════════════════════════

create table if not exists listing_unlocks (
  id                  uuid primary key default gen_random_uuid(),
  created_at          timestamptz default now(),

  listing_id          uuid not null references listings(id),
  buyer_agent_id      uuid references agent_profiles(id),
  buyer_email         text not null,
  buyer_phone         text,

  -- Payment
  amount_ugx          bigint not null,           -- 10% of listing price
  amount_ncx          bigint,
  payment_method      payment_method not null,
  payment_ref         text,
  payment_status      unlock_status default 'PENDING',

  -- What was revealed
  revealed_address    text,
  revealed_gps_lat    double precision,
  revealed_gps_lng    double precision,
  revealed_phone      text,
  revealed_whatsapp   text,
  revealed_meet       text,
  revealed_email      text,

  unlocked_at         timestamptz
);

-- ═══════════════════════════════════════════════════════════════
-- RESERVATIONS (10% escrow deposit)
-- ═══════════════════════════════════════════════════════════════

create table if not exists listing_reservations (
  id                  uuid primary key default gen_random_uuid(),
  created_at          timestamptz default now(),

  listing_id          uuid not null references listings(id),
  buyer_agent_id      uuid references agent_profiles(id),
  buyer_email         text not null,

  -- Escrow (10% of listing price)
  deposit_ugx         bigint not null,
  payment_method      payment_method not null,
  payment_ref         text,
  status              reserve_status default 'PENDING',

  -- Reservation window
  reserved_from       timestamptz,
  reserved_until      timestamptz,              -- typically 7-30 days
  released_at         timestamptz,
  release_reason      text
);

-- ═══════════════════════════════════════════════════════════════
-- TRUST SCORE LEDGER
-- ═══════════════════════════════════════════════════════════════

create table if not exists trust_score_events (
  id              uuid primary key default gen_random_uuid(),
  created_at      timestamptz default now(),

  agent_id        uuid not null references agent_profiles(id),
  event_type      text not null,
  score_delta     int not null,               -- positive or negative
  score_before    int not null,
  score_after     int not null,
  reason          text,
  ref_id          uuid                        -- listing_id, unlock_id etc
);

-- ═══════════════════════════════════════════════════════════════
-- NCX COINS LEDGER
-- ═══════════════════════════════════════════════════════════════

create table if not exists ncx_ledger (
  id              uuid primary key default gen_random_uuid(),
  created_at      timestamptz default now(),

  agent_id        uuid not null references agent_profiles(id),
  event_type      text not null,              -- MINT UNLOCK REWARD COMMISSION SLASH
  amount          bigint not null,            -- positive = credit, negative = debit
  balance_after   bigint not null,
  ref_id          uuid,
  notes           text
);

-- ═══════════════════════════════════════════════════════════════
-- MINT EVENTS (every verified listing is a minted asset)
-- ═══════════════════════════════════════════════════════════════

create table if not exists mint_events (
  id              uuid primary key default gen_random_uuid(),
  created_at      timestamptz default now(),

  listing_id      uuid not null references listings(id),
  agent_id        uuid not null references agent_profiles(id),
  mint_event_id   text unique not null,       -- e.g. NECXA-UG-2024-000001
  asset_hash      text,                       -- cryptographic fingerprint
  circulating_supply_after bigint
);

-- ═══════════════════════════════════════════════════════════════
-- HONEYPOT LOG
-- ═══════════════════════════════════════════════════════════════

create table if not exists honeypot_log (
  id              uuid primary key default gen_random_uuid(),
  created_at      timestamptz default now(),

  agent_id        uuid references agent_profiles(id),
  listing_id      uuid references listings(id),
  trigger_reason  text not null,
  fraud_patterns  jsonb,
  ip_address      text,
  device_info     jsonb,
  resolved        boolean default false
);

-- ═══════════════════════════════════════════════════════════════
-- AI SEARCH LOG
-- ═══════════════════════════════════════════════════════════════

create table if not exists search_log (
  id              uuid primary key default gen_random_uuid(),
  created_at      timestamptz default now(),

  searcher_id     uuid references agent_profiles(id),
  query           text,
  filters         jsonb,
  result_count    int,
  result_ids      uuid[]
);

-- ═══════════════════════════════════════════════════════════════
-- DISPUTES
-- ═══════════════════════════════════════════════════════════════

create table if not exists disputes (
  id              uuid primary key default gen_random_uuid(),
  created_at      timestamptz default now(),
  resolved_at     timestamptz,

  listing_id      uuid references listings(id),
  complainant_id  uuid not null references agent_profiles(id),
  respondent_id   uuid references agent_profiles(id),
  nature          text not null,
  evidence_paths  text[],
  resolution      text,
  favor_of        text                        -- 'complainant' | 'respondent' | 'inconclusive'
);

-- ═══════════════════════════════════════════════════════════════
-- TRIGGERS & FUNCTIONS
-- ═══════════════════════════════════════════════════════════════

-- Auto update_at
create or replace function set_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end; $$;

create or replace trigger listings_updated_at
  before update on listings for each row execute function set_updated_at();
create or replace trigger agents_updated_at
  before update on agent_profiles for each row execute function set_updated_at();

-- Auto-calculate unlock cost (10% of listing price)
create or replace function calc_unlock_cost()
returns trigger language plpgsql as $$
begin
  new.unlock_cost_ugx = round(new.price_ugx * 0.10);
  new.unlock_cost_ncx = round(new.price_ugx * 0.10 / 100); -- conversion rate
  return new;
end; $$;

create or replace trigger listings_unlock_cost
  before insert on listings for each row execute function calc_unlock_cost();

-- Update trust score status based on score value
create or replace function update_titan_status()
returns trigger language plpgsql as $$
begin
  if new.trust_score >= 90 then
    new.titan_trust_status = 'TITAN_TRUST';
  elsif new.trust_score >= 70 then
    new.titan_trust_status = 'VERIFIED';
  elsif new.trust_score >= 50 then
    new.titan_trust_status = 'LIMITED';
  else
    new.titan_trust_status = 'SHADOW_GRID';
  end if;
  return new;
end; $$;

create or replace trigger agent_titan_status
  before insert or update on agent_profiles
  for each row execute function update_titan_status();

-- On trust score event: update agent score + log
create or replace function apply_trust_event()
returns trigger language plpgsql security definer as $$
declare v_agent agent_profiles%rowtype;
begin
  select * into v_agent from agent_profiles where id = new.agent_id;
  new.score_before  = v_agent.trust_score;
  new.score_after   = greatest(0, least(100, v_agent.trust_score + new.score_delta));
  update agent_profiles set trust_score = new.score_after where id = new.agent_id;
  return new;
end; $$;

create or replace trigger trust_event_apply
  before insert on trust_score_events
  for each row execute function apply_trust_event();

-- Auto-mint on listing activation
create or replace function auto_mint_listing()
returns trigger language plpgsql security definer as $$
declare
  v_seq     bigint;
  v_mint_id text;
begin
  if new.status = 'ACTIVE' and old.status != 'ACTIVE' then
    select coalesce(max(circulating_supply_after), 0) + 1
    into v_seq from mint_events;
    v_mint_id = 'NECXA-' || upper(new.country::text) || '-' || to_char(now(),'YYYY') || '-' || lpad(v_seq::text, 6, '0');
    new.minted_at    = now();
    new.mint_event_id = v_mint_id;
    insert into mint_events (listing_id, agent_id, mint_event_id, circulating_supply_after)
    values (new.id, new.agent_id, v_mint_id, v_seq);
    -- Award +3 trust score
    insert into trust_score_events (agent_id, event_type, score_delta, score_before, score_after, reason, ref_id)
    values (new.agent_id, 'LISTING_VERIFIED', 3, 0, 0, 'Completed verified listing', new.id);
  end if;
  return new;
end; $$;

create or replace trigger listing_mint_trigger
  before update on listings
  for each row execute function auto_mint_listing();

-- Increment view count
create or replace function increment_listing_view(p_listing_id uuid)
returns void language plpgsql security definer as $$
begin
  update listings set view_count = view_count + 1 where id = p_listing_id;
end; $$;

-- Deduct NCX coins
create or replace function deduct_ncx(p_agent_id uuid, p_amount bigint)
returns void language plpgsql security definer as $$
begin
  if (select ncx_coins_balance from agent_profiles where id = p_agent_id) < p_amount then
    raise exception 'Insufficient NCX balance';
  end if;
  update agent_profiles set ncx_coins_balance = ncx_coins_balance - p_amount where id = p_agent_id;
end; $$;

-- ═══════════════════════════════════════════════════════════════
-- ROW LEVEL SECURITY
-- ═══════════════════════════════════════════════════════════════

alter table agent_profiles         enable row level security;
alter table identity_shards        enable row level security;
alter table utility_shards         enable row level security;
alter table gps_nodes              enable row level security;
alter table listings               enable row level security;
alter table listing_photos         enable row level security;
alter table listing_unlocks        enable row level security;
alter table listing_reservations   enable row level security;
alter table trust_score_events     enable row level security;
alter table ncx_ledger             enable row level security;
alter table mint_events            enable row level security;
alter table honeypot_log           enable row level security;
alter table disputes               enable row level security;
alter table search_log             enable row level security;

-- Public: read ACTIVE listings (without locked fields)
create policy "public_read_active_listings"
  on listings for select
  using (status = 'ACTIVE' and honeypot_flagged = false);

-- Agents manage own listings
create policy "agents_manage_own_listings"
  on listings for all
  using (agent_id = (select id from agent_profiles where auth_user_id = auth.uid()))
  with check (agent_id = (select id from agent_profiles where auth_user_id = auth.uid()));

-- Public can read listing photos
create policy "public_read_photos"
  on listing_photos for select using (true);

-- Agents manage own profile
create policy "agents_own_profile"
  on agent_profiles for all
  using (auth_user_id = auth.uid())
  with check (auth_user_id = auth.uid());

-- Identity shards: owner only + service role
create policy "identity_shard_owner"
  on identity_shards for all
  using (agent_id = (select id from agent_profiles where auth_user_id = auth.uid()));

-- Unlocks: buyer sees own unlocks
create policy "buyer_own_unlocks"
  on listing_unlocks for select
  using (buyer_email = (select email from agent_profiles where auth_user_id = auth.uid()));

-- Trust events: own only
create policy "own_trust_events"
  on trust_score_events for select
  using (agent_id = (select id from agent_profiles where auth_user_id = auth.uid()));

-- ═══════════════════════════════════════════════════════════════
-- INDEXES
-- ═══════════════════════════════════════════════════════════════

create index if not exists idx_listings_status      on listings(status);
create index if not exists idx_listings_type        on listings(property_type);
create index if not exists idx_listings_purpose     on listings(purpose);
create index if not exists idx_listings_country     on listings(country);
create index if not exists idx_listings_district    on listings(district);
create index if not exists idx_listings_agent       on listings(agent_id);
create index if not exists idx_listings_price       on listings(price_ugx);
create index if not exists idx_listings_titan       on listings(titan_trust_status);
create index if not exists idx_listings_honeypot    on listings(honeypot_flagged);
create index if not exists idx_listings_fulltext    on listings using gin(
  to_tsvector('english', coalesce(title,'') || ' ' || coalesce(description,'') || ' ' || coalesce(district,''))
);
create index if not exists idx_unlocks_listing      on listing_unlocks(listing_id);
create index if not exists idx_unlocks_buyer        on listing_unlocks(buyer_email);
create index if not exists idx_trust_agent          on trust_score_events(agent_id, created_at desc);
create index if not exists idx_mint_listing         on mint_events(listing_id);
create index if not exists idx_agent_trust          on agent_profiles(trust_score desc);

-- ═══════════════════════════════════════════════════════════════
-- USEFUL VIEWS
-- ═══════════════════════════════════════════════════════════════

-- Active listings with agent contact (for unlocked buyers)
create or replace view v_active_listings as
select
  l.id, l.title, l.description, l.property_type, l.purpose,
  l.country, l.district, l.price_ugx, l.price_period,
  l.bedrooms, l.bathrooms, l.sqft, l.is_furnished, l.amenities,
  l.photos, l.bathroom_photos,
  l.has_electricity, l.has_water, l.has_land_title, l.has_lc1_stamp,
  l.gps_display_lat, l.gps_display_lng,
  l.titan_trust_status, l.is_ai_verified, l.ai_score,
  l.unlock_cost_ugx, l.unlock_cost_ncx,
  l.view_count, l.save_count, l.unlock_count,
  l.published_at,
  -- Agent public info
  a.full_name as agent_name,
  a.trust_score as agent_trust_score,
  a.titan_trust_status as agent_titan_status,
  a.is_agent,
  -- Hidden fields (NULL for unverified viewers, real values after unlock)
  null::text as revealed_address,
  null::double precision as revealed_lat,
  null::double precision as revealed_lng,
  null::text as revealed_phone,
  null::text as revealed_whatsapp,
  null::text as revealed_meet
from listings l
join agent_profiles a on a.id = l.agent_id
where l.status = 'ACTIVE' and l.honeypot_flagged = false;

-- Platform revenue summary
create or replace view v_platform_revenue as
select
  date_trunc('day', created_at) as day,
  count(*) as unlocks,
  sum(amount_ugx) as total_ugx,
  sum(amount_ugx * 0.10) as necxa_2pct_fee,
  sum(amount_ugx * 0.50) as agent_5pct_fee
from listing_unlocks
where payment_status = 'COMPLETED'
group by 1
order by 1 desc;

-- ═══════════════════════════════════════════════════════════════
-- SEED: Gift catalogue + NCX conversion rate
-- ═══════════════════════════════════════════════════════════════

create table if not exists platform_config (
  key   text primary key,
  value text not null,
  notes text
);

insert into platform_config (key, value, notes) values
  ('ncx_ugx_rate',     '100',   'NCX coins per UGX 100'),
  ('unlock_pct',       '0.10',  'Unlock fee = 10% of listing price'),
  ('reserve_pct',      '0.10',  'Reservation deposit = 10% of listing price'),
  ('agent_commission', '0.05',  '5% of sale price to agent'),
  ('necxa_commission', '0.02',  '2% of sale price to NECXA platform'),
  ('trust_score_base', '70',    'Starting trust score for new agents'),
  ('titan_threshold',  '90',    'Minimum score for Titan Trust'),
  ('shadow_threshold', '50',    'Below this = Shadow Grid')
on conflict (key) do update set value = excluded.value;
