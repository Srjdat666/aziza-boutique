-- =====================================================================
-- AZIZA Boutique — Part 2: Secure checkout + admins + RLS
-- Standalone steps (no DO blocks). Every step is idempotent: re-running it is safe.
--
-- Before you start:
--   * Run Part 1 (01_fix_permissions.sql) and confirm section D is all true.
--   * The Role selector in the SQL Editor = postgres.
--   * Run each step on its own (select its text and press Run), in order.
-- =====================================================================


-- =====================================================================
-- Step 1: Admins table
-- =====================================================================
create table if not exists public.admins (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.admins enable row level security;

-- No policies and no permissions: the API (anon/authenticated) cannot read or modify it at all
revoke all on public.admins from anon, authenticated;


-- =====================================================================
-- Step 2: Add the two admins
--   The accounts must exist first under Authentication → Users.
-- =====================================================================
insert into public.admins (user_id)
select id
  from auth.users
 where lower(email) in ('srjawidat@gmail.com', 'azizabotiqe1@gmail.com')
on conflict (user_id) do nothing;

-- Verify: must return two rows. If only one appears, the second account doesn't exist
-- in auth.users or its email is spelled differently.
select u.email, a.created_at
  from public.admins a
  join auth.users u on u.id = a.user_id
 order by u.email;


-- =====================================================================
-- Step 3: is_admin() function
-- =====================================================================
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


-- =====================================================================
-- Step 4: Orders and products columns and constraints
-- =====================================================================
alter table public.orders add column if not exists stock_managed boolean not null default false;

create index if not exists orders_created_at_idx on public.orders (created_at desc);

alter table public.products drop constraint if exists products_stock_nonneg;
alter table public.products add constraint products_stock_nonneg check (stock >= 0) not valid;

alter table public.products drop constraint if exists products_price_nonneg;
alter table public.products add constraint products_price_nonneg check (price >= 0) not valid;


-- =====================================================================
-- Step 5: Drop old and new policies by name (if they exist), then enable RLS
-- =====================================================================
-- Old policies (from the screenshot plus likely names)
drop policy if exists "Auth can manage orders"   on public.orders;
drop policy if exists "Anyone can insert orders" on public.orders;
drop policy if exists "admin all orders"         on public.orders;
drop policy if exists "public create order"      on public.orders;
drop policy if exists "admin all categories"     on public.categories;
drop policy if exists "public read categories"   on public.categories;
drop policy if exists "admin all products"       on public.products;
drop policy if exists "public read products"     on public.products;
drop policy if exists "admin all settings"       on public.settings;
drop policy if exists "public read settings"     on public.settings;

-- New policies (so this step can be re-run)
drop policy if exists categories_read        on public.categories;
drop policy if exists categories_admin_write on public.categories;
drop policy if exists products_read          on public.products;
drop policy if exists products_admin_write   on public.products;
drop policy if exists settings_read          on public.settings;
drop policy if exists settings_admin_write   on public.settings;
drop policy if exists orders_admin_read      on public.orders;
drop policy if exists orders_admin_update    on public.orders;
drop policy if exists orders_admin_delete    on public.orders;

alter table public.categories enable row level security;
alter table public.products   enable row level security;
alter table public.settings   enable row level security;
alter table public.orders     enable row level security;

-- Check: any row here is an old policy not covered above → drop it manually with:
--   drop policy "name" on public.table;
select tablename, policyname, cmd, roles, qual
  from pg_policies
 where schemaname = 'public'
   and tablename in ('categories', 'products', 'settings', 'orders');


-- =====================================================================
-- Step 6: New table policies
-- =====================================================================
create policy categories_read on public.categories
  for select to anon, authenticated
  using (active is not false or (select public.is_admin()));

create policy categories_admin_write on public.categories
  for all to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

create policy products_read on public.products
  for select to anon, authenticated
  using (active is not false or (select public.is_admin()));

create policy products_admin_write on public.products
  for all to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

create policy settings_read on public.settings
  for select to anon, authenticated
  using (true);

create policy settings_admin_write on public.settings
  for all to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

-- Orders: no INSERT policy at all. Creation goes only through place_order()
create policy orders_admin_read on public.orders
  for select to authenticated
  using ((select public.is_admin()));

create policy orders_admin_update on public.orders
  for update to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

create policy orders_admin_delete on public.orders
  for delete to authenticated
  using ((select public.is_admin()));

-- Close direct inserts at the permission level too (in case Part 1 restored them)
revoke insert on public.orders from anon, authenticated;


-- =====================================================================
-- Step 7: Image storage policies
-- =====================================================================
drop policy if exists "admin delete images"          on storage.objects;
drop policy if exists "admin update images"          on storage.objects;
drop policy if exists "admin upload images"          on storage.objects;
drop policy if exists "public read images"           on storage.objects;
drop policy if exists product_images_public_read     on storage.objects;
drop policy if exists product_images_admin_insert    on storage.objects;
drop policy if exists product_images_admin_update    on storage.objects;
drop policy if exists product_images_admin_delete    on storage.objects;

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


-- =====================================================================
-- Step 8: place_order function (run the whole step together, from create to grant)
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

  begin
    select greatest(coalesce(nullif(data->>'shipping', '')::numeric, 0), 0)
      into v_shipping
      from public.settings where id = 1;
  exception when invalid_text_representation then
    v_shipping := 0;
  end;
  v_shipping := coalesce(v_shipping, 0);

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


-- =====================================================================
-- Step 9: Stock sync trigger (run the whole step together)
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

revoke all on function public.orders_stock_sync() from public, anon, authenticated;

drop trigger if exists orders_stock_sync on public.orders;
create trigger orders_stock_sync
  after update of status or delete on public.orders
  for each row execute function public.orders_stock_sync();


-- =====================================================================
-- Step 10: Final checks (they change nothing — every test ends in rollback)
-- =====================================================================

-- 10.a: An admin sees the orders (expected: true and a count > 0)
begin;
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', (select id from auth.users where lower(email) = 'srjawidat@gmail.com'),
                    'role', 'authenticated')::text, true);
select public.is_admin() as is_admin, count(*) as orders_visible from public.orders;
rollback;

-- 10.b: A visitor sees no orders (expected: 0)
begin;
set local role anon;
select count(*) as orders_visible_to_anon from public.orders;
rollback;

-- 10.c: A visitor cannot insert directly (expected: ERROR 42501 permission denied for table orders — this is correct)
begin;
set local role anon;
insert into public.orders (id, items, customer) values ('TEST', '[]', '{}');
rollback;

-- After 10.c make sure you are back to postgres:
reset role;
select current_user;
