/* assets/data.js — محتوى المتجر (هذا هو الملف الذي تُعدّله أو تُصدّره من لوحة التحكم) */
window.AZIZA_DATA = {
  version: 1,

  settings: {
    storeName: "AZIZA Boutique",
    tagline: "حيث تعبّر الأناقة عنكِ",
    whatsapp: "218944467520",
    phones: ["0919652924", "0944467520"],
    address: "سرت، شارع 5، العمارة رقم 89",
    currency: "د.ل",
    shipping: 0,
    notice: "التوصيل داخل سرت مجاناً — للطلبات راسلينا على الخاص.",
    instagram: "https://www.instagram.com/aziza.boutique01",
    tiktok: "https://www.tiktok.com/@aziza.store1",
    snapchat: "https://snapchat.com/t/UYMV2sWB",
    facebook: "https://www.facebook.com/share/1M7TuNEcYZ/",
    adminPin: "1234"
  },

  categories: [
    { id: "dresses",     name: "فساتين",        parent: null, order: 1, image: "paz1.jpg" },
    { id: "suits",       name: "أطقم وبدلات",   parent: null, order: 2, image: "paz2.jpg" },
    { id: "tops",        name: "تيشرتات وتوب",  parent: null, order: 3, image: "paz3.jpg" },
    { id: "sets",        name: "تركيبات عزيزة", parent: null, order: 4, image: "paz4.jpg" },
    { id: "abayas",      name: "عبايات",        parent: null, order: 5, image: "" },
    { id: "accessories", name: "إكسسوارات",     parent: null, order: 6, image: "" },

    { id: "dresses-evening", name: "فساتين سهرة",  parent: "dresses", order: 1, image: "" },
    { id: "dresses-daily",   name: "فساتين يومية", parent: "dresses", order: 2, image: "" }
  ],

  products: [
    {
      id: "pz-black-dress",
      name: "فستان أسود كلاسيك",
      category: "dresses-evening",
      price: 320, oldPrice: 380, stock: 6,
      sizes: ["S", "M", "L", "XL"], colors: ["أسود"],
      images: ["paz1.jpg"],
      desc: "فستان أسود بقصة أنيقة يناسب المناسبات المسائية. قماش مريح وخفيف.",
      featured: true, active: true, createdAt: "2025-01-10T10:00:00.000Z"
    },
    {
      id: "pz-khayal-suit",
      name: "بدلة خيال",
      category: "suits",
      price: 450, oldPrice: 0, stock: 4,
      sizes: ["M", "L"], colors: ["بيج", "أسود"],
      images: ["paz2.jpg"],
      desc: "طقم بدلة بقصّة عصرية، مثالي للعمل والمناسبات النهارية.",
      featured: true, active: true, createdAt: "2025-01-12T10:00:00.000Z"
    },
    {
      id: "pz-cotton-tee",
      name: "تيشرت قطني",
      category: "tops",
      price: 85, oldPrice: 110, stock: 12,
      sizes: ["S", "M", "L"], colors: ["أبيض", "وردي"],
      images: ["paz3.jpg"],
      desc: "تيشرت قطني ناعم بجودة عالية، أساسي في كل خزانة.",
      featured: false, active: true, createdAt: "2025-01-15T10:00:00.000Z"
    },
    {
      id: "pz-aziza-set",
      name: "تركيبة عزيزة",
      category: "sets",
      price: 390, oldPrice: 0, stock: 5,
      sizes: ["S", "M", "L"], colors: ["بيج"],
      images: ["paz4.jpg"],
      desc: "تركيبة كاملة من تصميم عزيزة، قطعتان متناسقتان بتفاصيل مميزة.",
      featured: true, active: true, createdAt: "2025-01-18T10:00:00.000Z"
    },
    {
      id: "pz-daily-rose",
      name: "فستان يومي وردي",
      category: "dresses-daily",
      price: 210, oldPrice: 0, stock: 8,
      sizes: ["S", "M", "L", "XL"], colors: ["وردي"],
      images: ["paz1.jpg"],
      desc: "فستان يومي خفيف بلون وردي هادئ، مناسب للاستخدام اليومي.",
      featured: false, active: true, createdAt: "2025-01-20T10:00:00.000Z"
    },
    {
      id: "pz-abaya-plain",
      name: "عباية سادة",
      category: "abayas",
      price: 280, oldPrice: 0, stock: 7,
      sizes: ["M", "L", "XL"], colors: ["أسود", "كحلي"],
      images: ["paz2.jpg"],
      desc: "عباية سادة بقماش فاخر وتفصيل مريح.",
      featured: false, active: true, createdAt: "2025-01-22T10:00:00.000Z"
    },
    {
      id: "pz-casual-set",
      name: "طقم كاجوال",
      category: "suits",
      price: 340, oldPrice: 400, stock: 3,
      sizes: ["M", "L"], colors: ["بيج"],
      images: ["paz3.jpg"],
      desc: "طقم كاجوال مريح بلون محايد يناسب كل الأوقات.",
      featured: false, active: true, createdAt: "2025-01-24T10:00:00.000Z"
    },
    {
      id: "pz-small-bag",
      name: "شنطة صغيرة",
      category: "accessories",
      price: 120, oldPrice: 0, stock: 10,
      sizes: [], colors: ["ذهبي", "أسود"],
      images: ["paz4.jpg"],
      desc: "شنطة صغيرة أنيقة تكمل إطلالتك.",
      featured: false, active: true, createdAt: "2025-01-26T10:00:00.000Z"
    }
  ]
};