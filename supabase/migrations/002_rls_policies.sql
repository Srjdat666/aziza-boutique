-- RLS policies
alter table categories enable row level security;
alter table products enable row level security;
alter table product_images enable row level security;
alter table variants enable row level security;
alter table delivery_zones enable row level security;
alter table orders enable row level security;
alter table order_items enable row level security;
alter table profiles enable row level security;
alter table customers enable row level security;
alter table promo_codes enable row level security;
alter table pos_sales enable row level security;
alter table cms_pages enable row level security;

create or replace function is_staff()
returns boolean as $$
  select exists (
    select 1 from profiles p
    where p.user_id = auth.uid()
    and p.role in ('owner', 'seller', 'fulfillment')
  );
$$ language sql stable security definer set search_path = public;

create or replace function is_owner_or_seller()
returns boolean as $$
  select exists (
    select 1 from profiles p
    where p.user_id = auth.uid()
    and p.role in ('owner', 'seller')
  );
$$ language sql stable security definer set search_path = public;

-- Public read: published catalog
create policy categories_public_read on categories for select using (true);
create policy products_public_read on products for select using (published = true);
create policy product_images_public_read on product_images for select using (
  exists (select 1 from products pr where pr.id = product_id and pr.published = true)
);
create policy variants_public_read on variants for select using (
  exists (select 1 from products pr where pr.id = product_id and pr.published = true)
);
create policy delivery_zones_public_read on delivery_zones for select using (active = true);
create policy cms_public_read on cms_pages for select using (true);

-- Staff write catalog
create policy products_staff_all on products for all using (is_staff()) with check (is_staff());
create policy product_images_staff_all on product_images for all using (is_staff()) with check (is_staff());
create policy variants_staff_all on variants for all using (is_staff()) with check (is_staff());
create policy categories_staff_all on categories for all using (is_staff()) with check (is_staff());
create policy delivery_zones_staff_all on delivery_zones for all using (is_owner_or_seller()) with check (is_owner_or_seller());
create policy cms_staff_all on cms_pages for all using (is_staff()) with check (is_staff());

-- Orders: staff full; public insert via RPC only (no direct insert policy)
create policy orders_staff_all on orders for all using (is_staff()) with check (is_staff());
create policy order_items_staff_read on order_items for select using (is_staff());

-- Track order by order_number — via security definer function (see 003)
create policy customers_staff_all on customers for all using (is_staff()) with check (is_staff());
create policy promo_staff_all on promo_codes for all using (is_owner_or_seller()) with check (is_owner_or_seller());
create policy pos_staff_all on pos_sales for all using (is_staff()) with check (is_staff());

create policy profiles_self_read on profiles for select using (user_id = auth.uid() or is_staff());
create policy profiles_owner_insert on profiles for insert with check (user_id = auth.uid());

-- Storage bucket policies (run in dashboard or storage migration)
-- bucket: product-images — public read, staff write
