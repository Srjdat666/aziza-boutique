/* store.js — طبقة البيانات (Supabase) والواجهة المشتركة — AZIZA Boutique */
(function (global) {
  'use strict';

  var CFG = global.AZIZA_CONFIG || {};
  var CART_KEY = 'aziza_cart_v2';
  var BUCKET = 'product-images';

  var DEFAULT_SETTINGS = {
    storeName: 'AZIZA Boutique',
    tagline: 'حيث تعبّر الأناقة عنكِ',
    whatsapp: '218944467520',
    phones: [],
    address: 'سرت، شارع 5، العمارة رقم 89',
    currency: 'د.ل',
    shipping: 0,
    notice: '',
    instagram: '', tiktok: '', snapchat: '', facebook: ''
  };

  var PLACEHOLDER = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 300 400"><rect width="300" height="400" fill="#EBD6CD"/><text x="150" y="210" text-anchor="middle" font-family="serif" font-size="30" fill="#6E1F33">AZIZA</text></svg>'
  );

  /* ---------- أدوات ---------- */
  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }
  function uid(prefix) {
    return (prefix || 'p') + Date.now().toString(36) + Math.random().toString(36).slice(2, 6);
  }

  /* ---------- الاتصال ---------- */
  var sb = null;
  var configured = CFG.url && CFG.key && !/PASTE_|YOUR_/.test(CFG.url + CFG.key);
  if (configured && global.supabase) {
    try { sb = global.supabase.createClient(CFG.url, CFG.key); } catch (e) { sb = null; }
  }

  var state = {
    settings: Object.assign({}, DEFAULT_SETTINGS),
    categories: [],
    products: [],
    error: null
  };

  /* ---------- تحويل الحقول (قاعدة البيانات <-> التطبيق) ---------- */
  function catFrom(r) {
    return { id: r.id, name: r.name, parent: r.parent || null, order: Number(r.sort_order) || 0, image: r.image || '', active: r.active !== false };
  }
  function prodFrom(r) {
    return {
      id: r.id, name: r.name, category: r.category || '',
      price: Number(r.price) || 0, oldPrice: Number(r.old_price) || 0, stock: Number(r.stock) || 0,
      sizes: r.sizes || [], colors: r.colors || [], images: r.images || [],
      desc: r.description || '', featured: !!r.featured, active: r.active !== false,
      createdAt: r.created_at || ''
    };
  }
  function prodTo(p) {
    return {
      id: p.id, name: p.name, category: p.category || null,
      price: Number(p.price) || 0, old_price: Number(p.oldPrice) || 0,
      stock: Math.max(0, parseInt(p.stock, 10) || 0),
      sizes: p.sizes || [], colors: p.colors || [], images: (p.images || []).filter(Boolean),
      description: p.desc || '', featured: !!p.featured, active: p.active !== false
    };
  }
  function catTo(c) {
    return { id: c.id, name: c.name, parent: c.parent || null, sort_order: Number(c.order) || 0, image: c.image || '', active: c.active !== false };
  }
  function orderFrom(r) {
    return { id: r.id, items: r.items || [], subtotal: Number(r.subtotal) || 0, shipping: Number(r.shipping) || 0, total: Number(r.total) || 0, customer: r.customer || {}, status: r.status || 'new', createdAt: r.created_at || '' };
  }

  /* ---------- تحميل البيانات ---------- */
  function refresh() {
    if (!sb) {
      state.error = configured ? 'تعذر تحميل مكتبة Supabase — تحققي من الاتصال بالإنترنت.' : 'لم يتم ضبط مفتاح Supabase في ملف config.js بعد.';
      return Promise.resolve();
    }
    return Promise.all([
      sb.from('categories').select('*'),
      sb.from('products').select('*'),
      sb.from('settings').select('data').eq('id', 1).maybeSingle()
    ]).then(function (r) {
      var c = r[0], p = r[1], s = r[2];
      if (c.error || p.error) {
        state.error = 'تعذر تحميل بيانات المتجر. تحققي من المفتاح وصلاحيات قاعدة البيانات.';
        console.warn(c.error || p.error);
        return;
      }
      state.error = null;
      state.categories = (c.data || []).map(catFrom);
      state.products = (p.data || []).map(prodFrom);
      if (s.data && s.data.data) state.settings = Object.assign({}, DEFAULT_SETTINGS, s.data.data);
    }).catch(function (e) {
      state.error = 'تعذر الاتصال بالخادم.';
      console.warn(e);
    });
  }

  /* ---------- قراءة ---------- */
  function getSettings() { return state.settings; }
  function getCategories(onlyActive) {
    var list = state.categories.slice().sort(function (a, b) { return (a.order || 0) - (b.order || 0); });
    return onlyActive === false ? list : list.filter(function (c) { return c.active !== false; });
  }
  function getCategory(id) { return state.categories.filter(function (c) { return c.id === id; })[0] || null; }
  function childrenOf(id) { return state.categories.filter(function (c) { return c.parent === id; }); }

  function getProduct(id) { return state.products.filter(function (p) { return p.id === id; })[0] || null; }
  function getProducts(opts) {
    opts = opts || {};
    var list = state.products.filter(function (p) { return opts.all ? true : p.active !== false; });
    if (opts.cat) {
      var ids = [opts.cat].concat(childrenOf(opts.cat).map(function (c) { return c.id; }));
      list = list.filter(function (p) { return ids.indexOf(p.category) !== -1; });
    }
    if (opts.q) {
      var q = String(opts.q).trim().toLowerCase();
      list = list.filter(function (p) {
        var hay = [p.name, p.desc, (p.colors || []).join(' '), (p.sizes || []).join(' ')].join(' ').toLowerCase();
        return hay.indexOf(q) !== -1;
      });
    }
    var sort = opts.sort || 'new';
    if (sort === 'price-asc') list.sort(function (a, b) { return a.price - b.price; });
    else if (sort === 'price-desc') list.sort(function (a, b) { return b.price - a.price; });
    else if (sort === 'name') list.sort(function (a, b) { return String(a.name).localeCompare(String(b.name), 'ar'); });
    else list.sort(function (a, b) { return String(b.createdAt || '').localeCompare(String(a.createdAt || '')); });
    return list;
  }
  function getRelated(product, limit) {
    if (!product) return [];
    var same = getProducts({ cat: product.category }).filter(function (p) { return p.id !== product.id; });
    var fill = getProducts({}).filter(function (p) { return p.id !== product.id && same.indexOf(p) === -1; });
    return same.concat(fill).slice(0, limit || 4);
  }

  /* ---------- العربة (في متصفح الزبونة) ---------- */
  function readCart() {
    try { var c = JSON.parse(localStorage.getItem(CART_KEY) || '[]'); return Array.isArray(c) ? c : []; }
    catch (e) { return []; }
  }
  function writeCart(items) {
    try { localStorage.setItem(CART_KEY, JSON.stringify(items)); } catch (e) {}
    updateCartBadge();
  }
  function keyOf(it) { return [it.id, it.size || '', it.color || ''].join('|'); }

  function stockOf(id) {
    var p = getProduct(id);
    return p ? Math.max(0, Number(p.stock) || 0) : 0;
  }
  // يضيف للعربة مع احترام المخزون. يرجع { ok, capped }
  function addToCart(item) {
    var max = stockOf(item.id);
    if (max <= 0) return { ok: false, capped: false };
    var items = readCart();
    var key = keyOf(item);
    var found = items.filter(function (x) { return keyOf(x) === key; })[0];
    var qty = Math.max(1, Number(item.qty) || 1);
    var capped = false;
    if (found) {
      var next = found.qty + qty;
      if (next > max) { next = max; capped = true; }
      found.qty = next;
    } else {
      if (qty > max) { qty = max; capped = true; }
      items.push({ id: item.id, size: item.size || '', color: item.color || '', qty: qty });
    }
    writeCart(items);
    return { ok: true, capped: capped };
  }
  function setQty(key, qty) {
    var items = readCart();
    var it = items.filter(function (x) { return keyOf(x) === key; })[0];
    if (!it) return;
    it.qty = Math.min(Math.max(0, Number(qty) || 0), stockOf(it.id));
    writeCart(items.filter(function (x) { return x.qty > 0; }));
  }
  function removeFromCart(key) { writeCart(readCart().filter(function (x) { return keyOf(x) !== key; })); }
  function clearCart() { writeCart([]); }
  function cartCount() { return cartDetailed().reduce(function (s, x) { return s + x.qty; }, 0); }

  function cartDetailed() {
    var out = [];
    readCart().forEach(function (it) {
      var p = getProduct(it.id);
      if (!p || p.active === false) return;
      var stock = Math.max(0, Number(p.stock) || 0);
      if (stock <= 0) return;
      var qty = Math.min(Number(it.qty) || 0, stock);
      if (qty <= 0) return;
      out.push({
        key: keyOf(it), id: p.id, name: p.name, price: Number(p.price) || 0,
        image: (p.images && p.images[0]) || PLACEHOLDER,
        size: it.size, color: it.color, qty: qty, stock: stock,
        lineTotal: (Number(p.price) || 0) * qty
      });
    });
    return out;
  }

  /* ---------- الطلبات (الزبونة) ---------- */
  function buildOrder(customer, items, subtotal, shipping) {
    return {
      id: 'AZ-' + Date.now().toString(36).toUpperCase(),
      items: items.map(function (i) { return { id: i.id, name: i.name, price: i.price, qty: i.qty, size: i.size, color: i.color }; }),
      subtotal: Number(subtotal) || 0,
      shipping: Number(shipping) || 0,
      total: (Number(subtotal) || 0) + (Number(shipping) || 0),
      customer: customer,
      status: 'new'
    };
  }
  // يحفظ الطلب في قاعدة البيانات. يرجع true/false (لا يقرأ شيئاً لأن الزائرة لا تملك صلاحية القراءة)
  function saveOrder(order) {
    if (!sb) return Promise.resolve(false);
    return sb.from('orders').insert(order).then(function (r) {
      if (r.error) console.warn(r.error);
      return !r.error;
    }).catch(function () { return false; });
  }

  var STATUS_LABELS = { new: 'جديد', confirmed: 'مؤكد', shipped: 'تم الشحن', done: 'مكتمل', cancelled: 'ملغي' };

  /* ---------- واتساب ---------- */
  function waLink(text) {
    var num = String(getSettings().whatsapp || '').replace(/\D/g, '');
    return 'https://wa.me/' + num + (text ? '?text=' + encodeURIComponent(text) : '');
  }
  function orderMessage(order) {
    var s = getSettings();
    var L = [];
    L.push('*طلب جديد من ' + s.storeName + '*');
    L.push('رقم الطلب: ' + order.id);
    L.push('');
    order.items.forEach(function (it) {
      var line = '• ' + it.name;
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
    var v = Number(n) || 0;
    return v.toLocaleString('en-US', { maximumFractionDigits: 2 }) + ' ' + (getSettings().currency || 'د.ل');
  }

  /* ---------- واجهة عامة ---------- */
  function toast(msg, type) {
    var box = document.getElementById('toasts');
    if (!box) { box = document.createElement('div'); box.id = 'toasts'; document.body.appendChild(box); }
    var el = document.createElement('div');
    el.className = 'toast ' + (type || '');
    el.textContent = msg;
    box.appendChild(el);
    setTimeout(function () { el.style.opacity = '0'; el.style.transition = 'opacity .3s'; }, 2200);
    setTimeout(function () { el.remove(); }, 2600);
  }
  function errorBox(el) {
    if (!state.error) return false;
    el.innerHTML = '<div class="notice-box err"><b>' + esc(state.error) + '</b></div>';
    return true;
  }

  function updateCartBadge() {
    var n = cartCount();
    document.querySelectorAll('[data-cart-count]').forEach(function (el) {
      el.textContent = n;
      el.hidden = n === 0;
    });
  }

  function productCard(p) {
    var img = (p.images && p.images[0]) || PLACEHOLDER;
    var out = Number(p.stock) <= 0;
    var sale = Number(p.oldPrice) > Number(p.price);
    var badge = '';
    if (out) badge = '<span class="badge out">نفدت الكمية</span>';
    else if (sale) badge = '<span class="badge sale">تخفيض</span>';
    else if (p.featured) badge = '<span class="badge">مميز</span>';

    return '<article class="card">' +
      '<div class="card-media">' +
        '<a href="product.html?id=' + encodeURIComponent(p.id) + '">' +
          '<img src="' + esc(img) + '" alt="' + esc(p.name) + '" loading="lazy" decoding="async">' +
        '</a>' + badge +
        (out ? '' : '<button class="card-add" type="button" data-add="' + esc(p.id) + '" aria-label="أضيفي ' + esc(p.name) + ' إلى العربة">' +
          '<svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true"><path fill="currentColor" d="M7 4H5L4 6h2l3.6 7.6L8.2 16c-.3.5 0 1 .6 1H18v-2H9.4l1-1.8h6.9c.4 0 .8-.2 1-.6L21 5H6.2L5.5 4H7zm2 15a1.5 1.5 0 100 3 1.5 1.5 0 000-3zm8 0a1.5 1.5 0 100 3 1.5 1.5 0 000-3z"/></svg>' +
        '</button>') +
      '</div>' +
      '<div class="card-body">' +
        '<a class="card-title" href="product.html?id=' + encodeURIComponent(p.id) + '">' + esc(p.name) + '</a>' +
        '<div class="card-price">' + money(p.price) + (sale ? '<span class="old">' + money(p.oldPrice) + '</span>' : '') + '</div>' +
      '</div>' +
    '</article>';
  }

  function categoryCard(c) {
    var img = c.image || PLACEHOLDER;
    return '<a class="cat-card" href="shop.html?cat=' + encodeURIComponent(c.id) + '">' +
      '<img src="' + esc(img) + '" alt="' + esc(c.name) + '" loading="lazy" decoding="async">' +
      '<span>' + esc(c.name) + '</span></a>';
  }

  /* ---------- الهيدر والفوتر ---------- */
  function headerHTML(page) {
    var nav = [
      ['home', 'index.html', 'الرئيسية'],
      ['shop', 'shop.html', 'المتجر'],
      ['about', 'index.html#about', 'عن البوتيك'],
      ['contact', 'index.html#contact', 'تواصلي معنا']
    ];
    return '<header class="site-header"><div class="wrap header-inner">' +
      '<a class="brand" href="index.html"><span lang="en" dir="ltr">AZIZA</span><span class="brand-sub">بوتيك</span></a>' +
      '<nav class="main-nav" id="main-nav" aria-label="التنقل الرئيسي">' +
        nav.map(function (n) { return '<a href="' + n[1] + '"' + (page === n[0] ? ' aria-current="page"' : '') + '>' + n[2] + '</a>'; }).join('') +
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
    var phones = (s.phones || []).map(function (p) { return '<a href="tel:' + esc(p) + '" dir="ltr">' + esc(p) + '</a>'; }).join('<br>');
    return '<footer class="site-footer"><div class="wrap footer-grid">' +
      '<div><p class="foot-brand" lang="en" dir="ltr">' + esc(s.storeName) + '</p>' +
        '<p class="foot-tag">' + esc(s.tagline) + '</p>' +
        '<p style="margin-top:.6rem;font-size:.85rem;opacity:.85">' + esc(s.address) + '</p></div>' +
      '<div><h3>تواصلي معنا</h3><div class="footer-links">' + phones + '</div>' +
        '<p style="margin-top:.6rem"><a href="' + esc(waLink('')) + '" target="_blank" rel="noopener">واتساب</a></p></div>' +
      '<div><h3>روابط</h3><div class="footer-links">' +
        '<a href="shop.html">المتجر</a><a href="cart.html">عربة التسوق</a>' +
        '<a href="index.html#contact">تواصلي معنا</a></div></div>' +
      '</div>' +
      '<p class="copyright">© ' + new Date().getFullYear() + ' ' + esc(s.storeName) + ' — جميع الحقوق محفوظة</p>' +
    '</footer>';
  }

  function renderChrome() {
    var s = getSettings();
    var page = document.body.dataset.page || '';
    var h = document.getElementById('site-header');
    if (h) h.innerHTML = headerHTML(page);
    var f = document.getElementById('site-footer');
    if (f) f.innerHTML = footerHTML(s);
    var btn = document.getElementById('menu-btn');
    var nav = document.getElementById('main-nav');
    if (btn && nav) {
      btn.addEventListener('click', function () {
        var open = nav.classList.toggle('open');
        btn.setAttribute('aria-expanded', open ? 'true' : 'false');
      });
    }
    updateCartBadge();
  }

  /* زر "أضيفي للعربة" في بطاقات المنتجات */
  document.addEventListener('click', function (e) {
    var btn = e.target.closest('[data-add]');
    if (!btn) return;
    e.preventDefault();
    var p = getProduct(btn.getAttribute('data-add'));
    if (!p) return;
    if ((p.sizes && p.sizes.length) || (p.colors && p.colors.length)) {
      location.href = 'product.html?id=' + encodeURIComponent(p.id);
      return;
    }
    var r = addToCart({ id: p.id, qty: 1 });
    if (!r.ok) toast('نفدت الكمية حالياً', 'err');
    else if (r.capped) toast('وصلتِ لأقصى كمية متوفرة', 'err');
    else toast('أُضيف إلى العربة ✓', 'ok');
  });

  /* ---------- الإدارة (تتطلب تسجيل دخول) ---------- */
  function resizeImage(file, max, quality) {
    return new Promise(function (resolve, reject) {
      var img = new Image();
      var url = URL.createObjectURL(file);
      img.onload = function () {
        URL.revokeObjectURL(url);
        var k = Math.min(1, max / Math.max(img.width, img.height));
        var w = Math.round(img.width * k), h = Math.round(img.height * k);
        var c = document.createElement('canvas');
        c.width = w; c.height = h;
        var x = c.getContext('2d');
        x.fillStyle = '#fff'; x.fillRect(0, 0, w, h);
        x.drawImage(img, 0, 0, w, h);
        c.toBlob(function (b) { b ? resolve(b) : reject(new Error('resize')); }, 'image/jpeg', quality);
      };
      img.onerror = function () { URL.revokeObjectURL(url); reject(new Error('bad image')); };
      img.src = url;
    });
  }

  function fail(error) { if (error) throw error; }

  var admin = {
    signIn: function (email, password) {
      return sb.auth.signInWithPassword({ email: email, password: password }).then(function (r) { fail(r.error); return r.data; });
    },
    signOut: function () { return sb.auth.signOut(); },
    getSession: function () {
      return sb.auth.getSession().then(function (r) { return (r.data && r.data.session) || null; });
    },
    changePassword: function (password) {
      return sb.auth.updateUser({ password: password }).then(function (r) { fail(r.error); });
    },

    saveProduct: function (p) {
      var item = prodTo(Object.assign({}, p, { id: p.id || uid('p') }));
      return sb.from('products').upsert(item).then(function (r) { fail(r.error); return refresh(); });
    },
    deleteProduct: function (id) {
      return sb.from('products').delete().eq('id', id).then(function (r) { fail(r.error); return refresh(); });
    },
    saveCategory: function (c) {
      var item = catTo(Object.assign({}, c, { id: c.id || uid('c') }));
      return sb.from('categories').upsert(item).then(function (r) { fail(r.error); return refresh(); });
    },
    deleteCategory: function (id) {
      if (state.products.some(function (p) { return p.category === id; })) return Promise.resolve(false);
      if (state.categories.some(function (c) { return c.parent === id; })) return Promise.resolve(false);
      return sb.from('categories').delete().eq('id', id).then(function (r) { fail(r.error); return refresh(); }).then(function () { return true; });
    },
    saveSettings: function (data) {
      return sb.from('settings').upsert({ id: 1, data: data }).then(function (r) { fail(r.error); return refresh(); });
    },

    getOrders: function () {
      return sb.from('orders').select('*').order('created_at', { ascending: false }).then(function (r) {
        fail(r.error); return (r.data || []).map(orderFrom);
      });
    },
    updateOrder: function (id, patch) {
      return sb.from('orders').update(patch).eq('id', id).then(function (r) { fail(r.error); });
    },
    deleteOrder: function (id) {
      return sb.from('orders').delete().eq('id', id).then(function (r) { fail(r.error); });
    },

    // يرفع صورة إلى التخزين بعد تصغيرها، ويرجع الرابط العام
    uploadImage: function (file) {
      return resizeImage(file, 1200, 0.85).then(function (blob) {
        var name = Date.now().toString(36) + Math.random().toString(36).slice(2, 6) + '.jpg';
        return sb.storage.from(BUCKET).upload(name, blob, { contentType: 'image/jpeg', cacheControl: '31536000' }).then(function (r) {
          fail(r.error);
          return sb.storage.from(BUCKET).getPublicUrl(name).data.publicUrl;
        });
      });
    },

    // استيراد البيانات الأولية من seed-data.js (آمن للتكرار)
    importSeed: function (seed) {
      var cats = (seed.categories || []).map(function (c) { return catTo(c); });
      var parents = cats.filter(function (c) { return !c.parent; });
      var kids = cats.filter(function (c) { return c.parent; });
      var prods = (seed.products || []).map(function (p) {
        var row = prodTo(p);
        row.created_at = p.createdAt || new Date().toISOString();
        return row;
      });
      return sb.from('categories').upsert(parents).then(function (r) {
        fail(r.error);
        return kids.length ? sb.from('categories').upsert(kids) : { error: null };
      }).then(function (r) {
        fail(r.error);
        return sb.from('products').upsert(prods);
      }).then(function (r) { fail(r.error); return refresh(); });
    }
  };

  /* ---------- التشغيل ---------- */
  var domReady = new Promise(function (resolve) {
    if (document.readyState !== 'loading') resolve();
    else document.addEventListener('DOMContentLoaded', resolve);
  });
  domReady.then(renderChrome);

  var ready = Promise.all([refresh(), domReady]).then(function () { renderChrome(); });

  global.AZ = {
    ready: ready,
    hasClient: function () { return !!sb; },
    error: function () { return state.error; },
    errorBox: errorBox,
    esc: esc, uid: uid, money: money, toast: toast,
    getSettings: getSettings,
    getCategories: getCategories, getCategory: getCategory, childrenOf: childrenOf,
    getProducts: getProducts, getProduct: getProduct, getRelated: getRelated,
    addToCart: addToCart, setQty: setQty, removeFromCart: removeFromCart, clearCart: clearCart,
    cartCount: cartCount, cartDetailed: cartDetailed, keyOf: keyOf,
    buildOrder: buildOrder, saveOrder: saveOrder, STATUS_LABELS: STATUS_LABELS,
    waLink: waLink, orderMessage: orderMessage,
    productCard: productCard, categoryCard: categoryCard, renderChrome: renderChrome,
    admin: admin,
    PLACEHOLDER: PLACEHOLDER
  };
})(window);
