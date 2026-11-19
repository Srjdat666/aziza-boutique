-- =====================================================================
-- AZIZA Boutique — Part 4: Stock per size/colour + auto-expiry of unconfirmed orders
-- Run after Parts 1, 2 and 3. Role selector = postgres. Each step on its own, in order.
-- Every step is idempotent (re-running is safe).
--
-- ⚠ Run this file BEFORE uploading the new store.js / product.html / admin.html,
--   because the new admin page saves the variant_stock column.
--
-- How variant stock works:
--   products.variant_stock = {"M|أسود": 2, "L|أسود": 0, "M|بيج": 3}
--   key = size + '|' + colour (empty string when the product has no sizes or no colours,
--   e.g. "M|" or "|أسود"). When variant_stock is set, products.stock is ALWAYS the sum
--   (a trigger recomputes it). When it is NULL, the product uses products.stock as before.
-- =====================================================================


-- =====================================================================
-- Step 1: Column
-- =====================================================================
alter table public.products add column if not exists variant_stock jsonb;

alter table public.products drop constraint if exists products_variant_stock_object;
alter table public.products add constraint products_variant_stock_object
  check (variant_stock is null or jsonb_typeof(variant_stock) = 'object');


-- =====================================================================
-- Step 2: Keep stock = sum of variant_stock (cleans bad values too)
--   (Run the whole step together)
-- =====================================================================
create or replace function public.products_variant_sum()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_clean jsonb := '{}'::jsonb;
  r record;
begin
  if new.variant_stock is null
     or jsonb_typeof(new.variant_stock) <> 'object'
     or new.variant_stock = '{}'::jsonb then
    new.variant_stock := null;
    return new;
  end if;

  for r in select key, value from jsonb_each_text(new.variant_stock) loop
    v_clean := v_clean || jsonb_build_object(
      r.key, case when r.value ~ '^[0-9]{1,6}$' then r.value::int else 0 end);
  end loop;

  new.variant_stock := v_clean;
  new.stock := (select coalesce(sum(value::int), 0) from jsonb_each_text(v_clean));
  return new;
end;
$$;

revoke all on function public.products_variant_sum() from public, anon, authenticated;

drop trigger if exists products_variant_sum on public.products;
create trigger products_variant_sum
  before insert or update on public.products
  for each row execute function public.products_variant_sum();


-- =====================================================================
-- Step 3: adjust_stock — one place that adds/removes stock
--   Returns false when there is not enough stock (nothing is changed then).
--   Internal only: not callable from the website.
--   (Run the whole step together)
-- =====================================================================
create or replace function public.adjust_stock(p_id text, p_size text, p_color text, p_delta int)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_vs  jsonb;
  v_key text;
  v_cur int;
begin
  select variant_stock into v_vs from public.products where id = p_id for update;
  if not found then
    return true;   -- product was deleted: nothing to adjust
  end if;

  if v_vs is not null and v_vs <> '{}'::jsonb then
    v_key := coalesce(p_size, '') || '|' || coalesce(p_color, '');
    v_cur := case when coalesce(v_vs->>v_key, '') ~ '^[0-9]+$' then (v_vs->>v_key)::int else 0 end;
    if v_cur + p_delta < 0 then
      return false;
    end if;
    -- the trigger from Step 2 recomputes products.stock
    update public.products
       set variant_stock = jsonb_set(v_vs, array[v_key], to_jsonb(v_cur + p_delta), true)
     where id = p_id;
    return true;
  end if;

  update public.products set stock = stock + p_delta
   where id = p_id and stock + p_delta >= 0;
  return found;
end;
$$;

-- Supabase grants EXECUTE to anon/authenticated by default; take it back
revoke all on function public.adjust_stock(text, text, text, int) from public, anon, authenticated;


-- =====================================================================
-- Step 4: place_order — same as Part 3, but stock is checked per size/colour
--   (Run the whole step together, from create to grant)
-- =====================================================================
create or replace function public.place_order(p_items jsonb, p_customer jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_name     text;
  v_phone    text;
  v_digits   text;
  v_region   text;
  v_city     text;
  v_address  text;
  v_note     text;
  v_line     jsonb;
  v_pid      text;
  v_qty      int;
  v_size     text;
  v_color    text;
  v_prod     record;
  v_lines    jsonb := '[]'::jsonb;
  v_subtotal numeric := 0;
  v_shipping numeric;
  v_recent   int;
  v_customer jsonb;
  v_id       text;
  v_now      timestamptz := now();
begin
  if coalesce(jsonb_typeof(p_customer), '') <> 'object' then
    raise exception using message = 'invalid_customer';
  end if;
  if coalesce(jsonb_typeof(p_items), '') <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception using message = 'empty_cart';
  end if;
  if jsonb_array_length(p_items) > 30 then
    raise exception using message = 'too_many_items';
  end if;

  v_name    := btrim(coalesce(p_customer->>'name', ''));
  v_phone   := btrim(coalesce(p_customer->>'phone', ''));
  v_digits  := regexp_replace(v_phone, '\D', '', 'g');
  v_region  := btrim(coalesce(p_customer->>'region', ''));
  v_city    := btrim(coalesce(p_customer->>'city', ''));
  v_address := left(btrim(coalesce(p_customer->>'address', '')), 300);
  v_note    := left(btrim(coalesce(p_customer->>'note', '')), 500);

  if char_length(v_name) < 3 or char_length(v_name) > 100 then
    raise exception using message = 'invalid_name';
  end if;
  if v_digits !~ '^(218|0)?9[0-9]{8}$' or char_length(v_phone) > 20 then
    raise exception using message = 'invalid_phone';
  end if;

  select r.price into v_shipping
    from public.shipping_rates r
   where r.region = v_region and r.city = v_city and r.active;
  if not found then
    raise exception using message = 'invalid_city', detail = v_region || ' / ' || v_city;
  end if;

  select count(*) into v_recent
    from public.orders
   where created_at > v_now - interval '30 minutes'
     and status = 'new'
     and right(regexp_replace(coalesce(customer->>'phone', ''), '\D', '', 'g'), 9) = right(v_digits, 9);
  if v_recent >= 3 then
    raise exception using message = 'rate_limited';
  end if;

  perform 1
     from public.products
    where id in (select e->>'id' from jsonb_array_elements(p_items) e where jsonb_typeof(e) = 'object')
    order by id
    for update;

  for v_line in select value from jsonb_array_elements(p_items) loop
    if jsonb_typeof(v_line) <> 'object' then
      raise exception using message = 'invalid_item';
    end if;
    v_pid := btrim(coalesce(v_line->>'id', ''));
    if v_pid = '' or coalesce(v_line->>'qty', '') !~ '^[0-9]{1,3}$' then
      raise exception using message = 'invalid_item';
    end if;
    v_qty := (v_line->>'qty')::int;
    if v_qty < 1 then
      raise exception using message = 'invalid_item';
    end if;

    select p.id, p.name, coalesce(p.price, 0) as price, p.active,
           coalesce(to_jsonb(p.sizes),  '[]'::jsonb) as sizes_j,
           coalesce(to_jsonb(p.colors), '[]'::jsonb) as colors_j
      into v_prod
      from public.products p
     where p.id = v_pid;

    if not found or v_prod.active is false then
      raise exception using message = 'product_unavailable', detail = v_pid;
    end if;

    v_size  := left(btrim(coalesce(v_line->>'size', '')), 40);
    v_color := left(btrim(coalesce(v_line->>'color', '')), 40);
    if jsonb_typeof(v_prod.sizes_j) = 'array' and jsonb_array_length(v_prod.sizes_j) > 0 then
      if not (v_prod.sizes_j ? v_size) then
        raise exception using message = 'invalid_option', detail = v_pid;
      end if;
    else
      v_size := '';
    end if;
    if jsonb_typeof(v_prod.colors_j) = 'array' and jsonb_array_length(v_prod.colors_j) > 0 then
      if not (v_prod.colors_j ? v_color) then
        raise exception using message = 'invalid_option', detail = v_pid;
      end if;
    else
      v_color := '';
    end if;

    -- NEW: stock per size/colour (or the product total when it has no variant stock)
    if not public.adjust_stock(v_pid, v_size, v_color, -v_qty) then
      raise exception using
        message = 'out_of_stock',
        detail  = v_pid,
        hint    = coalesce((select stock from public.products where id = v_pid), 0)::text;
    end if;

    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'id', v_pid, 'name', v_prod.name, 'price', v_prod.price,
      'qty', v_qty, 'size', v_size, 'color', v_color));
    v_subtotal := v_subtotal + v_prod.price * v_qty;
  end loop;

  loop
    v_id := 'AZ-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
    exit when not exists (select 1 from public.orders where id = v_id);
  end loop;

  v_customer := jsonb_build_object(
    'name', v_name, 'phone', v_phone, 'region', v_region, 'city', v_city,
    'address', v_address, 'note', v_note);

  insert into public.orders (id, items, subtotal, shipping, total, customer, status, created_at, stock_managed)
  values (v_id, v_lines, v_subtotal, v_shipping, v_subtotal + v_shipping, v_customer, 'new', v_now, true);

  return jsonb_build_object(
    'id', v_id, 'items', v_lines,
    'subtotal', v_subtotal, 'shipping', v_shipping, 'total', v_subtotal + v_shipping,
    'customer', v_customer, 'status', 'new', 'created_at', v_now);
end;
$$;

revoke all on function public.place_order(jsonb, jsonb) from public;
grant execute on function public.place_order(jsonb, jsonb) to anon, authenticated;


-- =====================================================================
-- Step 5: Stock sync trigger — returns/deducts per size/colour
--   (Run the whole step together)
-- =====================================================================
create or replace function public.orders_stock_sync()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_dir int := 0;
  v_src jsonb;
  v_it  jsonb;
  v_pid text;
  v_qty int;
begin
  if tg_op = 'UPDATE' then
    if not old.stock_managed then return new; end if;
    if old.status is distinct from 'cancelled' and new.status = 'cancelled' then
      v_dir := 1;  v_src := old.items;
    elsif old.status = 'cancelled' and new.status is distinct from 'cancelled' then
      v_dir := -1; v_src := new.items;
    end if;
  elsif tg_op = 'DELETE' then
    if old.stock_managed and old.status in ('new', 'confirmed') then
      v_dir := 1; v_src := old.items;
    end if;
  end if;

  if v_dir <> 0 then
    for v_it in select value from jsonb_array_elements(coalesce(v_src, '[]'::jsonb)) loop
      v_pid := v_it->>'id';
      v_qty := case when coalesce(v_it->>'qty', '') ~ '^[0-9]{1,4}$' then (v_it->>'qty')::int else 0 end;
      continue when v_pid is null or v_qty <= 0;
      if not public.adjust_stock(v_pid, coalesce(v_it->>'size', ''), coalesce(v_it->>'color', ''), v_dir * v_qty) then
        raise exception using message = 'out_of_stock', detail = v_pid;
      end if;
    end loop;
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

revoke all on function public.orders_stock_sync() from public, anon, authenticated;

drop trigger if exists orders_stock_sync on public.orders;
create trigger orders_stock_sync
  after update of status or delete on public.orders
  for each row execute function public.orders_stock_sync();


-- =====================================================================
-- Step 6: Auto-cancel "new" orders nobody confirmed (frees their stock)
--   Change 48 below if you want a different window.
--   (Run the whole step together)
-- =====================================================================
create or replace function public.expire_stale_orders(p_hours int default 48)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  n int;
begin
  -- status → cancelled fires orders_stock_sync, which returns the quantities
  update public.orders
     set status = 'cancelled'
   where status = 'new'
     and stock_managed
     and created_at < now() - make_interval(hours => p_hours);
  get diagnostics n = row_count;
  return n;
end;
$$;

revoke all on function public.expire_stale_orders(int) from public, anon, authenticated;


-- =====================================================================
-- Step 7: Schedule it every hour with pg_cron
--   If "create extension" fails: Dashboard → Database → Extensions → enable pg_cron,
--   then run the rest of this step.
-- =====================================================================
create extension if not exists pg_cron;

select cron.unschedule(jobid) from cron.job where jobname = 'aziza-expire-stale-orders';

select cron.schedule(
  'aziza-expire-stale-orders',
  '15 * * * *',                                   -- minute 15 of every hour
  $$select public.expire_stale_orders(48)$$
);

-- Check: one active row
select jobid, jobname, schedule, active from cron.job where jobname = 'aziza-expire-stale-orders';


-- =====================================================================
-- Step 8: Checks (they change nothing — every test ends in rollback)
-- =====================================================================

-- 8.a: The sum trigger. Expected: stock = 5, variant_stock = {"L|": 3, "M|": 2, "XL|": 0}
begin;
update public.products
   set variant_stock = '{"M|": 2, "L|": "3", "XL|": "abc"}'
 where id = (select id from public.products order by id limit 1)
returning id, stock, variant_stock;
rollback;

-- 8.b: The website cannot call the internal functions.
--      Expected: ERROR 42501 permission denied for function adjust_stock — this is correct.
begin;
set local role anon;
select public.adjust_stock('x', '', '', 100);
rollback;

reset role;
select current_user;   -- must be postgres
