-- NECXA FINANCIAL GRID — FINANCIAL IDENTITY & IMMUTABLE LEDGER SYSTEM
-- Enables verified financial profiles for agents/buyers and cryptographically chains all ledger entries.

-- ── 1. USER FINANCIAL IDENTITIES ──────────────────────────────────────────
create table if not exists financial_identities (
  id                  uuid primary key default gen_random_uuid(),
  user_id             uuid not null unique references profiles(id) on delete cascade,
  created_at          timestamptz default now(),
  updated_at          timestamptz default now(),

  -- Mobile Money Details
  mtn_momo_phone      text,
  airtel_money_phone  text,

  -- Bank Payout Details
  bank_name           text,
  bank_account_number text,
  bank_account_name   text,

  -- KYC & Compliance
  tax_id              text, -- Tax Identification Number (TIN)
  kyc_status          text default 'PENDING' check (kyc_status in ('PENDING', 'VERIFIED', 'REJECTED')),
  aml_checked         boolean default false,
  aml_status          text default 'PASSED' check (aml_status in ('PASSED', 'WARNING', 'FAILED')),
  risk_level          text default 'LOW' check (risk_level in ('LOW', 'MEDIUM', 'HIGH')),
  aml_limit_ugx       bigint default 10000000, -- 10M UGX default transaction limit
  verified_at         timestamptz
);

create index if not exists idx_financial_identities_user on financial_identities(user_id);
create index if not exists idx_financial_identities_kyc on financial_identities(kyc_status);

create trigger update_financial_identities_updated_at
  before update on financial_identities
  for each row execute function update_updated_at();

-- ── 2. IMMUTABLE FINANCIAL LEDGER (CRYPTOGRAPHICALLY CHAINED) ───────────────
create table if not exists immutable_financial_ledger (
  id                  uuid primary key default gen_random_uuid(),
  created_at          timestamptz default now(),
  user_id             uuid not null references profiles(id) on delete restrict,
  
  entry_type          text not null check (entry_type in (
    'COIN_PURCHASE',    -- purchase NCX coins
    'WALLET_DEPOSIT',   -- direct fiat deposit into wallet
    'LISTING_UNLOCK',   -- unlock contact details
    'ESCROW_DEPOSIT',   -- reserve property/goods
    'ESCROW_RELEASE',   -- complete deal & pay seller/broker
    'ESCROW_REFUND',    -- return reserved deposit
    'WITHDRAWAL',       -- cash out fiat
    'COMMISSION_PAYOUT',-- agent payout
    'SHOP_PURCHASE',    -- buying goods
    'GIFT_SENT',        -- sending a virtual gift
    'GIFT_RECEIVED',    -- receiving a virtual gift
    'DELIVERY_FEE',     -- logistics/trip fare
    'PLATFORM_FEE'      -- platform revenue cuts
  )),
  
  amount              bigint not null, -- stored in minor units or shillings/coins
  currency            text not null check (currency in ('UGX', 'NCX', 'USD')),
  direction           text not null check (direction in ('in', 'out')),
  balance_after       bigint not null,
  
  previous_id         uuid references immutable_financial_ledger(id),
  hash                text not null unique,
  
  reference_id        uuid, -- e.g. listing_id, reservation_id, unlock_id, etc.
  metadata            jsonb default '{}'::jsonb
);

create index if not exists idx_ledger_user on immutable_financial_ledger(user_id);
create index if not exists idx_ledger_entry_type on immutable_financial_ledger(entry_type);

-- ── 3. IMMUTABILITY RULES (ENFORCE APPEND-ONLY) ───────────────────────────
create or replace function prevent_ledger_modification()
returns trigger as $$
begin
  raise exception 'CRITICAL SECURITY ALERT: Immutable ledger records cannot be modified or deleted.';
end;
$$ language plpgsql;

create trigger tr_prevent_update_ledger
  before update on immutable_financial_ledger
  for each row execute function prevent_ledger_modification();

create trigger tr_prevent_delete_ledger
  before delete on immutable_financial_ledger
  for each row execute function prevent_ledger_modification();

-- ── 4. CRYPTOGRAPHIC CHAINING TRIGGER ─────────────────────────────────────
create or replace function chain_ledger_entry()
returns trigger as $$
declare
  prev_record record;
  prev_hash text;
  raw_payload text;
begin
  -- 1. Fetch the previous ledger entry
  select id, hash into prev_record 
  from immutable_financial_ledger 
  order by created_at desc, id desc 
  limit 1;

  if found then
    new.previous_id := prev_record.id;
    prev_hash := prev_record.hash;
  else
    new.previous_id := null;
    prev_hash := '0000000000000000000000000000000000000000000000000000000000000000'; -- Genesis seed
  end if;

  -- 2. Construct the raw payload for hashing
  -- Format: prev_hash | user_id | entry_type | amount | currency | direction | balance_after | created_at
  raw_payload := concat_ws('|',
    prev_hash,
    new.user_id::text,
    new.entry_type,
    new.amount::text,
    new.currency,
    new.direction,
    new.balance_after::text,
    to_char(new.created_at, 'YYYY-MM-DD HH24:MI:SS.USTZ')
  );

  -- 3. Calculate SHA-256 hash using pgcrypto extension
  new.hash := encode(digest(raw_payload, 'sha256'), 'hex');

  return new;
end;
$$ language plpgsql;

create trigger tr_chain_ledger_entry
  before insert on immutable_financial_ledger
  for each row execute function chain_ledger_entry();

-- ── 5. ROW LEVEL SECURITY (RLS) ──────────────────────────────────────────
alter table financial_identities enable row level security;
alter table immutable_financial_ledger enable row level security;

create policy "Users can view own financial identity"
  on financial_identities for select
  using (auth.uid() = user_id);

create policy "Users can insert own financial identity"
  on financial_identities for insert
  with check (auth.uid() = user_id);

create policy "Users can update own financial identity"
  on financial_identities for update
  using (auth.uid() = user_id);

create policy "Users can view own ledger entries"
  on immutable_financial_ledger for select
  using (auth.uid() = user_id);

-- ── 6. DUAL TRIGGERS FOR SYNCING WALLET & TRANSACTION EVENTS ─────────────

-- Automatically log listing unlocks to the immutable ledger
create or replace function log_unlock_to_ledger()
returns trigger as $$
declare
  v_wallet_balance bigint;
begin
  -- Only log completed unlocks
  if new.payment_status = 'COMPLETED' and (tg_op = 'INSERT' or old.payment_status != 'COMPLETED') then
    -- Fetch current coin balance after unlock
    select coin_balance into v_wallet_balance 
    from wallets 
    where user_id = new.buyer_agent_id;

    insert into immutable_financial_ledger (
      user_id,
      entry_type,
      amount,
      currency,
      direction,
      balance_after,
      reference_id,
      metadata
    ) values (
      new.buyer_agent_id,
      'LISTING_UNLOCK',
      new.amount_ugx,
      'UGX',
      'out',
      coalesce(v_wallet_balance, 0),
      new.id,
      jsonb_build_object(
        'listing_id', new.listing_id,
        'payment_method', new.payment_method,
        'payment_ref', new.payment_ref
      )
    );
  end if;
  return new;
end;
$$ language plpgsql;

create trigger tr_log_unlock_to_ledger
  after insert or update on listing_unlocks
  for each row execute function log_unlock_to_ledger();

-- Automatically log listing reservations (escrow deposits) to the ledger
create or replace function log_reservation_to_ledger()
returns trigger as $$
declare
  v_wallet_balance bigint;
begin
  -- Only log completed escrow reservations
  if new.status = 'COMPLETED' and (tg_op = 'INSERT' or old.status != 'COMPLETED') then
    -- Fetch current fiat balance
    select fiat_balance into v_wallet_balance 
    from wallets 
    where user_id = new.buyer_agent_id;

    insert into immutable_financial_ledger (
      user_id,
      entry_type,
      amount,
      currency,
      direction,
      balance_after,
      reference_id,
      metadata
    ) values (
      new.buyer_agent_id,
      'ESCROW_DEPOSIT',
      new.deposit_ugx,
      'UGX',
      'out',
      coalesce(v_wallet_balance, 0),
      new.id,
      jsonb_build_object(
        'listing_id', new.listing_id,
        'payment_method', new.payment_method,
        'payment_ref', new.payment_ref
      )
    );
  end if;
  return new;
end;
$$ language plpgsql;

create trigger tr_log_reservation_to_ledger
  after insert or update on listing_reservations
  for each row execute function log_reservation_to_ledger();
