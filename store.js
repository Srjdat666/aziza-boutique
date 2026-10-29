(function () {

  const KEY = "aziza_db_v1";

  function init() {

    if (!localStorage.getItem(KEY)) {

      localStorage.setItem(
        KEY,
        JSON.stringify(window.AZIZA_DATA)
      );

    }

  }

  function db() {
    return JSON.parse(localStorage.getItem(KEY));
  }

  window.AZ = {

    getProducts() {
      return db().products;
    },

    getProduct(id) {
      return db().products.find(
        p => p.id == id
      );
    }

  };

  init();

})();