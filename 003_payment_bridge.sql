-- Safely clean up existing mock objects if they exist
drop view if exists payments cascade;
drop table if exists payments cascade;

-- bridge to satisfy the frontend polling requirements
-- mapping listing_unlocks to a "payments" view
create view payments as
select 
  id,
  created_at,
  listing_id,
  buyer_phone,
  amount_ugx as amount,
  payment_method,
  payment_status as status,
  payment_ref as provider_reference
from listing_unlocks;

-- Ensure necessary columns exist for the orchestration layer
do $$
begin
  if not exists (select 1 from information_schema.columns where table_name = 'listing_unlocks' and column_name = 'provider_id') then
    alter table listing_unlocks add column provider_id text;
  end if;
end $$;
