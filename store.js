/* assets/store.js — طبقة البيانات والواجهة المشتركة */
(function (global) {
  'use strict';

  const DB_KEY = 'aziza_db_v1';
  const CART_KEY = 'aziza_cart_v1';
  const AUTH_KEY = 'aziza_admin_session';
  const SEED = global.AZIZA_DATA || {};

  const BASE_SETTINGS = {
    storeName: 'AZIZA Boutique',
    tagline: 'حيث تعبّر الأناقة عنكِ',
    whatsapp: '218944467520',
    phones: [],
    address: 'سرت، شارع 5، العمارة رقم 89',
    currency: 'د.ل',
    shipping: 0,
    notice: '',
    instagram: '', tiktok: '', snapchat: '', facebook: '',
    adminPin: '1234'
  };

  const PLACEHOLDER = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 300 400"><rect width="300" height="400" fill="#EBD6CD"/><text x="150" y="210" text-anchor="middle" font-family="serif" font-size="30" fill="#6E1F33">AZIZA</text></svg>'
  );

  /* ---------- أدوات ---------- */
  const clone = o => JSON.parse(JSON.stringify(o));
  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  }
  function uid(prefix) {
    return (prefix || 'p') + Date.now().toString(36) + Math.random().toString(36).slice(2, 6);
  }
  function emit(name, detail) {
    document.dispatchEvent(new CustomEvent(name, { detail: detail }));
  }

  /* ---------- قاعدة البيانات ---------- */
  let db = null;

  function freshDB() {
    return {
      seedVersion: SEED.version || 1,
      settings: Object.assign({}, BASE_SETTINGS, SEED.settings || {}),
      categories: clone(SEED.categories || []),
      products: clone(SEED.products || []),
      orders: []
    };
  }

  function load() {
    if (db) return db;
    let stored = null;
    try { stored = JSON.parse(localStorage.getItem(DB_KEY) || 'null'); } catch (e) { stored = null; }
    if (!stored || !stored.settings || !Array.isArray(stored.products)) {
      db = freshDB(); persist(); return db;
    }
    const seedVersion = SEED.version || 1;
    if (stored.seedVersion !== seedVersion) {
      const pin = stored.settings.adminPin;
      stored.settings = Object.assign({}, BASE_SETTINGS, SEED.settings || {});
      if (pin) stored.settings.adminPin = pin;
      stored.categories = clone(SEED.categories || []);
      stored.products = clone(SEED.products || []);
      stored.seedVersion = seedVersion;
      db = stored; persist();
      return db;
    }
    stored.settings = Object.assign({}, BASE_SETTINGS, stored.settings);
    db = stored;
    return db;
  }

  function persist() {
    try { localStorage.setItem(DB_KEY, JSON.stringify(db)); }
    catch (e) { toast('تعذر الحفظ في المتصفح — المساحة ممتلئة', 'err'); }
  }

  /* ---------- الإعدادات ---------- */
  function getSettings() { return load().settings; }
  function saveSettings(patch) {
    Object.assign(load().settings, patch);
    persist(); emit('aziza:db'); renderChrome();
  }

  /* ---------- التصنيفات ---------- */
  function getCategories(onlyActive) {
    const list = load().categories.slice().sort((a, b) => (a.order || 0) - (b.order || 0));
    return onlyActive === false ? list : list.filter(c => c.active !== false);
  }
  function getCategory(id) { return load().categories.find(c => c.id === id) || null; }
  function childrenOf(id) { return load().categories.filter(c => c.parent === id); }

  function saveCategory(cat) {
    const d = load();
    const item = {
      id: cat.id || uid('c'),
      name: (cat.name || '').trim(),
      parent: cat.parent || null,
      order: Number(cat.order) || 0,
      image: cat.image || '',
      active: cat.active !== false
    };
    const i = d.categories.findIndex(c => c.id === item.id);
    if (i > -1) d.categories[i] = item; else d.categories.push(item);
    persist(); emit('aziza:db');
    return item;
  }
  function deleteCategory(id) {
    const d = load();
    if (d.products.some(p => p.category === id)) return false;
    if (d.categories.some(c => c.parent === id)) return false;
    d.categories = d.categories.filter(c => c.id !== id);
    persist(); emit('aziza:db');
    return true;
  }

  /* ---------- المنتجات ---------- */
  function getProduct(id) { return load().products.find(p => p.id === id) || null; }

  function getProducts(opts) {
    opts = opts || {};
    let list = load().products.filter(p => p.active !== false);

    if (opts.cat) {
      const ids = [opts.cat].concat(childrenOf(opts.cat).map(c => c.id));
      list = list.filter(p => ids.indexOf(p.category) !== -1);
    }
    if (opts.q) {
      const q = String(opts.q).trim().toLowerCase();
      list = list.filter(p => {
        const hay = [p.name, p.desc, (p.colors || []).join(' '), (p.sizes || []).join(' ')].join(' ').toLowerCase();
        return hay.indexOf(q) !== -1;
      });
    }
    const sort = opts.sort || 'new';
    if (sort === 'price-asc') list.sort((a, b) => a.price - b.price);
    else if (sort === 'price-desc') list.sort((a, b) => b.price - a.price);
    else if (sort === 'name') list.sort((a, b) => String(a.name).localeCompare(String(b.name), 'ar'));
    else list.sort((a, b) => String(b.createdAt || '').localeCompare(String(a.createdAt || '')));

    return list;
  }

  function saveProduct(p) {
    const d = load();
    const item = {
      id: p.id || uid('p'),
      name: (p.name || '').trim(),
      category: p.category || '',
      price: Number(p.price) || 0,
      oldPrice: Number(p.oldPrice) || 0,
      stock: p.stock === '' || p.stock == null ? 0 : Number(p.stock),
      sizes: p.sizes || [],
      colors: p.colors || [],
      images: (p.images || []).filter(Boolean),
      desc: p.desc || '',
      featured: !!p.featured,
      active: p.active !== false,
      createdAt: p.createdAt || new Date().toISOString()
    };
    const i = d.products.findIndex(x => x.id === item.id);
    if (i > -1) d.products[i] = Object.assign({}, d.products[i], item);
    else d.products.push(item);
    persist(); emit('aziza:db');
    return item;
  }
  function deleteProduct(id) {
    const d = load();
    d.products = d.products.filter(p => p.id !== id);
    persist(); emit('aziza:db');
  }
  function getRelated(product, limit) {
    if (!product) return [];
    const same = getProducts({ cat: product.category }).filter(p => p.id !== product.id);
    const fill = getProducts({}).filter(p => p.id !== product.id && same.indexOf(p) === -1);
    return same.concat(fill).slice(0, limit || 4);
  }

  /* ---------- العربة ---------- */
  function readCart() {
    try { const c = JSON.parse(localStorage.getItem(CART_KEY) || '[]'); return Array.isArray(c) ? c : []; }
    catch (e) { return []; }
  }
  function writeCart(items) {
    localStorage.setItem(CART_KEY, JSON.stringify(items));
    updateCartBadge();
    emit('aziza:cart');
  }
  const keyOf = it => [it.id, it.size || '', it.color || ''].join('|');

  function addToCart(item) {
    const items = readCart();
    const key = keyOf(item);
    const found = items.find(x => keyOf(x) === key);
    const qty = Math.max(1, Number(item.qty) || 1);
    if (found) found.qty += qty;
    else items.push({ id: item.id, size: item.size || '', color: item.color || '', qty: qty });
    writeCart(items);
    return true;
  }
  function setQty(key, qty) {
    const items = readCart();
    const it = items.find(x => keyOf(x) === key);
    if (!it) return;
    it.qty = Math.max(0, Number(qty) || 0);
    writeCart(items.filter(x => x.qty > 0));
  }
  function removeFromCart(key) { writeCart(readCart().filter(x => keyOf(x) !== key)); }
  function clearCart() { writeCart([]); }
  function cartCount() { return readCart().reduce((s, x) => s + (Number(x.qty) || 0), 0); }

  function cartDetailed() {
    const out = [];
    readCart().forEach(it => {
      const p = getProduct(it.id);
      if (!p || p.active === false) return;
      out.push({
        key: keyOf(it), id: p.id, name: p.name, price: Number(p.price) || 0,
        image: (p.images && p.images[0]) || PLACEHOLDER,
        size: it.size, color: it.color, qty: Number(it.qty) || 0,
        lineTotal: (Number(p.price) || 0) * (Number(it.qty) || 0)
      });
    });
    return out;
  }
  function cartSubtotal() { return cartDetailed().reduce((s, x) => s + x.lineTotal, 0); }

  /* ---------- الطلبات ---------- */
  function getOrders() {
    return load().orders.slice().sort((a, b) => String(b.createdAt).localeCompare(String(a.createdAt)));
  }
  function createOrder(customer, items, subtotal, shipping) {
    const d = load();
    const order = {
      id: 'AZ-' + Date.now().toString(36).toUpperCase(),
      items: items.map(i => ({ id: i.id, name: i.name, price: i.price, qty: i.qty, size: i.size, color: i.color })),
      subtotal: Number(subtotal) || 0,
      shipping: Number(shipping) || 0,
      total: (Number(subtotal) || 0) + (Number(shipping) || 0),
      customer: customer,
      status: 'new',
      createdAt: new Date().toISOString()
    };
    d.orders.push(order);
    persist(); emit('aziza:db');
    return order;
  }
  function updateOrder(id, patch) {
    const d = load();
    const o = d.orders.find(x => x.id === id);
    if (!o) return null;
    Object.assign(o, patch);
    persist(); emit('aziza:db');
    return o;
  }
  function deleteOrder(id) {
    const d = load();
    d.orders = d.orders.filter(o => o.id !== id);
    persist(); emit('aziza:db');
  }

  const STATUS_LABELS = {
    new: 'جديد', confirmed: 'مؤكد', shipped: 'تم الشحن', done: 'مكتمل', cancelled: 'ملغي'
  };

  /* ---------- واتساب ---------- */
  function waLink(text) {
    const num = String(getSettings().whatsapp || '').replace(/\D/g, '');
    return 'https://wa.me/' + num + (text ? '?text=' + encodeURIComponent(text) : '');
  }
  function orderMessage(order) {
    const s = getSettings();
    const L = [];
    L.push('*طلب جديد من ' + s.storeName + '*');
    L.push('رقم الطلب: ' + order.id);
    L.push('');
    order.items.forEach(it => {
      let line = '• ' + it.name;
      if (it.size) line += ' — مقاس ' + it.size;
      if (it.color) line += ' — ' + it.color;
      line += ' × ' + it.qty + ' = ' + money(it.price * it.qty);
      L.push(line);
    });
    L.push('');
    L.push('المجموع: ' + money(order.total));
    if (order.shipping) L.push('التوصيل: ' + money(order.shipping));
    L.push('');
    L.push('الاسم: ' + order.customer.name);
    L.push('الهاتف: ' + order.customer.phone);
    if (order.customer.city) L.push('المدينة: ' + order.customer.city);
    if (order.customer.address) L.push('العنوان: ' + order.customer.address);
    if (order.customer.note) L.push('ملاحظات: ' + order.customer.note);
    return L.join('\n');
  }

  /* ---------- تنسيق ---------- */
  function money(n) {
    const v = Number(n) || 0;
    return v.toLocaleString('en-US', { maximumFractionDigits: 2 }) + ' ' + (getSettings().currency || 'د.ل');
  }

  /* ---------- واجهة عامة ---------- */
  function toast(msg, type) {
    let box = document.getElementById('toasts');
    if (!box) { box = document.createElement('div'); box.id = 'toasts'; document.body.appendChild(box); }
    const el = document.createElement('div');
    el.className = 'toast ' + (type || '');
    el.textContent = msg;
    box.appendChild(el);
    setTimeout(() => { el.style.opacity = '0'; el.style.transition = 'opacity .3s'; }, 2200);
    setTimeout(() => el.remove(), 2600);
  }

  function updateCartBadge() {
    const n = cartCount();
    document.querySelectorAll('[data-cart-count]').forEach(el => {
      el.textContent = n;
      el.hidden = n === 0;
    });
  }

  function productCard(p) {
    const img = (p.images && p.images[0]) || PLACEHOLDER;
    const out = Number(p.stock) === 0;
    const sale = Number(p.oldPrice) > Number(p.price);
    let badge = '';
    if (out) badge = '<span class="badge out">نفدت الكمية</span>';
    else if (sale) badge = '<span class="badge sale">تخفيض</span>';
    else if (p.featured) badge = '<span class="badge">مميز</span>';

    return '<article class="card">' +
      '<div class="card-media">' +
        '<a href="product.html?id=' + encodeURIComponent(p.id) + '">' +
          '<img src="' + esc(img) + '" alt="' + esc(p.name) + '" loading="lazy" decoding="async">' +
        '</a>' + badge +
        '<button class="card-add" type="button" data-add="' + esc(p.id) + '" aria-label="أضيفي ' + esc(p.name) + ' إلى العربة">' +
          '<svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true"><path fill="currentColor" d="M7 4H5L4 6h2l3.6 7.6L8.2 16c-.3.5 0 1 .6 1H18v-2H9.4l1-1.8h6.9c.4 0 .8-.2 1-.6L21 5H6.2L5.5 4H7zm2 15a1.5 1.5 0 100 3 1.5 1.5 0 000-3zm8 0a1.5 1.5 0 100 3 1.5 1.5 0 000-3z"/></svg>' +
        '</button>' +
      '</div>' +
      '<div class="card-body">' +
        '<a class="card-title" href="product.html?id=' + encodeURIComponent(p.id) + '">' + esc(p.name) + '</a>' +
        '<div class="card-price">' + money(p.price) + (sale ? '<span class="old">' + money(p.oldPrice) + '</span>' : '') + '</div>' +
      '</div>' +
    '</article>';
  }

  function categoryCard(c) {
    const img = c.image || PLACEHOLDER;
    return '<a class="cat-card" href="shop.html?cat=' + encodeURIComponent(c.id) + '">' +
      '<img src="' + esc(img) + '" alt="' + esc(c.name) + '" loading="lazy" decoding="async">' +
      '<span>' + esc(c.name) + '</span></a>';
  }

  /* ---------- الهيدر والفوتر ---------- */
  function headerHTML(page, s) {
    const nav = [
      ['home', 'index.html', 'الرئيسية'],
      ['shop', 'shop.html', 'المتجر'],
      ['about', 'index.html#about', 'عن البوتيك'],
      ['contact', 'index.html#contact', 'تواصلي معنا']
    ];
    return '<header class="site-header"><div class="wrap header-inner">' +
      '<a class="brand" href="index.html"><span lang="en" dir="ltr">AZIZA</span><span class="brand-sub">بوتيك</span></a>' +
      '<nav class="main-nav" id="main-nav" aria-label="التنقل الرئيسي">' +
        nav.map(n => '<a href="' + n[1] + '"' + (page === n[0] ? ' aria-current="page"' : '') + '>' + n[2] + '</a>').join('') +
      '</nav>' +
      '<div class="header-actions">' +
        '<a class="cart-btn" href="cart.html" aria-label="عربة التسوق">' +
          '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M7 4H5L4 6h2l3.6 7.6L8.2 16c-.3.5 0 1 .6 1H18v-2H9.4l1-1.8h6.9c.4 0 .8-.2 1-.6L21 5H6.2L5.5 4H7zm2 15a1.5 1.5 0 100 3 1.5 1.5 0 000-3zm8 0a1.5 1.5 0 100 3 1.5 1.5 0 000-3z"/></svg>' +
          '<span class="cart-count" data-cart-count hidden>0</span>' +
        '</a>' +
        '<button class="menu-btn" id="menu-btn" type="button" aria-label="القائمة" aria-expanded="false" aria-controls="main-nav">☰</button>' +
      '</div></div></header>';
  }

  function footerHTML(s) {
    const phones = (s.phones || []).map(p => '<a href="tel:' + esc(p) + '" dir="ltr">' + esc(p) + '</a>').join('<br>');
    return '<footer class="site-footer"><div class="wrap footer-grid">' +
      '<div><p class="foot-brand" lang="en" dir="ltr">' + esc(s.storeName) + '</p>' +
        '<p class="foot-tag">' + esc(s.tagline) + '</p>' +
        '<p style="margin-top:.6rem;font-size:.85rem;opacity:.85">' + esc(s.address) + '</p></div>' +
      '<div><h3>تواصلي معنا</h3><div class="footer-links">' + phones + '</div>' +
        '<p style="margin-top:.6rem"><a href="' + esc(waLink('')) + '" target="_blank" rel="noopener">واتساب</a></p></div>' +
      '<div><h3>روابط</h3><div class="footer-links">' +
        '<a href="shop.html">المتجر</a><a href="cart.html">عربة التسوق</a>' +
        '<a href="index.html#contact">تواصلي معنا</a><a href="admin.html">لوحة التحكم</a></div></div>' +
      '</div>' +
      '<p class="copyright">© ' + new Date().getFullYear() + ' ' + esc(s.storeName) + ' — جميع الحقوق محفوظة</p>' +
    '</footer>';
  }

  function renderChrome() {
    const s = getSettings();
    const page = document.body.dataset.page || '';
    const h = document.getElementById('site-header');
    if (h) h.innerHTML = headerHTML(page, s);
    const f = document.getElementById('site-footer');
    if (f) f.innerHTML = footerHTML(s);

    const btn = document.getElementById('menu-btn');
    const nav = document.getElementById('main-nav');
    if (btn && nav) {
      btn.addEventListener('click', () => {
        const open = nav.classList.toggle('open');
        btn.setAttribute('aria-expanded', open ? 'true' : 'false');
      });
    }
    updateCartBadge();
  }

  /* ---------- أحداث عامة ---------- */
  document.addEventListener('click', function (e) {
    const btn = e.target.closest('[data-add]');
    if (!btn) return;
    e.preventDefault();
    const p = getProduct(btn.getAttribute('data-add'));
    if (!p) return;
    if ((p.sizes && p.sizes.length) || (p.colors && p.colors.length)) {
      location.href = 'product.html?id=' + encodeURIComponent(p.id);
      return;
    }
    if (Number(p.stock) === 0) { toast('نفدت الكمية حالياً', 'err'); return; }
    addToCart({ id: p.id, qty: 1 });
    toast('أُضيف إلى العربة ✓', 'ok');
  });

  document.addEventListener('DOMContentLoaded', renderChrome);

  /* ---------- لوحة التحكم: جلسة ---------- */
  function isAdmin() { try { return sessionStorage.getItem(AUTH_KEY) === '1'; } catch (e) { return false; } }
  function login(pin) {
    if (String(pin) === String(getSettings().adminPin)) { sessionStorage.setItem(AUTH_KEY, '1'); return true; }
    return false;
  }
  function logout() { sessionStorage.removeItem(AUTH_KEY); }

  /* ---------- النسخ الاحتياطي ---------- */
  function exportSeed() {
    const d = load();
    return { version: d.seedVersion || 1, settings: d.settings, categories: d.categories, products: d.products };
  }
  function importSeed(obj) {
    const d = load();
    if (obj.settings) d.settings = Object.assign({}, BASE_SETTINGS, obj.settings, { adminPin: d.settings.adminPin });
    if (Array.isArray(obj.categories)) d.categories = obj.categories;
    if (Array.isArray(obj.products)) d.products = obj.products;
    d.seedVersion = obj.version || d.seedVersion || 1;
    persist(); emit('aziza:db'); renderChrome();
  }
  function resetAll() {
    localStorage.removeItem(DB_KEY);
    localStorage.removeItem(CART_KEY);
    db = null; load(); renderChrome();
  }

  global.AZ = {
    esc, uid, money, toast,
    getSettings, saveSettings,
    getCategories, getCategory, childrenOf, saveCategory, deleteCategory,
    getProducts, getProduct, saveProduct, deleteProduct, getRelated,
    addToCart, setQty, removeFromCart, clearCart, cartCount, cartDetailed, cartSubtotal, keyOf,
    getOrders, createOrder, updateOrder, deleteOrder, STATUS_LABELS,
    waLink, orderMessage,
    productCard, categoryCard, renderChrome,
    isAdmin, login, logout,
    exportSeed, importSeed, resetAll,
    PLACEHOLDER
  };
})(window);
