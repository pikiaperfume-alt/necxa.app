-- ================================================================
-- MIGRATION: Unified Gifting Logic
-- Goal: Create a single, atomic function to handle all social gifting.
-- NOTE: This requires a wallet to exist for the platform revenue account.
-- e.g., INSERT INTO wallets (user_id, ...) VALUES ('00000000-0000-0000-0000-000000000001', ...);
-- ================================================================

create or replace function public.process_gift_ncx(
  p_sender_auth_id uuid,
  p_receiver_auth_id uuid,
  p_post_id uuid,
  p_ncx_amount bigint,
  p_gift_platform_fee_rate float, -- e.g., 0.20 for 20%
  p_gift_details jsonb -- { "gift_item_id": "rose", "is_anonymous": false, "context_note": "Great post!" }
)
returns table (
  success boolean,
  message text,
  platform_fee_paid bigint,
  receiver_amount_credited bigint
) language plpgsql security definer as $$
declare
  v_sender_wallet public.wallets%rowtype;
  v_receiver_wallet public.wallets%rowtype;
  v_platform_revenue_wallet public.wallets%rowtype;
  v_platform_wallet_user_id uuid := '00000000-0000-0000-0000-000000000001'; -- Platform's dedicated user_id

  v_platform_fee_ncx bigint;
  v_receiver_ncx bigint;

  v_sender_new_balance bigint;
  v_receiver_new_balance bigint;
  v_platform_new_balance bigint;

  v_gift_id uuid;
begin
  -- 1. Input Validation & Fee Split
  if p_ncx_amount <= 0 then return query select false, 'Gift amount must be positive.', 0::bigint, 0::bigint; return; end if;
  if p_sender_auth_id = p_receiver_auth_id then return query select false, 'Cannot send a gift to yourself.', 0::bigint, 0::bigint; return; end if;
  v_platform_fee_ncx := floor(p_ncx_amount * p_gift_platform_fee_rate);
  v_receiver_ncx := p_ncx_amount - v_platform_fee_ncx;

  -- 2. Lock wallet rows in a consistent order to prevent deadlocks
  select * into v_sender_wallet from public.wallets where user_id = p_sender_auth_id for update;
  select * into v_receiver_wallet from public.wallets where user_id = p_receiver_auth_id for update;
  select * into v_platform_revenue_wallet from public.wallets where user_id = v_platform_wallet_user_id for update;

  -- 3. Check Sender's Balance
  if not found(v_sender_wallet.id) or v_sender_wallet.coin_balance < p_ncx_amount then
    return query select false, 'Insufficient NCX balance.', 0::bigint, 0::bigint;
    return;
  end if;

  -- 4. Perform Atomic Transfers
  update public.wallets set coin_balance = coin_balance - p_ncx_amount, updated_at = now() where id = v_sender_wallet.id returning coin_balance into v_sender_new_balance;
  update public.wallets set coin_balance = coin_balance + v_receiver_ncx, updated_at = now() where id = v_receiver_wallet.id returning coin_balance into v_receiver_new_balance;
  if v_platform_fee_ncx > 0 then
    update public.wallets set coin_balance = coin_balance + v_platform_fee_ncx, updated_at = now() where id = v_platform_revenue_wallet.id returning coin_balance into v_platform_new_balance;
  else
    v_platform_new_balance := v_platform_revenue_wallet.coin_balance;
  end if;

  -- 5. Record Gift in `community_gifts` table
  insert into public.community_gifts (post_id, sender_id, receiver_id, gift_type, coin_amount, creator_fiat_cut, necxa_fiat_fee)
  values (p_post_id, p_sender_auth_id, p_receiver_auth_id, p_gift_details->>'gift_item_id', p_ncx_amount, v_receiver_ncx, v_platform_fee_ncx)
  returning id into v_gift_id;

  -- 6. Record transactions in the immutable ledger
  insert into public.immutable_financial_ledger (user_id, entry_type, amount, currency, direction, balance_after, reference_id, metadata)
  values 
    (p_sender_auth_id, 'GIFT_SENT', p_ncx_amount, 'NCX', 'out', v_sender_new_balance, v_gift_id, jsonb_build_object('receiver_id', p_receiver_auth_id, 'post_id', p_post_id)),
    (p_receiver_auth_id, 'GIFT_RECEIVED', v_receiver_ncx, 'NCX', 'in', v_receiver_new_balance, v_gift_id, jsonb_build_object('sender_id', p_sender_auth_id, 'post_id', p_post_id));

  if v_platform_fee_ncx > 0 then
    insert into public.immutable_financial_ledger (user_id, entry_type, amount, currency, direction, balance_after, reference_id, metadata)
    values (v_platform_wallet_user_id, 'PLATFORM_FEE', v_platform_fee_ncx, 'NCX', 'in', v_platform_new_balance, v_gift_id, jsonb_build_object('source', 'gifting', 'sender_id', p_sender_auth_id, 'receiver_id', p_receiver_auth_id));
  end if;

  -- 7. Return success
  return query select true, 'Gift sent successfully.', v_platform_fee_ncx, v_receiver_ncx;

end;
$$;