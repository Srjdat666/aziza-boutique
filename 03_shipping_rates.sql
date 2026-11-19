-- =====================================================================
-- AZIZA Boutique — Part 3: Shipping rates by region and city
-- Run after Parts 1 and 2. Role selector = postgres. Each step on its own, in order.
-- Every step is idempotent (re-running is safe).
--
-- Why in the database and not in a JS file?
--   The shipping price is part of the order total. If the browser sent it, anyone could change it
--   the same way prices could be changed before. So place_order reads the price from this table
--   and ignores anything the browser sends. The site reads the same table only for display.
-- =====================================================================


-- =====================================================================
-- Step 1: Rates table
-- =====================================================================
create table if not exists public.shipping_rates (
  region     text          not null,
  city       text          not null,
  price      numeric(10,2) not null check (price >= 0),
  active     boolean       not null default true,
  sort_order int           not null default 0,
  primary key (region, city)
);

alter table public.shipping_rates enable row level security;

drop policy if exists shipping_rates_read        on public.shipping_rates;
drop policy if exists shipping_rates_admin_write on public.shipping_rates;

create policy shipping_rates_read on public.shipping_rates
  for select to anon, authenticated
  using (active or (select public.is_admin()));

create policy shipping_rates_admin_write on public.shipping_rates
  for all to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

grant select on public.shipping_rates to anon, authenticated;
grant insert, update, delete on public.shipping_rates to authenticated;


-- =====================================================================
-- Step 2: Data (updates the price if the city already exists)
--   sort_order: region (100s) + city order within it, so the list keeps your order
--
--   ⚠ Sirte: the store's city is not in the list you sent. It is added at price 0 to keep
--     the current behavior (local delivery free). Change the price or delete the row if needed.
-- =====================================================================
insert into public.shipping_rates (region, city, price, sort_order) values
  ('المنطقة الوسطى', 'سرت',        0, 100),
  ('المنطقة الوسطى', 'مصراتة',     20, 101),
  ('المنطقة الوسطى', 'أبوقرين',    20, 102),
  ('المنطقة الوسطى', 'الوشكة',     20, 103),
  ('المنطقة الوسطى', 'تاورغاء',    20, 104),
  ('المنطقة الوسطى', 'زليتن',      20, 105),
  ('المنطقة الوسطى', 'بني وليد',   20, 106),
  ('المنطقة الوسطى', 'الخمس',      25, 107),
  ('المنطقة الوسطى', 'مسلاتة',     30, 108),
  ('المنطقة الوسطى', 'قصر أخيار',  30, 109),
  ('المنطقة الوسطى', 'هراوة',      20, 110),
  ('المنطقة الوسطى', 'أم القنديل', 20, 111),
  ('المنطقة الوسطى', 'بن جواد',    20, 112),
  ('المنطقة الوسطى', 'رأس لانوف',  20, 113),

  ('المنطقة الغربية', 'طرابلس',    20, 201),
  ('المنطقة الغربية', 'تاجوراء',   30, 202),
  ('المنطقة الغربية', 'القربولي',  30, 203),
  ('المنطقة الغربية', 'ورشفانة',   40, 204),
  ('المنطقة الغربية', 'الزاوية',   40, 205),
  ('المنطقة الغربية', 'صبراتة',    40, 206),
  ('المنطقة الغربية', 'صرمان',     40, 207),
  ('المنطقة الغربية', 'العجيلات',  40, 208),
  ('المنطقة الغربية', 'زوارة',     40, 209),
  ('المنطقة الغربية', 'غريان',     40, 210),
  ('المنطقة الغربية', 'الزنتان',   45, 211),
  ('المنطقة الغربية', 'الأصابعة',  45, 212),
  ('المنطقة الغربية', 'نالوت',     45, 213),
  ('المنطقة الغربية', 'تيجي',      45, 214),
  ('المنطقة الغربية', 'بدر',       45, 215),
  ('المنطقة الغربية', 'مزدة',      45, 216),

  ('المنطقة الجنوبية', 'هون',          20, 301),
  ('المنطقة الجنوبية', 'ودان',         20, 302),
  ('المنطقة الجنوبية', 'سوكنة',        30, 303),
  ('المنطقة الجنوبية', 'زلة',          35, 304),
  ('المنطقة الجنوبية', 'سبها',         25, 305),
  ('المنطقة الجنوبية', 'براك الشاطئ',  40, 306),
  ('المنطقة الجنوبية', 'مرزق',         40, 307),
  ('المنطقة الجنوبية', 'الشويرف',      40, 308),
  ('المنطقة الجنوبية', 'أوباري',       40, 309),
  ('المنطقة الجنوبية', 'تراغن',        40, 310),
  ('المنطقة الجنوبية', 'أم الأرانب',   40, 311),
  ('المنطقة الجنوبية', 'غات',          45, 312),
  ('المنطقة الجنوبية', 'القطرون',      45, 313),

  ('المنطقة الشرقية', 'البريقة',  20, 401),
  ('المنطقة الشرقية', 'أجدابيا',  20, 402),
  ('المنطقة الشرقية', 'جالو',     40, 403),
  ('المنطقة الشرقية', 'أوجلة',    40, 404),
  ('المنطقة الشرقية', 'تازربو',   45, 405),
  ('المنطقة الشرقية', 'اجخرة',    45, 406),
  ('المنطقة الشرقية', 'الكفرة',   45, 407),
  ('المنطقة الشرقية', 'قمنيس',    20, 408),
  ('المنطقة الشرقية', 'بنغازي',   20, 409),
  ('المنطقة الشرقية', 'المرج',    35, 410),
  ('المنطقة الشرقية', 'البيضاء',  35, 411),
  ('المنطقة الشرقية', 'شحات',     35, 412),
  ('المنطقة الشرقية', 'درنة',     35, 413),
  ('المنطقة الشرقية', 'طبرق',     40, 414),
  ('المنطقة الشرقية', 'امساعد',   50, 415),
  ('المنطقة الشرقية', 'الأبيار',  40, 416),
  ('المنطقة الشرقية', 'سلوق',     40, 417)
on conflict (region, city) do update
  set price = excluded.price, sort_order = excluded.sort_order, active = true;

-- Check: expected 61 rows (60 from your list + Sirte)
select region, count(*) as cities, min(price) as min_price, max(price) as max_price
  from public.shipping_rates group by region order by min(sort_order);


-- =====================================================================
-- Step 3: place_order — shipping price from shipping_rates by region + city
--   Change from Part 2: p_customer must include region and city that exist in the table,
--   otherwise the error is invalid_city. The shipping value in settings is no longer used.
--   (Run the whole step together, from create to grant)
-- ⚠ SUPERSEDED by 04_variant_stock_and_expiry.sql — do NOT re-run this step after Part 4.
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

  -- Shipping price from the table only (the browser does not send a price)
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
-- Step 4: Checks (they change nothing)
-- =====================================================================
-- Must fail with invalid_city (city not in the list):
begin;
set local role anon;
select public.place_order('[{"id":"x","qty":1}]',
  '{"name":"اختبار","phone":"0912345678","region":"المنطقة الوسطى","city":"مدينة وهمية"}');
rollback;

reset role;

-- To change a price later (from the SQL Editor or from Table Editor → shipping_rates):
--   update public.shipping_rates set price = 25 where city = 'سبها';
-- To stop delivery to a city without deleting it:
--   update public.shipping_rates set active = false where city = 'غات';
