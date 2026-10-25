# AZIZA Boutique — نموذج البيانات (ERD)

## مخطط العلاقات

```mermaid
erDiagram
  categories ||--o{ products : has
  products ||--o{ product_images : has
  products ||--o{ variants : has
  variants ||--o{ order_items : sold_in
  orders ||--o{ order_items : contains
  delivery_zones ||--o{ orders : ships_to
  profiles ||--o{ orders : manages
  customers ||--o{ orders : places
  promo_codes ||--o{ orders : applied

  categories {
    uuid id PK
    text slug UK
    text name_ar
    int sort_order
  }

  products {
    uuid id PK
    uuid category_id FK
    text slug UK
    text title_ar
    text description_ar
    text[] badges
    boolean published
    timestamptz created_at
  }

  product_images {
    uuid id PK
    uuid product_id FK
    text storage_path
    text url
    int sort_order
  }

  variants {
    uuid id PK
    uuid product_id FK
    text size
    text color
    text sku UK
    numeric price_lyd
    numeric compare_at_price
    int stock_qty
    int low_stock_threshold
  }

  orders {
    uuid id PK
    text order_number UK
    text status
    text customer_name
    text customer_phone
    text city
    text address
    text delivery_method
    uuid delivery_zone_id FK
    numeric delivery_fee_lyd
    text payment_method
    text payment_status
    numeric subtotal_lyd
    numeric discount_lyd
    numeric total_lyd
    text promo_code
    timestamptz created_at
  }

  order_items {
    uuid id PK
    uuid order_id FK
    uuid variant_id FK
    int qty
    numeric unit_price_lyd
    text product_title_snapshot
    text size_snapshot
    text color_snapshot
  }

  delivery_zones {
    uuid id PK
    text name_ar
    text city_slug
    numeric fee_lyd
    boolean active
  }

  profiles {
    uuid id PK
    uuid user_id FK
    text role
    text display_name
  }

  customers {
    uuid id PK
    text phone UK
    text name
    text city
    timestamptz last_order_at
  }

  promo_codes {
    uuid id PK
    text code UK
    text discount_type
    numeric discount_value
    timestamptz valid_until
    int max_uses
    int used_count
    boolean active
  }

  pos_sales {
    uuid id PK
    uuid variant_id FK
    int qty
    numeric total_lyd
    uuid sold_by FK
    timestamptz created_at
  }
```

## حالات الطلب

| `status` | الوصف |
|----------|--------|
| `new` | جديد |
| `confirmed` | مؤكد |
| `preparing` | قيد التجهيز |
| `out_for_delivery` | خرج للتوصيل |
| `delivered` | سُلّم |
| `cancelled` | ملغى |

## شارات المنتج (`badges`)

`new`, `last_piece`, `sold_out`, `sale`

## تدفق الطلب المعتمد

**حفظ الطلب في النظام ثم فتح واتساب برسالة جاهزة** — يضمن رقم تتبع ومخزوناً دقيقاً مع بقاء واتساب قناة البيع.
