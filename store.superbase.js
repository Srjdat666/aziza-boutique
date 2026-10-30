/* store-supabase.js */

const SUPABASE_URL =
  "https://uqzltkgtqwwjruzoflbb.supabase.co";

const SUPABASE_KEY =
  "PASTE_YOUR_PUBLISHABLE_KEY_HERE";

const supabaseClient = supabase.createClient(
  SUPABASE_URL,
  SUPABASE_KEY
);

/* تحميل التصنيفات */
async function loadCategoriesFromSupabase() {
  const { data, error } = await supabaseClient
    .from("categories")
    .select("*");

  if (error) {
    console.error(error);
    return [];
  }

  return data || [];
}

/* تحميل المنتجات */
async function loadProductsFromSupabase() {
  const { data, error } = await supabaseClient
    .from("products")
    .select("*");

  if (error) {
    console.error(error);
    return [];
  }

  return (data || []).map(product => ({
    id: product.id,
    name: product.name,
    category: product.category,
    price: Number(product.price || 0),
    oldPrice: Number(product.old_price || 0),
    stock: Number(product.stock || 0),
    sizes: product.sizes || [],
    colors: product.colors || [],
    images: product.images || [],
    desc: product.description || "",
    featured: product.featured || false,
    active: true,
    createdAt: product.created_at
  }));
}

/* اختبار الاتصال */
async function testSupabase() {
  const products = await loadProductsFromSupabase();

  console.log(
    "Supabase Connected ✅",
    products
  );
}

testSupabase();
console.log("Supabase file loaded ✅");