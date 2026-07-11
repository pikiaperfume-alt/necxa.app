-- ================================================================
-- MIGRATION: Coin Purchase & Credit Logic
-- Goal: Create atomic functions for all coin acquisition paths.
-- ================================================================

--
-- Function 1: credit_ncx
-- Universal function to add coins to a wallet. Used by external payment
-- providers like Pesapal after a successful transaction.
--
create or replace function public.credit_ncx(
  p_user_auth_id uuid,
  p_amount_ncx bigint,
  p_transaction_type text, -- e.g., 'COIN_PURCHASE_PESAPAL'
  p_fiat_amount bigint,
  p_fiat_currency text,
  p_reference_id text,
  p_reference_type text,
  p_metadata jsonb
)
returns bigint language plpgsql security definer as $$
declare
  v_wallet public.wallets%rowtype;
  new_balance bigint;
begin
  -- 1. Get wallet and lock the row for the transaction
  select * into v_wallet from public.wallets where user_id = p_user_auth_id for update;

  if not found then
    raise exception 'Wallet not found for user %', p_user_auth_id;
  end if;

  -- 2. Calculate new balance
  new_balance := v_wallet.coin_balance + p_amount_ncx;

  -- 3. Credit coins to the wallet
  update public.wallets
  set coin_balance = new_balance, updated_at = now()
  where id = v_wallet.id;

  -- 4. Record the transaction in the single, cryptographically-chained ledger.
  -- This corrects the previous implementation which wrote to the wrong ledger table.
  insert into public.immutable_financial_ledger (user_id, entry_type, amount, currency, direction, balance_after, reference_id, metadata)
  values (
    p_user_auth_id,
    p_transaction_type,
    p_amount_ncx, -- Positive amount for credit
    'NCX',
    'in',
    new_balance,
    null, -- reference_id is UUID, p_reference_id is TEXT. Storing in metadata is safer.
    jsonb_build_object(
      'description', 'Purchased ' || p_amount_ncx || ' NCX coins',
      'fiat_amount', p_fiat_amount,
      'fiat_currency', p_fiat_currency,
      'reference_id_text', p_reference_id,
      'reference_type', p_reference_type
    ) || coalesce(p_metadata, '{}'::jsonb)
  );

  -- 5. Return the new coin balance
  return new_balance;
end;
$$;

--
-- Function 2: buy_coins_with_fiat_balance
-- Handles internal conversion from a user's fiat balance to coin balance.
--
create or replace function public.buy_coins_with_fiat_balance(
  p_user_auth_id uuid,
  p_fiat_amount_to_spend bigint,
  p_ncx_to_receive bigint,
  p_fiat_currency text
)
returns bigint language plpgsql security definer as $$
declare
  v_wallet public.wallets%rowtype;
  new_fiat_balance bigint;
  new_coin_balance bigint;
begin
  -- 1. Get wallet and lock the row
  select * into v_wallet from public.wallets where user_id = p_user_auth_id for update;

  if not found then
    raise exception 'Wallet not found for user %', p_user_auth_id;
  end if;

  -- 2. Check fiat balance
  if v_wallet.fiat_balance < p_fiat_amount_to_spend then
    raise exception 'Insufficient Fiat balance. Have: %, Need: %', v_wallet.fiat_balance, p_fiat_amount_to_spend;
  end if;

  -- 3. Atomically debit fiat and credit coins
  update public.wallets
  set
    fiat_balance = fiat_balance - p_fiat_amount_to_spend,
    coin_balance = coin_balance + p_ncx_to_receive,
    updated_at = now()
  where id = v_wallet.id
  returning fiat_balance, coin_balance into new_fiat_balance, new_coin_balance;

  -- 4. Record both sides of the internal transfer in the unified immutable ledger.
  insert into public.immutable_financial_ledger (user_id, entry_type, amount, currency, direction, balance_after, metadata)
  values
    (
      p_user_auth_id,
      'WALLET_DEPOSIT', -- Using WALLET_DEPOSIT with 'out' direction for the debit side.
      p_fiat_amount_to_spend,
      p_fiat_currency,
      'out',
      new_fiat_balance,
      jsonb_build_object('description', 'Converted ' || p_fiat_amount_to_spend || ' ' || p_fiat_currency || ' to NCX')
    ),
    (
      p_user_auth_id,
      'COIN_PURCHASE',
      p_ncx_to_receive,
      'NCX',
      'in',
      new_coin_balance,
      jsonb_build_object('description', 'Received ' || p_ncx_to_receive || ' NCX from ' || p_fiat_currency || ' balance')
    );

  -- 5. Return the new coin balance
  return new_coin_balance;
end;
$$;