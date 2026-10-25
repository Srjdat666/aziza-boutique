export type Category = {
  id: string;
  slug: string;
  name_ar: string;
  sort_order: number;
};

export type Product = {
  id: string;
  category_id: string | null;
  slug: string;
  title_ar: string;
  description_ar: string;
  badges: string[];
  published: boolean;
  created_at: string;
};

export type ProductImage = {
  id: string;
  product_id: string;
  url: string;
  sort_order: number;
};

export type Variant = {
  id: string;
  product_id: string;
  size: string;
  color: string;
  sku: string | null;
  price_lyd: number;
  compare_at_price: number | null;
  stock_qty: number;
  low_stock_threshold: number;
};

export type ProductWithDetails = Product & {
  images: ProductImage[];
  variants: Variant[];
  category?: Category | null;
};

export type CartLine = {
  variantId: string;
  productId: string;
  title: string;
  size: string;
  color: string;
  priceLyd: number;
  qty: number;
  imageUrl?: string;
};

export type DeliveryZone = {
  id: string;
  name_ar: string;
  city_slug: string;
  fee_lyd: number;
};

export type Order = {
  id: string;
  order_number: string;
  status: string;
  customer_name: string;
  customer_phone: string;
  city: string;
  total_lyd: number;
  created_at: string;
};
