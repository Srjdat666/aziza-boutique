(function () {

  const KEY = "aziza_db_v1";

  // إذا تغيّرت نسخة البيانات في data.js تُحدَّث النسخة المخزنة تلقائياً
  function init() {
    let saved = null;
    try { saved = JSON.parse(localStorage.getItem(KEY)); } catch (e) {}

    if (!saved || saved.version !== window.AZIZA_DATA.version) {
      localStorage.setItem(KEY, JSON.stringify(window.AZIZA_DATA));
    }
  }

  function db() {
    try {
      return JSON.parse(localStorage.getItem(KEY)) || window.AZIZA_DATA;
    } catch (e) {
      return window.AZIZA_DATA;
    }
  }

  window.AZ = {
    getSettings()  { return db().settings; },
    getProducts()  { return db().products; },
    getProduct(id) { return db().products.find(p => p.id == id); }
  };

  init();

})();