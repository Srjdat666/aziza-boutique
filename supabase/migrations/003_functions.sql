-- Order placement + tracking + POS

create or replace function generate_order_number()
returns text as $$
declare
  yr text := to_char(now(), 'YYYY');
  seq_val bigint;
begin
  seq_val := nextval('order_number_seq');
  return 'AZ-' || yr || '-' || lpad(seq_val::text, 5, '0');
end;
$$ language plpgsql;

create or replace function place_order(
  p_customer_name text,
  p_customer_phone text,
  p_city text,
  p_address text,
  p_delivery_method text,
  p_delivery_zone_id uuid,
  p_payment_method text,
  p_items jsonb,
  p_promo_code text default null
)
returns jsonb as $$
declare
  v_order_id uuid;
  v_order_number text;
  v_subtotal numeric(12,2) := 0;
  v_delivery_fee numeric(12,2) := 0;
  v_discount numeric(12,2) := 0;
  v_total numeric(12,2);
  v_item jsonb;
  v_variant_id uuid;
  v_qty int;
  v_variant variants%rowtype;
  v_product products%rowtype;
  v_customer_id uuid;
begin
  if jsonb_array_length(p_items) = 0 then
    raise exception 'EMPTY_CART';
  end if;

  if p_delivery_zone_id is not null then
    select fee_lyd into v_delivery_fee from delivery_zones where id = p_delivery_zone_id and active = true;
    if not found then
      v_delivery_fee := 0;
    end if;
  end if;

  v_order_number := generate_order_number();

  insert into customers (phone, name, city, last_order_at)
  values (p_customer_phone, p_customer_name, p_city, now())
  on conflict (phone) do update set
    name = excluded.name,
    city = excluded.city,
    last_order_at = now()
  returning id into v_customer_id;

  insert into orders (
    order_number, customer_id, customer_name, customer_phone, city, address,
    delivery_method, delivery_zone_id, delivery_fee_lyd, payment_method,
    payment_status, subtotal_lyd, discount_lyd, total_lyd, promo_code, status
  ) values (
    v_order_number, v_customer_id, p_customer_name, p_customer_phone, p_city, p_address,
    p_delivery_method, p_delivery_zone_id, v_delivery_fee, p_payment_method,
    case when p_payment_method = 'cod' then 'cod'::payment_status else 'pending'::payment_status end,
    0, 0, 0, p_promo_code, 'new'
  ) returning id into v_order_id;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_variant_id := (v_item->>'variant_id')::uuid;
    v_qty := (v_item->>'qty')::int;

    select * into v_variant from variants where id = v_variant_id for update;
    if not found then
      raise exception 'VARIANT_NOT_FOUND';
    end if;
    if v_variant.stock_qty < v_qty then
      raise exception 'INSUFFICIENT_STOCK';
    end if;

    select * into v_product from products where id = v_variant.product_id;
    if v_product.published is not true then
      raise exception 'PRODUCT_UNAVAILABLE';
    end if;

    update variants set stock_qty = stock_qty - v_qty where id = v_variant_id;

    insert into order_items (
      order_id, variant_id, qty, unit_price_lyd,
      product_title_snapshot, size_snapshot, color_snapshot
    ) values (
      v_order_id, v_variant_id, v_qty, v_variant.price_lyd,
      v_product.title_ar, v_variant.size, v_variant.color
    );

    v_subtotal := v_subtotal + (v_variant.price_lyd * v_qty);
  end loop;

  -- TODO: apply promo_code in phase 3
  v_total := v_subtotal + v_delivery_fee - v_discount;

  update orders set
    subtotal_lyd = v_subtotal,
    discount_lyd = v_discount,
    total_lyd = v_total
  where id = v_order_id;

  return jsonb_build_object(
    'order_id', v_order_id,
    'order_number', v_order_number,
    'total_lyd', v_total
  );
end;
$$ language plpgsql security definer set search_path = public;

grant execute on function place_order to anon, authenticated;

create or replace function get_order_by_number(p_order_number text)
returns jsonb as $$
declare
  v_order orders%rowtype;
  v_items jsonb;
begin
  select * into v_order from orders where order_number = p_order_number;
  if not found then
    return null;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'product_title', oi.product_title_snapshot,
    'size', oi.size_snapshot,
    'color', oi.color_snapshot,
    'qty', oi.qty,
    'unit_price', oi.unit_price_lyd
  )), '[]'::jsonb) into v_items
  from order_items oi where oi.order_id = v_order.id;

  return jsonb_build_object(
    'order_number', v_order.order_number,
    'status', v_order.status,
    'customer_name', v_order.customer_name,
    'city', v_order.city,
    'total_lyd', v_order.total_lyd,
    'created_at', v_order.created_at,
    'items', v_items
  );
end;
$$ language plpgsql security definer set search_path = public;

grant execute on function get_order_by_number to anon, authenticated;

create or replace function pos_sell(p_variant_id uuid, p_qty int)
returns jsonb as $$
declare
  v_variant variants%rowtype;
  v_total numeric(12,2);
  v_profile uuid;
begin
  if not is_staff() then
    raise exception 'FORBIDDEN';
  end if;

  select id into v_profile from profiles where user_id = auth.uid() limit 1;

  select * into v_variant from variants where id = p_variant_id for update;
  if not found then
    raise exception 'VARIANT_NOT_FOUND';
  end if;
  if v_variant.stock_qty < p_qty then
    raise exception 'INSUFFICIENT_STOCK';
  end if;

  update variants set stock_qty = stock_qty - p_qty where id = p_variant_id;
  v_total := v_variant.price_lyd * p_qty;

  insert into pos_sales (variant_id, qty, total_lyd, sold_by)
  values (p_variant_id, p_qty, v_total, v_profile);

  return jsonb_build_object('total_lyd', v_total);
end;
$$ language plpgsql security definer set search_path = public;

grant execute on function pos_sell to authenticated;

create or replace function handle_new_user()
returns trigger as $$
begin
  insert into profiles (user_id, role, display_name)
  values (new.id, 'owner', new.email)
  on conflict (user_id) do nothing;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

-- Enable in Supabase dashboard: trigger on auth.users after insert
