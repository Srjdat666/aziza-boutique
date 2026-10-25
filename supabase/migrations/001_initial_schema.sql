-- AZIZA Boutique — schema
create extension if not exists "pgcrypto";

create type order_status as enum (
  'new', 'confirmed', 'preparing', 'out_for_delivery', 'delivered', 'cancelled'
);

create type payment_status as enum (
  'pending', 'paid', 'cod', 'refunded'
);

create type user_role as enum (
  'owner', 'seller', 'fulfillment'
);

create table categories (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name_ar text not null,
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);

create table products (
  id uuid primary key default gen_random_uuid(),
  category_id uuid references categories(id) on delete set null,
  slug text not null unique,
  title_ar text not null,
  description_ar text default '',
  badges text[] not null default '{}',
  published boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table product_images (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references products(id) on delete cascade,
  storage_path text not null,
  url text not null,
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);

create table variants (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references products(id) on delete cascade,
  size text not null default '',
  color text not null default '',
  sku text unique,
  price_lyd numeric(12,2) not null check (price_lyd >= 0),
  compare_at_price numeric(12,2),
  stock_qty int not null default 0 check (stock_qty >= 0),
  low_stock_threshold int not null default 2,
  created_at timestamptz not null default now(),
  unique (product_id, size, color)
);

create table delivery_zones (
  id uuid primary key default gen_random_uuid(),
  name_ar text not null,
  city_slug text not null,
  fee_lyd numeric(12,2) not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table customers (
  id uuid primary key default gen_random_uuid(),
  phone text not null unique,
  name text,
  city text,
  last_order_at timestamptz,
  created_at timestamptz not null default now()
);

create table orders (
  id uuid primary key default gen_random_uuid(),
  order_number text not null unique,
  status order_status not null default 'new',
  customer_id uuid references customers(id) on delete set null,
  customer_name text not null,
  customer_phone text not null,
  city text not null,
  address text not null default '',
  delivery_method text not null default 'mara',
  delivery_zone_id uuid references delivery_zones(id) on delete set null,
  delivery_fee_lyd numeric(12,2) not null default 0,
  payment_method text not null default 'cod',
  payment_status payment_status not null default 'pending',
  subtotal_lyd numeric(12,2) not null default 0,
  discount_lyd numeric(12,2) not null default 0,
  total_lyd numeric(12,2) not null default 0,
  promo_code text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references orders(id) on delete cascade,
  variant_id uuid references variants(id) on delete set null,
  qty int not null check (qty > 0),
  unit_price_lyd numeric(12,2) not null,
  product_title_snapshot text not null,
  size_snapshot text not null default '',
  color_snapshot text not null default ''
);

create table profiles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  role user_role not null default 'owner',
  display_name text,
  created_at timestamptz not null default now()
);

create table promo_codes (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  discount_type text not null check (discount_type in ('percent', 'fixed')),
  discount_value numeric(12,2) not null,
  valid_until timestamptz,
  max_uses int,
  used_count int not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table pos_sales (
  id uuid primary key default gen_random_uuid(),
  variant_id uuid not null references variants(id) on delete restrict,
  qty int not null check (qty > 0),
  total_lyd numeric(12,2) not null,
  sold_by uuid references profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create table cms_pages (
  slug text primary key,
  title_ar text not null,
  body_html text not null default '',
  updated_at timestamptz not null default now()
);

create sequence order_number_seq start 1;

create index idx_products_published on products(published) where published = true;
create index idx_products_category on products(category_id);
create index idx_variants_product on variants(product_id);
create index idx_orders_status on orders(status);
create index idx_orders_phone on orders(customer_phone);
create index idx_order_items_order on order_items(order_id);

create or replace function set_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

create trigger products_updated before update on products
  for each row execute function set_updated_at();

create trigger orders_updated before update on orders
  for each row execute function set_updated_at();
