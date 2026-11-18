-- =====================================================================
-- AZIZA Boutique — Migration: secure checkout + admin role + RLS
-- 2026-11-18
--
-- What it does:
--   1. public.admins table + is_admin() function: only listed accounts are
--      admins (no longer "any signed-in account").
--   2. place_order(items, customer): the only way to create an order.
--      Prices come from the products table, stock is checked and decremented
--      atomically, the order ID is generated server-side, and there is a basic
--      per-phone-number rate limit.
--   3. orders_stock_sync trigger: cancelling a new/confirmed order (or deleting it)
--      returns its quantities to stock; un-cancelling deducts them again.
--   4. Drops every old policy on the categories / products / settings / orders
--      tables and the four product-images storage policies, then recreates them on is_admin().
--
-- Before running:
--   * Replace azizabotiqe1@gmail.com below with the admin account's email
--     (it must already exist under Authentication → Users).
--   * Run the whole file at once in the SQL Editor. It runs inside a single transaction:
--     any error rolls back everything.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 0) Check the assumed column types (fails early with a clear message)
-- ---------------------------------------------------------------------
do $$
declare
  v_items_type text;
  v_cust_type  text;
begin
  select data_type into v_items_type from information_schema.columns
   where table_schema = 'public' and table_name = 'orders' and column_name = 'items';
  select data_type into v_cust_type from information_schema.columns
   where table_schema = 'public' and table_name = 'orders' and column_name = 'customer';
  if v_items_type is distinct from 'jsonb' or v_cust_type is distinct from 'jsonb' then
    raise exception 'orders.items and orders.customer must be jsonb (found: % / %)', v_items_type, v_cust_type;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 1) Admins
-- ---------------------------------------------------------------------
create table if not exists public.admins (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.admins enable row level security;
-- No policies on purpose: no one reads or edits this table via the API.
revoke all on public.admins from anon, authenticated;

do $$
declare
  v_email text := 'srjawidat@gmail.com';   -- البريد الخاص بك
begin
  insert into public.admins (user_id)
  select id from auth.users where lower(email) = lower(btrim(v_email))
  on conflict do nothing;

  if not exists (select 1 from public.admins) then
    raise exception 'No user with this email in auth.users: %', v_email;
  end if;
end $$;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (select 1 from public.admins where user_id = auth.uid());
$$;
revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to anon, authenticated;

-- ---------------------------------------------------------------------
-- 2) Table hardening
-- ---------------------------------------------------------------------
-- Orders created before this migration did not deduct stock, so the trigger must not
-- return stock for them. This column tells them apart.
alter table public.orders add column if not exists stock_managed boolean not null default false;

create index if not exists orders_created_at_idx on public.orders (created_at desc);

do $$
begin
  -- NOT VALID: applies to new writes without checking old rows
  if not exists (select 1 from pg_constraint where conname = 'products_stock_nonneg') then
    alter table public.products add constraint products_stock_nonneg check (stock >= 0) not valid;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'products_price_nonneg') then
    alter table public.products add constraint products_price_nonneg check (price >= 0) not valid;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 3) Remove the old policies
-- ---------------------------------------------------------------------
do $$
declare r record;
begin
  for r in
    select schemaname, tablename, policyname from pg_policies
     where schemaname = 'public'
       and tablename in ('categories', 'products', 'settings', 'orders')
  loop
    execute format('drop policy %I on %I.%I', r.policyname, r.schemaname, r.tablename);
  end loop;
end $$;

drop policy if exists "admin delete images" on storage.objects;
drop policy if exists "admin update images" on storage.objects;
drop policy if exists "admin upload images" on storage.objects;
drop policy if exists "public read images"  on storage.objects;

alter table public.categories enable row level security;
alter table public.products   enable row level security;
alter table public.settings   enable row level security;
alter table public.orders     enable row level security;

-- ---------------------------------------------------------------------
-- 4) New policies
--    (select public.is_admin()) in parentheses so Postgres evaluates it once per query
-- ---------------------------------------------------------------------
-- Categories: everyone sees active ones, the admin sees all and edits
create policy categories_read on public.categories
  for select to anon, authenticated
  using (active is not false or (select public.is_admin()));
create policy categories_admin_write on public.categories
  for all to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));

-- Products
create policy products_read on public.products
  for select to anon, authenticated
  using (active is not false or (select public.is_admin()));
create policy products_admin_write on public.products
  for all to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));

-- Settings: public read, admin-only write
create policy settings_read on public.settings
  for select to anon, authenticated
  using (true);
create policy settings_admin_write on public.settings
  for all to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));

-- Orders: no direct insert policy at all. Creation goes only through place_order().
create policy orders_admin_read on public.orders
  for select to authenticated
  using ((select public.is_admin()));
create policy orders_admin_update on public.orders
  for update to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));
create policy orders_admin_delete on public.orders
  for delete to authenticated
  using ((select public.is_admin()));
revoke insert on public.orders from anon, authenticated;

-- Images
create policy product_images_public_read on storage.objects
  for select to public
  using (bucket_id = 'product-images');
create policy product_images_admin_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'product-images' and (select public.is_admin()));
create policy product_images_admin_update on storage.objects
  for update to authenticated
  using (bucket_id = 'product-images' and (select public.is_admin()))
  with check (bucket_id = 'product-images' and (select public.is_admin()));
create policy product_images_admin_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'product-images' and (select public.is_admin()));

-- ---------------------------------------------------------------------
-- 5) place_order — the only way to create an order
--    p_items:    [{ "id": "...", "qty": 2, "size": "M", "color": "Black" }, ...]
--    p_customer: { "name", "phone", "city", "address", "note" }
--    Errors (error.message): invalid_customer | empty_cart | too_many_items |
--      invalid_name | invalid_phone | invalid_item | product_unavailable |
--      invalid_option | out_of_stock | rate_limited
--      error.details = product id when relevant, error.hint = remaining stock (out_of_stock)
-- ---------------------------------------------------------------------
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
  v_shipping numeric := 0;
  v_recent   int;
  v_customer jsonb;
  v_id       text;
  v_now      timestamptz := now();
begin
  -- ---- Validate inputs ----
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
  v_city    := left(btrim(coalesce(p_customer->>'city', '')), 80);
  v_address := left(btrim(coalesce(p_customer->>'address', '')), 300);
  v_note    := left(btrim(coalesce(p_customer->>'note', '')), 500);

  if char_length(v_name) < 3 or char_length(v_name) > 100 then
    raise exception using message = 'invalid_name';
  end if;
  if v_digits !~ '^(218|0)?9[0-9]{8}$' or char_length(v_phone) > 20 then
    raise exception using message = 'invalid_phone';
  end if;

  -- ---- Basic rate limit: at most 3 new orders per number every 30 minutes ----
  select count(*) into v_recent
    from public.orders
   where created_at > v_now - interval '30 minutes'
     and status = 'new'
     and right(regexp_replace(coalesce(customer->>'phone', ''), '\D', '', 'g'), 9) = right(v_digits, 9);
  if v_recent >= 3 then
    raise exception using message = 'rate_limited';
  end if;

  -- ---- Lock product rows in a fixed order (prevents deadlocks between concurrent orders) ----
  perform 1
     from public.products
    where id in (select e->>'id' from jsonb_array_elements(p_items) e where jsonb_typeof(e) = 'object')
    order by id
    for update;

  -- ---- Process each line ----
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

    -- Size/color: must be one of the product's options; ignored if it has none
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

    -- Conditional deduction: fails if there isn't enough stock (correctly covers multiple lines of the same product)
    update public.products
       set stock = stock - v_qty
     where id = v_pid and stock >= v_qty;
    if not found then
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

  -- ---- Shipping from settings ----
  begin
    select greatest(coalesce(nullif(data->>'shipping', '')::numeric, 0), 0)
      into v_shipping
      from public.settings where id = 1;
  exception when invalid_text_representation then
    v_shipping := 0;
  end;
  v_shipping := coalesce(v_shipping, 0);

  -- ---- Order ID ----
  loop
    v_id := 'AZ-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
    exit when not exists (select 1 from public.orders where id = v_id);
  end loop;

  v_customer := jsonb_build_object(
    'name', v_name, 'phone', v_phone, 'city', v_city, 'address', v_address, 'note', v_note);

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

-- ---------------------------------------------------------------------
-- 6) Sync stock with order status
--    * new/confirmed/shipped/done → cancelled : return quantities
--    * cancelled → any other status : deduct again (fails if stock is insufficient)
--    * delete a new/confirmed order       : return quantities
--    Applies only to orders created through place_order (stock_managed = true).
-- ---------------------------------------------------------------------
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
      if v_dir = 1 then
        update public.products set stock = stock + v_qty where id = v_pid;
      else
        update public.products set stock = stock - v_qty where id = v_pid and stock >= v_qty;
        if not found and exists (select 1 from public.products where id = v_pid) then
          raise exception using message = 'out_of_stock', detail = v_pid;
        end if;
      end if;
    end loop;
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;
revoke all on function public.orders_stock_sync() from public;

drop trigger if exists orders_stock_sync on public.orders;
create trigger orders_stock_sync
  after update of status or delete on public.orders
  for each row execute function public.orders_stock_sync();

commit;

-- =====================================================================
-- Checks after running (run them separately):
--
--   select tablename, policyname, cmd, roles from pg_policies
--    where schemaname in ('public','storage') order by 1, 2;
--
--   -- must fail with invalid_phone:
--   select public.place_order('[{"id":"x","qty":1}]', '{"name":"test","phone":"123"}');
--
--   -- must fail with permission denied / RLS (direct insert closed):
--   set role anon; insert into public.orders (id, items, customer) values ('X','[]','{}'); reset role;
-- =====================================================================
